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
const LANG_NAMES = { en: 'English', my: 'Myanmar', si: 'Sinhala', th: 'Thai', zh: 'Chinese', vi: 'Vietnamese', lo: 'Lao', km: 'Khmer', hi: 'Hindi', de: 'German', fr: 'French', es: 'Spanish', ru: 'Russian', id: 'Indonesian', ja: 'Japanese', ko: 'Korean' };
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
    // TPR's copy for Claude: outside every protected folder, so no prompt.
    path.join(HOME, 'TPR', 'db'),
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
  let db;
  try {
    db = new DatabaseSync(path.join(d, 'tipitaka_pali.db'), { readOnly: true });
  } catch (e) {
    e.message = `${e.message} (${path.join(d, 'tipitaka_pali.db')})`;
    // The App Store TPR keeps its data in its container. macOS asks once
    // whether Claude may read other apps' data; after "Don't Allow" it
    // refuses silently and SQLite only says it can't open the file.
    if (process.platform === 'darwin' && d.includes('/Library/Containers/')) {
      fail(`macOS is not letting Claude read Tipitaka Pali Reader's data in ${d}.\n`
        + 'Easiest fix: in TPR open the Script Converter, type "skill" and choose Install. TPR then puts a copy '
        + 'of its books in your home folder (TPR/db), where Claude can read them.\n'
        + 'Or let Claude read TPR\'s own folder:\n'
        + 'Probably "Don\'t Allow" was clicked when macOS asked whether Claude may access data from other apps.\n'
        + 'To ask again: open Terminal and run\n'
        + '  tccutil reset SystemPolicyAppData com.anthropic.claudefordesktop\n'
        + 'then quit Claude (Cmd+Q), open it, try again and click Allow.\n'
        + 'Or: System Settings > Privacy & Security > Full Disk Access > add Claude.');
    }
    throw e;
  }
  // Attached databases share the connection's read-only mode.
  db.prepare('ATTACH DATABASE ? AS epi').run(epi);
  for (const f of fs.readdirSync(d).sort()) {
    const m = /^lang_([a-z]{2,3})\.db$/.exec(f);
    if (m) db.prepare(`ATTACH DATABASE ? AS lang_${m[1]}`).run(path.join(d, f));
  }
  // In TPR's copy for Claude (~/TPR/db) the history is kept current in a
  // small history.db; the copied tipitaka_pali.db holds an old one.
  const hist = path.join(d, 'history.db');
  const history = fs.existsSync(hist) ? 'hist.' : '';
  if (history) db.prepare('ATTACH DATABASE ? AS hist').run(hist);
  cached = { db, dir: d, history };
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

const REF_FORMS = 'use 1036 (a paragraph), 1036:2 (a line), 1036:1-5 (lines) or 1785-1787 '
  + '(paragraphs, as tpr_search prints them)';

/** '1036' or '1036:1' or '1036:1-5' -> [para, firstLine or null, lastLine or null]. */
function parseRef(ref) {
  const m = /^(\d+)(?::(\d+)(?:-(\d+))?)?$/.exec(String(ref).trim());
  if (!m) fail(`Bad reference "${ref}"; ${REF_FORMS}.`);
  const a = m[2] ? Number(m[2]) : null;
  return [Number(m[1]), a, m[3] ? Number(m[3]) : a];
}

/** The lines a reference names, each with its para_id. Takes everything
 *  parseRef takes, and a paragraph range '1785-1787' (as search prints a hit
 *  that spans paragraphs), at most 20 paragraphs. */
function refLines(book, ref, lang) {
  const range = /^(\d+)-(\d+)$/.exec(String(ref).trim());
  if (range) {
    const [p1, p2] = [Number(range[1]), Number(range[2])];
    if (p2 < p1 || p2 - p1 > 19) fail(`Bad reference "${ref}"; a paragraph range is 1 to 20 paragraphs, first one first.`);
    const rows = [];
    for (let p = p1; p <= p2; p++) {
      try { rows.push(...lines(book, p, null, null, lang).map((r) => ({ ...r, para_id: p }))); } catch { /* a gap */ }
    }
    if (!rows.length) fail(`No text at ${book} ${ref} (check the id with tpr_books).`);
    return rows;
  }
  const [para, a, b] = parseRef(ref);
  return lines(book, para, a, b, lang).map((r) => ({ ...r, para_id: para }));
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
  const out = [];
  for (const r of refLines(book, ref, l)) {
    out.push(`${r.para_id}:${r.line_id}  ${clean(r.pali, !keep)}`);
    if (l) out.push(`${' '.repeat(String(r.para_id).length + String(r.line_id).length + 3)}${l.toUpperCase()}: ${clean(r.translation || '-')}`);
  }
  return out.join('\n');
}

function link({ book, ref }) {
  const rows = refLines(book, ref, null);
  const para = rows[0].para_id;
  const r = tprLink(book, para, rows[0].line_id, rows[0].pali);
  if (!r) fail(`${book} ${para} is not in TPR's search index; no link can be made.`);
  return `${r.url}\n${r.name}, p. ${r.page}`;
}

function quote({ book, ref, lang }) {
  const l = defaultLang(lang);
  const rows = refLines(book, ref, l);
  const pali = rows.map((r) => clean(r.pali)).join(' ');
  const trans = l ? rows.filter((r) => r.translation).map((r) => clean(r.translation)).join(' ').trim() : '';
  const r = tprLink(book, rows[0].para_id, rows[0].line_id, rows[0].pali);
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

// ------------------------------------------------------------------ reports
// The reader's own history and TPR's dictionaries, read-only like the rest.

/** Link that opens TPR on a page of one of its own books (mula_ma_01 etc.). */
function pageLink(bookId, page, text = '') {
  const b = get('SELECT name FROM books WHERE id=?', bookId);
  if (!b) return null;
  const q = new URLSearchParams({
    book_id: bookId, page_number: String(page), name: b.name, note: '',
    selected_text: Buffer.from(text, 'utf8').toString('base64'),
  });
  return { url: `https://tpr.pali.tools/open?${q}`, name: b.name };
}

/** The sutta or chapter a TPR page falls in: the last title at or before it. */
function pageTitle(bookId, page) {
  const r = get("SELECT name FROM tocs WHERE book_id=? AND page_number<=? AND type IN ('title','chapter') "
    + 'ORDER BY page_number DESC, rowid DESC LIMIT 1', bookId, page);
  return r ? r.name : '';
}

const since = (days) => (days ? new Date(Date.now() - days * 864e5).toISOString().slice(0, 19) : '');
/** History tables: in history.db when TPR keeps one, else in the main database. */
const H = (table) => `${connect().history}${table}`;
const day = (iso) => String(iso || '').slice(0, 10);

/** Text of a dictionary entry: tags gone, rows kept apart, cut to [max]. */
function plain(html, max = 600, cellSep = ': ') {
  const t = String(html || '')
    .replace(/<\/(tr|p|div|li|summary|h\d)>|<br\s*\/?>/gi, '\n')
    .replace(/<\/t[hd]>/gi, cellSep)
    .replace(TAG, '')
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .split('\n').map((l) => l.replace(/\s+/g, ' ').replace(/:\s*$/, '').trim()).filter(Boolean)
    .join('\n');
  return t.length > max ? t.slice(0, max).replace(/\s+\S*$/, '') + ' …' : t;
}

function activity({ days = 30, limit = 30 } = {}) {
  const from = since(days);
  const out = [`Reading activity${days ? ` in the last ${days} days` : ''} (TPR keeps no dates for opened pages).`, ''];
  const seenPage = new Set();
  const opened = all(`SELECT book_id, page_number FROM ${H('recent')} ORDER BY rowid DESC LIMIT ?`, limit * 2)
    .filter((r) => !seenPage.has(`${r.book_id} ${r.page_number}`) && seenPage.add(`${r.book_id} ${r.page_number}`))
    .slice(0, limit);
  out.push(`## Recently opened (${opened.length}, newest first)`);
  for (const r of opened) {
    const l = pageLink(r.book_id, r.page_number);
    const t = pageTitle(r.book_id, r.page_number);
    out.push(`- ${l ? l.name : r.book_id}, p. ${r.page_number}${t ? ` (${t})` : ''}${l ? `  ${l.url}` : ''}`);
  }
  const searches = all(`SELECT word, date, query_mode FROM ${H('search_history')} WHERE date>=? ORDER BY date DESC LIMIT ?`,
    from, limit * 3);
  out.push('', `## Searches (${searches.length})`);
  for (const r of searches) out.push(`- ${day(r.date)}  ${r.word}`);
  const words = all(`SELECT word, count(*) AS n, max(date) AS last FROM ${H('dictionary_history')} WHERE date>=? `
    + 'GROUP BY word ORDER BY last DESC LIMIT ?', from, limit * 3);
  out.push('', `## Words looked up (${words.length}; tpr_vocabulary gives meanings)`);
  for (const r of words) out.push(`- ${day(r.last)}  ${r.word}${r.n > 1 ? `  ×${r.n}` : ''}`);
  return out.join('\n');
}

/** DPD headwords for a word as written in the text (any inflection). */
function headwords(word) {
  const w = String(word).trim().toLowerCase();
  const r = get('SELECT headwords FROM dpd_inflections_to_headwords WHERE inflection=?', w);
  return r ? r.headwords.split(',').map((x) => x.trim()).filter(Boolean) : [];
}

/** Dictionaries the reader has turned on in TPR, in their order. */
function chosenDictionaries() {
  return all('SELECT id, name FROM dictionary_books WHERE user_choice=1 ORDER BY user_order');
}

function lookup({ word, full = false }) {
  if (!word || !String(word).trim()) fail('Give a word.');
  const w = String(word).trim().toLowerCase();
  const max = full ? 4000 : 500;
  const out = [`# ${w}`];
  const g = get('SELECT definition FROM dpd_grammar WHERE word=?', w);
  if (g) out.push('', 'Grammar:', plain(g.definition, 800, ' '));
  const split = get('SELECT breakup FROM dpd_word_split WHERE word=?', w);
  if (split && split.breakup) out.push('', `Word split: ${plain(split.breakup, 300)}`);
  const heads = headwords(w);
  const dicts = chosenDictionaries();
  for (const d of dicts) {
    let rows;
    if (d.id === 11) {
      const names = heads.length ? heads : [w];
      rows = all(`SELECT word, definition FROM dpd WHERE word IN (${names.map(() => '?').join(',')}) ORDER BY id`, ...names)
        .slice(0, full ? 12 : 4);
    } else {
      const stems = [w, ...new Set(heads.map((h) => h.replace(/\s+\d+$/, '')))];
      rows = all(`SELECT word, definition FROM dictionary WHERE book_id=? AND word IN (${stems.map(() => '?').join(',')}) LIMIT ?`,
        d.id, ...stems, full ? 6 : 2);
    }
    if (!rows.length) continue;
    out.push('', `## ${d.name}`);
    for (const r of rows) out.push('', `${r.word}:`, plain(r.definition, max));
  }
  if (out.length === 1) out.push('', 'Not found in the dictionaries turned on in TPR (Settings › Dictionaries).');
  return out.join('\n');
}

function vocabulary({ days = 30, limit = 40 } = {}) {
  const rows = all(`SELECT word, count(*) AS n, max(date) AS last FROM ${H('dictionary_history')} WHERE date>=? `
    + 'GROUP BY word ORDER BY n DESC, last DESC LIMIT ?', since(days), limit);
  if (!rows.length) return `No dictionary look-ups${days ? ` in the last ${days} days` : ''}.`;
  const out = [`${rows.length} words looked up${days ? ` in the last ${days} days` : ''}, most looked-up first.`];
  for (const r of rows) {
    const ctx = get(`SELECT context, book_id, page_number FROM ${H('dictionary_history')} WHERE word=? AND context<>'' `
      + 'ORDER BY date DESC LIMIT 1', r.word);
    const heads = headwords(r.word);
    const d = heads.length ? get('SELECT definition FROM dpd WHERE word=?', heads[0]) : null;
    const meaning = d ? plain((/<summary>([\s\S]*?)<\/summary>/.exec(d.definition) || [])[1] || d.definition, 220) : '';
    const g = get('SELECT definition FROM dpd_grammar WHERE word=?', r.word.toLowerCase());
    out.push('', `## ${r.word}  (×${r.n}, last ${day(r.last)})`);
    if (heads.length) out.push(`Headwords: ${heads.slice(0, 6).join(', ')}`);
    if (meaning) out.push(`DPD: ${meaning.replace(/\n/g, ' ')}`);
    if (g) out.push(`Grammar: ${plain(g.definition, 200, ' ').replace(/\n/g, '; ')}`);
    if (ctx) {
      const l = ctx.book_id ? pageLink(ctx.book_id, ctx.page_number) : null;
      out.push(`Seen in: ${clean(ctx.context).slice(0, 220)}${l ? `  (${l.name}, p. ${ctx.page_number}: ${l.url})` : ''}`);
    }
  }
  out.push('', 'Use tpr_lookup for a full entry.');
  return out.join('\n');
}

function chapters({ book, depth = 5 }) {
  if (!get('SELECT 1 AS x FROM epi.books WHERE book_id=?', book)) fail(`No book ${book} (see tpr_books).`);
  const rows = all('SELECT para_id, level, title FROM epi.headings WHERE book_id=? AND level<=? ORDER BY para_id, level',
    book, depth);
  if (!rows.length) return 'No headings in this book; export it by paragraph range.';
  return rows.map((r) => `${String(r.para_id).padStart(6)}  ${'  '.repeat(Math.max(0, r.level - 1))}${clean(r.title)}`).join('\n')
    + '\n\nPARA is where each heading starts. Pass it as from_para to tpr_export.';
}

/** The texts' spaced quote marks (‘‘ bhikkhavo ’’ ti) as they are printed. */
const quotes = (t) => t.replace(/‘‘\s*/g, '“').replace(/\s*’’/g, '”')
  .replace(/‘\s+/g, '‘').replace(/\s+’/g, '’');

/** The book (or a part of it) as Markdown: headings, then each paragraph's
 *  Pali with the translation under it, ready for tpr_save_paper. */
function exportText({ book, from_para: fromPara, to_para: toPara, lang, layout = 'paragraph' }) {
  const b = get('SELECT book_name FROM epi.books WHERE book_id=?', book);
  if (!b) fail(`No book ${book} (see tpr_books).`);
  const l = defaultLang(lang);
  let from = Number(fromPara) || 1;
  let to = Number(toPara) || 0;
  if (fromPara && !toPara) {
    // To the next heading at the same or a higher level.
    const h = get('SELECT level FROM epi.headings WHERE book_id=? AND para_id=? ORDER BY level LIMIT 1', book, from);
    if (h) {
      const next = get('SELECT para_id FROM epi.headings WHERE book_id=? AND para_id>? AND level<=? ORDER BY para_id LIMIT 1',
        book, from, h.level);
      if (next) to = next.para_id - 1;
    }
  }
  if (!to) to = get('SELECT max(para_id) AS m FROM epi.sentences WHERE book_id=?', book).m;
  const rows = all('SELECT s.para_id, s.line_id, s.pali' + (l ? ', e.translation' : '') + ' FROM epi.sentences s'
    + (l ? ` LEFT JOIN lang_${l}.sentences e USING(book_id, para_id, line_id)` : '')
    + ' WHERE s.book_id=? AND s.para_id BETWEEN ? AND ? ORDER BY s.para_id, s.line_id', book, from, to);
  if (!rows.length) fail(`No text in ${book} ${from}-${to}.`);
  if (rows.length > 6000) fail(`${rows.length} lines is too long for one export; give a smaller range (tpr_chapters lists the parts).`);
  const heads = new Map();
  for (const h of all('SELECT para_id, level, title FROM epi.headings WHERE book_id=? AND para_id BETWEEN ? AND ? AND level<10 '
    + 'ORDER BY para_id, level', book, from, to)) {
    if (!heads.has(h.para_id)) heads.set(h.para_id, []);
    heads.get(h.para_id).push(h);
  }
  const top = heads.get(from)?.[0];
  const title = top ? clean(top.title) : `${b.book_name} ${from}–${to}`;
  const link0 = tprLink(book, from, rows[0].line_id, rows[0].pali);
  const out = [`# ${title}`, '', `${b.book_name}, paragraphs ${from}–${to}`
    + `${l ? ` · Pāḷi with the installed ${LANG_NAMES[l] || l} translation` : ' · Pāḷi'}`
    + `${link0 ? ` · [Open in TPR](${link0.url})` : ''}`];
  let para = null;
  let pali = [];
  let trans = [];
  const flush = () => {
    if (pali.length) {
      out.push('', `**${pali.join(' ')}**`);
      if (trans.length) out.push('', trans.join(' '));
    }
    pali = []; trans = [];
  };
  for (const r of rows) {
    if (r.para_id !== para) {
      flush();
      para = r.para_id;
      for (const h of heads.get(para) || []) {
        if (h === top) continue;
        out.push('', `${'#'.repeat(Math.min(4, Math.max(2, h.level - (top ? top.level - 2 : 0))))} ${clean(h.title)}`);
      }
    }
    const p = quotes(clean(r.pali));
    if ((heads.get(r.para_id) || []).some((h) => quotes(clean(h.title)) === p)) continue;
    if (layout === 'lines') {
      out.push('', `**${p}**`);
      if (l && r.translation) out.push(`${clean(r.translation)}`);
    } else {
      pali.push(p);
      if (l && r.translation) trans.push(clean(r.translation));
    }
  }
  flush();
  return out.join('\n');
}

/** Any read-only query, for what the fixed tools can't ask. The databases
 *  are opened read-only, so SQLite refuses every write whatever is sent. */
function query({ sql, limit = 50 }) {
  const text = String(sql || '').trim().replace(/;\s*$/, '');
  if (!/^(select|with)\b/i.test(text)) fail('Only SELECT (or WITH … SELECT) queries.');
  if (text.includes(';')) fail('One query at a time.');
  const max = Math.min(Math.max(Number(limit) || 50, 1), 500);
  let rows;
  try {
    const it = connect().db.prepare(text).iterate();
    rows = [];
    for (const r of it) { rows.push(r); if (rows.length >= max) break; }
  } catch (e) {
    fail(`Query failed: ${e.message}`);
  }
  if (!rows.length) return 'No rows.';
  const cols = Object.keys(rows[0]);
  const cell = (v) => (v == null ? '' : String(v).replace(/\s+/g, ' ').slice(0, 400));
  return [cols.join('\t'), ...rows.map((r) => cols.map((c) => cell(r[c])).join('\t'))].join('\n')
    + (rows.length >= max ? `\n(first ${max} rows; raise limit or narrow the query)` : '');
}

module.exports = {
  query,
  TprError, status, books, search, count, show, link, quote, commentary, clean,
  activity, vocabulary, lookup, chapters, exportText, refLink: tprLink, lines, parseRef, refLines, defaultLang,
  bookIds: () => all('SELECT book_id FROM epi.books').map((r) => r.book_id),
  bookName: (id) => (get('SELECT book_name FROM epi.books WHERE book_id=?', id) || {}).book_name,
};
