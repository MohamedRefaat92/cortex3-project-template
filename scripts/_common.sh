#!/usr/bin/env bash
# _common.sh — sourced by every other script in scripts/
#
# Provides:
#   - .env loading
#   - SLURM-aware path/state helpers
#   - sif_path(), sbatch arg parsing
#   - tunnel command printing for Mac browser access

set -euo pipefail

# ----- Resolve project root regardless of where the caller is
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ----- Load .env
if [[ -f "$PROJECT_ROOT/.env" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$PROJECT_ROOT/.env"
    set +a
else
    echo "Error: $PROJECT_ROOT/.env not found." >&2
    echo "Copy .env.example to .env and customize." >&2
    exit 1
fi

# ----- Required variable check
: "${PROJECT_NAME:?PROJECT_NAME not set in .env}"
: "${CONTAINER_NAME:?CONTAINER_NAME not set in .env}"
: "${SLURM_ACCOUNT:?SLURM_ACCOUNT not set in .env}"
: "${WORKSPACE:?WORKSPACE not set in .env}"

# ----- Export apptainer cache/tmp env vars so any apptainer call inherits them
export APPTAINER_CACHEDIR="${APPTAINER_CACHEDIR:-/mnt/scratch/users/$USER/.apptainer-cache}"
export APPTAINER_TMPDIR="${APPTAINER_TMPDIR:-/tmp/apptainer-$USER}"
mkdir -p "$APPTAINER_CACHEDIR" "$APPTAINER_TMPDIR"

# ----- Common directories
SLURM_LOG_DIR="$PROJECT_ROOT/slurm/logs"
SLURM_ARCHIVE_DIR="$PROJECT_ROOT/slurm/archive"
mkdir -p "$SLURM_LOG_DIR" "$SLURM_ARCHIVE_DIR"

# ----- Paths
sif_path() { echo "$PROJECT_ROOT/container/${CONTAINER_NAME}.sif"; }

# ----- SLURM helpers
# Returns the compute node a running job was allocated, or empty if not yet.
job_node() {
    local jobid="$1"
    squeue -h -j "$jobid" -o '%N' 2>/dev/null | tr -d ' '
}

# Wait for a job to be in RUNNING state, return its node. Timeout in seconds.
wait_for_job_running() {
    local jobid="$1"
    local timeout="${2:-300}"   # 5 min default
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        local state
        state="$(squeue -h -j "$jobid" -o '%T' 2>/dev/null | tr -d ' ')"
        if [[ -z "$state" ]]; then
            return 1    # job no longer in queue
        fi
        if [[ "$state" == "RUNNING" ]]; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 2    # timeout
}

# ----- Argument parsing helpers
# Parse --time/--cpus/--mem/--partition flags and emit sbatch-friendly options.
# Usage: parse_slurm_args "$@"
# Sets: SBATCH_TIME, SBATCH_CPUS, SBATCH_MEM, SBATCH_PARTITION, REMAINING_ARGS
parse_slurm_args() {
    SBATCH_TIME="${SLURM_DEFAULT_TIME:-4:00:00}"
    SBATCH_CPUS="${SLURM_DEFAULT_CPUS:-8}"
    SBATCH_MEM="${SLURM_DEFAULT_MEM:-64G}"
    SBATCH_PARTITION="${SLURM_PARTITION_SHORT:-short}"
    REMAINING_ARGS=()

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
            *)             REMAINING_ARGS+=("$1") ;;
        esac
        shift
    done

    # Auto-bump to 'long' partition if requested time > 1 day
    # (short's max is 1-00:00:00)
    local days="${SBATCH_TIME%%-*}"
    if [[ "$SBATCH_TIME" == *-* && "$days" -ge 1 && "$SBATCH_PARTITION" == "short" ]]; then
        if [[ "$days" -gt 1 ]] || [[ "$SBATCH_TIME" != "1-00:00:00" ]]; then
            SBATCH_PARTITION="${SLURM_PARTITION_LONG:-long}"
            msg "Auto-selected '$SBATCH_PARTITION' partition (--time > 1 day)"
        fi
    fi
}

# ----- Tunnel command printer
# Usage: print_tunnel_command <local_port> <compute_node> <remote_port>
print_tunnel_command() {
    local local_port="$1"
    local node="$2"
    local remote_port="$3"

    cat <<EOF

==================================================================
 TUNNEL TO YOUR MAC
==================================================================
 On your Mac, in a NEW terminal, run:

   ssh -N -L ${local_port}:${node}:${remote_port} ludwig_cluster

 Then open in your browser:

   http://localhost:${local_port}

 Leave the ssh command running until you're done.
 (Stop with Ctrl+C — it will kill the tunnel, not the job.)
==================================================================

 ALTERNATIVE: VS Code auto-forwarding
 If you're already connected to ludwig_cluster via VS Code
 Remote-SSH, VS Code will detect the port and offer to
 forward it automatically. Look for a popup in the bottom-right
 or check the "Ports" tab next to the integrated terminal.

EOF
}

# ----- Pretty printing
msg()  { printf "[%s] %s\n" "$PROJECT_NAME" "$*"; }
warn() { printf "[%s] WARN: %s\n" "$PROJECT_NAME" "$*" >&2; }
die()  { printf "[%s] ERROR: %s\n" "$PROJECT_NAME" "$*" >&2; exit 1; }
