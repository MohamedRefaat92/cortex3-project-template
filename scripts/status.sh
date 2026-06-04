#!/usr/bin/env bash
# status.sh — Show this project's SLURM jobs, container state, and tunnels.

source "$(dirname "$0")/_common.sh"

echo "=================================================================="
echo "Project: $PROJECT_NAME"
echo "Root:    $PROJECT_ROOT"
echo "Cluster: $(hostname -s) ($(uname -n))"
echo "User:    $USER"
echo "=================================================================="
echo

# --- Container ---
echo "Container:"
SIF="$(sif_path)"
if [[ -f "$SIF" ]]; then
    size="$(du -h "$SIF" | cut -f1)"
    age="$(date -r "$SIF" '+%Y-%m-%d %H:%M')"
    echo "  $SIF  ($size, built $age)"
else
    echo "  (not built — run ./scripts/build_container.sh)"
fi
echo

# --- SLURM jobs for this project ---
echo "SLURM jobs for this project:"

# Filter squeue by job name prefix to limit to our project
JOBS=$(squeue -u "$USER" -h \
    -o "%i|%j|%T|%M|%l|%N|%P|%C|%m" 2>/dev/null \
    | awk -F'|' -v proj=".${PROJECT_NAME}" '$2 ~ proj {print}')

if [[ -z "$JOBS" ]]; then
    echo "  No jobs running for this project."
else
    printf "  %-9s %-30s %-9s %-9s %-9s %-12s %-9s %s\n" \
        "JOBID" "NAME" "STATE" "TIME" "LIMIT" "NODE" "PART" "RES"
    while IFS='|' read -r jobid name state time limit node part cpus mem; do
        printf "  %-9s %-30s %-9s %-9s %-9s %-12s %-9s %s/%s\n" \
            "$jobid" "$name" "$state" "$time" "$limit" "$node" "$part" "${cpus}cpu" "$mem"
    done <<< "$JOBS"
fi
echo

# --- Active tunnels (info written by run_*.sh) ---
echo "Active tunnel info (from run_rstudio.sh / run_jupyter.sh):"
if [[ -d "$PROJECT_ROOT/.tunnel" ]]; then
    found=0
    for f in "$PROJECT_ROOT/.tunnel"/*.{rstudio,jupyter}.* 2>/dev/null; do
        [[ -e "$f" ]] || continue
    done
    for f in "$PROJECT_ROOT"/.tunnel/*; do
        [[ -e "$f" ]] || continue
        kind="$(basename "$f" | cut -d. -f1)"
        jobid="$(basename "$f" | cut -d. -f2)"
        # Is the job still alive?
        if squeue -h -j "$jobid" -o '%T' 2>/dev/null | grep -q .; then
            # shellcheck disable=SC1090
            ( source "$f"
              port_var="$(echo "${kind}_PORT" | tr '[:lower:]' '[:upper:]')"
              local_port="${!port_var:-?}"
              echo "  $kind (job $jobid): node=$NODE port=$PORT"
              echo "    ssh -N -L ${local_port}:${NODE}:${PORT} ludwig_cluster"
              echo "    -> http://localhost:${local_port}"
            )
            found=$((found + 1))
        else
            # Job is gone — clean up stale tunnel file
            rm -f "$f"
        fi
    done
    if [[ $found -eq 0 ]]; then
        echo "  None."
    fi
else
    echo "  None."
fi
echo

# --- Disk usage of project dir ---
echo "Disk usage:"
du -sh "$PROJECT_ROOT" 2>/dev/null | sed "s|$PROJECT_ROOT|.|"
echo
echo "Apptainer cache: $(du -sh "$APPTAINER_CACHEDIR" 2>/dev/null | cut -f1) at $APPTAINER_CACHEDIR"
echo
echo "Recent SLURM logs in $SLURM_LOG_DIR:"
ls -lt "$SLURM_LOG_DIR" 2>/dev/null | head -6 | tail -5 | awk '{print "  " $NF}'
