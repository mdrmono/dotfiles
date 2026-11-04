#!/usr/bin/env bash

# Apply the configured pointer behavior to whichever XInput IDs this session
# assigned to the real pointer devices. IDs are not stable across logins.

set -u

pointer_ids=()
for _attempt in {1..20}; do
    pointer_ids=()
    while IFS= read -r device_id; do
        [[ "$device_id" =~ ^[0-9]+$ ]] || continue
        if xinput list-props "$device_id" 2>/dev/null | grep -q 'libinput Accel Profile Enabled'; then
            pointer_ids+=("$device_id")
        fi
    done < <(
        xinput list --short 2>/dev/null |
            awk '/slave[[:space:]]+pointer/ { match($0, /id=[0-9]+/); if (RSTART) print substr($0, RSTART + 3, RLENGTH - 3) }'
    )

    ((${#pointer_ids[@]} > 0)) && break
    sleep 0.25
done

for device_id in "${pointer_ids[@]}"; do
    xinput set-prop "$device_id" "libinput Accel Profile Enabled" 0, 1, 0 >/dev/null 2>&1 || true
    xinput set-prop "$device_id" "libinput Accel Speed" 0.85 >/dev/null 2>&1 || true
done
