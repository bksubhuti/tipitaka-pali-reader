'use strict';
// TPR Research as a public web server (MCP "Streamable HTTP", JSON replies):
// Claude, ChatGPT and other apps on the web and on phones connect to
// TPR_PUBLIC_URL/mcp with no install. Started by index.js with TPR_WEB=1,
// behind a web server (Caddy) that does HTTPS and passes the visitor's
// address in X-Forwarded-For.
//
// Settings (environment):
//   TPR_DB_DIR       the folder with tipitaka_pali.db, epitaka.db, lang_*.db
//   TPR_PAPERS_DIR   where papers are saved (each in a folder of its own)
//   TPR_PUBLIC_URL   e.g. https://tpr.americanmonk.org (for paper links)
//   PORT             default 8787, on 127.0.0.1 only
//   TPR_WORKERS      tool calls run at once (default 2)
//   TPR_ADMIN_PASSWORD  for /admin (no password set: /admin is off)
//
// Tool calls run in worker threads with a time limit; each visitor has a
// request limit and a paper limit. Papers are kept: /admin (password
// TPR_ADMIN_PASSWORD) lists them all and publishes the good ones to the
// public /library; a paper not published is reached only by its own link.

const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { Worker } = require('node:worker_threads');
const { handle, VERSION } = require('./core');

const PORT = Number(process.env.PORT) || 8787;
const PAPERS = (process.env.TPR_PAPERS_DIR || '').trim() || path.join(require('node:os').homedir(), 'TPR');
const WORKERS = Math.max(1, Number(process.env.TPR_WORKERS) || 2);
const MAX_BODY = 4 * 1024 * 1024; // a long paper's Markdown
const CALL_TIMEOUT = 30e3;
const PAPER_TIMEOUT = 150e3; // printing the PDF

// ------------------------------------------------------------ rate limits
// Per visitor, in a sliding window: plenty for one person researching,
// too little to scrape the books or flood the server.
const LIMITS = { request: [300, 10 * 60e3], paper: [20, 60 * 60e3] };
const seen = new Map(); // `${kind} ${ip}` -> times

function allowed(kind, ip) {
  const [max, window] = LIMITS[kind];
  const key = `${kind} ${ip}`;
  const now = Date.now();
  const times = (seen.get(key) || []).filter((t) => now - t < window);
  if (times.length >= max) return false;
  times.push(now);
  seen.set(key, times);
  return true;
}

setInterval(() => {
  const now = Date.now();
  for (const [key, times] of seen) if (now - times[times.length - 1] > 60 * 60e3) seen.delete(key);
}, 10 * 60e3).unref();

// ---------------------------------------------------------------- workers
const idle = [];
const queue = [];

function spawn() {
  const w = new Worker(path.join(__dirname, 'worker.js'), { env: process.env });
  w.on('error', (e) => console.error('worker:', e.message));
  idle.push(w);
}
for (let i = 0; i < WORKERS; i++) spawn();

/** Runs a tool call in a worker; a call that runs too long ends its worker. */
function callTool(name, args) {
  return new Promise((resolve, reject) => {
    queue.push({ name, args, resolve, reject });
    next();
  });
}

function next() {
  while (idle.length && queue.length) {
    const w = idle.pop();
    const job = queue.shift();
    const timer = setTimeout(() => {
      w.removeAllListeners('message');
      w.terminate();
      spawn();
      job.resolve({
        content: [{ type: 'text', text: 'This took too long and was stopped. Use a narrower search or query.' }],
        isError: true,
      });
      next();
    }, job.name === 'tpr_save_paper' ? PAPER_TIMEOUT : CALL_TIMEOUT);
    w.once('message', (m) => {
      clearTimeout(timer);
      idle.push(w);
      if (m.error) job.reject(Object.assign(new Error(m.error.message), { code: m.error.code }));
      else job.resolve(m.result);
      next();
    });
    w.postMessage({ name: job.name, args: job.args });
  }
}

// ----------------------------------------------------------------- papers
const TYPES = { '.pdf': 'application/pdf', '.html': 'text/html; charset=utf-8', '.md': 'text/markdown; charset=utf-8' };

function servePaper(req, res, rest) {
  const [id, file] = rest.split('/').map((x) => decodeURIComponent(x || ''));
  const type = TYPES[path.extname(file || '')];
  if (!/^[\w-]{6,40}$/.test(id || '') || !file || file.includes('/') || file.startsWith('.') || !type) {
    return reply(res, 404, 'Not found');
  }
  const p = path.join(PAPERS, id, file);
  fs.stat(p, (err, st) => {
    if (err || !st.isFile()) return reply(res, 404, 'Not found');
    res.writeHead(200, { 'Content-Type': type, 'Content-Length': st.size, 'Cache-Control': 'public, max-age=86400' });
    if (req.method === 'HEAD') return res.end();
    fs.createReadStream(p).pipe(res);
  });
}

// ---------------------------------------------------------------- library
const LIBRARY = path.join(PAPERS, 'library.json');
const PRIVACY_URL = 'https://americanmonk.org/privacy-policy-for-tpr-research/';
const html = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function published() {
  try { return new Set(JSON.parse(fs.readFileSync(LIBRARY, 'utf8')).published || []); } catch { return new Set(); }
}

function setPublished(set) {
  fs.writeFileSync(LIBRARY + '.part', JSON.stringify({ published: [...set] }, null, 1));
  fs.renameSync(LIBRARY + '.part', LIBRARY);
}

/** Every saved paper, newest first. */
function papers() {
  let dirs = [];
  try { dirs = fs.readdirSync(PAPERS, { withFileTypes: true }); } catch { return []; }
  const out = [];
  for (const d of dirs) {
    if (!d.isDirectory()) continue;
    try {
      const meta = JSON.parse(fs.readFileSync(path.join(PAPERS, d.name, 'meta.json'), 'utf8'));
      out.push({ id: d.name, ...meta });
    } catch {}
  }
  return out.sort((a, b) => String(b.saved).localeCompare(String(a.saved)));
}

const PAGE_CSS = `
:root{--ink:#1f1f1f;--muted:#5f5f5f;--rule:#e2ddd3;--bg:#fbf8f2;--card:#fff;--qbg:#efefef;--link:#1a5fb4;--accent:#8a5a14}
@media (prefers-color-scheme:dark){:root{--ink:#e8e4dc;--muted:#a59f94;--rule:#3a362f;--bg:#1b1916;--card:#24211d;
 --qbg:#2e2b26;--link:#8ab4f8;--accent:#e0b060}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:17px/1.55 "Noto Serif","Gentium Plus",Georgia,serif}
main{max-width:46rem;margin:0 auto;padding:1.5rem 16px 3rem}
a{color:var(--link);text-decoration:none}a:hover{text-decoration:underline}
header{display:flex;align-items:center;gap:14px;margin:.5rem 0 1.2rem}
header img{width:64px;height:64px}
header h1{font-size:1.7rem;line-height:1.15;margin:0}
header p{margin:.15rem 0 0;color:var(--muted);font-size:.95rem}
.box{background:var(--qbg);border-left:4px solid var(--accent);border-radius:6px;padding:.8rem 1rem;margin:1rem 0}
.box p{margin:.35rem 0}
.url{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin:.5rem 0}
.url code{font:15px ui-monospace,Menlo,monospace;background:var(--card);border:1px solid var(--rule);border-radius:6px;
 padding:.35rem .6rem;word-break:break-all}
button,.btn{font:600 13px system-ui,-apple-system,"Segoe UI",sans-serif;border:1px solid var(--rule);background:var(--card);
 color:var(--ink);border-radius:6px;padding:.35rem .7rem;cursor:pointer}
button:hover{border-color:var(--accent)}
button.danger{color:#c62828}
input[type=search]{width:100%;font:16px system-ui,sans-serif;padding:.55rem .8rem;border:1px solid var(--rule);
 border-radius:8px;background:var(--card);color:var(--ink);margin:.4rem 0 1rem}
.card{background:var(--card);border:1px solid var(--rule);border-radius:10px;padding:.9rem 1.1rem;margin:.8rem 0}
.card h2{font-size:1.15rem;line-height:1.3;margin:0 0 .3rem}
.card p{margin:.2rem 0;color:var(--muted);font-size:.95rem}
.meta{font:13px system-ui,-apple-system,"Segoe UI",sans-serif;color:var(--muted);margin-top:.5rem;display:flex;
 gap:.9rem;flex-wrap:wrap;align-items:center}
.pill{font:700 11px system-ui,sans-serif;letter-spacing:.05em;text-transform:uppercase;color:#1b5e20;background:#e6f4e8;
 border-radius:999px;padding:.1rem .5rem}
form{display:inline}
details{margin:.5rem 0;border-top:1px solid var(--rule);padding-top:.45rem}
summary{cursor:pointer}
details ol,details ul{margin:.4rem 0 .4rem 1.2rem;padding:0}
details li{margin:.25rem 0}
details p{font-size:.92rem;color:var(--muted)}
code{font:14px ui-monospace,Menlo,monospace;background:var(--card);border-radius:4px;padding:0 .25em}
footer{margin-top:2.5rem;padding-top:1rem;border-top:1px solid var(--rule);color:var(--muted);font-size:.85rem;text-align:center}
.empty{color:var(--muted);font-style:italic}
`;

const page = (title, body) => `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>${html(title)}</title>
<link rel="icon" href="/logo.png"><style>${PAGE_CSS}</style></head><body><main>${body}
<footer><a href="https://americanmonk.org/tipitaka-pali-reader/">Tipitaka Pali Reader</a> ·
<a href="/library">Library</a> · <a href="${PRIVACY_URL}">Privacy</a></footer></main></body></html>`;

const head = (title, sub) => `<header><img src="/logo.png" alt=""><div><h1>${html(title)}</h1>
${sub ? `<p>${sub}</p>` : ''}</div></header>`;

const sendHtml = (res, body, extra = {}) => reply(res, 200, body, { 'Content-Type': 'text/html; charset=utf-8', ...extra });

/** The paper's first paragraph of text, for the library card. */
const excerpts = new Map();
function excerptOf(p) {
  if (excerpts.has(p.id)) return excerpts.get(p.id);
  let text = '';
  try {
    const md = fs.readFileSync(path.join(PAPERS, p.id, p.file + '.md'), 'utf8');
    const para = md.split(/\n\s*\n/).map((x) => x.trim())
      .find((x) => x && !/^(#|>|\||[-*]\s|\d+\.\s|\{\{|<)/.test(x) && x.length > 40) || '';
    text = para.replace(/\[([^\]]*)\]\([^)]*\)/g, '$1').replace(/[*_`#>]/g, '').replace(/\s+/g, ' ').trim();
    if (text.length > 240) text = text.slice(0, 240).replace(/\s+\S*$/, '') + '…';
  } catch {}
  excerpts.set(p.id, text);
  return text;
}

function card(p, extra = '') {
  const f = encodeURIComponent(p.file);
  const ex = excerptOf(p);
  return `<article class="card" data-text="${html((p.title + ' ' + ex).toLowerCase())}">
<h2><a href="/p/${p.id}/${f}.html">${html(p.title)}</a></h2>${ex ? `<p>${html(ex)}</p>` : ''}
<div class="meta"><span>${html(String(p.saved).slice(0, 10))}</span>
${p.pdf ? `<a href="/p/${p.id}/${f}.pdf">PDF</a>` : ''}<a href="/p/${p.id}/${f}.md">Markdown</a>${extra}</div></article>`;
}

const FILTER = `<input type="search" placeholder="Search the papers…" oninput="
for(const c of document.querySelectorAll('.card'))c.hidden=!c.dataset.text.includes(this.value.toLowerCase())">`;

const connectBox = () => {
  const url = (process.env.TPR_PUBLIC_URL || '') + '/mcp';
  const step = (title, open, body) => `<details${open ? ' open' : ''}><summary><b>${title}</b></summary>${body}</details>`;
  return `<div class="box"><p><b>Research the Tipiṭaka with your AI app.</b> Add this address to it as a custom
connector:</p>
<div class="url"><code>${html(url)}</code><button onclick="navigator.clipboard.writeText('${url}');
this.textContent='Copied'">Copy</button></div>
${step('Claude (claude.ai, desktop and phone)', true, `<ol>
<li>On claude.ai, open <b>Customize › Connectors</b> (older layout: Settings › Connectors).</li>
<li>Click <b>Add custom connector</b>. Name: <i>TPR Research</i>; URL: the address above.</li>
<li>Authentication: <b>No sign-in</b>. Click <b>Add</b>.</li>
<li>In a new chat, turn TPR Research on in the tools menu (<b>+</b>) and ask. It then works in the Claude phone app too.</li>
</ol><p>The free plan allows one custom connector.</p>`)}
${step('ChatGPT', false, `<ol>
<li>Open <b>Settings › Apps</b> (or Apps &amp; Connectors) <b>› Advanced settings</b> and turn on <b>Developer mode</b>.</li>
<li>Back in Apps, click <b>Create</b>. Name: <i>TPR Research</i>; MCP server URL: the address above;
authentication: <b>None</b>. Tick that you trust it, then <b>Create</b>.</li>
<li>In a new chat, choose TPR Research from the <b>+</b> menu (Developer mode) and ask.</li>
</ol><p>Needs a paid plan (Plus, Pro, Business…). On a work account the admin may have to allow developer mode.
Some plans allow only read-only tools: if ChatGPT cannot save the paper, ask it to give the paper in the chat.</p>`)}
${step('Grok', false, `<ol>
<li>Go to <b>grok.com/connectors</b>, click <b>New Connector › Custom</b>.</li>
<li>Enter the address above, with no authentication, and save.</li>
<li>In a new chat, turn the connector on and ask.</li>
</ol><p>Custom connectors may need a paid Grok plan.</p>`)}
${step('Gemini', false, `<p>The Gemini website and phone app cannot add connectors yet. Use Google's
<b>Antigravity</b> app or the <b>Gemini CLI</b>:</p><ul>
<li><b>Antigravity:</b> in <code>~/.gemini/config/mcp_config.json</code>, under <code>"mcpServers"</code>, add
<code>"tpr-research": { "serverUrl": "${html(url)}" }</code>, then restart Antigravity. (Or use
<b>Settings › AI › Gemini (Antigravity) setup</b> in Tipitaka Pali Reader on a computer.)</li>
<li><b>Gemini CLI:</b> <code>gemini mcp add --transport http tpr-research ${html(url)}</code></li>
</ul>`)}
<p>Then ask about a sutta, a word or a teaching, and ask for a paper: quotes come with their translation and links
that open <a href="https://americanmonk.org/tipitaka-pali-reader/">Tipitaka Pali Reader</a> on the right page.</p></div>`;
};

function homePage(res) {
  const n = published().size;
  sendHtml(res, page('TPR Research', `${head('TPR Research', 'Pāḷi Tipiṭaka research tools for AI apps')}
${connectBox()}
<p>TPR Research searches the Pāḷi canon, the Aṭṭhakathā and Ṭīkā, translations and the Digital Pāḷi Dictionary, and
writes research papers with every claim quoted from the texts.</p>
<div class="card"><p style="margin:0 0 .3rem;font:700 11px system-ui,sans-serif;letter-spacing:.05em;
text-transform:uppercase">Sample paper</p><h2><a href="/p/xIZ0RW2L7EFL/venerable-subhuti-tpr-report.html">How great was
Venerable Subhūti? A Tipiṭaka report</a></h2><p>His two titles as foremost disciple, explained from the Mūla, Aṭṭhakathā
and Ṭīkā, with every quote linked to TPR.</p><div class="meta"><a href="/p/xIZ0RW2L7EFL/venerable-subhuti-tpr-report.pdf">PDF</a>
<a href="/p/xIZ0RW2L7EFL/venerable-subhuti-tpr-report.html">Web page</a></div></div>
<p><a href="/library">The library</a>${n ? ` has ${n} paper${n === 1 ? '' : 's'}` : ''}: papers chosen after review.</p>
<p style="color:var(--muted);font-size:.9rem">Papers are kept on this server and may be shared, without names, in the
library after review. <a href="${PRIVACY_URL}">Privacy</a></p>`));
}

function libraryPage(res) {
  const on = published();
  const list = papers().filter((p) => on.has(p.id));
  sendHtml(res, page('TPR Research library', `${head('TPR Research library',
    'Research papers on the Pāḷi Tipiṭaka and its commentaries')}
<p>Written by AI with TPR Research from the texts in Tipitaka Pali Reader, and chosen after review. AI can make
mistakes: every quote links to its text, so check what matters to you.</p>
${list.length ? FILTER + list.map((p) => card(p)).join('') : '<p class="empty">No papers yet.</p>'}
${connectBox()}`));
}
/** True when the request carries the admin password (any user name). */
function isAdmin(req) {
  const pw = process.env.TPR_ADMIN_PASSWORD || '';
  if (!pw) return false;
  const m = /^Basic (.+)$/.exec(req.headers.authorization || '');
  if (!m) return false;
  const given = Buffer.from(m[1], 'base64').toString('utf8').split(':').slice(1).join(':');
  const a = Buffer.from(given);
  const b = Buffer.from(pw);
  return a.length === b.length && require('node:crypto').timingSafeEqual(a, b);
}

function adminPage(res) {
  const on = published();
  const list = papers();
  const row = (p) => card(p, `${on.has(p.id) ? '<span class="pill">In library</span>' : ''}
<form method="post" action="/admin"><input type="hidden" name="id" value="${p.id}">
<button name="do" value="${on.has(p.id) ? 'hide' : 'publish'}">${on.has(p.id) ? 'Hide' : 'Publish'}</button>
<button class="danger" name="do" value="delete" onclick="return confirm('Delete this paper for good?')">Delete</button>
</form>`);
  sendHtml(res, page('TPR Research papers', `${head('All papers', `${list.length} saved · ${on.size} in the
<a href="/library">library</a>`)}${list.length ? FILTER + list.map(row).join('') : '<p class="empty">No papers yet.</p>'}`),
  { 'Cache-Control': 'no-store' });
}

function adminPost(req, res) {
  let body = '';
  req.on('data', (c) => { body += c; if (body.length > 4096) req.destroy(); });
  req.on('end', () => {
    const form = new URLSearchParams(body);
    const id = form.get('id') || '';
    if (!/^[\w-]{6,40}$/.test(id) || !fs.existsSync(path.join(PAPERS, id))) return reply(res, 400, 'No such paper');
    const on = published();
    const what = form.get('do');
    if (what === 'publish') on.add(id);
    else if (what === 'hide') on.delete(id);
    else if (what === 'delete') {
      on.delete(id);
      fs.rmSync(path.join(PAPERS, id), { recursive: true, force: true });
    }
    setPublished(on);
    res.writeHead(303, { Location: '/admin' });
    res.end();
  });
}

// ------------------------------------------------------------------- HTTP
function reply(res, status, body, headers = {}) {
  const text = typeof body === 'string' ? body : JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': typeof body === 'string' ? 'text/plain; charset=utf-8' : 'application/json',
    ...headers,
  });
  res.end(text);
}

const rpcError = (id, code, message) => ({ jsonrpc: '2.0', id: id ?? null, error: { code, message } });

/** One JSON-RPC message; null for a notification (no reply). */
async function answer(msg, ip) {
  const isRequest = msg && msg.id !== undefined && msg.id !== null;
  if (!msg || msg.jsonrpc !== '2.0' || typeof msg.method !== 'string') {
    return isRequest ? rpcError(msg.id, -32600, 'Invalid request') : null;
  }
  try {
    let result;
    if (msg.method === 'tools/call') {
      const name = msg.params && msg.params.name;
      if (name === 'tpr_save_paper' && !allowed('paper', ip)) {
        result = { content: [{ type: 'text', text: 'Too many papers from here this hour; try again later.' }], isError: true };
      } else {
        result = await callTool(name, (msg.params && msg.params.arguments) || {});
      }
    } else {
      result = handle(msg);
    }
    return isRequest ? { jsonrpc: '2.0', id: msg.id, result } : null;
  } catch (e) {
    return isRequest ? rpcError(msg.id, e.code || -32603, e.message) : null;
  }
}

const server = http.createServer((req, res) => {
  const ip = String(req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').split(',')[0].trim();
  const url = new URL(req.url, 'http://x');

  if (url.pathname.startsWith('/p/') && (req.method === 'GET' || req.method === 'HEAD')) {
    return servePaper(req, res, url.pathname.slice(3));
  }
  if (url.pathname === '/library' && req.method === 'GET') return libraryPage(res);
  if (url.pathname === '/admin') {
    if (!isAdmin(req)) {
      return reply(res, 401, 'Password needed', { 'WWW-Authenticate': 'Basic realm="TPR Research admin"' });
    }
    // A form posted from another site must not act with the admin's login.
    const origin = req.headers.origin;
    if (req.method === 'POST' && origin && origin !== (process.env.TPR_PUBLIC_URL || '').replace(/\/$/, '')) {
      return reply(res, 403, 'Forbidden');
    }
    if (req.method === 'POST') return adminPost(req, res);
    return adminPage(res);
  }
  if (url.pathname === '/' && req.method === 'GET') return homePage(res);
  if (url.pathname === '/logo.png' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'image/png', 'Cache-Control': 'public, max-age=604800' });
    return fs.createReadStream(path.join(__dirname, '..', 'icon.png')).pipe(res);
  }
  if (url.pathname !== '/mcp') return reply(res, 404, 'Not found');
  // No server-to-client stream: everything is answered in the POST's reply.
  if (req.method === 'GET') return reply(res, 405, 'Method not allowed', { Allow: 'POST' });
  if (req.method === 'DELETE') return reply(res, 200, '');
  if (req.method !== 'POST') return reply(res, 405, 'Method not allowed', { Allow: 'POST' });
  if (!allowed('request', ip)) {
    return reply(res, 429, rpcError(null, -32000, 'Too many requests; wait a few minutes.'), { 'Retry-After': '120' });
  }

  const chunks = [];
  let size = 0;
  req.on('data', (c) => {
    size += c.length;
    if (size > MAX_BODY) {
      reply(res, 413, rpcError(null, -32600, 'Request too large'));
      req.destroy();
    } else chunks.push(c);
  });
  req.on('end', async () => {
    if (res.writableEnded) return;
    let body;
    try {
      body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    } catch {
      return reply(res, 400, rpcError(null, -32700, 'Parse error'));
    }
    const batch = Array.isArray(body);
    const replies = (await Promise.all((batch ? body : [body]).map((m) => answer(m, ip)))).filter(Boolean);
    if (!replies.length) {
      res.writeHead(202);
      return res.end();
    }
    reply(res, 200, batch ? replies : replies[0]);
  });
});

server.listen(PORT, '127.0.0.1', () => {
  console.error(`TPR Research ${VERSION} web server on 127.0.0.1:${PORT}, papers in ${PAPERS}`);
});
