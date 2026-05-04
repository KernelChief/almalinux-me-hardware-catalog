/* ================================================================
   AlmaLinux M&E Works On — Table-to-Cards & Stats
   Transforms the auto-generated markdown table into card grids.
   ================================================================ */

(function () {
  'use strict';

  /* ── GPU / CPU name cleanup ─────────────────────────────────── */
  function cleanGpu(name) {
    return name
      .replace(/NVIDIA Corporation /g, 'NVIDIA ')
      .replace(/Advanced Micro Devices, Inc\. \[AMD\/ATI\] /g, 'AMD ')
      .replace(/Advanced Micro Devices, Inc\. /g, 'AMD ')
      .replace(/ \(rev [a-f0-9]+\)/gi, '')
      .replace(/\[([^\]]+)\]/g, '$1')
      .trim();
  }

  function cleanCpu(name) {
    return name
      .replace(/ \d+-Core Processor$/i, '')
      .replace(/ Processor$/i, '')
      .replace(/\(R\)/g, '')
      .replace(/\(TM\)/g, '')
      .trim();
  }

  function fmtDate(iso) {
    if (!iso) return '';
    try {
      return new Date(iso).toLocaleDateString('en-US', {
        year: 'numeric', month: 'short', day: 'numeric'
      });
    } catch (_) { return iso.slice(0, 10); }
  }

  /* ── Build a single card element ────────────────────────────── */
  function makeCard(data) {
    const card = document.createElement('a');
    card.href = data.href;
    card.className = 'hw-card';

    const body = document.createElement('div');
    body.className = 'hw-card-body';

    const gpuEl = document.createElement('div');
    gpuEl.className = 'hw-card-gpu';
    gpuEl.textContent = cleanGpu(data.gpu) || '—';

    const cpuEl = document.createElement('div');
    cpuEl.className = 'hw-card-cpu';
    cpuEl.textContent = cleanCpu(data.cpu) || '—';

    body.appendChild(gpuEl);
    body.appendChild(cpuEl);

    const footer = document.createElement('div');
    footer.className = 'hw-card-footer';

    if (data.ram) {
      const b = document.createElement('span');
      b.className = 'hw-badge hw-badge-ram';
      b.textContent = data.ram + ' GB';
      footer.appendChild(b);
    }

    if (data.id) {
      const b = document.createElement('span');
      b.className = 'hw-badge hw-badge-id';
      b.textContent = data.id;
      footer.appendChild(b);
    }

    if (data.date) {
      const b = document.createElement('span');
      b.className = 'hw-badge hw-badge-date';
      b.textContent = data.date;
      footer.appendChild(b);
    }

    card.appendChild(body);
    card.appendChild(footer);
    return card;
  }

  /* ── Transform a reports table into a card grid ─────────────── */
  function transformTable(table) {
    const headers = Array.from(table.querySelectorAll('thead th'))
      .map(th => th.textContent.trim().toLowerCase());

    if (!headers.includes('report id') || !headers.includes('gpu')) return;

    const idIdx   = headers.indexOf('report id');
    const tsIdx   = headers.indexOf('timestamp (utc)');
    const cpuIdx  = headers.indexOf('processor');
    const ramIdx  = headers.indexOf('memory (gb)');
    const gpuIdx  = headers.indexOf('gpu');

    const rows = Array.from(table.querySelectorAll('tbody tr'));
    if (!rows.length) return;

    const grid = document.createElement('div');
    grid.className = 'hw-card-grid';

    rows.forEach(function (row) {
      const cells = Array.from(row.querySelectorAll('td'));
      if (!cells.length) return;

      const idCell = cells[idIdx];
      const link   = idCell && idCell.querySelector('a');
      const id     = link ? link.textContent.trim() : (idCell ? idCell.textContent.trim() : '');
      const href   = link ? link.href : '#';

      grid.appendChild(makeCard({
        href : href,
        id   : id,
        gpu  : cells[gpuIdx]  ? cells[gpuIdx].textContent.trim()  : '',
        cpu  : cells[cpuIdx]  ? cells[cpuIdx].textContent.trim()  : '',
        ram  : cells[ramIdx]  ? cells[ramIdx].textContent.trim()  : '',
        date : cells[tsIdx]   ? fmtDate(cells[tsIdx].textContent.trim()) : '',
      }));
    });

    table.parentNode.replaceChild(grid, table);
    return rows.length;
  }

  /* ── Update stat counters ────────────────────────────────────── */
  function updateStats(count) {
    document.querySelectorAll('[data-stat]').forEach(function (el) {
      if (el.dataset.stat === 'reports') el.textContent = count;
    });
  }

  /* ── Run after navigation (MkDocs instant-loading) ──────────── */
  function run() {
    var total = 0;
    document.querySelectorAll('.md-content table').forEach(function (t) {
      var n = transformTable(t);
      if (n) total += n;
    });
    if (total) updateStats(total);
  }

  /* ── Copy command buttons ────────────────────────────────────── */
  function initCopyButtons() {
    document.querySelectorAll('.hw-cmd-copy').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var text = btn.closest('.hw-cmd').querySelector('.hw-cmd-text').textContent;
        navigator.clipboard.writeText(text).then(function () {
          btn.classList.add('copied');
          setTimeout(function () { btn.classList.remove('copied'); }, 2000);
        });
      });
    });
  }

  /* Support both initial load and MkDocs instant navigation */
  document.addEventListener('DOMContentLoaded', function () { run(); initCopyButtons(); });

  if (typeof document$ !== 'undefined') {
    /* MkDocs Material instant navigation uses RxJS document$ observable */
    document$.subscribe(function () { run(); initCopyButtons(); });
  }
})();
