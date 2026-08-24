#!/usr/bin/env bash

set -euo pipefail

scrot --freeze --select --format png --file - | xclip -selection clipboard -t image/png -i
