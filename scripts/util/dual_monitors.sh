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

# Reorder monitors array to put laptop display first if it exists
LAPTOP_DISPLAY=$(get_laptop_display)
if [ -n "$LAPTOP_DISPLAY" ]; then
  # Create new array with laptop display first
  REORDERED=("$LAPTOP_DISPLAY")
  for mon in "${MONITORS[@]}"; do
    if [ "$mon" != "$LAPTOP_DISPLAY" ]; then
      REORDERED+=("$mon")
    fi
  done
  MONITORS=("${REORDERED[@]}")
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

  mode_rate0=$(get_highest_mode "${MONITORS[0]}")
  mode_rate1=$(get_highest_mode "${MONITORS[1]}")

  if [ -z "$mode_rate0" ] || [ -z "$mode_rate1" ]; then
    echo "Error: Could not determine best modes for monitors"
    exit 1
  fi

  set -- $mode_rate0
  echo "Setting ${MONITORS[0]} (primary) to mode $1 at ${2}Hz"
  xrandr --output "${MONITORS[0]}" --primary --mode "$1" --rate "$2"

  set -- $mode_rate1
  echo "Setting ${MONITORS[1]} to mode $1 at ${2}Hz (right of ${MONITORS[0]})"
  xrandr --output "${MONITORS[1]}" --mode "$1" --rate "$2" --right-of "${MONITORS[0]}"

else
  echo "Setting up ${#MONITORS[@]} monitors"

  mode_rate0=$(get_highest_mode "${MONITORS[0]}")
  if [ -z "$mode_rate0" ]; then
    echo "Error: Could not determine best mode for primary monitor ${MONITORS[0]}"
    exit 1
  fi

  set -- $mode_rate0
  echo "Setting ${MONITORS[0]} (primary) to mode $1 at ${2}Hz"
  xrandr --output "${MONITORS[0]}" --primary --mode "$1" --rate "$2"

  PREV="${MONITORS[0]}"
  for MON in "${MONITORS[@]:1}"; do
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
