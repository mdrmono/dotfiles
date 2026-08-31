#!/usr/bin/env bash

set -u

connected_color='#A9C48C'
transition_color='#89B6BB'
disabled_color='#AAA29A'
icon=''

pia_state=''
pia_protocol=''
warp_connected=false

if command -v piactl >/dev/null 2>&1; then
    pia_state=$(timeout 2 piactl get connectionstate 2>/dev/null || true)

    if [[ "$pia_state" == 'Connected' ]]; then
        pia_protocol=$(timeout 2 piactl get protocol 2>/dev/null || true)
    fi
fi

if command -v warp-cli >/dev/null 2>&1; then
    if timeout 2 warp-cli --accept-tos status 2>/dev/null |
        grep -q '^Status update: Connected$'; then
        warp_connected=true
    fi
fi

if [[ "$pia_state" == 'Connected' ]]; then
    case "$pia_protocol" in
        wireguard) label='VPN WG' ;;
        openvpn) label='VPN OVPN' ;;
        *) label='VPN PIA' ;;
    esac

    if [[ "$warp_connected" == true ]]; then
        label+=' + WARP'
    fi

    color="$connected_color"
elif [[ "$warp_connected" == true ]]; then
    label='VPN WARP'
    color="$connected_color"
elif [[ "$pia_state" =~ ^(Connecting|Reconnecting|DisconnectingToReconnect|Disconnecting)$ ]]; then
    label='VPN ...'
    color="$transition_color"
else
    label='VPN off'
    color="$disabled_color"
fi

printf '%%{F%s}%%{T2}%s%%{T-}%%{F-}  %s\n' "$color" "$icon" "$label"
