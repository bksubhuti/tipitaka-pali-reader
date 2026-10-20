#!/usr/bin/env node
'use strict';
// TPR Research: a Claude Desktop extension (MCP server over stdio).
//
// Lets Claude search the reader's own Tipitaka Pali Reader databases and
// write papers with Pali quotes and links that open TPR on the right page.
// Plain Node, no packages: Claude Desktop starts it with the Node it ships.
// Messages are JSON-RPC 2.0, one per line; nothing but replies may go to
// stdout, so anything else goes to stderr, which Claude Desktop logs.

const fs = require('node:fs');
const path = require('node:path');
const readline = require('node:readline');
const tpr = require('./tpr');
const paper = require('./paper');

const VERSION = require('../manifest.json').version;
const GUIDE = fs.readFileSync(path.join(__dirname, 'guide.md'), 'utf8');

const str = (description) => ({ type: 'string', description });
const readOnly = { readOnlyHint: true, destructiveHint: false, openWorldHint: false };
const LANG = str('Translation code, e.g. "en" (the default when installed), "my", "zh"; "none" for Pali only.');
const BOOK = str('ePitaka book id, e.g. "M-i", "S-ii", "Vism-ii", "As" (see tpr_books).');
const REF = str('Paragraph, optionally with lines: "1036", "1036:1" or "1036:1-5".');
const LAYER = str('Limit to layers, comma separated: mula, attha, tika, anna.');

const TOOLS = [
  {
    name: 'tpr_research_guide',
    title: 'Research guide',
    description: 'How to research the Tipiṭaka with these tools and the paper format to use. '
      + 'Read it once before any research in a conversation.',
    inputSchema: { type: 'object', properties: {} },
    annotations: readOnly,
    run: () => GUIDE,
  },
  {
    name: 'tpr_status',
    title: 'Check TPR',
    description: 'Finds the Tipitaka Pali Reader data folder and reports the search index and installed translations.',
    inputSchema: { type: 'object', properties: {} },
    annotations: readOnly,
    run: () => tpr.status(),
  },
  {
    name: 'tpr_books',
    title: 'List books',
    description: 'Book ids, layer (Mūla / Aṭṭhakathā / Ṭīkā / Añña) and names. Filter with any text.',
    inputSchema: { type: 'object', properties: { text: str('Filter, e.g. "majjhima", "vism", "Ṭīkā".') } },
    annotations: readOnly,
    run: (a) => tpr.books(a.text),
  },
  {
    name: 'tpr_search',
    title: 'Search',
    description: "Full-text search with TPR's own index. Pali by default; lang \"en\" searches the English. "
      + 'FTS5 syntax: words are ANDed; "exact phrase", OR, NOT, prefix*. Prints BOOK PARA:LINE [layer] text.',
    inputSchema: {
      type: 'object',
      properties: {
        query: str('Search, e.g. kakacena, "dve kalāpā", saw AND bandits.'),
        lang: str('"pali" (default) or a translation code such as "en".'),
        layer: LAYER,
        book: str('Limit to one book id.'),
        limit: { type: 'integer', description: 'Most results to return (default 20).', minimum: 1, maximum: 200 },
      },
      required: ['query'],
    },
    annotations: readOnly,
    run: (a) => tpr.search(a),
  },
  {
    name: 'tpr_count',
    title: 'Count',
    description: 'Counts sentences containing a substring, per book, with totals per layer. '
      + 'Use it to prove presence or absence. Search all spelling forms (e.g. "kalāp").',
    inputSchema: {
      type: 'object',
      properties: { pattern: str('Substring, e.g. "kalāp".'), layer: LAYER, lang: str('Count in a translation instead of the Pali.') },
      required: ['pattern'],
    },
    annotations: readOnly,
    run: (a) => tpr.count(a),
  },
  {
    name: 'tpr_show',
    title: 'Show passage',
    description: 'Pali with the parallel translation, line by line. Read the context before quoting.',
    inputSchema: {
      type: 'object',
      properties: { book: BOOK, ref: REF, lang: LANG, keep_variants: { type: 'boolean', description: 'Keep [variant readings].' } },
      required: ['book', 'ref'],
    },
    annotations: readOnly,
    run: (a) => tpr.show(a),
  },
  {
    name: 'tpr_quote',
    title: 'Quote',
    description: 'A ready Markdown block quote: bold Pali, the translation, and a link that opens TPR on the right page. '
      + 'Paste it into the paper as it is.',
    inputSchema: { type: 'object', properties: { book: BOOK, ref: REF, lang: LANG }, required: ['book', 'ref'] },
    annotations: readOnly,
    run: (a) => tpr.quote(a),
  },
  {
    name: 'tpr_link',
    title: 'Link',
    description: 'The TPR link and page for one line.',
    inputSchema: { type: 'object', properties: { book: BOOK, ref: REF }, required: ['book', 'ref'] },
    annotations: readOnly,
    run: (a) => tpr.link(a),
  },
  {
    name: 'tpr_commentary',
    title: 'Linked commentary',
    description: 'The Aṭṭhakathā and Ṭīkā paragraphs TPR links to a passage, with their first line.',
    inputSchema: {
      type: 'object',
      properties: { book: BOOK, para: { type: 'integer', description: 'Paragraph number.' } },
      required: ['book', 'para'],
    },
    annotations: readOnly,
    run: (a) => tpr.commentary(a),
  },
  {
    name: 'tpr_save_paper',
    title: 'Save paper',
    description: 'Saves a finished Markdown paper in the papers folder (Documents/TPR Research by default) '
      + 'as .md, a styled .html page with grey quote boxes and the TPR logo, and a .pdf when Chrome or Edge '
      + 'is installed, then opens it. Follow the paper format in tpr_research_guide.',
    inputSchema: {
      type: 'object',
      properties: {
        markdown: str('The whole paper, starting with its # title.'),
        file_name: str('File name without extension (default: from the title).'),
        byline: str('Line under the title (default: "Tipitaka Pali Reader sources · <date>").'),
        pdf: { type: 'boolean', description: 'Also print a PDF (default true).' },
        open: { type: 'boolean', description: 'Open the result when done (default true).' },
      },
      required: ['markdown'],
    },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    run: (a) => paper.save(a),
  },
];

const PROMPTS = [
  {
    name: 'research_paper',
    title: 'Research paper',
    description: 'Research a question in your TPR library and write a paper with Pali quotes and TPR links.',
    arguments: [{ name: 'question', description: 'What to research or prove.', required: true }],
    render: (a) => `${GUIDE}\n\n---\n\nResearch this and write the paper, then save it with tpr_save_paper:\n\n${a.question || ''}`,
  },
];

const INSTRUCTIONS = 'TPR Research reads the Pali Tipiṭaka, commentaries and translations in the user\'s '
  + 'Tipitaka Pali Reader, read-only. Before researching, call tpr_research_guide and follow it: '
  + 'search before claiming, quote only with tpr_quote, check context, and use its paper format.';

function handle(msg) {
  const { method, params = {} } = msg;
  switch (method) {
    case 'initialize':
      return {
        protocolVersion: params.protocolVersion || '2025-06-18',
        capabilities: { tools: {}, prompts: {} },
        serverInfo: { name: 'tpr-research', title: 'TPR Research', version: VERSION },
        instructions: INSTRUCTIONS,
      };
    case 'ping':
      return {};
    case 'tools/list':
      return { tools: TOOLS.map(({ run, ...t }) => t) };
    case 'tools/call': {
      const tool = TOOLS.find((t) => t.name === params.name);
      if (!tool) throw Object.assign(new Error(`Unknown tool ${params.name}`), { code: -32602 });
      try {
        return { content: [{ type: 'text', text: tool.run(params.arguments || {}) }] };
      } catch (e) {
        // A tool's failure is a result Claude can read and act on, not a protocol error.
        if (!(e instanceof tpr.TprError)) console.error(e);
        return { content: [{ type: 'text', text: e.message }], isError: true };
      }
    }
    case 'prompts/list':
      return { prompts: PROMPTS.map(({ render, ...p }) => p) };
    case 'prompts/get': {
      const p = PROMPTS.find((x) => x.name === params.name);
      if (!p) throw Object.assign(new Error(`Unknown prompt ${params.name}`), { code: -32602 });
      return {
        description: p.description,
        messages: [{ role: 'user', content: { type: 'text', text: p.render(params.arguments || {}) } }],
      };
    }
    case 'resources/list':
      return { resources: [] };
    default:
      throw Object.assign(new Error(`Method not found: ${method}`), { code: -32601 });
  }
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
