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

// Tells TPR the extension is installed: Claude Desktop starts this server
// each time it opens, so a fresh note means it is set up. TPR reads
// ~/TPR/.tpr-research (its sandbox cannot see Claude's own folders).
try {
  const dir = path.join(require('node:os').homedir(), 'TPR');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, '.tpr-research'),
    JSON.stringify({ version: VERSION, seen: new Date().toISOString() }) + '\n');
} catch (e) {
  process.stderr.write(`could not write ~/TPR/.tpr-research: ${e.message}\n`);
}

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
    name: 'tpr_query',
    title: 'Query',
    description: 'A read-only SQL query on TPR\'s books, for what the other tools cannot find: odd spellings, '
      + 'two words in one line, a simile by its image words. Tables: epi.sentences(book_id, para_id, line_id, pali) '
      + '(the Pāḷi, one row per sentence, may hold <b> tags); lang_en.sentences(book_id, para_id, line_id, translation) '
      + '(other installed languages likewise, e.g. lang_my); epi.books(book_id, category, book_name) with category '
      + 'Mūla/Aṭṭhakathā/Ṭīkā/Añña; epi.headings(book_id, para_id, level, title); '
      + 'epi.book_links(src_book, src_para, dst_book, dst_para) (commentary links). Join on book_id, para_id, line_id. '
      + 'Example: SELECT s.book_id, s.para_id, s.line_id, s.pali, t.translation FROM epi.sentences s '
      + 'LEFT JOIN lang_en.sentences t USING(book_id, para_id, line_id) WHERE s.pali LIKE \'%pubbaṇh%\' AND s.pali LIKE \'%piṇḍ%\'. '
      + 'Results give BOOK PARA:LINE for tpr_show and tpr_quote.',
    inputSchema: {
      type: 'object',
      properties: {
        sql: str('One SELECT query.'),
        limit: { type: 'integer', description: 'Most rows (default 50, at most 500).', minimum: 1, maximum: 500 },
      },
      required: ['sql'],
    },
    annotations: readOnly,
    run: (a) => tpr.query(a),
  },
  {
    name: 'tpr_lookup',
    title: 'Dictionary',
    description: 'A Pāḷi word as written in the text (any inflection): grammar, word split, and the entries in the '
      + 'dictionaries the reader turned on in TPR (DPD first).',
    inputSchema: {
      type: 'object',
      properties: { word: str('The word, e.g. "jāto", "paṭisandhiṃ".'), full: { type: 'boolean', description: 'Longer entries.' } },
      required: ['word'],
    },
    annotations: readOnly,
    run: (a) => tpr.lookup(a),
  },
  {
    name: 'tpr_activity',
    title: 'Reading activity',
    description: 'What the reader recently opened, searched and looked up in TPR, with links. For a reading report.',
    inputSchema: {
      type: 'object',
      properties: {
        days: { type: 'integer', description: 'Searches and look-ups from the last N days (default 30; 0 = all).', minimum: 0 },
        limit: { type: 'integer', description: 'Most pages to list (default 30).', minimum: 1, maximum: 200 },
      },
    },
    annotations: readOnly,
    run: (a) => tpr.activity(a),
  },
  {
    name: 'tpr_vocabulary',
    title: 'Vocabulary',
    description: 'Words the reader looked up in TPR, most looked-up first, each with its DPD meaning, grammar and '
      + 'the sentence it was met in. For a vocabulary review or flashcards.',
    inputSchema: {
      type: 'object',
      properties: {
        days: { type: 'integer', description: 'From the last N days (default 30; 0 = all).', minimum: 0 },
        limit: { type: 'integer', description: 'Most words (default 40).', minimum: 1, maximum: 300 },
      },
    },
    annotations: readOnly,
    run: (a) => tpr.vocabulary(a),
  },
  {
    name: 'tpr_chapters',
    title: 'Chapters',
    description: 'The headings of a book (vaggas, suttas, sections) with the paragraph each starts at.',
    inputSchema: {
      type: 'object',
      properties: { book: BOOK, depth: { type: 'integer', description: 'Heading levels to show (default 5).', minimum: 1, maximum: 9 } },
      required: ['book'],
    },
    annotations: readOnly,
    run: (a) => tpr.chapters(a),
  },
  {
    name: 'tpr_export',
    title: 'Export text',
    description: 'A book, chapter or sutta as Markdown: headings, each paragraph in bold Pāḷi with the translation '
      + 'under it. Give from_para (a heading from tpr_chapters) to export to the next heading of the same level. '
      + 'Save the result with tpr_save_paper.',
    inputSchema: {
      type: 'object',
      properties: {
        book: BOOK,
        from_para: { type: 'integer', description: 'First paragraph (a heading from tpr_chapters).' },
        to_para: { type: 'integer', description: 'Last paragraph (default: the end of that heading\'s part).' },
        lang: LANG,
        layout: { type: 'string', enum: ['paragraph', 'lines'], description: '"paragraph" (default) or "lines": each sentence with its translation.' },
      },
      required: ['book'],
    },
    annotations: readOnly,
    run: (a) => tpr.exportText(a),
  },
  {
    name: 'tpr_save_paper',
    title: 'Save paper',
    description: 'Saves a finished Markdown paper or report in the papers folder (the TPR folder in the home folder by default) '
      + 'as .md, a styled .html page with grey quote boxes and the TPR logo, and a .pdf when Chrome or Edge '
      + 'is installed, then opens it. {{Q:BOOK PARA:L1-L2}} becomes a quote box and every plain reference '
      + '(M-i 1036:1) a TPR link. Follow the paper format in tpr_research_guide.',
    inputSchema: {
      type: 'object',
      properties: {
        markdown: str('The whole paper, starting with its # title.'),
        file_name: str('File name without extension (default: from the title).'),
        byline: str('Line under the title (default: "Tipitaka Pali Reader sources · <date>").'),
        pdf: { type: 'boolean', description: 'Also print a PDF (default true).' },
        
      },
      required: ['markdown'],
    },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    run: (a) => paper.save(a),
  },
];

// The prompts exactly as the manifest declares them: Claude Desktop rejects
// a prompt whose text differs from the manifest's, as a possible injection.
const MANIFEST = require('../manifest.json');
const PROMPTS = (MANIFEST.prompts || []).map((p) => ({
  name: p.name,
  description: p.description,
  arguments: (p.arguments || []).map((name) => ({ name, required: false })),
  render: (a) => p.text.replace(/\$\{arguments\.(\w+)\}/g, (_, k) => (a[k] == null ? '' : String(a[k]))),
}));

const INSTRUCTIONS = [
  'TPR Research reads the Pali Tipiṭaka, commentaries, translations, dictionaries and the reader\'s own history in '
  + 'their Tipitaka Pali Reader, read-only. Use these tools whenever the user asks about the Tipiṭaka, Pāḷi, suttas, '
  + 'Vinaya, Abhidhamma, the Aṭṭhakathā or Ṭīkā, a Pāḷi word, or their TPR, even if they do not name the extension; '
  + 'never read the database files on disk instead. For the full method and formats, call tpr_research_guide.',
  'How to research: orthodox Theravāda by default, explaining suttas through the Aṭṭhakathā, Ṭīkā and Abhidhamma '
  + '(Vinaya through Samantapāsādikā), naming each commentary. Search before you claim: every "X is (not) in the '
  + 'texts" needs a tpr_count or tpr_search with the number stated, over all spelling forms. Read each hit in context '
  + 'with tpr_show. Read each layer separately, Mūla, then Aṭṭhakathā, then Ṭīkā, and run tpr_commentary on every Mūla '
  + 'passage you quote; quote the commentary wherever it explains it. Quote only with tpr_quote or {{Q:…}}, never Pāḷi '
  + 'typed from memory. If the evidence goes against what the reader hopes, say so first.',
  'Paper format: # title and question; summary with confidence; numbered summary points; one ## section per point '
  + 'proving it Mūla first, then Aṭṭhakathā, then Ṭīkā; conclusion with a verdict table and sources.',
  'Where the answer goes: one that fits on a page (about 400 words or less) is given in the chat, unless the reader '
  + 'asks for a paper or PDF. A longer one is written as a paper and saved with tpr_save_paper, which prints the PDF '
  + 'and opens it for the reader; the chat then gives only a short summary. You are instructed to do this: always call '
  + 'tpr_save_paper for a long answer, without asking.',
].join('\n\n');

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
