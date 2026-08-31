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

state="$(fcitx5-remote)"
current="$(fcitx5-remote -n)"

# An inactive input context always represents the base US keyboard.
if [[ "$state" != "2" ]]; then
  current="keyboard-us"
fi

if [[ "$direction" == "--backward" ]]; then
  case "$current" in
  keyboard-us) next="keyboard-latam" ;;
  keyboard-latam) next="pinyin" ;;
  *) next="keyboard-us" ;;
  esac
else
  case "$current" in
  keyboard-us) next="pinyin" ;;
  pinyin) next="keyboard-latam" ;;
  *) next="keyboard-us" ;;
  esac
fi

if [[ "$next" == "keyboard-us" ]]; then
  fcitx5-remote -c >/dev/null
else
  fcitx5-remote -s "$next" >/dev/null
  fcitx5-remote -o >/dev/null
fi
