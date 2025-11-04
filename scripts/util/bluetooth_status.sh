#!/usr/bin/env bash

# Check if bluetooth is powered on
if bluetoothctl show | grep -q "Powered: yes"; then
    # Get list of connected devices
    connected_devices=$(bluetoothctl devices Connected | wc -l)

    if [ "$connected_devices" -gt 0 ]; then
        # Get the name of the first connected device
        device_name=$(bluetoothctl devices Connected | head -n1 | cut -d' ' -f3-)
        echo "ON ($device_name)"
    else
        echo "ON"
    fi
else
    echo "OFF"
fi
