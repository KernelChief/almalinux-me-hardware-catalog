#!/usr/bin/env python3
"""Validate a hardware report pasted into a GitHub issue and write it to disk.

This is the whole ingest step: pull the JSON out of the issue body, validate it
strictly (it gets published automatically, so "valid" must mean "safe"), and
write a single `data/reports/{report_id}.json`. The site's per-report page and
index tables are generated at build time by `scripts/gen_reports.py`, so this
script never touches Markdown or the index.

It communicates back to the workflow via GITHUB_OUTPUT:
  status=ok      report_id=<id>     -> workflow commits the file and deploys
  status=invalid message=<reason>   -> workflow comments the reason on the issue
A bad submission is the submitter's mistake, not a pipeline error, so we exit 0
in both cases and let the workflow decide what to say.
"""
import json
import os
import re
import sys

EVENT_PATH = os.environ.get("GITHUB_EVENT_PATH")
if not EVENT_PATH:
    print("GITHUB_EVENT_PATH not set", file=sys.stderr)
    sys.exit(1)

with open(EVENT_PATH, "r", encoding="utf-8") as f:
    event = json.load(f)

body = event.get("issue", {}).get("body", "") or ""

# Limits. Reports are public and auto-published, so anything oversized or weird
# is rejected rather than rendered.
MAX_BODY_BYTES = 64 * 1024
MAX_STRING = 2000
MAX_ARRAY = 128
MAX_DEPTH = 8

REQUIRED_TOP = [
    "report_id",
    "timestamp",
    "system",
    "processor",
    "memory",
    "graphics",
    "storage_controllers",
]

PASTE_HELP = (
    "Re-run the script and paste the entire contents of "
    "`almalinux_me_report.json` exactly as generated, with no edits. "
    "It must start with `{` and end with `}`."
)


def set_output(name, value):
    out = os.environ.get("GITHUB_OUTPUT")
    if not out:
        return
    with open(out, "a", encoding="utf-8") as fh:
        fh.write(f"{name}<<__ISSUE_EOF__\n{value}\n__ISSUE_EOF__\n")


def reject(message):
    print(f"Rejected submission: {message}", file=sys.stderr)
    set_output("status", "invalid")
    set_output("message", message)
    sys.exit(0)


# ── Extract the JSON ────────────────────────────────────────────────────────
# Prefer the ```json fence the issue form produces, then the first {...} blob.
# Take the fence content verbatim so a malformed paste yields an honest parse
# error instead of brace-matching onto the wrong braces.
json_text = None
fence = re.search(r"```json\s*\n(.*?)```", body, re.DOTALL)
if fence:
    json_text = fence.group(1).strip()
if not json_text:
    blob = re.search(r"\{.*\}", body, re.DOTALL)
    if blob:
        json_text = blob.group(0).strip()

if not json_text:
    reject(f"No JSON was found in the issue body. {PASTE_HELP}")
if len(json_text.encode("utf-8")) > MAX_BODY_BYTES:
    reject("The pasted JSON is too large (over 64 KB). Please submit a single report.")
if not json_text.lstrip().startswith("{"):
    reject(
        "The pasted JSON does not start with `{`: the opening brace is missing "
        f"or there is text before it. {PASTE_HELP}"
    )

try:
    report = json.loads(json_text)
except json.JSONDecodeError as e:
    reject(f"The pasted JSON is not valid: {e}. {PASTE_HELP}")

if not isinstance(report, dict):
    reject(f"The pasted JSON must be a single object. {PASTE_HELP}")


# ── Strict structural validation ────────────────────────────────────────────
def check_safe(value, depth=0):
    """Reject oversized strings/arrays, control characters, and deep nesting."""
    if depth > MAX_DEPTH:
        reject("The report is nested too deeply.")
    if isinstance(value, str):
        if len(value) > MAX_STRING:
            reject(f"A field is too long (over {MAX_STRING} characters).")
        if any(ord(ch) < 32 and ch not in "\t\n\r" for ch in value):
            reject("A field contains control characters. Please paste the file as-is.")
    elif isinstance(value, list):
        if len(value) > MAX_ARRAY:
            reject(f"A list has too many entries (over {MAX_ARRAY}).")
        for item in value:
            check_safe(item, depth + 1)
    elif isinstance(value, dict):
        for key, item in value.items():
            check_safe(key, depth + 1)
            check_safe(item, depth + 1)


check_safe(report)

for key in REQUIRED_TOP:
    if key not in report:
        reject(f"The report is missing the required field `{key}`. {PASTE_HELP}")

if not isinstance(report.get("system"), dict):
    reject("Field `system` must be an object. " + PASTE_HELP)
if not isinstance(report.get("processor"), dict):
    reject("Field `processor` must be an object. " + PASTE_HELP)
if not isinstance(report.get("memory"), dict):
    reject("Field `memory` must be an object. " + PASTE_HELP)
if not isinstance(report.get("graphics"), list):
    reject("Field `graphics` must be a list. " + PASTE_HELP)
if not isinstance(report.get("storage_controllers"), list):
    reject("Field `storage_controllers` must be a list. " + PASTE_HELP)

report_id = str(report.get("report_id", "")).strip()
if not re.fullmatch(r"[a-f0-9]{8,16}", report_id):
    reject(
        f"`report_id` must be 8 to 16 hexadecimal characters (got `{report_id}`). "
        + PASTE_HELP
    )

# ── Write the single source-of-truth file ───────────────────────────────────
reports_dir = os.path.join("data", "reports")
os.makedirs(reports_dir, exist_ok=True)
json_path = os.path.join(reports_dir, f"{report_id}.json")

if os.path.exists(json_path):
    reject(
        f"A report with ID `{report_id}` already exists. Each machine submits "
        "once; open a new issue only for different hardware."
    )

with open(json_path, "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2, sort_keys=True)
    f.write("\n")

set_output("status", "ok")
set_output("report_id", report_id)
print(f"Wrote {json_path}")
