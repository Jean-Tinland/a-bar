#!/usr/bin/env bash

# World Clock — a-bar custom widget example
#
# Demonstrates the full xbar output format:
#   • Multiple header lines (cycled in the bar)
#   • --- separator before the dropdown menu
#   • Submenu items (-- prefix)
#   • Color coding based on business hours
#   • href= to open timezone info links
#   • shell= + refresh= to copy the time to the clipboard
#   • disabled= for non-interactive labels
#   • length= for capping text width
#
# SETUP
#   1. Make executable:  chmod +x world-clock.sh
#   2. In a-bar Settings → Custom Widgets, add a new widget.
#   3. Set the command to the full path of this script, e.g.:
#        bash /path/to/world-clock.sh
#   4. Set Refresh interval to 60 (seconds) and Cycle duration to 4.
# ──────────────────────────────────────────────────────────────────────────────

# Timezone : Display label pairs — edit freely
ZONES=(
  "America/New_York:New York"
  "Europe/London:London"
  "Europe/Paris:Paris"
  "Asia/Tokyo:Tokyo"
  "Australia/Sydney:Sydney"
)

# ── Header lines (cycle in the bar) ──────────────────────────────────────────
# Each line is displayed in turn according to the widget's Cycle Duration.
for entry in "${ZONES[@]}"; do
  tz="${entry%%:*}"
  city="${entry##*:}"
  time=$(TZ="$tz" date "+%H:%M")
  echo "🌍 $city $time"
done

echo "---"

# ── Dropdown menu ─────────────────────────────────────────────────────────────

echo "World Clock | disabled=true color=#888888"
echo "---"

for entry in "${ZONES[@]}"; do
  tz="${entry%%:*}"
  city="${entry##*:}"
  time=$(TZ="$tz" date "+%H:%M")
  day=$(TZ="$tz" date "+%a %d %b")
  offset=$(TZ="$tz" date "+%Z (UTC%z)")
  hour=$(TZ="$tz" date "+%H")

  # Color: green = business hours, orange = evening, blue = night
  if [ "$hour" -ge 9 ] && [ "$hour" -lt 18 ]; then
    color="#4CAF50"
  elif [ "$hour" -ge 18 ] && [ "$hour" -lt 22 ]; then
    color="#FF9800"
  else
    color="#5C6BC0"
  fi

  # Top-level entry: city + time, color-coded
  echo "$city  $time | color=$color"

  # Sub-menu: date
  echo "--📅 $day | disabled=true"

  # Sub-menu: timezone info (links to worldtimeapi.org)
  echo "--🌐 $offset | disabled=true"

  # Sub-menu: copy time string to clipboard (shell= runs silently, refresh=false)
  echo "--Copy to clipboard | shell=/bin/bash param1=-c param2=\"echo -n '${city}: ${time}' | pbcopy\" terminal=false refresh=false"

  echo "---"
done

echo "---"

# Refresh the widget
echo "⟳ Refresh | key=CmdOrCtrl+R | refresh=true"
