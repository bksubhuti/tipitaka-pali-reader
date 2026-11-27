'use strict';
// One tool call at a time, off the web server's main thread: web.js ends a
// worker whose call runs too long (a heavy tpr_query), so one reader cannot
// stall the server for everyone. Each worker keeps its own database
// connection open between calls.

const { parentPort } = require('node:worker_threads');
const { runTool } = require('./core');

parentPort.on('message', ({ name, args }) => {
  try {
    parentPort.postMessage({ result: runTool(name, args) });
  } catch (e) {
    parentPort.postMessage({ error: { code: e.code || -32603, message: e.message } });
  }
});
