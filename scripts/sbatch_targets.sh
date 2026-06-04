#!/usr/bin/env bash
# sbatch_targets.sh — Run a targets pipeline as a batch SLURM job.
#
# Usage:
#   ./scripts/sbatch_targets.sh                       # tar_make() in default
#   ./scripts/sbatch_targets.sh --time=2-0:00:00      # long job (auto-uses long partition)
#   ./scripts/sbatch_targets.sh --mem=256G --cpus=32

source "$(dirname "$0")/_common.sh"

SIF="$(sif_path)"
[[ -f "$SIF" ]] || die "Container not found: $SIF"

# Targets pipelines tend to be long-running; bump default time
SLURM_DEFAULT_TIME="${SLURM_DEFAULT_TIME:-12:00:00}"
SLURM_DEFAULT_CPUS="${SLURM_DEFAULT_CPUS:-16}"
SLURM_DEFAULT_MEM="${SLURM_DEFAULT_MEM:-128G}"

parse_slurm_args "$@"

JOB_NAME="targets.${PROJECT_NAME}"
LOG_OUT="$SLURM_LOG_DIR/${JOB_NAME}_%j.out"
LOG_ERR="$SLURM_LOG_DIR/${JOB_NAME}_%j.err"

msg "Submitting targets pipeline..."
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
        Rscript -e 'targets::tar_make()'")

msg "Submitted job $JOBID"
msg "Logs:    ${LOG_OUT//%j/$JOBID}"
msg "Follow:  ./scripts/logs.sh $JOBID"
msg "Stop:    scancel $JOBID"
