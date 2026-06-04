#!/usr/bin/env bash
# run_shell.sh — Drop into an interactive bash shell on a compute node,
#                inside the container.
#
# This is FOREGROUND (uses srun, not sbatch). Stays in your terminal until
# you exit the shell. Good for exploration, quick scripts, debugging.
#
# Usage:
#   ./scripts/run_shell.sh                # default time/resources
#   ./scripts/run_shell.sh --time=2:00:00 --mem=32G --cpus=4

source "$(dirname "$0")/_common.sh"

SIF="$(sif_path)"
[[ -f "$SIF" ]] || die "Container not found: $SIF — build with ./scripts/build_container.sh"

SBATCH_TIME="${SLURM_DEFAULT_TIME:-4:00:00}"
SBATCH_CPUS="${SLURM_DEFAULT_CPUS:-8}"
SBATCH_MEM="${SLURM_DEFAULT_MEM:-64G}"
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

msg "Allocating compute node ($SBATCH_CPUS cpus, $SBATCH_MEM, $SBATCH_TIME)..."

srun \
    --account="$SLURM_ACCOUNT" \
    --partition="$SBATCH_PARTITION" \
    --time="$SBATCH_TIME" \
    --cpus-per-task="$SBATCH_CPUS" \
    --mem="$SBATCH_MEM" \
    --job-name="shell.${PROJECT_NAME}" \
    --pty \
    apptainer exec \
        --bind "$PROJECT_ROOT":"$WORKSPACE" \
        --bind "$PROJECT_ROOT/R":/usr/local/lib/R/site-library \
        --pwd "$WORKSPACE" \
        "$SIF" \
        /bin/bash
