# Changelog

## Unreleased

- **Ephemeral connections by default:** `pgide postgres://…` (or `pgide connect`, or `pgide`
  with no saved connections) opens a workbench without saving the URL; the temporary
  session file is deleted when the editor closes.
- `pgide add` now stores the URL in the 0600 connection file; `--keychain` opts in to the
  Keychain. URL input is no longer hidden, and `pgide ls` and the psql pane show the URL.
- The installer appends a marked, idempotent block to `wezterm.lua` (`--no-wezterm`,
  `--uninstall`). Helix is no longer edited: pgide starts it with a generated merged config
  (`hx -c`) and a per-workspace `.helix/languages.toml`, so the keys only exist in pgide
  sessions.
- `PGIDE_SNIPPETS` sets the shared snippet directory; `pgide snippets` prints it.
- `space , ?` opens a cheat-sheet buffer (`pgide keys`); single-command keys carry descriptions in the popup.
- `space , r` on a blank line runs the block above; `$$` function bodies with blank lines are one block.
- `pgide csv FILE|DIR` views CSV files in pspg.
- success-scripts integration (`PGIDE_SCRIPTS`): Helix keys `space , i/s/g/m/A/o` run its inspect, Logflare and analyze scripts for the session in a pane under psql, `space , v` and the CSV picker show CSVs in the existing results pane, and each workspace gets `./outputs`. `pgide csv DIR` now searches recursively, newest first, and reads TSV.
- CSVs open with a column cursor and cells trimmed to `PGIDE_CSV_WIDTH` (default 60); `pgide csv --width N|--full`.
- Helix now starts in `PGIDE_HOME` (not the workspace), so `_snippets/` and the workspaces are real siblings and file-browser navigation works; no more per-workspace `snippets` symlink (a custom `PGIDE_SNIPPETS` shows as `snippets/` at the root).
- pspg now runs with `-s 0` (terminal background, no blue).
- WezTerm key defaults to `CMD+SHIFT+p` when no leader is set; `option_as_alt` is now opt-in.
- The installer downloads postgres-language-server's official release binary instead of
  using Homebrew. Homebrew's build (0.28.2 with libpg_query 18.1.0) reports a "failed to
  decode Protobuf message" syntax error on every statement. The installer warns if the
  Homebrew build is still installed.
- `pgide doctor` runs a parser self-check against the language server.
- `install.sh --no-lsp` and `--update-lsp`.

## 0.1.0 — 2026-11-26

First release.

- One WezTerm tab per connection: Helix on top, a persistent psql session below, results in pspg.
- Helix keys under `space ,`: run selection or block, run file, run clipboard, EXPLAIN,
  EXPLAIN ANALYZE (always rolled back), describe, cancel, toggle `\x`, focus results,
  open a browser tab, reopen the last run, and a `?` legend.
- Connections stored in the macOS Keychain, with production, read-only and LSP flags.
- Per-connection `postgres-language-server.jsonc`, so the shared LSP daemon never mixes
  up databases; credentials are kept out of Helix's environment.
- psqlrc with prompts, a read-only guard and diagnostic macros (`:activity`, `:rls`,
  `:definers`, `:slow`, …) plus `:csv` / `:vd` result sinks.
- Every run saved to `~/.local/state/pgide/runs/<connection>/`.
- Works with macOS's stock bash 3.2.
