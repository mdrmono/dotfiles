#!/usr/bin/env bash

# Get list of paired devices
devices=$(bluetoothctl devices Paired | cut -d' ' -f2-)

# Build a list for rofi
choices=""
while IFS= read -r line; do
    mac=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | cut -d' ' -f2-)
    choices="${choices}${name}\n"
done <<< "$devices"

# Show rofi menu
selected=$(echo -e "$choices" | rofi -dmenu -p "Connect to Bluetooth Device")

# Exit if nothing selected
[ -z "$selected" ] && exit 0

# Find MAC address for selected device
mac_addr=$(bluetoothctl devices Paired | grep "$selected" | awk '{print $2}')

# Connect to the device
if [ -n "$mac_addr" ]; then
    bluetoothctl connect "$mac_addr"
fi
