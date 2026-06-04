#!/usr/bin/env bash
# _setup_tunnel.sh — Print the SSH tunnel command for a running interactive job.
#
# Usage:
#   ./scripts/_setup_tunnel.sh <jobid>
#
# Use this when you closed the terminal after run_rstudio.sh / run_jupyter.sh
# and need to re-read the tunnel command, or to copy it to a different Mac.

source "$(dirname "$0")/_common.sh"

[[ $# -ge 1 ]] || die "Usage: $0 <jobid>"
jobid="$1"

# Verify the job is still alive
state="$(squeue -h -j "$jobid" -o '%T' 2>/dev/null | tr -d ' ')"
[[ -n "$state" ]] || die "Job $jobid is not in the queue (already finished or cancelled)"
[[ "$state" == "RUNNING" ]] || die "Job $jobid is in state '$state', not RUNNING"

# Find the matching tunnel file
tunnel_file="$(find "$PROJECT_ROOT/.tunnel" -name "*.${jobid}" 2>/dev/null | head -1)"
[[ -f "$tunnel_file" ]] || die "No tunnel info for job $jobid (was it started by run_rstudio.sh or run_jupyter.sh?)"

# Determine the kind (rstudio / jupyter) from filename
kind="$(basename "$tunnel_file" | cut -d. -f1)"

# Find the matching local port from .env
port_var="$(echo "${kind}_PORT" | tr '[:lower:]' '[:upper:]')"
local_port="${!port_var:-8800}"

# shellcheck disable=SC1090
source "$tunnel_file"

msg "Tunnel info for $kind job $jobid:"
msg "  Compute node: $NODE"
msg "  Remote port:  $PORT"
msg "  Local port:   $local_port"

print_tunnel_command "$local_port" "$NODE" "$PORT"
