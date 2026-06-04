#!/usr/bin/env bash
# run_jupyter.sh — Submit a Jupyter Lab job on a compute node.
#
# Same pattern as run_rstudio.sh — see that script for the flow.
#
# Usage:
#   ./scripts/run_jupyter.sh
#   ./scripts/run_jupyter.sh --time=6:00:00 --mem=128G --cpus=24
#
# Token is printed in the job log (slurm/logs/jupyter.*.out)

source "$(dirname "$0")/_common.sh"

SIF="$(sif_path)"
[[ -f "$SIF" ]] || die "Container not found: $SIF — build with ./scripts/build_container.sh"

SBATCH_TIME="${INTERACTIVE_TIME:-8:00:00}"
SBATCH_CPUS="${INTERACTIVE_CPUS:-16}"
SBATCH_MEM="${INTERACTIVE_MEM:-96G}"
SBATCH_PARTITION="${SLURM_PARTITION_SHORT:-short}"

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

JOB_NAME="jupyter.${PROJECT_NAME}"
LOG_OUT="$SLURM_LOG_DIR/${JOB_NAME}_%j.out"
LOG_ERR="$SLURM_LOG_DIR/${JOB_NAME}_%j.err"

msg "Submitting Jupyter Lab job..."
msg "  Partition: $SBATCH_PARTITION    Time: $SBATCH_TIME"
msg "  CPUs:      $SBATCH_CPUS         Mem:  $SBATCH_MEM"

JOB_SCRIPT="$(mktemp)"
cat > "$JOB_SCRIPT" <<'JOBEOF'
#!/usr/bin/env bash
set -euo pipefail

PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')
NODE=$(hostname -s)

mkdir -p "$PROJECT_ROOT/.tunnel"
cat > "$PROJECT_ROOT/.tunnel/jupyter.$SLURM_JOB_ID" <<INFO
NODE=$NODE
PORT=$PORT
JOB=$SLURM_JOB_ID
STARTED=$(date -Iseconds)
INFO

echo "[jupyter job $SLURM_JOB_ID] starting on $NODE:$PORT"

apptainer exec \
    --bind "$PROJECT_ROOT":"$WORKSPACE" \
    --pwd "$WORKSPACE" \
    --env HOME="$WORKSPACE" \
    "$SIF" \
    jupyter lab \
        --ip=0.0.0.0 \
        --port="$PORT" \
        --no-browser \
        --notebook-dir="$WORKSPACE/notebooks" \
        --ServerApp.terminado_settings='{"shell_command":["/bin/bash"]}'
JOBEOF

chmod +x "$JOB_SCRIPT"

JOBID=$(sbatch --parsable \
    --account="$SLURM_ACCOUNT" \
    --partition="$SBATCH_PARTITION" \
    --time="$SBATCH_TIME" \
    --cpus-per-task="$SBATCH_CPUS" \
    --mem="$SBATCH_MEM" \
    --job-name="$JOB_NAME" \
    --output="$LOG_OUT" \
    --error="$LOG_ERR" \
    --export=ALL,PROJECT_ROOT="$PROJECT_ROOT",SIF="$SIF",WORKSPACE="$WORKSPACE" \
    "$JOB_SCRIPT")

rm -f "$JOB_SCRIPT"

msg "Submitted job $JOBID"
msg "Waiting for allocation..."

if ! wait_for_job_running "$JOBID" 300; then
    warn "Job didn't start in 5 minutes — still queued."
    warn "Check: squeue -j $JOBID"
    exit 0
fi

sleep 5

TUNNEL_FILE="$PROJECT_ROOT/.tunnel/jupyter.$JOBID"
[[ -f "$TUNNEL_FILE" ]] || die "No tunnel info — check logs at ${LOG_OUT//%j/$JOBID}"
# shellcheck disable=SC1090
source "$TUNNEL_FILE"

msg "Jupyter Lab is running:"
msg "  Job:  $JOBID"
msg "  Node: $NODE"
msg "  Port: $PORT (on compute node)"
msg "  Log:  ${LOG_OUT//%j/$JOBID}"
msg ""
msg "Token URL (look in log for the full URL with token):"
sleep 3
grep -E 'token=' "${LOG_OUT//%j/$JOBID}" 2>/dev/null | head -1 || \
    msg "  (waiting for token to appear; tail the log: ./scripts/logs.sh $JOBID)"

print_tunnel_command "${JUPYTER_PORT:-8802}" "$NODE" "$PORT"

msg "When done: scancel $JOBID"
