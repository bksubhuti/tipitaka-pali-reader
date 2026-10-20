# TPR Research for Claude Desktop

A Claude Desktop extension that lets Claude research the books in a reader's
own Tipitaka Pali Reader, and write papers with Pāḷi quotes in grey boxes, the
English under each, and links that open TPR on the right page.

It is the `tpr-research` Claude Code skill made into something anyone with
Claude Desktop can install with a click: no VS Code, no terminal, no Python.

## For readers

1. Install Tipitaka Pali Reader and open it once, so it finishes setting up.
   Run one search, so its index is built. For English under the quotes,
   install the English translation (Settings → Download).
2. Install Claude Desktop (claude.ai/download) and sign in.
3. Open `tpr-research.mcpb`. Claude Desktop shows an install dialog: click
   **Install**.
4. In a new chat, ask for example: *"Find where the suttas describe the four
   great elements. Give me a paper with quotes."* Or pick **Research paper**
   from the prompts menu.

Papers are saved in `Documents/TPR Research` as Markdown, HTML and, when
Chrome or Edge is installed, PDF, and opened when done. The folder can be
changed in the extension's settings.

On a Mac with TPR from the App Store, macOS asks once whether Claude may
access another app's data. Allow it. The extension only reads: it opens
every database read-only, so SQLite refuses any write.

## What it does

| Tool | |
| --- | --- |
| `tpr_research_guide` | The research method and paper format, read before researching |
| `tpr_status` | The TPR data folder, the search index, installed translations |
| `tpr_books` | Book ids, layers, names |
| `tpr_search` | TPR's own full-text index, Pāḷi or a translation |
| `tpr_count` | Occurrences per book and layer, to prove presence or absence |
| `tpr_show` | A passage with its translation, line by line |
| `tpr_quote` | A ready quote: bold Pāḷi, translation, TPR link |
| `tpr_link` | The TPR link and page for a line |
| `tpr_commentary` | Commentary passages TPR links to a paragraph |
| `tpr_save_paper` | Saves the paper as Markdown, HTML and PDF |

The method and paper format are in `server/guide.md`, taken from the skill.

## For developers

- `server/tpr.js` is a port of the skill's `tpr.py`. Links, pages, searches
  and counts match it exactly; check again after changing either.
- `server/paper.js` is a port of `md2html.py`.
- `server/index.js` speaks MCP over stdio with no packages. Claude Desktop
  runs it with the Node it ships, which has `node:sqlite`. Node 22.13 or later
  is needed.
- Nothing is ever written to TPR's folder.

Build the installable file:

```
./build.sh          # writes tpr-research.mcpb here
```

It runs `npx @anthropic-ai/mcpb pack`, so it needs Node and npm. Raise
`version` in `manifest.json` for every release, so Claude Desktop offers the
update.

Try the server without Claude Desktop:

```
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"tpr_status","arguments":{}}}' | node server/index.js
```
