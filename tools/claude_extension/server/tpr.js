'use strict';
// Read-only access to Tipitaka Pali Reader's databases.
//
// A port of the tpr-research skill's tpr.py, so that the Claude Desktop
// extension answers exactly as the skill does. Every database is opened
// read-only: SQLite refuses any write, whatever the operating system allows.
// node:sqlite comes with the Node that Claude Desktop runs extensions in, so
// nothing has to be installed.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');

const HOME = os.homedir();
const LAYERS = { mula: 'Mūla', attha: 'Aṭṭhakathā', tika: 'Ṭīkā', anna: 'Añña' };
const TAG = /<[^>]*>/g;
const VARIANT = /\s*\[[^\]]*\]/g;

class TprError extends Error {}
const fail = (msg) => { throw new TprError(msg); };

/** Folders named like [pattern] (a * wildcard in one segment) under [dir]. */
function globDirs(dir, pattern) {
  try {
    const re = new RegExp('^' + pattern.split('*').map(escapeRe).join('.*') + '$');
    return fs.readdirSync(dir).filter((n) => re.test(n)).map((n) => path.join(dir, n));
  } catch {
    return [];
  }
}
const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function candidates() {
  const appData = process.env.APPDATA || '';
  const local = process.env.LOCALAPPDATA || '';
  return [
    // macOS (App Store / notarized build is sandboxed)
    `${HOME}/Library/Containers/org.americanmonk.tpp/Data/Library/Application Support/org.americanmonk.tpp`,
    `${HOME}/Library/Application Support/org.americanmonk.tpp`,
    // Windows (installer build, then Microsoft Store build)
    appData && path.join(appData, 'com.paauk', 'Tipitaka Pali Reader'),
    ...(local
      ? globDirs(path.join(local, 'Packages'), '*TipitakaPaliReader*').map((p) =>
          path.join(p, 'LocalCache', 'Roaming', 'com.paauk', 'Tipitaka Pali Reader'))
      : []),
    // Linux
    `${HOME}/.local/share/com.paauk.tipitaka_pali_reader`,
    ...globDirs(`${HOME}/snap`, '*').map((p) => path.join(p, 'current', '.local', 'share', 'com.paauk.tipitaka_pali_reader')),
    ...globDirs(`${HOME}/.var/app`, '*').map((p) => path.join(p, 'data', 'com.paauk.tipitaka_pali_reader')),
  ].filter(Boolean);
}

const hasDb = (d) => fs.existsSync(path.join(d, 'tipitaka_pali.db'));

/** A value Claude Desktop passed in, or nothing if the setting was left empty. */
function setting(name) {
  const v = (process.env[name] || '').trim();
  return v && !v.startsWith('${') ? v : '';
}

function findDir() {
  const chosen = setting('TPR_DB_DIR');
  if (chosen) {
    if (hasDb(chosen)) return chosen;
    fail(`The TPR data folder in this extension's settings (${chosen}) has no tipitaka_pali.db.`);
  }
  for (const d of candidates()) if (hasDb(d)) return d;
  // Last resort: look a few levels down the usual roots.
  const roots = [`${HOME}/Library`, process.env.APPDATA, process.env.LOCALAPPDATA,
    `${HOME}/.local/share`, `${HOME}/snap`, `${HOME}/.var`].filter(Boolean);
  for (const root of roots) {
    const found = walk(root, 6);
    if (found) return found;
  }
  fail('Could not find the TPR data folder (tipitaka_pali.db).\n'
    + 'Open Tipitaka Pali Reader once so it finishes setting up, then try again.\n'
    + "If it is installed somewhere unusual, set the folder in this extension's settings in Claude.");
}

function walk(dir, depth) {
  if (depth < 0) return null;
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return null; }
  if (entries.some((e) => e.name === 'tipitaka_pali.db') && fs.existsSync(path.join(dir, 'epitaka.db'))) return dir;
  for (const e of entries) {
    if (e.isDirectory() && !e.isSymbolicLink()) {
      const found = walk(path.join(dir, e.name), depth - 1);
      if (found) return found;
    }
  }
  return null;
}

let cached = null;

/** The open connection, with ePitaka and every installed translation attached. */
function connect() {
  if (cached) return cached;
  const d = findDir();
  const epi = path.join(d, 'epitaka.db');
  if (!fs.existsSync(epi)) {
    fail('epitaka.db (the sentence-level Pali) is missing. Open TPR and let it finish its first-run setup.');
  }
  const db = new DatabaseSync(path.join(d, 'tipitaka_pali.db'), { readOnly: true });
  // Attached databases share the connection's read-only mode.
  db.prepare('ATTACH DATABASE ? AS epi').run(epi);
  for (const f of fs.readdirSync(d).sort()) {
    const m = /^lang_([a-z]{2,3})\.db$/.exec(f);
    if (m) db.prepare(`ATTACH DATABASE ? AS lang_${m[1]}`).run(path.join(d, f));
  }
  cached = { db, dir: d };
  return cached;
}

const all = (sql, ...args) => connect().db.prepare(sql).all(...args);
const get = (sql, ...args) => connect().db.prepare(sql).get(...args);

function langs() {
  return all('PRAGMA database_list').map((r) => r.name).filter((n) => n.startsWith('lang_')).map((n) => n.slice(5));
}

/** Text for display: tags removed in place (<b>x</b>ti stays one word). */
function clean(t, variants = true) {
  t = (t || '').replace(TAG, '').replace(/\s+/g, ' ').trim();
  t = t.replace(/\s+\)/g, ')').replace(/\(\s+/g, '(');
  return variants ? t.replace(VARIANT, '') : t;
}

/** Words as TPR's index builder counts them: each tag becomes a space. */
function indexWords(t) {
  t = (t || '').replace(TAG, ' ').replace(/\s+/g, ' ').trim();
  return t ? t.split(' ').length : 0;
}

/** '1036' or '1036:1' or '1036:1-5' -> [para, firstLine or null, lastLine or null]. */
function parseRef(ref) {
  const m = /^(\d+)(?::(\d+)(?:-(\d+))?)?$/.exec(String(ref).trim());
  if (!m) fail(`Bad reference "${ref}"; use PARA, PARA:LINE or PARA:L1-L2`);
  const a = m[2] ? Number(m[2]) : null;
  return [Number(m[1]), a, m[3] ? Number(m[3]) : a];
}

function lines(book, para, a, b, lang) {
  let sql = 'SELECT s.line_id, s.pali' + (lang ? ', e.translation' : '') + ' FROM epi.sentences s'
    + (lang ? ` LEFT JOIN lang_${lang}.sentences e USING(book_id, para_id, line_id)` : '')
    + ' WHERE s.book_id=? AND s.para_id=?';
  const args = [book, para];
  if (a !== null) { sql += ' AND s.line_id BETWEEN ? AND ?'; args.push(a, b); }
  const rows = all(sql + ' ORDER BY s.line_id', ...args);
  if (!rows.length) fail(`No text at ${book} ${para}${a !== null ? ':' + a : ''} (check the id with tpr_books).`);
  return rows;
}

/** Opens TPR on the page where the line is. The page comes from the unit's
 *  page_map ('wordOffset:page'), counted exactly as TPR's index builder counts
 *  words; the unit's own start page is often one page too early. */
function tprLink(book, para, line = 1, firstWords = '') {
  const u = get('SELECT u.bookid, b.name, u.page_map, u.start_para FROM search_unit u '
    + 'JOIN books b ON b.id=u.bookid WHERE u.epi_book=? AND ? BETWEEN u.start_para AND u.end_para '
    + 'ORDER BY u.start_para DESC LIMIT 1', book, para);
  if (!u) return null;
  let offset = 0;
  for (const r of all('SELECT para_id, line_id, pali FROM epi.sentences WHERE book_id=? '
    + 'AND para_id BETWEEN ? AND ? ORDER BY para_id, line_id', book, u.start_para, para)) {
    if (r.para_id === para && r.line_id >= line) break;
    offset += indexWords(r.pali);
  }
  let page = null;
  for (const entry of String(u.page_map || '').split(',')) {
    const [at, pg] = entry.split(':');
    if (Number(at) <= offset) page = Number(pg);
  }
  const sel = clean(firstWords, false).split(/\s+/).filter(Boolean).slice(0, 6).join(' ');
  const q = new URLSearchParams({
    book_id: u.bookid, page_number: String(page), name: u.name, note: '',
    selected_text: Buffer.from(sel, 'utf8').toString('base64'),
  });
  return { url: `https://tpr.pali.tools/open?${q}`, name: u.name, page };
}

function defaultLang(want) {
  const have = langs();
  if (!want) return have.includes('en') ? 'en' : (have[0] || null);
  if (want === 'none' || want === 'pali') return null;
  if (!have.includes(want)) {
    fail(`No lang_${want}.db installed. Installed: ${have.join(', ') || 'none'}. `
      + 'Download translations in TPR: Settings > Download.');
  }
  return want;
}

function layerFilter(layer) {
  if (!layer) return ['', []];
  const cats = String(layer).split(',').map((x) => x.trim()).filter(Boolean).map((x) => {
    if (!LAYERS[x]) fail(`Unknown layer "${x}"; use mula, attha, tika or anna.`);
    return LAYERS[x];
  });
  return [` AND b.category IN (${cats.map(() => '?').join(',')})`, cats];
}

// ------------------------------------------------------------------ commands

function status() {
  const { dir } = connect();
  const meta = Object.fromEntries(all('SELECT key, value FROM search_meta').map((r) => [r.key, r.value]));
  const units = get('SELECT count(*) AS n FROM search_unit').n;
  const out = [
    `TPR folder  ${dir}`,
    `Pali index  ${units} units${units ? '' : '  <- missing: open TPR and run a search once'}`,
    `Index langs ${meta.languages || '(none)'}`,
    `Sentences   ${get('SELECT count(*) AS n FROM epi.sentences').n.toLocaleString('en')} Pali`,
  ];
  for (const code of langs()) {
    out.push(`            ${get(`SELECT count(*) AS n FROM lang_${code}.sentences`).n.toLocaleString('en')} ${code}`);
  }
  if (!langs().includes('en')) out.push('No English: in TPR open Settings > Download and add the English translation.');
  return out.join('\n');
}

function books(text) {
  const f = (text || '').toLowerCase();
  return all('SELECT book_id, category, book_name FROM epi.books ORDER BY id')
    .filter((r) => !f || `${r.book_id} ${r.category} ${r.book_name}`.toLowerCase().includes(f))
    .map((r) => `${r.book_id.padEnd(16)} ${r.category.padEnd(11)} ${r.book_name}`)
    .join('\n') || 'No books match.';
}

function search({ query, lang = 'pali', layer, book, limit = 20 }) {
  const l = lang === 'pali' ? null : defaultLang(lang);
  const [lf, la] = layerFilter(layer);
  const bf = book ? ' AND u.epi_book=?' : '';
  const ba = book ? [book] : [];
  let sql, params;
  if (l) {
    sql = 'SELECT u.epi_book, u.start_para, u.end_para, b.category FROM fts_translation_unit f '
      + 'JOIN search_translation_unit t ON t.rowid_=f.rowid JOIN search_unit u ON u.id=t.unit_id '
      + 'JOIN epi.books b ON b.book_id=u.epi_book WHERE fts_translation_unit MATCH ? AND t.lang=?'
      + `${lf}${bf} ORDER BY u.id LIMIT ?`;
    params = [query, l, ...la, ...ba, limit];
  } else {
    sql = 'SELECT u.epi_book, u.start_para, u.end_para, b.category FROM fts_unit f '
      + 'JOIN search_unit u ON u.id=f.rowid JOIN epi.books b ON b.book_id=u.epi_book '
      + `WHERE fts_unit MATCH ?${lf}${bf} ORDER BY u.id LIMIT ?`;
    params = [query, ...la, ...ba, limit];
  }
  let hits;
  try {
    hits = all(sql, ...params);
  } catch (e) {
    fail(`Search failed (${e.message}). FTS5 syntax: words are ANDed; use "exact phrase", OR, NOT, prefix*.`);
  }
  const words = (query.match(/"[^"]+"|\S+/g) || [])
    .filter((w) => !['AND', 'OR', 'NOT'].includes(w.toUpperCase()))
    .map((w) => w.replace(/^["*]+|["*]+$/g, '').toLowerCase());
  const out = [];
  const seen = new Set();
  for (const h of hits) {
    // Show the first line in the unit that holds the first search word.
    const col = l ? 'e.translation' : 's.pali';
    const join = l ? ` JOIN lang_${l}.sentences e USING(book_id, para_id, line_id)` : '';
    let best = null;
    const first = words.length ? words[0].split(/\s+/)[0] : '';
    for (const r of all(`SELECT s.para_id, s.line_id, ${col} AS text FROM epi.sentences s${join} `
      + 'WHERE s.book_id=? AND s.para_id BETWEEN ? AND ? ORDER BY s.para_id, s.line_id',
    h.epi_book, h.start_para, h.end_para)) {
      if (first && (r.text || '').toLowerCase().includes(first)) { best = r; break; }
    }
    const where = best ? `${best.para_id}:${best.line_id}` : `${h.start_para}-${h.end_para}`;
    const key = `${h.epi_book} ${where}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(`${key}  [${h.category}]  ${best ? clean(best.text).slice(0, 160) : ''}`);
  }
  return out.join('\n') || 'No matches.';
}

function count({ pattern, layer, lang }) {
  const [lf, la] = layerFilter(layer);
  let col = 's.pali';
  let join = '';
  if (lang) {
    const l = defaultLang(lang);
    if (l) { col = 'e.translation'; join = ` JOIN lang_${l}.sentences e USING(book_id, para_id, line_id)`; }
  }
  const rows = all(`SELECT b.category, s.book_id, b.book_name, count(*) AS n FROM epi.sentences s${join} `
    + 'JOIN epi.books b ON b.book_id=s.book_id '
    + `WHERE ${col} LIKE ?${lf} GROUP BY s.book_id ORDER BY b.category, count(*) DESC`,
  `%${pattern}%`, ...la);
  const total = {};
  const out = rows.map((r) => {
    total[r.category] = (total[r.category] || 0) + r.n;
    return `${r.category.padEnd(11)} ${r.book_id.padEnd(16)} ${String(r.n).padStart(6)}  ${r.book_name}`;
  });
  out.push('--');
  for (const cat of ['Mūla', 'Aṭṭhakathā', 'Ṭīkā', 'Añña']) out.push(`${cat.padEnd(11)} ${String(total[cat] || 0).padStart(6)}`);
  return out.join('\n');
}

function show({ book, ref, lang, keep_variants: keep }) {
  const l = defaultLang(lang);
  const [para, a, b] = parseRef(ref);
  const out = [];
  for (const r of lines(book, para, a, b, l)) {
    out.push(`${para}:${r.line_id}  ${clean(r.pali, !keep)}`);
    if (l) out.push(`${' '.repeat(String(para).length + String(r.line_id).length + 3)}${l.toUpperCase()}: ${clean(r.translation || '-')}`);
  }
  return out.join('\n');
}

function link({ book, ref }) {
  const [para, a] = parseRef(ref);
  const rows = lines(book, para, a ?? 1, a ?? 1, null);
  const r = tprLink(book, para, a ?? rows[0].line_id, rows[0].pali);
  if (!r) fail(`${book} ${para} is not in TPR's search index; no link can be made.`);
  return `${r.url}\n${r.name}, p. ${r.page}`;
}

function quote({ book, ref, lang }) {
  const l = defaultLang(lang);
  const [para, a, b] = parseRef(ref);
  const rows = lines(book, para, a, b, l);
  const pali = rows.map((r) => clean(r.pali)).join(' ');
  const trans = l ? rows.filter((r) => r.translation).map((r) => clean(r.translation)).join(' ').trim() : '';
  const r = tprLink(book, para, rows[0].line_id, rows[0].pali);
  const name = get('SELECT book_name FROM epi.books WHERE book_id=?', book).book_name;
  const out = [`> **${pali}**`, '>'];
  if (trans) out.push(`> ${trans}`, '>');
  out.push(r ? `> [${name}, p. ${r.page} (TPR)](${r.url})` : `> ${name} ${ref}`);
  return out.join('\n');
}

function commentary({ book, para }) {
  const rows = all('SELECT DISTINCT k.dst_book, k.dst_para, b.category, b.book_name FROM epi.book_links k '
    + 'JOIN epi.books b ON b.book_id=k.dst_book WHERE k.src_book=? AND k.src_para=? '
    + 'ORDER BY b.category, k.dst_book, k.dst_para', book, Number(para));
  if (!rows.length) return 'No linked commentary for that paragraph.';
  return rows.map((r) => {
    const first = get('SELECT pali FROM epi.sentences WHERE book_id=? AND para_id=? ORDER BY line_id LIMIT 1',
      r.dst_book, r.dst_para);
    return `${r.category.padEnd(11)} ${r.dst_book} ${String(r.dst_para).padEnd(6)} ${r.book_name}: ${clean(first ? first.pali : '').slice(0, 140)}`;
  }).join('\n');
}

module.exports = { TprError, status, books, search, count, show, link, quote, commentary, clean };
