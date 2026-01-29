#!/usr/bin/env python3
import json
import os
from datetime import datetime
from pathlib import Path

REPORTS_DIR = Path("data/reports")
DOCS_DIR = Path("docs")
DATABASE_MD = Path("DATABASE.md")
INDEX_JSON = DOCS_DIR / "index.json"

def safe_get(dct, path, default="Unknown"):
    cur = dct
    for key in path:
        if not isinstance(cur, dict) or key not in cur:
            return default
        cur = cur[key]
    return cur

def summarize_gpu(report):
    gpus = report.get("graphics") or []
    if not gpus:
        return "N/A"
    devices = []
    for g in gpus[:2]:
        dev = (g.get("device") or "").strip()
        if dev:
            devices.append(dev)
    if not devices:
        return "N/A"
    s = " / ".join(devices)
    return s[:140] + ("…" if len(s) > 140 else "")

def read_reports():
    reports = []
    if not REPORTS_DIR.exists():
        return reports

    for f in sorted(REPORTS_DIR.glob("*.json")):
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
            data["_file"] = f.name
            reports.append(data)
        except Exception:
            continue

    reports.sort(key=lambda x: x.get("timestamp", ""), reverse=True)
    return reports

def write_database_md(reports):
    lines = []
    lines.append("# 🖥️ M&E Hardware Compatibility Database\n\n")
    lines.append("> This database is generated automatically from approved reports (PR merged).\n\n")
    lines.append("| Date | ID | OS | CPU | GPU | Notes |\n")
    lines.append("| :--- | :--- | :--- | :--- | :--- | :--- |\n")

    for r in reports:
        ts = r.get("timestamp") or "N/A"
        date = ts[:10] if isinstance(ts, str) else "N/A"
        rid = r.get("report_id") or "N/A"
        os_rel = safe_get(r, ["system", "os_release"], "Unknown")
        cpu = safe_get(r, ["processor", "model"], "Unknown")
        gpu = summarize_gpu(r)
        notes = (r.get("user_notes") or "No notes").replace("\n", " ").strip()
        if len(notes) > 180:
            notes = notes[:180] + "…"

        lines.append(f"| {date} | `{rid}` | {os_rel} | {cpu} | {gpu} | {notes} |\n")

    DATABASE_MD.write_text("".join(lines), encoding="utf-8")

def write_index_json(reports):
    DOCS_DIR.mkdir(parents=True, exist_ok=True)

    rows = []
    for r in reports:
        ts = r.get("timestamp") or ""
        rows.append({
            "timestamp": ts,
            "date": ts[:10] if isinstance(ts, str) else "",
            "report_id": r.get("report_id") or "",
            "os_release": safe_get(r, ["system", "os_release"], ""),
            "kernel": safe_get(r, ["system", "kernel"], ""),
            "platform": safe_get(r, ["system", "platform"], ""),
            "cpu": safe_get(r, ["processor", "model"], ""),
            "cores": safe_get(r, ["processor", "cores"], ""),
            "memory_total_gb": safe_get(r, ["memory", "total_gb"], ""),
            "gpu": summarize_gpu(r),
            "notes": (r.get("user_notes") or "").strip(),
            "raw_file": r.get("_file", ""),
        })

    payload = {
        "generated_at_utc": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "count": len(rows),
        "reports": rows
    }

    INDEX_JSON.write_text(json.dumps(payload, indent=2), encoding="utf-8")

def main():
    reports = read_reports()
    write_database_md(reports)
    write_index_json(reports)

if __name__ == "__main__":
    main()
