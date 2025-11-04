#!/usr/bin/env zsh
export $(cat "$HOME/dotfiles/.env" | xargs)

state_file="/tmp/myscript_start"

case "$1" in
start)
  if [[ -e $state_file ]]; then
    echo "Already started!"
    exit 1
  fi
  date +%s >"$state_file"
  echo "Started at: $(date -d @$(cat "$state_file"))"
  exit 0
  ;;
stop)
  if [[ ! -e $state_file ]]; then
    echo "Not started!"
    exit 1
  fi
  start_time=$(cat "$state_file")
  end_time=$(date +%s)
  rm "$state_file"
  echo "Stopped at: $(date -d @$end_time)"
  echo "Elapsed: $((end_time - start_time))s"
  ;;
toggle)
  if [ -e $state_file ]; then
    "$0" stop # call itself with stop
    exit 0
  else
    "$0" start # call itself with start
    exit 0
  fi
  ;;
*)
  echo "Usage: $0 {start|stop|toggle}"
  exit 1
  ;;
esac

projects=(
  "201000779:Active Listening"
  "201000768:Anki"
  "201000782:Chinese Reading"
  "201000775:Passive Listening"
)

# Build a list for rofi
choices=$(printf "%s\n" "${projects[@]#*:}")

# Show rofi menu
selected=$(echo "$choices" | rofi -dmenu -p "Select Project")

# Exit if nothing selected
[ -z "$selected" ] && exit 1

# Find matching project id
for p in "${projects[@]}"; do
  id="${p%%:*}"
  name="${p#*:}"
  if [[ "$name" == "$selected" ]]; then
    project_id=$id
    break
  fi
done

# Convert start_time to ISO8601 UTC format
start_iso=$(date -u -d @"$start_time" +"%Y-%m-%dT%H:%M:%SZ")
duration=$((end_time - start_time))

# Create time entry and log response
response=$(curl -s -u $TOGGL_API_KEY":api_token" \
  -H "Content-Type: application/json" \
  -d "{
    \"workspace_id\": $TOGGL_WID,
    \"duration\": $duration,
    \"start\": \"$start_iso\",
    \"created_with\": \"rofi\",
    \"project_id\": $project_id
  }" \
  -X POST "https://api.track.toggl.com/api/v9/workspaces/${TOGGL_WID}/time_entries")

echo "$(date): $response" >> /tmp/toggl_responses.log
