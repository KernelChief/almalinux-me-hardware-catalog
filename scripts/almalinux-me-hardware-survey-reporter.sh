#!/usr/bin/env bash
#
# AlmaLinux M&E Hardware Reporting Script v1.0
# Copyright (C) 2026
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# --------------------------------------------------------------------
# What this script does:
# - DOES NOT send any data over the network
# - Collects local hardware + OS details and writes a local JSON report
# - You manually submit the JSON to GitHub (PR approval gate recommended)
# --------------------------------------------------------------------

set -euo pipefail

VERSION="1.0"
OUTPUT_FILE="almalinux_me_report.json"

# Stable-ish ID: hostname + epoch + random, hashed down
REPORT_ID="$(echo "${HOSTNAME:-unknown}-$(date +%s)-$RANDOM" | md5sum | awk '{print $1}' | head -c 8)"

# -------- helpers --------

have_cmd() { command -v "$1" >/dev/null 2>&1; }

json_escape() {
  # Escapes a string for JSON value context (without surrounding quotes)
  # Uses Python's json.dumps for correctness.
  python3 - "$1" <<'PY'
import json,sys
s=sys.argv[1]
print(json.dumps(s)[1:-1])
PY
}

require_deps() {
  local missing=0

  for cmd in lspci lshw dmidecode free uname nproc awk grep cut tr xargs md5sum; do
    if ! have_cmd "$cmd"; then
      echo "❌ Missing required command: $cmd"
      missing=1
    fi
  done

  if ! have_cmd python3; then
    echo "❌ Missing required command: python3"
    missing=1
  fi

  if [ "$missing" -eq 1 ]; then
    echo
    echo "Please install missing dependencies and re-run."
    echo "On Alma/RHEL: sudo dnf install -y pciutils lshw dmidecode python3"
    exit 1
  fi
}

get_os_name() {
  if [ -r /etc/os-release ]; then
    local pretty
    pretty="$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')"
    if [ -n "${pretty:-}" ]; then
      echo "$pretty"
      return
    fi
  fi

  if [ -r /etc/almalinux-release ]; then
    cat /etc/almalinux-release
  elif [ -r /etc/redhat-release ]; then
    cat /etc/redhat-release
  else
    echo "Unknown OS"
  fi
}

# -------- main --------

echo "-------------------------------------------------------"
echo "AlmaLinux M&E Hardware Reporting Tool v$VERSION [$REPORT_ID]"
echo "-------------------------------------------------------"

require_deps

read -r -p "Any notes (bugs, performance, 'all good')?: " USER_NOTES

OS_NAME="$(get_os_name)"

# Memory modules via dmidecode (requires sudo)
mem_info=""

if sudo -n true >/dev/null 2>&1; then
  DMIDECODE_CMD=(sudo dmidecode -t 17)
else
  echo
  echo "⚠️ dmidecode typically requires sudo to read memory module details."
  echo "   You'll be prompted for sudo password (if allowed)."
  DMIDECODE_CMD=(sudo dmidecode -t 17)
fi

mem_info="$("${DMIDECODE_CMD[@]}" 2>/dev/null | awk '
  /Size: [0-9]/ { s=$2" "$3 }
  /Speed: [0-9]/ { sp=$2" "$3 }
  /Manufacturer:/ { m=$2 }
  /Configured Memory Speed: [0-9]/ { cs=$4" "$5 }
  /Locator:/ {
    if(s!="") {
      if(found) printf ",\n";
      printf "    {\"size\": \"%s\", \"speed\": \"%s\", \"configured_speed\": \"%s\", \"manufacturer\": \"%s\"}", s, sp, cs, m;
      found=1; s=""; sp=""; cs=""; m="";
    }
  }
' || true)"

mem_info="${mem_info:-}"

# GPU list (escape device + driver)
gpu_json=""
while read -r line; do
  slot="$(echo "$line" | cut -d' ' -f1)"
  name="$(echo "$line" | cut -d: -f3- | xargs)"
  driver="$(lspci -nnk -s "$slot" 2>/dev/null | grep -m1 "Kernel driver in use" | cut -d: -f2- | xargs || true)"

  [ -n "$gpu_json" ] && gpu_json="$gpu_json,"
  gpu_json="$gpu_json {\"device\": \"$(json_escape "$name")\", \"driver\": \"$(json_escape "$driver")\"}"
done < <(lspci 2>/dev/null | grep -E "VGA|3D|Display" || true)

# Storage controllers (escape device)
storage_json="$(
  lspci 2>/dev/null | grep -i "storage" | while read -r line; do
    dev="$(echo "$line" | cut -d: -f3- | xargs)"
    printf "    {\"device\": \"%s\"}\n" "$(json_escape "$dev")"
  done | paste -sd "," - || true
)"

cpu_model="$(grep -m 1 'model name' /proc/cpuinfo | cut -d: -f2- | xargs || true)"
mem_total_gb="$(free -g | awk '/^Mem:/{print $2}' || echo "")"

cat > "$OUTPUT_FILE" <<EOF
{
  "report_id": "$REPORT_ID",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "user_notes": "$(json_escape "$USER_NOTES")",
  "system": {
    "os_release": "$(json_escape "$OS_NAME")",
    "kernel": "$(json_escape "$(uname -r)")",
    "platform": "$(json_escape "$(uname -m)")"
  },
  "processor": {
    "model": "$(json_escape "$cpu_model")",
    "cores": "$(nproc)"
  },
  "memory": {
    "total_gb": "$(json_escape "$mem_total_gb")",
    "modules": [ ${mem_info} ]
  },
  "graphics": [ ${gpu_json} ],
  "storage_controllers": [
${storage_json}
  ]
}
EOF

echo "-------------------------------------------------------"
echo "DONE! Report ID: $REPORT_ID"
echo "File saved to: $OUTPUT_FILE"
echo "-------------------------------------------------------"
echo "SUBMISSION INSTRUCTIONS:"
echo "1. Go to: https://github.com/AlmaLinux/me-sig-workson/issues/new"
echo "2. Select 'Hardware Report Submission'"
echo "3. Use [$REPORT_ID] as the Report ID"
echo "4. Paste the content of $OUTPUT_FILE into the JSON field."
echo "-------------------------------------------------------"
