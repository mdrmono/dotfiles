#!/usr/bin/env bash

set -euo pipefail

direction="${1:---forward}"

case "$direction" in
--forward | --backward) ;;
*)
  printf 'Usage: %s [--forward|--backward]\n' "${0##*/}" >&2
  exit 2
  ;;
esac

if ! fcitx5-remote --check >/dev/null 2>&1; then
  notify-send --urgency=critical "Input method" "fcitx5 is not running"
  exit 1
fi

group="$(fcitx5-remote -q)"

# A newly focused text field may be inactive even when the Chinese group
# was selected elsewhere. Use the same shortcut to enable Pinyin there.
if [[ "$direction" == --forward && "$group" == "Chinese Pinyin" && "$(fcitx5-remote)" == 1 ]]; then
  fcitx5-remote -s pinyin >/dev/null
  fcitx5-remote -o >/dev/null
  exit 0
fi

case "$group" in
Default) current=keyboard-us ;;
"Chinese Pinyin") current=pinyin ;;
"Latin American") current=keyboard-latam ;;
*)
  notify-send --urgency=critical "Input method" "Unknown Fcitx keyboard group" 2>/dev/null || true
  exit 1
  ;;
esac

if [[ "$direction" == --backward ]]; then
  case "$current" in
  keyboard-us) next=keyboard-latam ;;
  keyboard-latam) next=pinyin ;;
  pinyin) next=keyboard-us ;;
  esac
else
  case "$current" in
  keyboard-us) next=pinyin ;;
  pinyin) next=keyboard-latam ;;
  keyboard-latam) next=keyboard-us ;;
  esac
fi

case "$next" in
keyboard-us)
  fcitx5-remote -g Default >/dev/null
  fcitx5-remote -c >/dev/null
  ;;
pinyin)
  fcitx5-remote -g "Chinese Pinyin" >/dev/null
  fcitx5-remote -s pinyin >/dev/null
  fcitx5-remote -o >/dev/null
  ;;
keyboard-latam)
  fcitx5-remote -g "Latin American" >/dev/null
  fcitx5-remote -c >/dev/null
  ;;
*)
  exit 1 ;;
esac
