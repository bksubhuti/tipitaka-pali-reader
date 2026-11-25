'use strict';
// Saves a research paper: the Markdown, a styled HTML page (grey Pali quote
// boxes, the TPR logo), and a PDF when Chrome or Edge is there to print it.
// A port of the tpr-research skill's md2html.py and its pdf command.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');
const tpr = require('./tpr');

const CSS = `
@page { size: letter; margin: 0.75in 0.7in 0.95in;
  @bottom-right { content: counter(page) " / " counter(pages); font-family: Georgia, serif; font-size: 8.5pt; color: #9a9a9a; vertical-align: middle; } }
:root { --ink:#1f1f1f; --muted:#5f5f5f; --rule:#d9d9d9; --qbg:#efefef; --qbar:#9a9a9a; --link:#1a5fb4; }
body { font-family: "Noto Serif", "Gentium Plus", Georgia, "Times New Roman", serif; color: var(--ink);
       background:#fff; line-height:1.5; font-size:11pt; max-width:46rem; margin:2rem auto; padding:0 16px; }
h1 { font-size:21pt; line-height:1.2; margin:0 0 .3rem; }
.byline { color:var(--muted); font-size:10pt; margin-bottom:1.2rem; }
h2 { font-size:14.5pt; margin:1.6rem 0 .5rem; border-bottom:1px solid var(--rule); padding-bottom:.2rem; break-after:avoid; }
h3 { font-size:12pt; margin:1.2rem 0 .4rem; break-after:avoid; }
p { margin:.45rem 0; }
a { color:var(--link); text-decoration:none; }
blockquote { background:var(--qbg); border-left:4px solid var(--qbar); margin:.8rem 0; padding:.55rem .9rem;
             border-radius:4px; break-inside:avoid; }
blockquote p { margin:.3rem 0; }
blockquote p.src { font-size:9.5pt; }
table { border-collapse:collapse; width:100%; margin:.8rem 0; font-size:9.5pt; }
tr { break-inside:avoid; }
th, td { border:1px solid var(--rule); padding:.3rem .45rem; text-align:left; vertical-align:top; }
th { background:#f6f6f6; }
li { margin:.15rem 0; }
code { font-size:9.5pt; background:#f4f4f4; padding:0 .2em; border-radius:3px; }
.brand { float:right; width:.85in; height:.85in; margin:0 0 .4rem 1rem; }
.watermark { position:fixed; top:50%; left:50%; width:5.5in; height:5.5in; transform:translate(-50%,-50%);
             opacity:.06; z-index:-1; pointer-events:none; }
.footer { position:fixed; bottom:0; left:0; right:0; text-align:center; font-size:8.5pt; color:#9a9a9a; }
.footer a { color:#9a9a9a; }
@media screen { .footer { position:static; margin-top:2rem; } }
@media print { .footer { display:none; } }
hr { border:0; border-top:1px solid var(--rule); margin:1.2rem 0; }
body { -webkit-print-color-adjust:exact; print-color-adjust:exact; }
ol.toc a { color:var(--ink); border-bottom:1px dotted var(--qbar); }
ol.toc a:hover { color:var(--link); }
h2 a.up { font-size:10pt; color:#9a9a9a; margin-left:.4rem; font-weight:normal; }
.tag { font-family: system-ui, -apple-system, "Segoe UI", sans-serif; font-size:8pt; font-weight:700;
       letter-spacing:.06em; text-transform:uppercase; color:#6a6a6a; margin:0 0 .2rem !important; }
td.ok { background:#e6f4e8; color:#1b5e20; }
td.no { background:#fdecea; color:#b71c1c; }
td.half { background:#fff4e0; color:#8a5100; }
td.nts { background:#f1f1f1; color:#555; }
.legend { border:1px solid #2e7d32; background:#e6f4e8; padding:.4rem .7rem; border-radius:4px; }
`;

const FOOTER = 'Tipitaka Pali Reader · americanmonk.org/tipitaka-pali-reader';

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

function inline(text) {
  text = esc(text).replace(/&lt;br&gt;/g, '<br>'); // <br> breaks a line inside a table cell
  text = text.replace(/`([^`]+)`/g, '<code>$1</code>');
  text = text.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, '<a href="$2">$1</a>');
  text = text.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
  text = text.replace(/(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])/g, '<em>$1</em>');
  return text;
}

const VERDICTS = [[/^\*\*HALF RIGHT\b/, '◐', 'half'], [/^\*\*RIGHT\b/, '✓', 'ok'], [/^\*\*WRONG\b/, '✗', 'no'],
  [/^(\*\*)?No textual support found/, '–', 'nts']];

/** A verdict cell gets its mark and colour: green ✓, red ✗, amber ◐, grey –. */
function cell(c) {
  for (const [re, mark, cls] of VERDICTS) if (re.test(c)) return `<td class="${cls}">${inline(`${mark} ${c}`)}</td>`;
  const cls = c.startsWith('✓ **') ? ' class="ok"' : c.startsWith('✗ **') ? ' class="no"' : '';
  return `<td${cls}>${inline(c)}</td>`;
}

function table(lines) {
  const rows = lines.map((l) => l.trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim()));
  const out = ['<table>', '<tr>' + rows[0].map((c) => `<th>${inline(c)}</th>`).join('') + '</tr>'];
  for (const r of rows.slice(2)) out.push('<tr>' + r.map(cell).join('') + '</tr>');
  out.push('</table>');
  return out.join('\n');
}

const LAYER_TAGS = [['mula', 'Mūla'], ['attha', 'Aṭṭhakathā'], ['tika', 'Ṭīkā'], ['annya', 'Añña']];

function blockquote(lines) {
  const paras = [];
  let cur = [];
  for (let l of lines) {
    l = l.replace(/^>\s?/, '');
    if (l.trim()) cur.push(l.trim());
    else if (cur.length) { paras.push(cur.join(' ')); cur = []; }
  }
  if (cur.length) paras.push(cur.join(' '));
  const src = paras.length && paras[paras.length - 1].includes('tpr.pali.tools') ? paras[paras.length - 1] : '';
  const layer = (LAYER_TAGS.find(([k]) => src.includes(`book_id=${k}_`)) || [])[1];
  const out = ['<blockquote>'];
  if (layer) out.push(`<p class="tag">${layer}</p>`);
  paras.forEach((p, i) => {
    const cls = i === paras.length - 1 && p.includes('tpr.pali.tools') ? ' class="src"' : '';
    out.push(`<p${cls}>${inline(p)}</p>`);
  });
  out.push('</blockquote>');
  return out.join('\n');
}

const LIST = /^\s*([-*]|\d+\.)\s+/;

function toHtml(md, { byline, logo, footer } = {}) {
  const lines = md.split(/\r?\n/);
  const out = [];
  let i = 0;
  let title = 'Paper';
  const hasPoints = /^##\s+Summary points\s*$/m.test(md);
  let lastH2 = '';
  while (i < lines.length) {
    const l = lines[i];
    if (!l.trim()) { i++; continue; }
    const h = /^(#{1,4})\s+(.*)/.exec(l);
    if (h) {
      const level = h[1].length;
      if (level === 1) {
        title = h[2].replace(/[*`]/g, '');
        if (logo) out.push(`<img class="brand" src="${logo}" alt="">`);
      }
      const num = level === 2 ? /^(\d+)\.\s/.exec(h[2]) : null;
      const id = num ? `p${num[1]}`
        : h[2].replace(/[*`]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
      const back = num && hasPoints ? ' <a class="up" href="#summary-points" title="Back to the summary points">↑</a>' : '';
      if (level === 2) lastH2 = id;
      out.push(`<h${level} id="${id}">${inline(h[2])}${back}</h${level}>`);
      if (level === 1 && byline) out.push(`<div class="byline">${esc(byline)}</div>`);
      i++; continue;
    }
    if (/^\s*(---|\*\*\*)\s*$/.test(l)) { out.push('<hr>'); i++; continue; }
    if (l.startsWith('>')) {
      const block = [];
      while (i < lines.length && lines[i].startsWith('>')) block.push(lines[i++]);
      out.push(blockquote(block)); continue;
    }
    if (l.trim().startsWith('|') && i + 1 < lines.length && /^\s*\|[\s:|-]+\|\s*$/.test(lines[i + 1])) {
      const block = [];
      while (i < lines.length && lines[i].trim().startsWith('|')) block.push(lines[i++]);
      out.push(table(block)); continue;
    }
    if (LIST.test(l)) {
      const tag = /^\s*\d+\./.test(l) ? 'ol' : 'ul';
      const items = [];
      while (i < lines.length && (LIST.test(lines[i]) || (lines[i].startsWith('  ') && lines[i].trim()))) {
        if (LIST.test(lines[i])) items.push(lines[i].replace(LIST, ''));
        else items[items.length - 1] += ' ' + lines[i].trim();
        i++;
      }
      if (tag === 'ol' && lastH2 === 'summary-points') {
        out.push('<ol class="toc">' + items.map((t, n) => `<li><a href="#p${n + 1}">${inline(t)}</a></li>`).join('') + '</ol>');
      } else {
        out.push(`<${tag}>` + items.map((t) => `<li>${inline(t)}</li>`).join('') + `</${tag}>`);
      }
      continue;
    }
    const para = [];
    while (i < lines.length && lines[i].trim() && !/^(#|>|\s*\||\s*([-*]|\d+\.)\s)/.test(lines[i])) para.push(lines[i++].trim());
    const text = para.join(' ');
    if (text.startsWith('!legend ')) out.push(`<p class="legend">${inline(text.slice(8))}</p>`);
    else out.push(`<p>${hasPoints ? xref(inline(text)) : inline(text)}</p>`);
  }
  return '<!doctype html>\n<html lang="en"><head><meta charset="utf-8">'
    + '<meta name="viewport" content="width=device-width, initial-scale=1">'
    + `<title>${esc(title)}</title><style>${CSS}${pageFooter(footer)}</style></head><body>\n`
    + (logo ? `<img class="watermark" src="${logo}" alt="">\n` : '')
    + out.join('\n')
    + (footer ? `\n<div class="footer">${linkFooter(footer)}</div>` : '')
    + '\n</body></html>\n';
}

/** 'point 4' / 'points 3' link to #p4 / #p3, outside existing links. */
function xref(h) {
  return h.split(/(<a\b.*?<\/a>)/).map((part, k) => (k % 2 ? part
    : part.replace(/\b(points?) (\d+)/g, '<a href="#p$2">$1 $2</a>'))).join('');
}

/** The footer printed in each page's bottom margin, so it never covers text. */
function pageFooter(text) {
  if (!text) return '';
  const s = text.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  return `@page { @bottom-center { content: "${s}"; font-family: Georgia, serif; `
    + 'font-size: 8.5pt; color: #9a9a9a; vertical-align: middle; } }';
}

/** Escape the footer and make any web address in it clickable. */
function linkFooter(text) {
  return esc(text).replace(/((?:https?:\/\/)?[\w-]+(?:\.[\w-]+)+(?:\/[\w./-]*)?)/g,
    (m) => `<a href="${m.startsWith('http') ? m : 'https://' + m}">${m}</a>`);
}

function logoUri() {
  const p = path.join(__dirname, '..', 'icon.png');
  return fs.existsSync(p) ? 'data:image/png;base64,' + fs.readFileSync(p).toString('base64') : null;
}

function papersDir() {
  const chosen = (process.env.TPR_PAPERS_DIR || '').trim();
  if (chosen && !chosen.startsWith('${')) return chosen;
  return path.join(os.homedir(), 'TPR');
}

// ------------------------------------------------------------- references
// A port of the skill's expand.py: {{Q:BOOK PARA:L1-L2|translation}} becomes
// a quote box, {{L:BOOK PARA:LINE}} a link, and every bare reference in the
// text (M-i 1036:1; 1040:2) a TPR link, so no reference is left unlinked.

function quoteBox(spec) {
  const [ref, over = ''] = spec.split('|');
  const [book, r] = ref.trim().split(/\s+/);
  const rows = tpr.refLines(book, r, langOrNull());
  const pali = rows.map((x) => tpr.clean(x.pali)).join(' ');
  const trans = over.trim() || rows.filter((x) => x.translation).map((x) => tpr.clean(x.translation)).join(' ').trim();
  const ln = tpr.refLink(book, rows[0].para_id, rows[0].line_id, rows[0].pali);
  const name = tpr.bookName(book);
  const src = ln ? `[${name}, p. ${ln.page} (TPR)](${ln.url})` : `${name} ${r}`;
  return `> **${pali}**\n>\n${trans ? `> ${trans}\n>\n` : ''}> ${src}`;
}

/** The reader's default translation (English when installed), or none. */
function langOrNull() {
  try { return tpr.defaultLang(); } catch { return null; }
}

function refUrl(book, ref) {
  const m = /^(\d+)(?::(\d+))?/.exec(ref);
  const para = Number(m[1]);
  const line = Number(m[2] || 1);
  try {
    const rows = tpr.lines(book, para, line, line, null);
    return tpr.refLink(book, para, rows[0].line_id, rows[0].pali);
  } catch { return null; }
}

function expand(md) {
  md = md.replace(/\{\{Q:([\s\S]+?)\}\}/g, (all, spec) => {
    try { return quoteBox(spec); } catch (e) { return `${all} (${e.message})`; }
  });
  md = md.replace(/\{\{L:(.+?)\}\}/g, (all, spec) => {
    const [book, r] = spec.trim().split(/\s+/);
    const ln = refUrl(book, r);
    return ln ? `[${book} ${r} (p. ${ln.page})](${ln.url})` : `${book} ${r}`;
  });
  const ids = tpr.bookIds().sort((x, y) => y.length - x.length).map((x) => x.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
  const REF = '\\d+(?::\\d+(?:-\\d+)?|[–-]\\d+)';
  const bare = new RegExp(`(?<![\\w\\-\\[])(${ids.join('|')}) (${REF})((?:[,;] ${REF})*)`, 'g');
  const one = (book, r, text) => { const ln = refUrl(book, r); return ln ? `[${text}](${ln.url})` : text; };
  const auto = (_, book, first, rest) => one(book, first, `${book} ${first}`)
    + rest.replace(new RegExp(`([,;] )(${REF})`, 'g'), (m, sep, r) => sep + one(book, r, r));
  return md.split('\n').map((line) => {
    if (/^[>#]/.test(line)) return line;
    return line.split(/(\[[^\]]*\]\([^)]*\))/).map((part, k) => (k % 2 ? part : part.replace(bare, auto))).join('');
  }).join('\n');
}

/** A file name from the title: letters, digits and dashes. */
function slug(text) {
  return (text.normalize('NFKD').replace(/[̀-ͯ]/g, '')
    .replace(/[^\w\s-]/g, '').trim().replace(/[\s_]+/g, '-').slice(0, 80)) || 'paper';
}

function browser() {
  const pf = process.env.PROGRAMFILES || '';
  const pf86 = process.env['PROGRAMFILES(X86)'] || '';
  const list = [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
    '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
    pf86 && path.join(pf86, 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
    pf && path.join(pf, 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
    pf && path.join(pf, 'Google', 'Chrome', 'Application', 'chrome.exe'),
    '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/microsoft-edge',
  ];
  return list.find((b) => b && fs.existsSync(b)) || null;
}

function printPdf(htmlPath, pdfPath) {
  const exe = browser();
  if (!exe) return 'No Chrome or Edge found for the PDF. Open the HTML in a browser and use Print > Save as PDF.';
  const url = 'file:///' + htmlPath.replace(/\\/g, '/').replace(/^\/+/, '');
  const args = ['--headless', '--disable-gpu', '--no-pdf-header-footer', `--print-to-pdf=${pdfPath}`];
  const written = () => fs.existsSync(pdfPath) && fs.statSync(pdfPath).size > 0;
  fs.rmSync(pdfPath, { force: true }); // an old copy must not pass for a new one
  spawnSync(exe, [...args, url], { timeout: 120000, stdio: 'ignore' });
  if (written()) return null;
  // Codex runs this server in a sandbox: Chrome may not write its usual
  // profile there, nor start its own sandbox inside Codex's. Again with an
  // empty throwaway profile (none of the reader's cookies or logins) and
  // without Chrome's sandbox; it only opens this local page.
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'tpr-chrome-'));
  try {
    spawnSync(exe, [...args, `--user-data-dir=${profile}`, '--no-sandbox', url],
      { timeout: 120000, stdio: 'ignore' });
  } finally {
    fs.rmSync(profile, { recursive: true, force: true });
  }
  return written() ? null : 'The PDF was not written. Open the HTML in a browser and use Print > Save as PDF.';
}

function openFile(p) {
  const [cmd, args] = process.platform === 'darwin' ? ['open', [p]]
    : process.platform === 'win32' ? ['cmd', ['/c', 'start', '', p]] : ['xdg-open', [p]];
  try {
    spawn(cmd, args, { detached: true, stdio: 'ignore', windowsHide: true }).unref();
  } catch { /* the path is in the reply anyway */ }
}

/** Writes the paper and returns what was written, for the reply. */
function save({ markdown, file_name: fileName, byline, pdf = true, open = true }) {
  if (!markdown || !markdown.trim()) throw new Error('The paper is empty.');
  markdown = expand(markdown);
  const title = (/^#\s+(.+)$/m.exec(markdown) || [])[1] || 'Paper';
  const dir = papersDir();
  fs.mkdirSync(dir, { recursive: true });
  const base = path.join(dir, slug(fileName || title.replace(/[*`]/g, '')));
  const now = new Date();
  const date = new Date(now - now.getTimezoneOffset() * 6e4).toISOString().slice(0, 10); // local date
  const html = toHtml(markdown, {
    byline: byline || `Tipitaka Pali Reader sources · ${date}`,
    logo: logoUri(),
    footer: FOOTER,
  });
  fs.writeFileSync(base + '.md', markdown, 'utf8');
  fs.writeFileSync(base + '.html', html, 'utf8');
  const lines = [`Saved:\n  ${base}.md\n  ${base}.html`];
  let shown = base + '.html';
  if (pdf) {
    const problem = printPdf(base + '.html', base + '.pdf');
    if (problem) lines.push(problem);
    else { lines.push(`  ${base}.pdf`); shown = base + '.pdf'; }
  }
  // Always opened: the reader asked for the PDF to come up every time.
  openFile(shown);
  lines.push(`Opened ${path.basename(shown)} for the reader.`);
  return lines.join('\n');
}

module.exports = { save, toHtml, expand };
