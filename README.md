# pgide

A Postgres workbench for the terminal. Write SQL in [Helix](https://helix-editor.com),
run it in a long-lived `psql` session, read the results in
[pspg](https://github.com/okbob/pspg), all wired together in one
[WezTerm](https://wezterm.org) tab per database.

```
┌─ WezTerm tab "pg:acme-prod" (red if flagged production) ─────────────────┐
│ Helix: scratch.sql, snippets/, Postgres language server                   │
│   space , r  → selection, or the block under the cursor ─┐                │
├──────────────────────────────────────────────────────────┼────────────────┤
│ psql: one persistent session per tab                     ▼                │
│   results open in pspg (sort, freeze columns, search, copy)               │
└───────────────────────────────────────────────────────────────────────────┘
   space , b  →  rainfrog (or Harlequin) on the same connection in a new tab
```

## Why

Terminal SQL clients like [Harlequin](https://harlequin.sh) and
[rainfrog](https://github.com/achristmascarl/rainfrog) are good, but each brings its own
editor, its own keybindings and its own subset of what `psql` can do. pgide keeps the
tools you already use and joins them up:

- **Your editor.** Helix with its normal keys, plus Supabase's
  [Postgres language server](https://github.com/supabase-community/postgres-language-server)
  for completion and diagnostics.
- **The real psql.** Every meta-command works (`\d+`, `\sf+`, `\gset`, `\if`, `\watch`), and
  session state survives between runs: open transactions, `SET ROLE`, temp tables,
  variables. That makes things like RLS impersonation testing straightforward.
- **A pager built for tables.** pspg gives you sorting, frozen columns, search and copying
  to the clipboard.
- **Guard rails for production.** Credentials live in the macOS Keychain, there's an
  optional read-only session guard, `EXPLAIN ANALYZE` is always rolled back, and
  production tabs are coloured red.

## Requirements

- macOS (Linux mostly works: use `pgide add --plain`, and the clipboard features need `pbcopy`)
- [WezTerm](https://wezterm.org)
- [Helix](https://helix-editor.com) 25.07 or newer (for command-line expansions)
- `psql` (from `libpq`), `pspg`, `jq`, `fzf`
- Optional: `postgres-language-server` (the installer fetches the official release binary,
  because the Homebrew build is currently broken; see Troubleshooting), `rainfrog` or
  `harlequin`, `visidata`

## Install

```sh
git clone https://github.com/<you>/pgide.git && cd pgide
./install.sh --link      # symlinks, so `git pull` updates you; plain ./install.sh copies
```

The installer Homebrew-installs the tools (`--no-brew` to skip), downloads the Postgres
language server's release binary into `~/.local/bin` (`--no-lsp` to skip, `--update-lsp`
to refresh), and prints the remaining steps: append `config/helix/*.toml` to your Helix config, add
`require('pgide').apply(config)` to `wezterm.lua`, and check your PATH. Run
`pgide doctor` to check everything is in place.

## Quick start

```sh
pgide add acme-prod     # paste the URL (hidden input) → macOS Keychain
pgide test acme-prod    # one-shot connectivity check
pgide                   # pick a connection; or LEADER + d in WezTerm
```

`pgide add` asks three questions, each stored as a flag you can change later with
`pgide edit NAME`:

| Flag | Effect |
|---|---|
| `PGIDE_DANGER=1` | Red tab, banner and prompt. |
| `PGIDE_READONLY=1` | psql starts with `default_transaction_read_only = on`. This is a guard rail, not a permission: `SET default_transaction_read_only = off` to write. |
| `PGIDE_LSP_DB=1` | The language server connects to this database for schema-aware completion. The URL is written to a 0600 file in the workspace while the tab is open, then removed. |

Use `pgide add NAME --plain` for local databases, where storing the URL in the connection
file is fine.

## Keys

In Helix, press Space, then `,`, then the key (one after another, not held):

| Key | Does |
|---|---|
| `r` | Run the selection, or with no selection, the **block** under the cursor |
| `a` | Run the whole file |
| `p` | Run whatever is on the clipboard |
| `e` / `E` | `EXPLAIN` / `EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS, WAL)`. ANALYZE runs inside `BEGIN … ROLLBACK`, or a savepoint if you're already in a transaction |
| `d` | Describe the name under the cursor: `\d+` for relations, `\sf+` / `\df+` for functions |
| `x` | Toggle expanded output (`\x`) |
| `c` | Cancel the running query |
| `f` | Focus the results pane |
| `b` | Open rainfrog / Harlequin on the same connection in a new tab |
| `l` | Open the exact SQL file of the last run |
| `?` | Show a legend |

A **block** is the run of non-blank lines around the cursor and may hold several
statements. Keep a unit of work (`begin; set local role …; select …; rollback;`) together
with no blank lines inside it. For function bodies containing blank lines, select them or
use `space , a`.

Helix can't put descriptions on custom keys, so the `space ,` popup shows the multi-step
bindings as "[Multiple commands]". The `?` entry puts a legend in the popup instead.

Every run is saved under `~/.local/state/pgide/runs/<connection>/` before it executes, so
there's a timestamped record of exactly what ran against which database. Scripts stop at
the first error. The prompt shows `*` inside a transaction and `!` in a failed one.

## Results (pspg)

Use `hjkl` or the arrow keys to move, `/` to search, `0`–`9` to freeze that many columns,
`a` / `d` / `u` to sort ascending / descending / restore the original order, select rows,
columns or a block and copy them, `F9` for the menu, and `q` to go back to psql. Results
that fit on screen print inline without opening the pager. `\watch 2` in the psql pane
streams into pspg.

pspg's default theme is blue. On a light terminal, try `-s 0` (black & white), `20`
(Tao Light), `21` (FlatWhite) or `23` (Paper Color). Test one live in the psql pane with
`\setenv PSQL_PAGER 'pspg -X -F --ignore-case --bold-labels --no-commandbar -s 20'`, then
set `PGIDE_PAGER` in `~/.config/pgide/config` to keep it.

## psql macros

These come from [`config/psqlrc`](config/psqlrc). Type one on its own line in the psql
pane, or put it in a block:

`:activity` `:blocking` `:conns` `:sizes` `:vacuum` `:cache_hit` `:unused_indexes`
`:slow` (needs pg_stat_statements) `:rls` (RLS status and policy counts, unprotected
tables first) `:policies` `:definers` (SECURITY DEFINER functions, with anon /
authenticated EXECUTE) `:settings` `:uptime`

End a query with `:csv` (copy as CSV) or `:vd` (open in VisiData in a split) instead of
`;`.

[`snippets/rls-impersonate.sql`](snippets/rls-impersonate.sql) runs checks as an
authenticated user or as anon, the way PostgREST does, inside a rolled-back transaction.

## Configuration

Settings go in `~/.config/pgide/config`. pgide sources this file in every process,
including the panes WezTerm spawns, which don't inherit your shell's environment.

```sh
PGIDE_LAYOUT=right           # psql pane beside the editor instead of below
PGIDE_SPLIT_PERCENT=50       # size of the psql pane (default 55)
PGIDE_BROWSER=harlequin      # default: rainfrog
PGIDE_FOCUS_RESULTS=1        # jump to the results after every run
PGIDE_ECHO=0                 # don't echo statements above their results
PGIDE_PAGER='pspg -X -F --ignore-case --bold-labels --no-commandbar -s 20'
PGIDE_HOME=~/work/sql        # per-connection workspaces (default ~/sql)
```

## How it works

1. `pgide open NAME` splits the current WezTerm pane. It starts `pgide repl NAME` in the
   new pane, which reads the URL from the Keychain itself and runs psql in a reconnect
   loop. Then it launches Helix with the psql pane's id in the environment.
2. The Helix keys call `pgide` through `:pipe-to` and `:sh`, using expansions such as
   `%{buffer_name}` and `%{cursor_line}`.
3. `pgide run` writes the SQL to a run file and checks the pane's TTY: if pspg is open, it
   closes it. It then clears any half-typed input and sends `\i <file>` with
   `wezterm cli send-text`.
4. Helix never receives credentials through its environment. The language server runs as
   a daemon shared by every Helix instance, so environment variables could leak one
   tab's database into another. Instead, each connection's settings go in its own
   workspace's `postgres-language-server.jsonc`.

## Troubleshooting

- `PGIDE_DRYRUN=1 pgide run --mode clipboard` prints what would be sent instead of
  sending it.
- **Every statement shows "Error decoding result: failed to decode Protobuf message …
  (syntax)":** that's the Homebrew build of postgres-language-server (seen with 0.28.2 and
  libpg_query 18.1.0), not your SQL. `pgide doctor` flags it. Fix:
  `brew uninstall postgres-language-server && ./install.sh --no-brew --update-lsp`, then
  `:lsp-restart` in Helix.
- **`space ,` isn't in the Space popup:** the Helix snippet isn't in your config, or the
  config failed to parse. Run `:config-reload` and read the status line.
- **"the psql pane is gone":** reopen with `pgide NAME`.
- **"results pager is busy":** pspg is in a prompt or menu. Press `q` there.
- **Supabase transaction pooler (port 6543):** session state doesn't persist between runs.
  Use the direct connection or session mode (port 5432) for interactive work.

## Development

```sh
bash tests/run.sh          # offline tests: no WezTerm, psql or network needed
/bin/bash tests/run.sh     # on macOS, also test the stock bash 3.2 that WezTerm panes use
```

`bin/pgide` has to stay compatible with bash 3.2. That rules out associative arrays,
`mapfile` and `${var,,}`, and means escaping should be done with `sed` rather than
`${var//pattern/replacement}`. CI runs the tests on Linux and macOS (bash 3.2), and also
runs ShellCheck and syntax checks on the TOML and Lua configs.

## Licence

[MIT](LICENSE)
