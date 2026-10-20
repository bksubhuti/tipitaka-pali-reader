'use strict';
// Saves a research paper: the Markdown, a styled HTML page (grey Pali quote
// boxes, the TPR logo), and a PDF when Chrome or Edge is there to print it.
// A port of the tpr-research skill's md2html.py and its pdf command.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');

const CSS = `
@page { size: letter; margin: 0.75in 0.7in; }
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
hr { border:0; border-top:1px solid var(--rule); margin:1.2rem 0; }
`;

const FOOTER = 'Tipitaka Pali Reader · americanmonk.org/tipitaka-pali-reader';

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

function inline(text) {
  text = esc(text);
  text = text.replace(/`([^`]+)`/g, '<code>$1</code>');
  text = text.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, '<a href="$2">$1</a>');
  text = text.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
  text = text.replace(/(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])/g, '<em>$1</em>');
  return text;
}

function table(lines) {
  const rows = lines.map((l) => l.trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim()));
  const out = ['<table>', '<tr>' + rows[0].map((c) => `<th>${inline(c)}</th>`).join('') + '</tr>'];
  for (const r of rows.slice(2)) out.push('<tr>' + r.map((c) => `<td>${inline(c)}</td>`).join('') + '</tr>');
  out.push('</table>');
  return out.join('\n');
}

function blockquote(lines) {
  const paras = [];
  let cur = [];
  for (let l of lines) {
    l = l.replace(/^>\s?/, '');
    if (l.trim()) cur.push(l.trim());
    else if (cur.length) { paras.push(cur.join(' ')); cur = []; }
  }
  if (cur.length) paras.push(cur.join(' '));
  const out = ['<blockquote>'];
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
      out.push(`<h${level}>${inline(h[2])}</h${level}>`);
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
      out.push(`<${tag}>` + items.map((t) => `<li>${inline(t)}</li>`).join('') + `</${tag}>`);
      continue;
    }
    const para = [];
    while (i < lines.length && lines[i].trim() && !/^(#|>|\s*\||\s*([-*]|\d+\.)\s)/.test(lines[i])) para.push(lines[i++].trim());
    out.push(`<p>${inline(para.join(' '))}</p>`);
  }
  return '<!doctype html>\n<html lang="en"><head><meta charset="utf-8">'
    + '<meta name="viewport" content="width=device-width, initial-scale=1">'
    + `<title>${esc(title)}</title><style>${CSS}</style></head><body>\n`
    + (logo ? `<img class="watermark" src="${logo}" alt="">\n` : '')
    + out.join('\n')
    + (footer ? `\n<div class="footer">${linkFooter(footer)}</div>` : '')
    + '\n</body></html>\n';
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
  return path.join(os.homedir(), 'Documents', 'TPR Research');
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
  spawnSync(exe, ['--headless', '--disable-gpu', '--no-pdf-header-footer', `--print-to-pdf=${pdfPath}`, url],
    { timeout: 120000, stdio: 'ignore' });
  return fs.existsSync(pdfPath) ? null : 'The PDF was not written. Open the HTML in a browser and use Print > Save as PDF.';
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
  const title = (/^#\s+(.+)$/m.exec(markdown) || [])[1] || 'Paper';
  const dir = papersDir();
  fs.mkdirSync(dir, { recursive: true });
  const base = path.join(dir, slug(fileName || title.replace(/[*`]/g, '')));
  const date = new Date().toISOString().slice(0, 10);
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
  if (open) openFile(shown);
  return lines.join('\n');
}

module.exports = { save, toHtml };
