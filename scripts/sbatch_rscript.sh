#!/usr/bin/env bash
# sbatch_rscript.sh — Submit an R script as a SLURM batch job.
#
# Usage:
#   ./scripts/sbatch_rscript.sh <path/to/script.R> [args...] [--time=...] [--mem=...] [--cpus=...]
#
# Examples:
#   ./scripts/sbatch_rscript.sh src/preprocess.R
#   ./scripts/sbatch_rscript.sh src/integrate.R --time=12:00:00 --mem=128G --cpus=16
#   ./scripts/sbatch_rscript.sh src/big_analysis.R --time=2-0:00:00   # auto-uses long partition
#
# Logs go to slurm/logs/<scriptname>_<jobid>.{out,err}

source "$(dirname "$0")/_common.sh"

SIF="$(sif_path)"
[[ -f "$SIF" ]] || die "Container not found: $SIF — build with ./scripts/build_container.sh"

[[ $# -ge 1 ]] || die "Usage: $0 <script.R> [args...] [--time=...] [--mem=...] [--cpus=...]"

R_SCRIPT="$1"
shift

[[ -f "$PROJECT_ROOT/$R_SCRIPT" || -f "$R_SCRIPT" ]] || die "Script not found: $R_SCRIPT"

# Resolve to absolute path for the job
if [[ "$R_SCRIPT" != /* ]]; then
    R_SCRIPT="$PROJECT_ROOT/$R_SCRIPT"
fi

# Parse SLURM-related flags; remaining args are passed to the R script
parse_slurm_args "$@"

SCRIPT_BASE="$(basename "$R_SCRIPT" .R)"
JOB_NAME="${SCRIPT_BASE}.${PROJECT_NAME}"
LOG_OUT="$SLURM_LOG_DIR/${JOB_NAME}_%j.out"
LOG_ERR="$SLURM_LOG_DIR/${JOB_NAME}_%j.err"

msg "Submitting batch R job..."
msg "  Script:    $R_SCRIPT"
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
        --bind '$PROJECT_ROOT/R':/usr/local/lib/R/site-library \
        --env R_LIBS_USER=/usr/local/lib/R/site-library \
        --pwd '$WORKSPACE' \
        '$SIF' \
        Rscript '$R_SCRIPT' ${REMAINING_ARGS[*]:-}")

msg "Submitted job $JOBID"
msg "Stdout: ${LOG_OUT//%j/$JOBID}"
msg "Stderr: ${LOG_ERR//%j/$JOBID}"
msg ""
msg "Follow: ./scripts/logs.sh $JOBID"
msg "Stop:   scancel $JOBID"
