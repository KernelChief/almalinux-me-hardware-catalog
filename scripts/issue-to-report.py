#!/usr/bin/env python3
import base64
import json
import os
import re
import sys
from datetime import datetime

EVENT_PATH = os.environ.get("GITHUB_EVENT_PATH")
if not EVENT_PATH:
    print("GITHUB_EVENT_PATH not set", file=sys.stderr)
    sys.exit(1)

with open(EVENT_PATH, "r", encoding="utf-8") as f:
    event = json.load(f)

issue = event.get("issue", {})
body = issue.get("body", "")

json_text = None
m = re.search(r"```json\s*(\{.*?\})\s*```", body, re.DOTALL)
if m:
    json_text = m.group(1)
else:
    m2 = re.search(r"(\{.*\})", body, re.DOTALL)
    if m2:
        json_text = m2.group(1)

if not json_text:
    m3 = re.search(r"```(?:text|)\s*([A-Za-z0-9+/=\\s]+)\\s*```", body, re.DOTALL)
    if m3:
        try:
            decoded = base64.b64decode(m3.group(1), validate=True).decode("utf-8", errors="strict")
            json_text = decoded
        except (ValueError, UnicodeDecodeError):
            json_text = None

if not json_text:
    print("No JSON found in issue body", file=sys.stderr)
    sys.exit(1)

try:
    report = json.loads(json_text)
except json.JSONDecodeError as e:
    print(f"Invalid JSON in issue body: {e}", file=sys.stderr)
    sys.exit(1)

required_top = [
    "report_id",
    "timestamp",
    "system",
    "processor",
    "memory",
    "graphics",
    "storage_controllers",
]
for key in required_top:
    if key not in report:
        print(f"Missing required field: {key}", file=sys.stderr)
        sys.exit(1)

if not isinstance(report.get("system"), dict):
    print("Field 'system' must be an object", file=sys.stderr)
    sys.exit(1)
if not isinstance(report.get("processor"), dict):
    print("Field 'processor' must be an object", file=sys.stderr)
    sys.exit(1)
if not isinstance(report.get("memory"), dict):
    print("Field 'memory' must be an object", file=sys.stderr)
    sys.exit(1)
if not isinstance(report.get("graphics"), list):
    print("Field 'graphics' must be a list", file=sys.stderr)
    sys.exit(1)
if not isinstance(report.get("storage_controllers"), list):
    print("Field 'storage_controllers' must be a list", file=sys.stderr)
    sys.exit(1)

report_id = str(report.get("report_id", "")).strip()
if not re.fullmatch(r"[a-f0-9]{8}", report_id):
    print("Invalid or missing report_id", file=sys.stderr)
    sys.exit(1)

reports_dir = os.path.join("data", "reports")
results_dir = os.path.join("docs", "results", report_id)
os.makedirs(reports_dir, exist_ok=True)
os.makedirs(results_dir, exist_ok=True)

json_path = os.path.join(reports_dir, f"{report_id}.json")
with open(json_path, "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2, sort_keys=True)
    f.write("\n")

notes = report.get("user_notes") or "None"

system = report.get("system", {})
processor = report.get("processor", {})
memory = report.get("memory", {})

graphics = report.get("graphics", []) or []
storage = report.get("storage_controllers", []) or []

md_lines = []
md_lines.append(f"# Hardware Report: {report_id}")
md_lines.append("")
md_lines.append(f"Timestamp (UTC): {report.get('timestamp', '')}")
md_lines.append("")
md_lines.append("## Notes")
md_lines.append(notes)
md_lines.append("")
md_lines.append("## System")
md_lines.append(f"- OS: {system.get('os_release', '')}")
md_lines.append(f"- Kernel: {system.get('kernel', '')}")
md_lines.append(f"- Platform: {system.get('platform', '')}")
md_lines.append("")
md_lines.append("## Processor")
md_lines.append(f"- Model: {processor.get('model', '')}")
md_lines.append(f"- Cores: {processor.get('cores', '')}")
md_lines.append("")
md_lines.append("## Memory")
md_lines.append(f"- Total (GB): {memory.get('total_gb', '')}")
modules = memory.get("modules", []) or []
if modules:
    md_lines.append("")
    md_lines.append("### Modules")
    for mod in modules:
        size = mod.get("size", "")
        speed = mod.get("speed", "")
        conf = mod.get("configured_speed", "")
        maker = mod.get("manufacturer", "")
        md_lines.append(f"- {size} @ {speed} (configured: {conf}, maker: {maker})")

md_lines.append("")
md_lines.append("## Graphics")
if graphics:
    for gpu in graphics:
        device = gpu.get("device", "")
        driver = gpu.get("driver", "")
        md_lines.append(f"- {device} (driver: {driver})")
else:
    md_lines.append("- None detected")

md_lines.append("")
md_lines.append("## Storage Controllers")
if storage:
    for ctrl in storage:
        md_lines.append(f"- {ctrl.get('device', '')}")
else:
    md_lines.append("- None detected")

md_path = os.path.join(results_dir, "index.md")
with open(md_path, "w", encoding="utf-8") as f:
    f.write("\n".join(md_lines).strip() + "\n")

print(f"Wrote {json_path} and {md_path}")
