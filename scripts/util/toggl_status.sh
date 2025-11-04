#!/usr/bin/env zsh

state_file="/tmp/myscript_start"

if [[ -e "$state_file" ]]; then
  start_time=$(cat "$state_file")
  current_time=$(date +%s)
  elapsed=$((current_time - start_time))

  # Format elapsed time as HH:MM:SS
  hours=$((elapsed / 3600))
  minutes=$(((elapsed % 3600) / 60))
  seconds=$((elapsed % 60))

  printf "%02d:%02d:%02d" "$hours" "$minutes" "$seconds"
else
  echo "NOT TRACKING"
fi
