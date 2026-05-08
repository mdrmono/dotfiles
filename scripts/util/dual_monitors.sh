#!/usr/bin/env bash

# Turn off all disconnected monitors first
DISCONNECTED=($(xrandr --query | grep " disconnected" | cut -d" " -f1))
for MON in "${DISCONNECTED[@]}"; do
  echo "Disabling disconnected monitor: $MON"
  xrandr --output "$MON" --off
done

# Detect connected monitors
MONITORS=($(xrandr --query | grep " connected" | cut -d" " -f1))

# Function to identify laptop's built-in display
get_laptop_display() {
  for mon in "${MONITORS[@]}"; do
    # Common names for laptop built-in displays
    if [[ "$mon" =~ ^(eDP|LVDS|DSI) ]]; then
      echo "$mon"
      return 0
    fi
  done
  return 1
}

# Prefer an external display as primary, keeping the laptop display to its left.
LAPTOP_DISPLAY=$(get_laptop_display)
PRIMARY_DISPLAY="${MONITORS[0]}"
if [ -n "$LAPTOP_DISPLAY" ] && [ ${#MONITORS[@]} -gt 1 ]; then
  for mon in "${MONITORS[@]}"; do
    if [ "$mon" != "$LAPTOP_DISPLAY" ]; then
      PRIMARY_DISPLAY="$mon"
      break
    fi
  done
fi

get_highest_mode() {
  local MON=$1
  local best_mode=""
  local max_rate=0

  # Get all modes for this monitor and find the one with highest refresh rate
  xrandr --query | awk -v mon="$MON" '
        BEGIN { in_monitor=0; max_rate=0; best_mode="" }
        
        # Start of monitor section
        $0 ~ mon" connected" { 
            in_monitor=1
            next 
        }
        
        # End of monitor section (next monitor or end)
        in_monitor && /^[A-Za-z]/ && $0 !~ mon { 
            in_monitor=0 
        }
        
        # Parse mode lines (they start with spaces and have resolution)
        in_monitor && /^[[:space:]]+[0-9]+x[0-9]+/ {
            resolution = $1
            
            # Parse all refresh rates on this line
            for (i = 2; i <= NF; i++) {
                rate = $i
                # Remove any non-numeric characters except decimal point
                gsub(/[^0-9.]/, "", rate)
                
                # Skip empty strings or invalid rates
                if (rate == "" || rate == 0) continue
                
                # Convert to number and compare
                if (rate + 0 > max_rate + 0) {
                    max_rate = rate
                    best_mode = resolution
                }
            }
        }
        
        END { 
            if (best_mode != "") {
                print best_mode, max_rate
            }
        }
    '
}

# Debug function to show what modes are found
debug_modes() {
  local MON=$1
  echo "Debug: Available modes for $MON:"
  xrandr --query | awk -v mon="$MON" '
        $0 ~ mon" connected" { in_monitor=1; next }
        in_monitor && /^[A-Za-z]/ && $0 !~ mon { in_monitor=0 }
        in_monitor && /^[[:space:]]+[0-9]+x[0-9]+/ { print "  " $0 }
    '
}

# Main logic
if [ ${#MONITORS[@]} -eq 0 ]; then
  echo "No monitors detected!"
  exit 1
fi

echo "Detected monitors: ${MONITORS[*]}"

if [ ${#MONITORS[@]} -eq 1 ]; then
  echo "Setting up single monitor: ${MONITORS[0]}"

  # Debug output
  # debug_modes "${MONITORS[0]}"

  mode_rate=$(get_highest_mode "${MONITORS[0]}")
  if [ -z "$mode_rate" ]; then
    echo "Error: Could not determine best mode for ${MONITORS[0]}"
    exit 1
  fi

  set -- $mode_rate
  echo "Setting ${MONITORS[0]} to mode $1 at ${2}Hz"
  xrandr --output "${MONITORS[0]}" --mode "$1" --rate "$2"

elif [ ${#MONITORS[@]} -eq 2 ]; then
  echo "Setting up dual monitors"

  if [ -n "$LAPTOP_DISPLAY" ] && [ "$PRIMARY_DISPLAY" != "$LAPTOP_DISPLAY" ]; then
    SECONDARY_DISPLAY="$LAPTOP_DISPLAY"
  else
    for mon in "${MONITORS[@]}"; do
      if [ "$mon" != "$PRIMARY_DISPLAY" ]; then
        SECONDARY_DISPLAY="$mon"
        break
      fi
    done
  fi

  mode_rate0=$(get_highest_mode "$PRIMARY_DISPLAY")
  mode_rate1=$(get_highest_mode "$SECONDARY_DISPLAY")

  if [ -z "$mode_rate0" ] || [ -z "$mode_rate1" ]; then
    echo "Error: Could not determine best modes for monitors"
    exit 1
  fi

  set -- $mode_rate0
  echo "Setting $PRIMARY_DISPLAY (primary) to mode $1 at ${2}Hz"
  xrandr --output "$PRIMARY_DISPLAY" --primary --mode "$1" --rate "$2"

  set -- $mode_rate1
  if [ "$SECONDARY_DISPLAY" = "$LAPTOP_DISPLAY" ]; then
    echo "Setting $SECONDARY_DISPLAY to mode $1 at ${2}Hz (left of $PRIMARY_DISPLAY)"
    xrandr --output "$SECONDARY_DISPLAY" --mode "$1" --rate "$2" --left-of "$PRIMARY_DISPLAY"
  else
    echo "Setting $SECONDARY_DISPLAY to mode $1 at ${2}Hz (right of $PRIMARY_DISPLAY)"
    xrandr --output "$SECONDARY_DISPLAY" --mode "$1" --rate "$2" --right-of "$PRIMARY_DISPLAY"
  fi

else
  echo "Setting up ${#MONITORS[@]} monitors"

  mode_rate0=$(get_highest_mode "$PRIMARY_DISPLAY")
  if [ -z "$mode_rate0" ]; then
    echo "Error: Could not determine best mode for primary monitor $PRIMARY_DISPLAY"
    exit 1
  fi

  set -- $mode_rate0
  echo "Setting $PRIMARY_DISPLAY (primary) to mode $1 at ${2}Hz"
  xrandr --output "$PRIMARY_DISPLAY" --primary --mode "$1" --rate "$2"

  if [ -n "$LAPTOP_DISPLAY" ] && [ "$LAPTOP_DISPLAY" != "$PRIMARY_DISPLAY" ]; then
    mode_rate=$(get_highest_mode "$LAPTOP_DISPLAY")
    if [ -n "$mode_rate" ]; then
      set -- $mode_rate
      echo "Setting $LAPTOP_DISPLAY to mode $1 at ${2}Hz (left of $PRIMARY_DISPLAY)"
      xrandr --output "$LAPTOP_DISPLAY" --mode "$1" --rate "$2" --left-of "$PRIMARY_DISPLAY"
    else
      echo "Warning: Could not determine best mode for $LAPTOP_DISPLAY, skipping"
    fi
  fi

  PREV="$PRIMARY_DISPLAY"
  for MON in "${MONITORS[@]}"; do
    if [ "$MON" = "$PRIMARY_DISPLAY" ] || [ "$MON" = "$LAPTOP_DISPLAY" ]; then
      continue
    fi

    mode_rate=$(get_highest_mode "$MON")
    if [ -z "$mode_rate" ]; then
      echo "Warning: Could not determine best mode for $MON, skipping"
      continue
    fi

    set -- $mode_rate
    echo "Setting $MON to mode $1 at ${2}Hz (right of $PREV)"
    xrandr --output "$MON" --mode "$1" --rate "$2" --right-of "$PREV"
    PREV="$MON"
  done
fi

echo "Monitor setup complete!"
