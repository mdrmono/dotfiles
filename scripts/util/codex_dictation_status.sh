#!/usr/bin/env bash

set -u

state_dir="${XDG_RUNTIME_DIR:-/tmp}/codex-dictation-${UID}"
status_file="${state_dir}/status"
idle_icon=''
active_icon=''

status="$(/usr/bin/head -n 1 "${status_file}" 2>/dev/null || true)"
if [[ "${status}" == "recording" || "${status}" == "transcribing" ]]; then
    status_mtime="$(/usr/bin/stat -c '%Y' "${status_file}" 2>/dev/null || printf '0')"
    now="$(/usr/bin/date +%s)"
    if [[ "${status_mtime}" =~ ^[0-9]+$ && "${now}" =~ ^[0-9]+$ ]] && (( now - status_mtime <= 130 )); then
        printf '%s\n' "%{F#B04027}${active_icon}%{F-}"
        exit 0
    fi
fi

# Keep the disabled microphone visible even when the model or capture service
# is unavailable. The toggle writes status before doing slow startup/IPC work.
printf '%s\n' "%{F#6B7280}${idle_icon}%{F-}"
