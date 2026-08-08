#!/usr/bin/env bash

set -u

state_dir="${XDG_RUNTIME_DIR:-/tmp}/codex-dictation-${UID}"
status_file="${state_dir}/status"
capture_socket="${state_dir}/capture.sock"
capture_client="${HOME}/.local/bin/codex-dictation-capture-client.js"
idle_icon=''
active_icon=''

status_line="$(/usr/bin/head -n 1 "${status_file}" 2>/dev/null || true)"
status="${status_line%% *}"
session_pid="${status_line#* }"

print_active() {
    printf '%s\n' "%{F#B04027}${active_icon}%{F-}"
    exit 0
}

if [[ "${status}" == "recording" ]]; then
    status_mtime="$(/usr/bin/stat -c '%Y' "${status_file}" 2>/dev/null || printf '0')"
    now="$(/usr/bin/date +%s)"
    if [[ "${status_mtime}" =~ ^[0-9]+$ && "${now}" =~ ^[0-9]+$ ]] && (( now - status_mtime <= 15 )); then
        print_active
    fi
    capture_state="$(/usr/bin/timeout 0.3 env CODEX_DICTATION_CAPTURE_TIMEOUT_MS=150 \
        /usr/bin/node "${capture_client}" "${capture_socket}" status 2>/dev/null || true)"
    if [[ "${capture_state}" == "recording" ]]; then
        print_active
    fi
elif [[ "${status}" == "transcribing" && "${session_pid}" =~ ^[0-9]+$ ]]; then
    if [[ -r "/proc/${session_pid}/cmdline" ]]; then
        process_command="$(/usr/bin/tr '\0' ' ' <"/proc/${session_pid}/cmdline" 2>/dev/null || true)"
        if [[ "${process_command}" == *codex-dictation-toggle* ]]; then
            print_active
        fi
    fi
fi

# Keep the disabled microphone visible even when the model or capture service
# is unavailable. The toggle writes status before doing slow startup/IPC work.
printf '%s\n' "%{F#6B7280}${idle_icon}%{F-}"
