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
