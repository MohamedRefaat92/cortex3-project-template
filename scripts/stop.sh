#!/usr/bin/env bash
# stop.sh — Cancel SLURM jobs for this project.
#
# Usage:
#   ./scripts/stop.sh <jobid>            # cancel one job by ID
#   ./scripts/stop.sh rstudio            # cancel all rstudio.<project> jobs
#   ./scripts/stop.sh jupyter            # cancel all jupyter.<project> jobs
#   ./scripts/stop.sh all                # cancel all jobs for this project
#   ./scripts/stop.sh                    # list cancellable jobs

source "$(dirname "$0")/_common.sh"

list_project_jobs() {
    squeue -u "$USER" -h -o "%i %j %T" 2>/dev/null \
        | awk -v proj=".${PROJECT_NAME}" '$2 ~ proj {print $1, $2, $3}'
}

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <jobid> | <name> | all"
    echo
    echo "Cancellable jobs for this project:"
    while read -r jobid name state; do
        [[ -z "$jobid" ]] && continue
        echo "  $jobid  $name  ($state)"
    done < <(list_project_jobs)
    exit 1
fi

target="$1"

if [[ "$target" =~ ^[0-9]+$ ]]; then
    # Numeric — treat as job ID
    msg "Cancelling job $target"
    scancel "$target"
    rm -f "$PROJECT_ROOT"/.tunnel/*."$target" 2>/dev/null || true
elif [[ "$target" == "all" ]]; then
    while read -r jobid name state; do
        [[ -z "$jobid" ]] && continue
        msg "Cancelling job $jobid ($name)"
        scancel "$jobid"
        rm -f "$PROJECT_ROOT"/.tunnel/*."$jobid" 2>/dev/null || true
    done < <(list_project_jobs)
else
    # Match by entry-point name (rstudio, jupyter, etc.)
    matched=0
    while read -r jobid name state; do
        [[ -z "$jobid" ]] && continue
        if [[ "$name" == "${target}.${PROJECT_NAME}" ]]; then
            msg "Cancelling job $jobid ($name)"
            scancel "$jobid"
            rm -f "$PROJECT_ROOT"/.tunnel/*."$jobid" 2>/dev/null || true
            matched=$((matched + 1))
        fi
    done < <(list_project_jobs)
    if [[ $matched -eq 0 ]]; then
        warn "No '$target' jobs found for project $PROJECT_NAME"
        warn "Use ./scripts/stop.sh with no args to see cancellable jobs."
    fi
fi
