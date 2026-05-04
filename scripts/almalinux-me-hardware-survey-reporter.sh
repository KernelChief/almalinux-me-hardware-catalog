#!/usr/bin/env bash
#
# AlmaLinux M&E Hardware Reporting Script
# Copyright (C) 2026
#
# GPLv3
#
# --------------------------------------------------------------------
# M&E QUICK HARDWARE SURVEY (SAFE / NON-DESTRUCTIVE)
# --------------------------------------------------------------------
# - DOES NOT send any data over the network
# - Collects basic hardware + OS details
# - Writes a local JSON file
# - User manually submits JSON to GitHub
# --------------------------------------------------------------------

set -euo pipefail

VERSION="1.3"

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN="\e[32m"; BLUE="\e[34m"; PURPLE="\e[35m"; YELLOW="\e[33m"; CYAN="\e[36m"
BOLD="\e[1m"; RESET="\e[0m"
step_ok()  { echo -e "  ${GREEN}✔${RESET} $1"; }
step_run() { echo -ne "  ${CYAN}…${RESET} $1"; }
# TODO: Replace with official AlmaLinux M&E SIG email once assigned
SURVEY_EMAIL="tristan.theroux@pm.me"
# Allow override, but never allow empty.
OUTPUT_FILE_JSON="${OUTPUT_FILE_JSON:-almalinux_me_report.json}"

# If running via curl | bash, stdin is the script itself.
# Re-exec from a temp file so we can read prompts from /dev/tty.
if [ -z "${ALMA_SURVEY_NO_REEXEC:-}" ] && [ ! -t 0 ] && [ -t 1 ]; then
  if [ -r /dev/tty ] && [ -w /dev/tty ]; then
    tmp_script="$(mktemp -t almalinux-me-hardware-survey.XXXXXX)"
    cat > "$tmp_script"
    chmod +x "$tmp_script"
    export ALMA_SURVEY_NO_REEXEC=1
    exec bash "$tmp_script" </dev/tty
  fi
fi

# If the script is piped (curl | bash), stdin is not a TTY.
# Use /dev/tty for prompts so interactive questions still work.
PROMPT_IN=0
PROMPT_OUT=1
# Prefer /dev/tty for prompts when available so we always see them.
if [ -r /dev/tty ] && [ -w /dev/tty ] && { [ -t 0 ] || [ -t 1 ]; }; then
  if exec 3<>/dev/tty; then
    PROMPT_IN=3
    PROMPT_OUT=3
  fi
fi

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
  REPORT_ID="$(echo "$(date +%s%N)-$RANDOM-$$" | md5sum | awk '{print $1}' | head -c 12)"
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

prompt_from_tty() {
  local prompt="$1"
  local ans=""
  # Only prompt when we can write to a terminal.
  if [ "$PROMPT_OUT" -ne 1 ] || [ -t 1 ] || [ -t 0 ]; then
    printf "%s" "$prompt" >&$PROMPT_OUT
    if ! read -r ans <&$PROMPT_IN; then
      ans=""
    fi
  fi
  printf "%s" "$ans"
}

prompt_yes_no() {
  local ans
  ans="$(prompt_from_tty "$1 [y/N]: ")"
  [[ "${ans,,}" =~ ^y(es)?$ ]]
}

# ==============================================================
# SECTION 1 — M&E QUICK HARDWARE SURVEY
# ==============================================================

echo ""
echo -e "${BLUE}${BOLD}  AlmaLinux M&E SIG — Hardware Survey v${VERSION}${RESET}"
echo -e "${BLUE}  ──────────────────────────────────────────────${RESET}"
echo -e "  Privacy-first. No network calls, no hostnames, no IPs."
echo -e "  Report ID : ${PURPLE}${REPORT_ID}${RESET}"
echo -e "  ID file   : ${REPORT_ID_FILE}"
echo ""

# ---- dependency check (survey only) ----
missing=0
for cmd in lspci free uname nproc python3 awk grep cut tr xargs md5sum; do
  if ! have_cmd "$cmd"; then
    echo -e "  ${YELLOW}❌ Missing required command: $cmd${RESET}"
    missing=1
  fi
done

if ! have_cmd dmidecode; then
  echo -e "  ${YELLOW}⚠  dmidecode not found: memory module details will be skipped.${RESET}"
fi

if [ "$missing" -eq 1 ]; then
  echo ""
  echo -e "  ${YELLOW}Install on Alma/RHEL with:${RESET}"
  echo -e "  ${YELLOW}  sudo dnf install -y pciutils python3${RESET}"
  echo -e "  ${YELLOW}Optional: sudo dnf install -y dmidecode${RESET}"
  exit 1
fi

USER_NOTES="$(prompt_from_tty "Any notes (bugs, performance, 'all good')?: ")"
echo

# ---- OS ----
step_run "Collecting OS info...          "
if [ -r /etc/os-release ]; then
  OS_NAME="$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')"
else
  OS_NAME="Unknown"
fi
step_ok ""

# ---- CPU ----
step_run "Collecting CPU info...         "
CPU_MODEL="$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | xargs || true)"
CPU_CORES="$(nproc)"
step_ok ""

# ---- Memory totals ----
step_run "Collecting RAM info...         "
MEM_TOTAL_GB="$(free -g | awk '/^Mem:/{print $2}' || echo "")"
step_ok ""

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
step_run "Collecting GPU info...         "
GPU_JSON=""
while read -r line; do
  SLOT="${line%% *}"
  NAME="$(echo "$line" | cut -d: -f3- | xargs)"
  DRIVER="$(lspci -nnk -s "$SLOT" 2>/dev/null | grep -m1 'Kernel driver in use' | cut -d: -f2- | xargs || true)"
  [ -n "$GPU_JSON" ] && GPU_JSON+=","
  GPU_JSON+=" {\"device\":\"$(json_escape "$NAME")\",\"driver\":\"$(json_escape "$DRIVER")\"}"
done < <(lspci 2>/dev/null | grep -E "VGA|3D|Display" || true)
step_ok ""

# ---- Storage ----
step_run "Collecting storage info...     "
STORAGE_JSON="$(
lspci 2>/dev/null | grep -i storage | while read -r l; do
  DEV="$(echo "$l" | cut -d: -f3- | xargs)"
  printf "    {\"device\":\"%s\"}\n" "$(json_escape "$DEV")"
done | paste -sd "," - || true
)"
step_ok ""
step_run "Writing report...              "


# ---- Output file safety (in case OUTPUT_FILE_JSON is empty) ----
if [ -z "$OUTPUT_FILE_JSON" ]; then
  OUTPUT_FILE_JSON="almalinux_me_report.json"
fi

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

step_ok ""

# ── Preview box ───────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}  ┌──────────────────────────────────────────────┐${RESET}"
echo -e "${BLUE}  │${RESET}  ${BOLD}📋 Report Preview${RESET}"
echo -e "${BLUE}  │${RESET}"
echo -e "${BLUE}  │${RESET}  Report ID : ${PURPLE}${REPORT_ID}${RESET}"
echo -e "${BLUE}  │${RESET}  OS        : ${OS_NAME}"
echo -e "${BLUE}  │${RESET}  CPU       : ${CPU_MODEL} (${CPU_CORES} cores)"
echo -e "${BLUE}  │${RESET}  RAM       : ${MEM_TOTAL_GB} GB"
echo -e "${BLUE}  │${RESET}  File      : ${OUTPUT_FILE_JSON}"
echo -e "${BLUE}  └──────────────────────────────────────────────┘${RESET}"
echo ""

# ── Auto-copy JSON to clipboard ───────────────────────────────────────────────
if have_cmd wl-copy; then
  wl-copy < "$OUTPUT_FILE_JSON"
  echo -e "  ${GREEN}✔ JSON copied to clipboard (Wayland)${RESET}"
elif have_cmd xclip; then
  xclip -selection clipboard < "$OUTPUT_FILE_JSON"
  echo -e "  ${GREEN}✔ JSON copied to clipboard (X11/xclip)${RESET}"
elif have_cmd xsel; then
  xsel --clipboard --input < "$OUTPUT_FILE_JSON"
  echo -e "  ${GREEN}✔ JSON copied to clipboard (X11/xsel)${RESET}"
else
  echo -e "  ${YELLOW}⚠  Clipboard tool not found — paste manually from: ${OUTPUT_FILE_JSON}${RESET}"
fi

# ── Open submission form ──────────────────────────────────────────────────────
ISSUE_URL="https://github.com/KernelChief/almalinux-me-hardware-catalog/issues/new?template=hardware_report.yml"
echo ""
echo -e "  ${GREEN}${BOLD}Opening submission form in your browser...${RESET}"
xdg-open "$ISSUE_URL" 2>/dev/null || true
echo ""
echo -e "${BLUE}  ┌─ Next steps ──────────────────────────────────┐${RESET}"
echo -e "${BLUE}  │${RESET}  1. Enter Report ID : ${PURPLE}${REPORT_ID}${RESET}"
echo -e "${BLUE}  │${RESET}  2. Paste JSON (already in your clipboard)"
echo -e "${BLUE}  │${RESET}  3. Submit — a maintainer will review & merge"
echo -e "${BLUE}  └───────────────────────────────────────────────┘${RESET}"
echo ""

# ── Non-GitHub fallback ───────────────────────────────────────────────────────
echo -e "${YELLOW}  ──────────────────────────────────────────────────${RESET}"
echo -e "${YELLOW}  No GitHub account? Submit by email instead:${RESET}"
echo -e "  ${YELLOW}mailto:${SURVEY_EMAIL}?subject=M%26E%20Hardware%20Report%20%5B${REPORT_ID}%5D${RESET}"
echo -e "  ${YELLOW}(Attach ${OUTPUT_FILE_JSON} to the email)${RESET}"
echo ""

echo -e "  ${YELLOW}Please delete both the script and the JSON file after submitting.${RESET}"
echo ""
exit 0
