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
//
// Tool calls run in worker threads with a time limit; each visitor has a
// request limit and a paper limit; papers are deleted after 30 days.

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
const KEEP_PAPERS = 30 * 864e5;

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

function cleanPapers() {
  let dirs = [];
  try { dirs = fs.readdirSync(PAPERS, { withFileTypes: true }); } catch { return; }
  for (const d of dirs) {
    if (!d.isDirectory()) continue;
    const p = path.join(PAPERS, d.name);
    try {
      if (Date.now() - fs.statSync(p).mtimeMs > KEEP_PAPERS) fs.rmSync(p, { recursive: true, force: true });
    } catch {}
  }
}
cleanPapers();
setInterval(cleanPapers, 6 * 60 * 60e3).unref();

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
  if (url.pathname === '/' && req.method === 'GET') {
    return reply(res, 200, `TPR Research ${VERSION}: Pāḷi Tipiṭaka research tools for AI apps.\n`
      + 'Add this server in your AI app as a custom connector: ' + (process.env.TPR_PUBLIC_URL || '') + '/mcp\n');
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
