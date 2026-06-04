#!/usr/bin/env bash
# logs.sh — Tail SLURM logs for a job.
#
# Usage:
#   ./scripts/logs.sh <jobid>           # tail both .out and .err
#   ./scripts/logs.sh <jobid> --err     # only stderr
#   ./scripts/logs.sh <jobid> --once    # print and exit
#   ./scripts/logs.sh                   # list recent logs

source "$(dirname "$0")/_common.sh"

if [[ $# -eq 0 ]]; then
    echo "Recent logs in $SLURM_LOG_DIR:"
    ls -lt "$SLURM_LOG_DIR" 2>/dev/null | grep -v '^total' | head -10 | awk '{print "  " $NF}'
    echo
    echo "Usage: $0 <jobid> [--err|--once]"
    exit 1
fi

jobid="$1"
shift || true

MODE="follow"
STREAM="both"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --once)   MODE="once" ;;
        --err)    STREAM="err" ;;
        --out)    STREAM="out" ;;
        *) die "Unknown option: $1" ;;
    esac
    shift
done

out_file="$(find "$SLURM_LOG_DIR" -name "*_${jobid}.out" 2>/dev/null | head -1)"
err_file="$(find "$SLURM_LOG_DIR" -name "*_${jobid}.err" 2>/dev/null | head -1)"

[[ -n "$out_file" || -n "$err_file" ]] || die "No log files found for job $jobid in $SLURM_LOG_DIR"

case "$STREAM" in
    out)  files=("$out_file") ;;
    err)  files=("$err_file") ;;
    both) files=("$out_file" "$err_file") ;;
esac

# Filter to existing files
existing=()
for f in "${files[@]}"; do
    [[ -f "$f" ]] && existing+=("$f")
done

if [[ "$MODE" == "once" ]]; then
    for f in "${existing[@]}"; do
        echo "===== $f ====="
        cat "$f"
        echo
    done
else
    msg "Tailing: ${existing[*]}"
    msg "(Ctrl+C to stop tailing — does NOT kill the job)"
    tail -n 50 -f "${existing[@]}"
fi
