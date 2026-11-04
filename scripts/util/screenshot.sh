#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
temp_dir=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/screenshot.XXXXXX")
full_image="$temp_dir/full.png"
selected_image="$temp_dir/selected.png"
error_file="$temp_dir/scrot.err"

cleanup() {
  rm -f -- "$full_image" "$selected_image" "$error_file"
  rmdir -- "$temp_dir"
}
trap cleanup EXIT

capture_failed() {
  if [[ -s $error_file ]]; then
    cat -- "$error_file" >&2
  fi
  notify-send --urgency=normal -t 4000 "Screenshot failed" "The screen could not be captured."
  exit 1
}

capture_focused_monitor() {
  local geometry
  geometry=$("$script_dir/focused_monitor_geometry.py" 2>"$error_file") || capture_failed
  scrot --autoselect "$geometry" --format png --file "$full_image" 2>"$error_file" || capture_failed
}

if [[ ${1:-} == --monitor && $# == 1 ]]; then
  capture_focused_monitor
  image_to_copy=$full_image
elif [[ ${1:-} == --delayed && $# == 1 ]]; then
  notify-send -t 1200 "Screenshot" "Capture in five seconds; open the dropdown now." >/dev/null 2>&1 || true
  sleep 5
  capture_focused_monitor
  image_to_copy=$full_image
elif (( $# > 0 )); then
  printf 'Usage: %s [--monitor|--delayed]\n' "${0##*/}" >&2
  exit 2
else
  # A dropdown may own the pointer, so save it before starting the selector.
  capture_focused_monitor
  if scrot --freeze --select --format png --file "$selected_image" 2>"$error_file"; then
    image_to_copy=$selected_image
  elif grep -Fq "couldn't grab pointer" "$error_file"; then
    image_to_copy=$full_image
  else
    capture_failed
  fi
fi

if ! "$script_dir/clipboard_image.py" < "$image_to_copy"; then
  notify-send --urgency=normal -t 4000 "Screenshot failed" "The image could not be copied to the clipboard."
  exit 1
fi

if [[ ${1:-} == --delayed || ${1:-} == --monitor ]]; then
  notify-send -t 3000 "Screenshot copied" "The image is in the clipboard." >/dev/null 2>&1 || true
fi
