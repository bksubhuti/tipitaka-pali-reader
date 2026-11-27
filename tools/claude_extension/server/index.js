#!/usr/bin/env node
'use strict';
// TPR Research: a Claude Desktop extension (MCP server over stdio).
//
// Lets Claude search the reader's own Tipitaka Pali Reader databases and
// write papers with Pali quotes and links that open TPR on the right page.
// Plain Node, no packages: Claude Desktop starts it with the Node it ships.
// Messages are JSON-RPC 2.0, one per line; nothing but replies may go to
// stdout, so anything else goes to stderr, which Claude Desktop logs.
//
// With TPR_WEB=1 it is the public web server instead (web.js).

if (process.env.TPR_WEB === '1') {
  require('./web');
  return;
}

const fs = require('node:fs');
const path = require('node:path');
const readline = require('node:readline');
const { handle, VERSION } = require('./core');

// Tells TPR the extension is installed: Claude Desktop starts this server
// each time it opens, so a fresh note means it is set up. TPR reads
// ~/TPR/.tpr-research (its sandbox cannot see Claude's own folders).
// Other apps start the same server with TPR_HOST set by TPR's setup
// (codex in ~/.codex/config.toml, antigravity in ~/.gemini/config/
// mcp_config.json): their note is .tpr-research-<host>, so TPR can tell
// which app has it.
const HOST = /^[a-z]+$/.test(process.env.TPR_HOST || '') ? process.env.TPR_HOST : '';
const NOTE = HOST ? `.tpr-research-${HOST}` : '.tpr-research';
try {
  const dir = path.join(require('node:os').homedir(), 'TPR');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, NOTE),
    JSON.stringify({ version: VERSION, seen: new Date().toISOString() }) + '\n');
} catch (e) {
  process.stderr.write(`could not write ~/TPR/${NOTE}: ${e.message}\n`);
}

const send = (obj) => process.stdout.write(JSON.stringify(obj) + '\n');

readline.createInterface({ input: process.stdin }).on('line', (line) => {
  if (!line.trim()) return;
  let msg;
  try {
    msg = JSON.parse(line);
  } catch {
    send({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error' } });
    return;
  }
  const isRequest = msg.id !== undefined && msg.id !== null;
  try {
    const result = handle(msg);
    if (isRequest) send({ jsonrpc: '2.0', id: msg.id, result });
  } catch (e) {
    if (isRequest) send({ jsonrpc: '2.0', id: msg.id, error: { code: e.code || -32603, message: e.message } });
  }
});

process.stdin.on('end', () => process.exit(0));
