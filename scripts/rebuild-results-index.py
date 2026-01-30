#!/usr/bin/env python3
import json
import os
from datetime import datetime

REPORTS_TABLE_START = "<!-- REPORTS_TABLE_START -->"
REPORTS_TABLE_END = "<!-- REPORTS_TABLE_END -->"


def parse_timestamp(value):
    if not value:
        return None
    ts = str(value).strip()
    if not ts:
        return None
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(ts)
    except ValueError:
        return None


def build_report_rows(reports_dir):
    rows = []
    if not os.path.isdir(reports_dir):
        return rows
    for filename in sorted(os.listdir(reports_dir)):
        if not filename.endswith(".json"):
            continue
        path = os.path.join(reports_dir, filename)
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, json.JSONDecodeError):
            continue
        report_id = str(data.get("report_id", "")).strip()
        if not report_id:
            continue
        system = data.get("system", {}) or {}
        processor = data.get("processor", {}) or {}
        memory = data.get("memory", {}) or {}

        vendor = system.get("vendor") or system.get("manufacturer") or system.get("brand") or ""
        model = system.get("model") or system.get("product") or system.get("name") or ""
        system_label = " ".join([part for part in [str(vendor).strip(), str(model).strip()] if part])

        processor_label = str(processor.get("model") or processor.get("name") or "").strip()
        memory_label = str(memory.get("total_gb") or memory.get("total") or "").strip()

        timestamp = data.get("timestamp", "")
        timestamp_dt = parse_timestamp(timestamp)

        rows.append(
            {
                "report_id": report_id,
                "timestamp": str(timestamp).strip(),
                "timestamp_dt": timestamp_dt,
                "system": system_label,
                "processor": processor_label,
                "memory": memory_label,
            }
        )

    rows.sort(
        key=lambda item: (item["timestamp_dt"] or datetime.min, item["report_id"]),
        reverse=True,
    )
    return rows


def render_reports_table(rows, link_prefix):
    if not rows:
        return "_No reports yet. Submitted reports will appear here after approval._"
    lines = []
    lines.append("| Report ID | Timestamp (UTC) | System | Processor | Memory (GB) |")
    lines.append("| --- | --- | --- | --- | --- |")
    for row in rows:
        report_id = row["report_id"]
        timestamp = row["timestamp"] or ""
        system = row["system"] or ""
        processor = row["processor"] or ""
        memory = row["memory"] or ""
        link = f"[{report_id}]({link_prefix}{report_id}/)"
        lines.append(f"| {link} | {timestamp} | {system} | {processor} | {memory} |")
    return "\n".join(lines)


def update_marked_section(path, new_content):
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
    except OSError:
        content = ""

    if REPORTS_TABLE_START in content and REPORTS_TABLE_END in content:
        before = content.split(REPORTS_TABLE_START)[0]
        after = content.split(REPORTS_TABLE_END)[1]
        updated = (
            before
            + REPORTS_TABLE_START
            + "\n"
            + new_content
            + "\n"
            + REPORTS_TABLE_END
            + after
        )
    else:
        if content and not content.endswith("\n"):
            content += "\n"
        updated = (
            content
            + REPORTS_TABLE_START
            + "\n"
            + new_content
            + "\n"
            + REPORTS_TABLE_END
            + "\n"
        )

    with open(path, "w", encoding="utf-8") as f:
        f.write(updated)


def update_results_indexes(reports_dir):
    rows = build_report_rows(reports_dir)
    results_table = render_reports_table(rows, "./")
    index_table = render_reports_table(rows, "./results/")

    update_marked_section(os.path.join("docs", "results", "index.md"), results_table)
    update_marked_section(os.path.join("docs", "index.md"), index_table)


def main():
    update_results_indexes(os.path.join("data", "reports"))
    print("Updated docs/index.md and docs/results/index.md")


if __name__ == "__main__":
    main()
