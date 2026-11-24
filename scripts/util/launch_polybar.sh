#!/bin/bash

# A connected output can be disabled. Start bars only on active monitors.
monitor_state=$(xrandr --listactivemonitors) || exit 1
mapfile -t monitors < <(awk 'NR > 1 {print $NF}' <<< "$monitor_state")
if [ "${#monitors[@]}" -eq 0 ]; then
    echo "No active monitors for Polybar" >&2
    exit 1
fi
primary=$(awk 'NR > 1 && $2 ~ /\*/ {print $NF; exit}' <<< "$monitor_state")
primary=${primary:-${monitors[0]}}

# Kill existing polybar instances
killall -q polybar

# Wait until polybar has shut down
while pgrep -x polybar >/dev/null; do sleep 0.1; done

MONITOR=$primary polybar main &

# Launch secondary bars on the rest
for m in "${monitors[@]}"; do
    [[ "$m" == "$primary" ]] && continue
    MONITOR=$m polybar secondary &
done
