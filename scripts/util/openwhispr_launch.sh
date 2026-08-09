#!/usr/bin/env bash

set -euo pipefail

cuda_lib_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/openwhispr/cuda-12-runtime/usr/lib/x86_64-linux-gnu"
event_fifo="${XDG_RUNTIME_DIR:-/tmp}/openwhispr-status-${UID}.fifo"

notify_status() {
    if [[ -p "${event_fifo}" ]]; then
        printf 'lifecycle\n' |
            /usr/bin/timeout 0.2 /usr/bin/tee "${event_fifo}" >/dev/null 2>&1 || true
    fi
}

openwhispr_is_running() {
    /usr/bin/pgrep -x open-whispr-app >/dev/null 2>&1
}

if [[ -d "${cuda_lib_dir}" ]]; then
    if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
        export LD_LIBRARY_PATH="${cuda_lib_dir}:${LD_LIBRARY_PATH}"
    else
        export LD_LIBRARY_PATH="${cuda_lib_dir}"
    fi
fi

/opt/OpenWhispr/open-whispr "$@" &
openwhispr_pid=$!

while kill -0 "${openwhispr_pid}" 2>/dev/null; do
    if openwhispr_is_running; then
        notify_status
        break
    fi
    /usr/bin/sleep 0.05
done

set +e
wait "${openwhispr_pid}"
exit_code=$?
set -e

notify_status
exit "${exit_code}"
