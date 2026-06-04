#!/usr/bin/env bash
# build_container.sh — Build the project's .sif from .def
#
# Runs the build inside an srun-allocated compute node (NOT on login node).
# Apptainer build is CPU/memory hungry and would be killed on login nodes
# at most institutions.
#
# Usage:
#   ./scripts/build_container.sh                # build container/$CONTAINER_NAME.def
#   ./scripts/build_container.sh --force        # rebuild even if .sif exists
#
# Resources requested: 8 CPUs, 32G memory, 2h walltime — adjust if your
# container has heavy build steps (e.g. compiling R packages from source).

source "$(dirname "$0")/_common.sh"

DEF="$PROJECT_ROOT/container/${CONTAINER_NAME}.def"
SIF="$(sif_path)"

FORCE=0
if [[ "${1:-}" == "--force" ]]; then
    FORCE=1
fi

[[ -f "$DEF" ]] || die "Definition file not found: $DEF"

if [[ -f "$SIF" && $FORCE -eq 0 ]]; then
    msg "Image already exists: $SIF ($(du -h "$SIF" | cut -f1))"
    msg "Use --force to rebuild."
    exit 0
fi

msg "Submitting build job to SLURM..."
msg "  Definition: $DEF"
msg "  Output:     $SIF"
msg "  Cache:      $APPTAINER_CACHEDIR"
msg "  Tmp:        $APPTAINER_TMPDIR"

# Use srun (foreground, blocking) so you see the build output live.
# Use sbatch instead if you want to detach and come back later.
srun \
    --account="$SLURM_ACCOUNT" \
    --partition="$SLURM_PARTITION_SHORT" \
    --time=2:00:00 \
    --cpus-per-task=8 \
    --mem=32G \
    --job-name="build.${PROJECT_NAME}" \
    bash -c "
        export APPTAINER_CACHEDIR='$APPTAINER_CACHEDIR'
        export APPTAINER_TMPDIR='$APPTAINER_TMPDIR'
        mkdir -p \"\$APPTAINER_CACHEDIR\" \"\$APPTAINER_TMPDIR\"
        apptainer build --force '$SIF' '$DEF'
    "

if [[ -f "$SIF" ]]; then
    msg "Build complete: $SIF ($(du -h "$SIF" | cut -f1))"
else
    die "Build did not produce $SIF — check srun output above"
fi
