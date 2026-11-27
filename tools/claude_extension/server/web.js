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

const PAGE_CSS = `body{font:16px/1.5 Georgia,serif;max-width:760px;margin:2em auto;padding:0 16px;color:#222;background:#fffdf8}
h1{font-weight:normal}a{color:#7a4b00}li{margin:.6em 0}small{color:#777}
form{display:inline}button{font:inherit;font-size:13px;margin-left:.4em}
@media (prefers-color-scheme:dark){body{background:#1d1b18;color:#ddd}a{color:#e0b060}}`;

const page = (title, body) => `<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>${html(title)}</title>
<style>${PAGE_CSS}</style></head><body>${body}</body></html>`;

function paperLinks(p) {
  const f = encodeURIComponent(p.file);
  return `<a href="/p/${p.id}/${f}.html">${html(p.title)}</a> `
    + (p.pdf ? `<small>(<a href="/p/${p.id}/${f}.pdf">PDF</a>)</small> ` : '')
    + `<small>${html(String(p.saved).slice(0, 10))}</small>`;
}

function libraryPage(res) {
  const on = published();
  const list = papers().filter((p) => on.has(p.id));
  reply(res, 200, page('TPR Research library', `<h1>TPR Research library</h1>
<p>Research papers on the Pāḷi Tipiṭaka and its commentaries, written by AI with TPR Research from the texts in
<a href="https://americanmonk.org/tipitaka-pali-reader/">Tipitaka Pali Reader</a>, and chosen after review.
AI can make mistakes: check the quotes, which link to the texts.</p>
${list.length ? `<ul>${list.map((p) => `<li>${paperLinks(p)}</li>`).join('')}</ul>` : '<p>No papers yet.</p>'}
<p><small><a href="${PRIVACY_URL}">Privacy</a></small></p>`), { 'Content-Type': 'text/html; charset=utf-8' });
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
  const row = (p) => `<li>${paperLinks(p)}
<form method="post" action="/admin"><input type="hidden" name="id" value="${p.id}">
<button name="do" value="${on.has(p.id) ? 'hide' : 'publish'}">${on.has(p.id) ? 'Hide from library' : 'Publish'}</button>
<button name="do" value="delete" onclick="return confirm('Delete this paper for good?')">Delete</button></form>
${on.has(p.id) ? ' <small>✓ in library</small>' : ''}</li>`;
  reply(res, 200, page('TPR Research papers', `<h1>All papers (${list.length})</h1>
<p><a href="/library">Public library</a> · ${on.size} published</p><ul>${list.map(row).join('')}</ul>`),
  { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
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
  if (url.pathname === '/' && req.method === 'GET') {
    return reply(res, 200, `TPR Research ${VERSION}: Pāḷi Tipiṭaka research tools for AI apps.\n\n`
      + 'Add this server in your AI app as a custom connector: ' + (process.env.TPR_PUBLIC_URL || '') + '/mcp\n\n'
      + 'Papers made with it are kept on this server and may be shared, without names, in the library after '
      + `review: ${(process.env.TPR_PUBLIC_URL || '')}/library\nPrivacy: ${PRIVACY_URL}\n`);
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
