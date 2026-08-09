#!/usr/bin/env bash

set -u

active_icon=''
idle_icon=''
active_color='#B04027'
idle_color='#3C7B82'
disabled_color='#6E6863'
event_fifo="${XDG_RUNTIME_DIR:-/tmp}/openwhispr-status-${UID}.fifo"
lock_file="${event_fifo}.lock"

cleanup() {
    if [[ -n "${pulse_events_pid:-}" ]]; then
        kill "${pulse_events_pid}" 2>/dev/null || true
        wait "${pulse_events_pid}" 2>/dev/null || true
    fi
    /usr/bin/rm -f "${event_fifo}"
}

exec {event_lock_fd}>"${lock_file}"
/home/linuxbrew/.linuxbrew/bin/flock -n "${event_lock_fd}" || exit 0

if [[ -e "${event_fifo}" && ! -p "${event_fifo}" ]]; then
    exit 1
fi

/usr/bin/rm -f "${event_fifo}"
/usr/bin/mkfifo -m 600 "${event_fifo}"

trap cleanup EXIT INT TERM

emit_status() {
    if ! /usr/bin/pgrep -x open-whispr-app >/dev/null 2>&1; then
        printf '%%{F%s}%s%%{F-}\n' "${disabled_color}" "${idle_icon}"
        return
    fi

    # OpenWhispr exposes a PulseAudio-compatible source-output through PipeWire
    # only while it is recording. Match the packaged binary or application name
    # so another app using the microphone cannot turn this indicator red.
    if /home/linuxbrew/.linuxbrew/bin/pactl list source-outputs 2>/dev/null |
        /usr/bin/awk '
            BEGIN { RS = "Source Output #" }
            /application\.process\.binary = "open-whispr-app"/ ||
            /application\.process\.binary = "open-whispr"/ ||
            /application\.name = "OpenWhispr"/ {
                found = 1
            }
            END { exit found ? 0 : 1 }
        '; then
        printf '%%{F%s}%s%%{F-}\n' "${active_color}" "${active_icon}"
    else
        printf '%%{F%s}%s%%{F-}\n' "${idle_color}" "${idle_icon}"
    fi
}

publish_pulse_events() {
    local attempt
    local event
    local subscription_fd
    local subscription_input_fd
    local subscription_pid=''
    local subscription_ready

    stop_pulse_subscription() {
        if [[ -n "${subscription_pid:-}" ]]; then
            kill "${subscription_pid}" 2>/dev/null || true
            wait "${subscription_pid}" 2>/dev/null || true
            subscription_pid=''
        fi
    }

    trap stop_pulse_subscription EXIT
    trap 'exit 0' INT TERM

    while true; do
        coproc PULSE_SUBSCRIPTION {
            export LC_ALL=C
            exec /home/linuxbrew/.linuxbrew/bin/pactl subscribe 2>/dev/null
        }
        subscription_fd="${PULSE_SUBSCRIPTION[0]}"
        subscription_input_fd="${PULSE_SUBSCRIPTION[1]}"
        subscription_pid="${PULSE_SUBSCRIPTION_PID}"
        exec {subscription_input_fd}>&- 2>/dev/null || true
        subscription_ready=false

        # The subscription has no ready marker. A short-lived pactl client
        # generates an event that confirms this subscriber is receiving data;
        # only then is it safe to resynchronize after the startup window.
        for ((attempt = 0; attempt < 20; attempt++)); do
            /usr/bin/timeout 0.2 \
                /home/linuxbrew/.linuxbrew/bin/pactl info >/dev/null 2>&1 || true
            if IFS= read -r -t 0.1 event <&"${subscription_fd}"; then
                subscription_ready=true
                break
            fi
            if ! kill -0 "${subscription_pid}" 2>/dev/null; then
                break
            fi
        done

        if [[ "${subscription_ready}" == true ]]; then
            printf 'resync\n'
            case "${event}" in
                *' on source-output #'*) printf 'pulse\n' ;;
            esac

            while IFS= read -r event <&"${subscription_fd}"; do
                case "${event}" in
                    *' on source-output #'*) printf 'pulse\n' ;;
                esac
            done
        fi

        exec {subscription_fd}<&- 2>/dev/null || true
        stop_pulse_subscription
        /usr/bin/sleep 2
    done
}

emit_status

publish_pulse_events >"${event_fifo}" &
pulse_events_pid=$!

while IFS= read -r _; do
    /usr/bin/sleep 0.1
    emit_status
done <"${event_fifo}"
