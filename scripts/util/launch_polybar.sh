#!/bin/bash

# Kill existing polybar instances
killall -q polybar

# Wait until polybar has shut down
while pgrep -x polybar >/dev/null; do sleep 0.1; done

# Get list of connected monitors
monitors=($(xrandr --query | grep " connected" | cut -d" " -f1))

# Get primary monitor
primary=$(xrandr --query | grep " primary" | cut -d" " -f1)

# Launch main bar on primary
if [[ -n "$primary" ]]; then
    MONITOR=$primary polybar main &
else
    # fallback: first monitor if no primary is set
    MONITOR=${monitors[0]} polybar main &
    unset monitors[0]
fi

# Launch secondary bars on the rest
for m in "${monitors[@]}"; do
    [[ "$m" == "$primary" ]] && continue
    MONITOR=$m polybar secondary &
done
