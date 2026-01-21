#!/usr/bin/env bash

# Send a notification when battery is low and discharging.
BATTERY_PATH="${BATTERY_PATH:-/sys/class/power_supply/BAT0}"
THRESHOLD="${THRESHOLD:-10}"
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"
COOLDOWN="${COOLDOWN:-900}"
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/battery_alert_state"
PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/battery_alert.pid"

if [ -f "$PID_FILE" ]; then
  existing_pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
  if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
    exit 0
  fi
fi

echo $$ > "$PID_FILE"
trap 'rm -f "$PID_FILE"' EXIT

resolve_battery_path() {
  if [ -d "$BATTERY_PATH" ]; then
    echo "$BATTERY_PATH"
    return 0
  fi

  local found
  found=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n 1)
  if [ -n "$found" ]; then
    echo "$found"
    return 0
  fi

  return 1
}

if ! command -v notify-send >/dev/null 2>&1; then
  exit 0
fi

battery_path=$(resolve_battery_path) || exit 0

while true; do
  if [ ! -d "$battery_path" ]; then
    battery_path=$(resolve_battery_path) || {
      sleep "$CHECK_INTERVAL"
      continue
    }
  fi

  if [ ! -f "$battery_path/capacity" ] || [ ! -f "$battery_path/status" ]; then
    sleep "$CHECK_INTERVAL"
    continue
  fi

  capacity=$(cat "$battery_path/capacity" 2>/dev/null)
  status=$(cat "$battery_path/status" 2>/dev/null)

  if [[ "$capacity" =~ ^[0-9]+$ ]] && [ "$status" = "Discharging" ] && [ "$capacity" -le "$THRESHOLD" ]; then
    now=$(date +%s)
    last=0
    if [ -f "$STATE_FILE" ]; then
      last=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
    fi
    if [ $((now - last)) -ge "$COOLDOWN" ]; then
      notify-send -u critical -a "Battery" "Low battery" "Battery is at ${capacity}%. Plug in your charger."
      echo "$now" > "$STATE_FILE"
    fi
  else
    rm -f "$STATE_FILE" 2>/dev/null || true
  fi

  sleep "$CHECK_INTERVAL"
done
