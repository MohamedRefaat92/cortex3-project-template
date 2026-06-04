#!/usr/bin/env bash
# run_rstudio.sh — Submit an RStudio Server job on a compute node.
#
# Flow:
#   1. sbatch submits a job that runs apptainer + rserver on a compute node
#   2. Wait for the job to start (allocated to a node)
#   3. Print the SSH tunnel command you run on your Mac to reach it
#
# Usage:
#   ./scripts/run_rstudio.sh                          # use INTERACTIVE_* defaults
#   ./scripts/run_rstudio.sh --time=4:00:00 --mem=128G --cpus=32
#   ./scripts/run_rstudio.sh --partition=long --time=2-0:00:00
#
# Stop with: scancel <jobid>   or   ./scripts/stop.sh <jobid>

source "$(dirname "$0")/_common.sh"

SIF="$(sif_path)"
[[ -f "$SIF" ]] || die "Container not found: $SIF — build with ./scripts/build_container.sh"

# Defaults for interactive sessions (heftier than batch defaults)
SBATCH_TIME="${INTERACTIVE_TIME:-8:00:00}"
SBATCH_CPUS="${INTERACTIVE_CPUS:-16}"
SBATCH_MEM="${INTERACTIVE_MEM:-96G}"
SBATCH_PARTITION="${SLURM_PARTITION_SHORT:-short}"

# Allow override
while [[ $# -gt 0 ]]; do
    case "$1" in
        --time=*)      SBATCH_TIME="${1#*=}" ;;
        --time)        shift; SBATCH_TIME="$1" ;;
        --cpus=*)      SBATCH_CPUS="${1#*=}" ;;
        --cpus)        shift; SBATCH_CPUS="$1" ;;
        --mem=*)       SBATCH_MEM="${1#*=}" ;;
        --mem)         shift; SBATCH_MEM="$1" ;;
        --partition=*) SBATCH_PARTITION="${1#*=}" ;;
        --partition)   shift; SBATCH_PARTITION="$1" ;;
        *) die "Unknown option: $1" ;;
    esac
    shift
done

JOB_NAME="rstudio.${PROJECT_NAME}"
LOG_OUT="$SLURM_LOG_DIR/${JOB_NAME}_%j.out"
LOG_ERR="$SLURM_LOG_DIR/${JOB_NAME}_%j.err"

msg "Submitting RStudio Server job..."
msg "  Partition: $SBATCH_PARTITION    Time: $SBATCH_TIME"
msg "  CPUs:      $SBATCH_CPUS         Mem:  $SBATCH_MEM"

# The compute-node-side script: starts rserver, picks a free port, advertises it.
# We use heredoc to a temp script the SLURM job will execute.
JOB_SCRIPT="$(mktemp)"
cat > "$JOB_SCRIPT" <<'JOBEOF'
#!/usr/bin/env bash
set -euo pipefail

# Pick a free random high port on the compute node
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()' 2>/dev/null \
    || perl -MIO::Socket::INET -e '$s=IO::Socket::INET->new(Listen=>1); print $s->sockport()')
NODE=$(hostname -s)

# Write the connection info where the launcher can read it
mkdir -p "$PROJECT_ROOT/.tunnel"
cat > "$PROJECT_ROOT/.tunnel/rstudio.$SLURM_JOB_ID" <<INFO
NODE=$NODE
PORT=$PORT
JOB=$SLURM_JOB_ID
STARTED=$(date -Iseconds)
INFO

echo "[rstudio job $SLURM_JOB_ID] starting on $NODE:$PORT"

# Tell rserver to use a writable per-job state dir (rocker image's default
# locations may not be writable by the user inside an apptainer container)
RSERVER_TMP=$(mktemp -d -p "$APPTAINER_TMPDIR" rserver.XXXXXX)
mkdir -p "$RSERVER_TMP/server" "$RSERVER_TMP/data"

apptainer exec \
    --bind "$PROJECT_ROOT":"$WORKSPACE" \
    --bind "$DATA_ROOT_HOST":"$DATA_ROOT_CONTAINER":ro \
    --bind "$RSERVER_TMP/server":/var/run/rstudio-server \
    --bind "$RSERVER_TMP/data":/var/lib/rstudio-server \
    --env R_LIBS_USER=/usr/local/lib/R/site-library \
    --env USER="$USER" \
    --env HOME="$WORKSPACE" \
    --pwd "$WORKSPACE" \
    "$SIF" \
    /usr/lib/rstudio-server/bin/rserver \
        --server-daemonize=0 \
        --server-user="$USER" \
        --www-port="$PORT" \
        --www-address=0.0.0.0 \
        --auth-none=1 \
        --auth-validate-users=0 \
        --secure-cookie-key-file="$RSERVER_TMP/cookie-key"
JOBEOF

chmod +x "$JOB_SCRIPT"

# Submit the job, capturing job ID
JOBID=$(sbatch --parsable \
    --account="$SLURM_ACCOUNT" \
    --partition="$SBATCH_PARTITION" \
    --time="$SBATCH_TIME" \
    --cpus-per-task="$SBATCH_CPUS" \
    --mem="$SBATCH_MEM" \
    --job-name="$JOB_NAME" \
    --output="$LOG_OUT" \
    --error="$LOG_ERR" \
    --export=ALL,PROJECT_ROOT="$PROJECT_ROOT",SIF="$SIF",WORKSPACE="$WORKSPACE",APPTAINER_TMPDIR="$APPTAINER_TMPDIR" \
    "$JOB_SCRIPT")

rm -f "$JOB_SCRIPT"

msg "Submitted job $JOBID"
msg "Waiting for compute node allocation..."

if ! wait_for_job_running "$JOBID" 300; then
    warn "Job $JOBID didn't start within 5 minutes."
    warn "It's still queued. Check status: squeue -j $JOBID"
    warn "When it starts, get tunnel info with: ./scripts/_setup_tunnel.sh $JOBID"
    exit 0
fi

# Give rserver a moment to actually start listening
sleep 5

# Read the tunnel info written by the job
TUNNEL_FILE="$PROJECT_ROOT/.tunnel/rstudio.$JOBID"
if [[ ! -f "$TUNNEL_FILE" ]]; then
    warn "Job is running but didn't write tunnel info. Check logs:"
    warn "  tail -f ${LOG_OUT//%j/$JOBID}"
    exit 1
fi

# shellcheck disable=SC1090
source "$TUNNEL_FILE"

msg "RStudio Server is running:"
msg "  Job:  $JOBID"
msg "  Node: $NODE"
msg "  Port: $PORT (on the compute node)"
msg "  Log:  ${LOG_OUT//%j/$JOBID}"

print_tunnel_command "${RSTUDIO_PORT:-8801}" "$NODE" "$PORT"

msg "When done: scancel $JOBID  (or ./scripts/stop.sh $JOBID)"
