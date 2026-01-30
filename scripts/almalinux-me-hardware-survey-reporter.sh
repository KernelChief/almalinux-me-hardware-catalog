#!/usr/bin/env bash
#
# AlmaLinux M&E Hardware Reporting Script
# Copyright (C) 2026
#
# GPLv3
#
# --------------------------------------------------------------------
# SECTION 1: M&E QUICK HARDWARE SURVEY (SAFE / NON-DESTRUCTIVE)
# --------------------------------------------------------------------
# - DOES NOT send any data over the network
# - Collects basic hardware + OS details
# - Writes a local JSON file
# - User manually submits JSON to GitHub
#
# SECTION 2: OPTIONAL CERTIFICATION SIG SCAN (DESTRUCTIVE / OPT-IN)
# --------------------------------------------------------------------
# - VERY HEAVY system load
# - Uses benchmarks (Phoronix)
# - Sends results upstream automatically
# - Requires explicit user confirmation
# --------------------------------------------------------------------

set -euo pipefail

VERSION="1.3"
OUTPUT_FILE_JSON="almalinux_me_report.json"

if [ -n "${XDG_CONFIG_HOME:-}" ]; then
  REPORT_ID_FILE_DEFAULT="$XDG_CONFIG_HOME/almalinux-me-hardware-survey/report_id"
else
  REPORT_ID_FILE_DEFAULT="${HOME:-/tmp}/.config/almalinux-me-hardware-survey/report_id"
fi
REPORT_ID_FILE="${REPORT_ID_FILE:-$REPORT_ID_FILE_DEFAULT}"

persist_report_id() {
  local target="$1"
  local dir
  dir="$(dirname "$target")"
  if mkdir -p "$dir" 2>/dev/null; then
    (umask 077 && printf "%s" "$REPORT_ID" > "$target") 2>/dev/null || return 1
    return 0
  fi
  return 1
}

if [ -f "$REPORT_ID_FILE" ]; then
  REPORT_ID="$(tr -d '\n' < "$REPORT_ID_FILE")"
else
  REPORT_ID="$(echo "$(date +%s%N)-$RANDOM-$$" | md5sum | awk '{print $1}' | head -c 8)"
  if ! persist_report_id "$REPORT_ID_FILE"; then
    REPORT_ID_FILE="$PWD/.almalinux-me-hardware-survey-report-id"
    persist_report_id "$REPORT_ID_FILE" || true
  fi
fi

# ==============================================================
# Helpers (shared)
# ==============================================================

have_cmd() { command -v "$1" >/dev/null 2>&1; }

die() {
  echo "❌ $*" >&2
  exit 1
}

json_escape() {
  python3 - "$1" <<'PY'
import json,sys
print(json.dumps(sys.argv[1])[1:-1])
PY
}

prompt_yes_no() {
  local ans
  read -r -p "$1 [y/N]: " ans
  [[ "${ans,,}" =~ ^y(es)?$ ]]
}

# ==============================================================
# SECTION 1 — M&E QUICK HARDWARE SURVEY
# ==============================================================

echo "======================================================="
echo " AlmaLinux M&E Hardware Survey (Quick / Safe)"
echo "======================================================="
echo "Report ID: $REPORT_ID"
echo "Report ID file: $REPORT_ID_FILE"
echo

# ---- dependency check (survey only) ----
missing=0
for cmd in lspci free uname nproc python3 awk grep cut tr xargs md5sum; do
  if ! have_cmd "$cmd"; then
    echo "❌ Missing required command: $cmd"
    missing=1
  fi
done

# dmidecode is optional now (we'll still produce JSON without module list)
if ! have_cmd dmidecode; then
  echo "⚠️ dmidecode not found: memory module details will be skipped."
fi

if [ "$missing" -eq 1 ]; then
  echo
  echo "Install on Alma/RHEL with:"
  echo "  sudo dnf install -y pciutils python3"
  echo "Optional (for memory module details):"
  echo "  sudo dnf install -y dmidecode"
  exit 1
fi

read -r -p "Any notes (bugs, performance, 'all good')?: " USER_NOTES
echo

# ---- OS ----
if [ -r /etc/os-release ]; then
  OS_NAME="$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')"
else
  OS_NAME="Unknown"
fi

# ---- CPU ----
CPU_MODEL="$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | xargs || true)"
CPU_CORES="$(nproc)"

# ---- Memory totals ----
MEM_TOTAL_GB="$(free -g | awk '/^Mem:/{print $2}' || echo "")"

# ---- Memory modules (optional; no sudo required, will attempt sudo if allowed) ----
MEM_MODULES=""
if have_cmd dmidecode; then
  DMIDECODE_OUT=""
  if sudo -n true >/dev/null 2>&1; then
    DMIDECODE_OUT="$(sudo dmidecode -t 17 2>/dev/null || true)"
  else
    # Try without sudo (will often fail); don't stop the survey if it fails
    DMIDECODE_OUT="$(dmidecode -t 17 2>/dev/null || true)"
  fi

  if [ -n "$DMIDECODE_OUT" ]; then
    MEM_MODULES="$(printf "%s" "$DMIDECODE_OUT" | awk '
      /Size: [0-9]/ { s=$2" "$3 }
      /Speed: [0-9]/ { sp=$2" "$3 }
      /Manufacturer:/ { m=$2 }
      /Configured Memory Speed:/ { cs=$4" "$5 }
      /Locator:/ {
        if(s!=""){
          if(found) printf ",\n";
          printf "    {\"size\":\"%s\",\"speed\":\"%s\",\"configured_speed\":\"%s\",\"manufacturer\":\"%s\"}", s, sp, cs, m;
          found=1; s=""; sp=""; cs=""; m=""
        }
      }'
    )"
  else
    echo "⚠️ Could not read memory module details (dmidecode requires sudo on most systems)."
  fi
fi

# ---- GPU ----
GPU_JSON=""
while read -r line; do
  SLOT="${line%% *}"
  NAME="$(echo "$line" | cut -d: -f3- | xargs)"
  DRIVER="$(lspci -nnk -s "$SLOT" 2>/dev/null | grep -m1 'Kernel driver in use' | cut -d: -f2- | xargs || true)"
  [ -n "$GPU_JSON" ] && GPU_JSON+=","
  GPU_JSON+=" {\"device\":\"$(json_escape "$NAME")\",\"driver\":\"$(json_escape "$DRIVER")\"}"
done < <(lspci 2>/dev/null | grep -E "VGA|3D|Display" || true)

# ---- Storage ----
STORAGE_JSON="$(
lspci 2>/dev/null | grep -i storage | while read -r l; do
  DEV="$(echo "$l" | cut -d: -f3- | xargs)"
  printf "    {\"device\":\"%s\"}\n" "$(json_escape "$DEV")"
done | paste -sd "," - || true
)"

# ---- Write JSON (always valid) ----
cat > "$OUTPUT_FILE_JSON" <<EOF
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
    "model": "$(json_escape "$CPU_MODEL")",
    "cores": "$CPU_CORES"
  },
  "memory": {
    "total_gb": "$(json_escape "$MEM_TOTAL_GB")",
    "modules": [ ${MEM_MODULES} ]
  },
  "graphics": [ ${GPU_JSON} ],
  "storage_controllers": [
${STORAGE_JSON}
  ]
}
EOF

echo "✅ M&E survey complete."
echo "File written: $OUTPUT_FILE_JSON"
echo
echo "SUBMISSION INSTRUCTIONS (Manual - easy):"
echo "1. Open the issue form:"
echo "   https://github.com/KernelChief/almalinux-me-hardware-catalog/issues/new?template=hardware_report.yml"
echo "2. Title the issue with your Report ID:"
echo "   $REPORT_ID"
echo "3. Paste the full JSON from:"
echo "   $OUTPUT_FILE_JSON"
if have_cmd wl-copy; then
  echo "Tip (Wayland): cat $OUTPUT_FILE_JSON | wl-copy"
elif have_cmd xclip; then
  echo "Tip (X11): cat $OUTPUT_FILE_JSON | xclip -selection clipboard"
else
  echo "Tip: You can view the file with: cat $OUTPUT_FILE_JSON"
fi
echo

# ==============================================================
# SECTION 2 — CERTIFICATION SIG (OPTIONAL / DESTRUCTIVE)
# ==============================================================

echo "======================================================="
echo " AlmaLinux Hardware Certification (OPTIONAL)"
echo "======================================================="
echo "⚠️  WARNING:"
echo "This will heavily stress the system and may make it unusable"
echo "for the duration of the benchmarks."
echo
echo "Results WILL be sent automatically to the AlmaLinux"
echo "Hardware Certification SIG."
echo
echo "More info:"
echo "https://github.com/AlmaLinux/Hardware-Certification-Suite"
echo

if ! prompt_yes_no "Run Certification SIG benchmarks now"; then
  echo "Certification skipped. Exiting."
  exit 0
fi

echo
echo "Proceeding with Certification SIG scan..."
echo

sudo dnf install -y git-core tmux python3 python3-pip

WORKDIR="$PWD"
SUITE_DIR="$WORKDIR/Hardware-Certification-Suite"

[ -d "$SUITE_DIR" ] || git clone https://github.com/AlmaLinux/Hardware-Certification-Suite.git "$SUITE_DIR"

python3 -m venv venv
# shellcheck disable=SC1091
source venv/bin/activate
pip install --upgrade pip ansible

cd "$SUITE_DIR"

SESSION="almalinux-certification-tests"
CMD="ansible-playbook -c local -i 127.0.0.1, automated.yml --tags=phoronix"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "tmux session already running: $SESSION"
  echo "Attach with: tmux attach -t $SESSION"
else
  tmux new-session -d -s "$SESSION" "$CMD; echo; echo 'Done. Press Enter to exit.'; read -r"
  echo "Certification started in tmux session: $SESSION"
  echo "Attach with: tmux attach -t $SESSION"
fi
