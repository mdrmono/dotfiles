#!/usr/bin/env bash

# Check if Bluetooth is powered on.
if ! bluetoothctl show | grep -q "Powered: yes"; then
    echo "OFF"
    exit 0
fi

# Show the first connected device and its battery level, when BlueZ exposes it.
connected_device=$(bluetoothctl devices Connected | head -n1)

if [ -z "$connected_device" ]; then
    echo "ON"
    exit 0
fi

mac_address=$(printf '%s\n' "$connected_device" | cut -d' ' -f2)
device_name=$(printf '%s\n' "$connected_device" | cut -d' ' -f3-)
battery_percentage=$(
    bluetoothctl info "$mac_address" |
        sed -n 's/^[[:space:]]*Battery Percentage:.*(\([0-9][0-9]*\)).*/\1/p' |
        head -n1
)

if [ -n "$battery_percentage" ]; then
    echo "ON ($device_name, $battery_percentage%)"
else
    echo "ON ($device_name)"
fi
