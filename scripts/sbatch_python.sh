#!/usr/bin/env bash
# sbatch_python.sh — Submit a Python script as a SLURM batch job.
#
# Usage:
#   ./scripts/sbatch_python.sh <path/to/script.py> [args...] [--time=...] [--mem=...] [--cpus=...]
#
# Examples:
#   ./scripts/sbatch_python.sh src/scvelo_run.py
#   ./scripts/sbatch_python.sh src/big_model.py --time=12:00:00 --mem=256G

source "$(dirname "$0")/_common.sh"

SIF="$(sif_path)"
[[ -f "$SIF" ]] || die "Container not found: $SIF — build with ./scripts/build_container.sh"

[[ $# -ge 1 ]] || die "Usage: $0 <script.py> [args...] [--time=...] [--mem=...] [--cpus=...]"

PY_SCRIPT="$1"
shift

[[ -f "$PROJECT_ROOT/$PY_SCRIPT" || -f "$PY_SCRIPT" ]] || die "Script not found: $PY_SCRIPT"
if [[ "$PY_SCRIPT" != /* ]]; then
    PY_SCRIPT="$PROJECT_ROOT/$PY_SCRIPT"
fi

parse_slurm_args "$@"

SCRIPT_BASE="$(basename "$PY_SCRIPT" .py)"
JOB_NAME="${SCRIPT_BASE}.${PROJECT_NAME}"
LOG_OUT="$SLURM_LOG_DIR/${JOB_NAME}_%j.out"
LOG_ERR="$SLURM_LOG_DIR/${JOB_NAME}_%j.err"

msg "Submitting batch Python job..."
msg "  Script:    $PY_SCRIPT"
msg "  Args:      ${REMAINING_ARGS[*]:-(none)}"
msg "  Partition: $SBATCH_PARTITION    Time: $SBATCH_TIME"
msg "  CPUs:      $SBATCH_CPUS         Mem:  $SBATCH_MEM"

JOBID=$(sbatch --parsable \
    --account="$SLURM_ACCOUNT" \
    --partition="$SBATCH_PARTITION" \
    --time="$SBATCH_TIME" \
    --cpus-per-task="$SBATCH_CPUS" \
    --mem="$SBATCH_MEM" \
    --job-name="$JOB_NAME" \
    --output="$LOG_OUT" \
    --error="$LOG_ERR" \
    --wrap="apptainer exec \
        --bind '$PROJECT_ROOT':'$WORKSPACE' \
        --pwd '$WORKSPACE' \
        '$SIF' \
        python '$PY_SCRIPT' ${REMAINING_ARGS[*]:-}")

msg "Submitted job $JOBID"
msg "Stdout: ${LOG_OUT//%j/$JOBID}"
msg "Stderr: ${LOG_ERR//%j/$JOBID}"
msg ""
msg "Follow: ./scripts/logs.sh $JOBID"
msg "Stop:   scancel $JOBID"
