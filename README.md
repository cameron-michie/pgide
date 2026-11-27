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
- **Guard rails for production.** Connections are ephemeral by default (nothing is saved),
  there's an optional read-only session guard, `EXPLAIN ANALYZE` is always rolled back, and
  production tabs are coloured red.

## Requirements

- macOS (Linux mostly works; the clipboard features need `pbcopy`)
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

The installer Homebrew-installs the tools (`--no-brew` to skip) and downloads the Postgres
language server's release binary into `~/.local/bin` (`--no-lsp` to skip, `--update-lsp`
to refresh). It also:

- **WezTerm:** appends one marked block (`require('pgide').apply(config)`) to your
  `wezterm.lua` before `return config`, keeping a `.pgide.bak`. Re-running updates it in
  place; `--no-wezterm` skips it. The key is `LEADER + d` if you have a leader, otherwise
  `CMD+SHIFT+p`. Tab colouring only affects tabs titled `pg:…`.
- **Helix:** doesn't edit your config. pgide starts Helix with `hx -c` on a generated file
  (your `config.toml` plus the pgide keys) and writes the language server settings into each
  workspace's `.helix/languages.toml`. So the `space ,` keys exist only in pgide sessions.

`./install.sh --uninstall` removes the block and pgide's files (connections and `~/sql`
stay). Run `pgide doctor` to check everything is in place.

## Quick start

```sh
pgide postgres://user:pass@host:5432/db    # opens a workbench; nothing is saved
pgide                                      # no saved connections: asks for a URL
```

A URL session is ephemeral: the URL lives in a 0600 file under `~/.local/state/pgide/ephemeral/`
only while the editor is open, then it is deleted. The session is named from the URL (for a
Supabase pooler, the project ref) and gets a workspace in `~/sql/<name>/`. Options:
`--name N`, `--prod` (red tab, read-only), `--readonly`, `--lsp` (schema-aware completion).

To keep a connection:

```sh
pgide add acme-prod     # paste the URL → ~/.config/pgide/connections/acme-prod.conf (0600)
pgide add acme-prod --keychain   # or store the URL in the macOS Keychain instead
pgide test acme-prod    # one-shot connectivity check
pgide acme-prod         # or `pgide` and pick it; `pgide ls` lists them with their URLs
```

`pgide add` asks three questions, each stored as a flag you can change later with
`pgide edit NAME`:

| Flag | Effect |
|---|---|
| `PGIDE_DANGER=1` | Red tab, banner and prompt. |
| `PGIDE_READONLY=1` | psql starts with `default_transaction_read_only = on`. This is a guard rail, not a permission: `SET default_transaction_read_only = off` to write. |
| `PGIDE_LSP_DB=1` | The language server connects to this database for schema-aware completion. The URL is written to a 0600 file in the workspace while the tab is open, then removed. |

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
| `?` | Open a cheat sheet |

A **block** is the run of non-blank lines around the cursor and may hold several
statements. Keep a unit of work (`begin; set local role …; select …; rollback;`) together
with no blank lines inside it. Blank lines inside a `$$ … $$` function body don't end the
block. On a blank line, `r` runs the nearest block above it, so you can press it just after
a statement or function.

Helix can't put descriptions on custom keys, so the `space ,` popup shows the multi-step
bindings as "[Multiple commands]". Press `?` there to open a cheat sheet in a buffer.

Every run is saved under `~/.local/state/pgide/runs/<connection>/` before it executes, so
there's a timestamped record of exactly what ran against which database. Scripts stop at
the first error. The prompt shows `*` inside a transaction and `!` in a failed one.

## Results (pspg)

Use `hjkl` or the arrow keys to move, `/` to search, `0`–`9` to freeze that many columns,
`a` / `d` / `u` to sort ascending / descending / restore the original order, select rows,
columns or a block and copy them, `F9` for the menu, and `q` to go back to psql. Results
that fit on screen print inline without opening the pager. `\watch 2` in the psql pane
streams into pspg.

To read CSV files in the same pager (sort, search, freeze columns), use `pgide csv`:

```sh
supabase inspect report --output-dir ~/inspect    # one CSV per inspect command
pgide csv ~/inspect                               # pick one with fzf; q returns to the picker
pgide csv bloat.csv                               # a single file
some-command-that-prints-csv | pgide csv          # or stdin
```

Moving across columns: `Shift`+`←`/`→` scroll one column at a time, `c` searches for a column by
name, `Alt`+`v` toggles a column cursor (on by default for CSVs, so `←`/`→` move between
columns), and `0`–`9` freeze that many columns. pspg can't wrap text. For wide columns, CSV
cells are trimmed to 60 characters (`PGIDE_CSV_WIDTH=N` in `~/.config/pgide/config`, `0` for no
trimming). One-off: `pgide csv --width 30 FILE` or `pgide csv --full FILE`. Trimming only
affects the display, so `--full` shows long SQL in a cell when you need to read it.

pgide runs pspg with `-s 0`, which uses your terminal's own background and colours (pspg's
own default is a solid blue). For another theme try `20` (Tao Light), `21` (FlatWhite) or `23`
(Paper Color). Test one live in the psql pane with
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

## success-scripts

With `PGIDE_SCRIPTS=~/supabase-projects/success-scripts` in `~/.config/pgide/config`, the
session's own connection drives that repo's scripts, so you never paste the URL again. Each
key runs in a pane stacked under the psql pane (the repo's `.env` supplies `LOGFLARE_KEY`), and
the pane closes when the job ends. CSVs open in the existing psql/pspg pane: pgide sends it
`\! pgide csv …`, so pspg takes over that pane and `q` returns you to the psql prompt. The customer
name is the session name, or `PGIDE_CUSTOMER` in the connection file
(`pgide connect URL --name x --customer acme`).

| Key | Runs |
|---|---|
| `space , i` | `inspect.sh <url> <customer> --csv`: `supabase inspect report` plus Logflare slow logs as CSV |
| `space , s` | 30 days of slow logs from Logflare, converted to CSV |
| `space , g` | Postgres logs for one backend type, paged out of Logflare (it asks for type and times) |
| `space , m` | REST path metrics from the Logflare endpoints |
| `space , A` | `analyze.sh`, the unchecked `queries/*.sql`. It asks first, and warns on production |
| `space , o` | Browse this customer's CSVs, newest first |
| `space , v` | Open the CSV in the current Helix buffer in pspg |

When a job finishes it offers to open the customer's CSV picker in the results pane (`q` in pspg returns to the picker, Esc leaves it).
Each workspace also gets `outputs/`, a link to `customers/<name>`, so `space f` then
`<name>/outputs/` opens any result in Helix. Helix has no hook that fires when a file opens, so a CSV
opened there shows as text; press `space , v` to read it in pspg instead.

## Snippets

Your bank of saved queries is one directory, `~/sql/_snippets` by default (`pgide snippets`
prints it). Helix starts in `~/sql`, so `_snippets/` and every connection's workspace are
sibling folders: `space e` (file explorer) or `space f` (picker) reaches them, and going
"back" from one lands next to the others. In Helix, save a query with
`:write _snippets/name.sql`. To keep the bank somewhere else, set `PGIDE_SNIPPETS` in
`~/.config/pgide/config` (a git repo, say); it appears as `snippets/` next to the workspaces.
The installer seeds the bank with the examples in this repo's `snippets/` but never overwrites.

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
PGIDE_CSV_WIDTH=60           # trim CSV cells in the pager (0 = off)
PGIDE_PAGER='pspg -X -F --ignore-case --bold-labels --no-commandbar -s 20'  # default is -s 0
PGIDE_HOME=~/work/sql        # per-connection workspaces (default ~/sql)
PGIDE_SNIPPETS=~/work/queries  # your snippet bank (default ~/sql/_snippets)
PGIDE_SCRIPTS=~/supabase-projects/success-scripts   # enables the space , i/s/g/m/A/o keys
```

## How it works

1. `pgide open NAME` splits the current WezTerm pane. It starts `pgide repl NAME` in the
   new pane, which reads the URL from the connection file (or Keychain) itself and runs
   psql in a reconnect loop. Then it launches Helix with the psql pane's id in the environment.
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
- **`space ,` isn't in the Space popup:** you opened Helix outside pgide (the keys are only
  in pgide's generated config), or your own `config.toml` fails to parse.
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
