"""MkDocs build hook: render report pages and tables from data/reports/*.json.

This makes `data/reports/*.json` the single source of truth. The per-report
pages and the index tables are produced at build time and never committed, so
report submissions only ever add one unique JSON file (no merge conflicts, no
separate rebuild step).

Every user-supplied value is HTML-escaped before it reaches a page, so a
submitted report cannot inject markup or scripts into the published site.
"""
import html
import json
import os
import re
from datetime import datetime

from mkdocs.structure.files import File

TABLE_START = "<!-- REPORTS_TABLE_START -->"
TABLE_END = "<!-- REPORTS_TABLE_END -->"
STATS_START = "<!-- STATS_START -->"
STATS_END = "<!-- STATS_END -->"
REPORT_ID_RE = re.compile(r"[a-f0-9]{8,16}")


def _reports_dir(config):
    root = os.path.dirname(config["config_file_path"])
    return os.path.join(root, "data", "reports")


def _esc(value):
    return html.escape(str(value), quote=True)


def _cell(value):
    text = _esc(value).replace("|", r"\|").replace("\n", " ").strip()
    return text or "—"


def _parse_timestamp(value):
    ts = str(value or "").strip()
    if not ts:
        return None
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(ts)
    except ValueError:
        return None


def _load_reports(config):
    reports = []
    reports_dir = _reports_dir(config)
    if not os.path.isdir(reports_dir):
        return reports
    for filename in sorted(os.listdir(reports_dir)):
        if not filename.endswith(".json"):
            continue
        try:
            with open(os.path.join(reports_dir, filename), encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, json.JSONDecodeError):
            continue
        rid = str(data.get("report_id", "")).strip()
        if not REPORT_ID_RE.fullmatch(rid):
            continue
        reports.append(data)
    reports.sort(
        key=lambda d: (
            _parse_timestamp(d.get("timestamp")) or datetime.min,
            str(d.get("report_id", "")),
        ),
        reverse=True,
    )
    return reports


def _hero_gpu(name):
    """Short consumer-facing GPU name for the hero (e.g. "GeForce RTX 3060")."""
    name = re.sub(r" \(rev [a-f0-9]+\)", "", str(name), flags=re.IGNORECASE)
    bracketed = re.search(r"\[([^\]]+)\]", name)
    if bracketed:
        return bracketed.group(1).strip() or "—"
    name = name.replace("NVIDIA Corporation ", "NVIDIA ")
    name = re.sub(r"Advanced Micro Devices, Inc\.( \[AMD/ATI\])? ", "AMD ", name)
    return name.strip() or "—"


def _clean_cpu(value):
    text = re.sub(r" \d+-Core Processor$", "", str(value), flags=re.IGNORECASE)
    text = re.sub(r" Processor$", "", text, flags=re.IGNORECASE).strip()
    return text or "—"


def _system_label(data):
    system = data.get("system", {}) or {}
    vendor = system.get("vendor") or system.get("manufacturer") or system.get("brand") or ""
    model = system.get("model") or system.get("product") or system.get("name") or ""
    return " ".join(p for p in [str(vendor).strip(), str(model).strip()] if p)


def render_table(reports, link_prefix, limit=None):
    if not reports:
        return "_No reports yet. Submitted reports appear here automatically._"
    rows = reports[:limit] if limit else reports
    lines = [
        "| Report ID | Timestamp (UTC) | System | Processor | Memory (GB) | GPU |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for d in rows:
        rid = str(d.get("report_id", "")).strip()
        processor = d.get("processor", {}) or {}
        memory = d.get("memory", {}) or {}
        graphics = d.get("graphics", []) or []
        gpu_names = [
            str(g.get("device", "")).strip()
            for g in graphics
            if isinstance(g, dict) and g.get("device")
        ]
        cells = [
            f"[{rid}]({link_prefix}{rid}/index.md)",
            _cell(d.get("timestamp", "")),
            _cell(_system_label(d)),
            _cell(processor.get("model") or processor.get("name") or ""),
            _cell(memory.get("total_gb") or memory.get("total") or ""),
            _cell(", ".join(gpu_names)),
        ]
        lines.append("| " + " | ".join(cells) + " |")
    return "\n".join(lines)


def render_stats(reports):
    gpus, platforms = set(), set()
    for d in reports:
        for gpu in d.get("graphics") or []:
            if isinstance(gpu, dict):
                name = str(gpu.get("device", "")).strip()
                if name:
                    gpus.add(_hero_gpu(name))
        platform = str((d.get("system") or {}).get("platform", "")).strip()
        if platform:
            platforms.add(platform)
    plat_label = "Platform" if len(platforms) == 1 else "Platforms"
    return "\n".join(
        [
            '    <div class="hw-stat">',
            f'      <div class="hw-stat-n">{len(reports)}</div>',
            '      <div class="hw-stat-l">Reports</div>',
            "    </div>",
            '    <div class="hw-stat">',
            f'      <div class="hw-stat-n">{len(gpus)}</div>',
            '      <div class="hw-stat-l">Unique GPUs</div>',
            "    </div>",
            '    <div class="hw-stat">',
            f'      <div class="hw-stat-n">{len(platforms)}</div>',
            f'      <div class="hw-stat-l">{plat_label}</div>',
            "    </div>",
        ]
    )


def render_report_page(data):
    rid = str(data.get("report_id", "")).strip()
    system = data.get("system", {}) or {}
    processor = data.get("processor", {}) or {}
    memory = data.get("memory", {}) or {}
    graphics = data.get("graphics", []) or []
    storage = data.get("storage_controllers", []) or []
    modules = memory.get("modules", []) or []
    notes = str(data.get("user_notes") or "").strip()

    total_gb = _cell(memory.get("total_gb", memory.get("total", "")))
    os_short = re.sub(r"\s*\([^)]+\)\s*$", "", str(system.get("os_release", ""))).strip()

    out = [f"# Hardware Report: `{_esc(rid)}`", ""]

    if graphics:
        main = next((g for g in graphics if isinstance(g, dict)), {})
        gpu_display = _esc(_hero_gpu(main.get("device", "")))
        cpu_display = _esc(_clean_cpu(processor.get("model", processor.get("name", ""))))
        out += [
            '<div class="hw-report-hero">',
            '  <div class="hw-report-gpu-label">Primary GPU</div>',
            f'  <div class="hw-report-gpu-name">{gpu_display}</div>',
            '  <div class="hw-report-quick-stats">',
            f'    <span class="hw-qs-item"><span class="hw-qs-label">CPU</span><span class="hw-qs-val">{cpu_display}</span></span>',
            f'    <span class="hw-qs-item"><span class="hw-qs-label">RAM</span><span class="hw-qs-val">{total_gb} GB</span></span>',
        ]
        if os_short:
            out.append(
                f'    <span class="hw-qs-item"><span class="hw-qs-label">OS</span>'
                f'<span class="hw-qs-val">{_esc(os_short)}</span></span>'
            )
        out += ["  </div>", "</div>", ""]

    out += [f"**Submitted:** {_esc(data.get('timestamp', ''))}", "", "---", ""]

    if notes:
        out.append('!!! quote "User Notes"')
        out += ["    " + _esc(line) for line in notes.split("\n")]
        out.append("")

    out += [
        "## System",
        "",
        "| Field | Value |",
        "|-------|-------|",
        f"| OS | {_cell(system.get('os_release', ''))} |",
        f"| Kernel | `{_cell(system.get('kernel', ''))}` |",
        f"| Platform | {_cell(system.get('platform', ''))} |",
        "",
        "## Processor",
        "",
        "| Field | Value |",
        "|-------|-------|",
        f"| Model | {_cell(processor.get('model', processor.get('name', '')))} |",
        f"| Cores | {_cell(processor.get('cores', ''))} |",
        "",
        "## Memory",
        "",
        f"**Total:** {total_gb} GB",
        "",
    ]

    if modules:
        out += [
            "### Memory Modules",
            "",
            "| Size | Speed | Configured Speed | Manufacturer |",
            "|------|-------|-----------------|--------------|",
        ]
        for mod in modules:
            if not isinstance(mod, dict):
                continue
            out.append(
                f"| {_cell(mod.get('size', ''))} "
                f"| {_cell(mod.get('speed', ''))} "
                f"| {_cell(mod.get('configured_speed', ''))} "
                f"| {_cell(mod.get('manufacturer', ''))} |"
            )
        out.append("")

    out += ["## Graphics", ""]
    if graphics:
        out += ["| Device | Driver |", "|--------|--------|"]
        for gpu in graphics:
            if not isinstance(gpu, dict):
                continue
            out.append(f"| {_cell(gpu.get('device', ''))} | {_cell(gpu.get('driver', ''))} |")
    else:
        out.append("_No graphics devices detected._")
    out.append("")

    out += ["## Storage Controllers", ""]
    if storage:
        out += ["| Device |", "|--------|"]
        for ctrl in storage:
            if not isinstance(ctrl, dict):
                continue
            out.append(f"| {_cell(ctrl.get('device', ''))} |")
    else:
        out.append("_No storage controllers detected._")

    return "\n".join(out).strip() + "\n"


# ── MkDocs hook entry points ────────────────────────────────────────────────
def on_files(files, config):
    for data in _load_reports(config):
        rid = str(data.get("report_id", "")).strip()
        files.append(
            File.generated(
                config,
                f"results/{rid}/index.md",
                content=render_report_page(data),
            )
        )
    return files


def _replace_marked(text, start, end, payload):
    if start in text and end in text:
        before = text.split(start)[0]
        after = text.split(end)[1]
        return f"{before}{start}\n{payload}\n{end}{after}"
    return text


def on_page_markdown(markdown, page, config, files, **kwargs):
    src = page.file.src_uri
    if src not in ("index.md", "results/index.md"):
        return markdown
    reports = _load_reports(config)
    if src == "index.md":
        markdown = _replace_marked(
            markdown, TABLE_START, TABLE_END, render_table(reports, "results/", limit=5)
        )
        markdown = _replace_marked(
            markdown, STATS_START, STATS_END, render_stats(reports)
        )
    else:
        markdown = _replace_marked(markdown, TABLE_START, TABLE_END, render_table(reports, ""))
    return markdown
