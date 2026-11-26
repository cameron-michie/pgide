#!/usr/bin/env bash
# install.sh — install pgide and the tools it drives. Safe to re-run.
#
#   ./install.sh               copy pgide + psqlrc into place
#   ./install.sh --link        symlink them instead, so `git pull` updates your install
#   ./install.sh --no-brew     skip the Homebrew step
#   ./install.sh --no-lsp      skip the Postgres language server
#   ./install.sh --update-lsp  re-download the latest language server release
#   ./install.sh --no-wezterm  don't touch wezterm.lua
#   ./install.sh --uninstall   remove the wezterm.lua block and pgide's files (keeps ~/sql and connections)
#
# WezTerm: appends one marked block to wezterm.lua (a .bak is kept; re-runs update it in place).
# Helix: your config is never edited. pgide merges its keys into a generated config that only
# pgide-launched Helix instances use (hx -c), and puts the language server settings in each
# workspace's .helix/languages.toml.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
link=0; brew=1; lsp=1; update_lsp=0; wez=1; uninstall=0
for arg in "$@"; do
  case "$arg" in
    --link)       link=1 ;;
    --no-brew)    brew=0 ;;
    --no-lsp)     lsp=0 ;;
    --update-lsp) update_lsp=1 ;;
    --no-wezterm) wez=0 ;;
    --uninstall)  uninstall=1 ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg (try --help)" >&2; exit 1 ;;
  esac
done

place() {  # place SRC DEST MODE — copy, or symlink with --link
  if [ "$1" -ef "$2" ]; then return 0; fi   # already the same file (re-running over a --link install)
  if [ "$link" = 1 ]; then ln -sfn "$1" "$2"; else install -m "$3" "$1" "$2"; fi
}

lsp_parser_ok() {  # does this language server binary parse a trivial statement?
  local d; d="$(mktemp -d)"
  printf 'create table t (id int);\n' > "$d/t.sql"
  if (cd "$d" && "$1" check t.sql >/dev/null 2>&1); then rm -rf "$d"; return 0; fi
  rm -rf "$d"; return 1
}

# The official release binary rather than Homebrew's build: the Homebrew build links
# Homebrew's own libpg_query, and with 0.28.2 + libpg_query 18.1.0 it fails to decode the
# parser's output for every statement ("failed to decode Protobuf message").
install_lsp() {
  local target dest="$HOME/.local/bin/postgres-language-server" tmpd
  case "$(uname -s)-$(uname -m)" in
    Darwin-arm64)              target=aarch64-apple-darwin ;;
    Darwin-x86_64)             target=x86_64-apple-darwin ;;
    Linux-aarch64|Linux-arm64) target=aarch64-unknown-linux-gnu ;;
    Linux-x86_64)              target=x86_64-unknown-linux-gnu ;;
    *) echo "  no release binary for $(uname -sm); skipping"; return 0 ;;
  esac
  tmpd="$(mktemp -d)"
  if ! curl -fsSL -o "$tmpd/pls" \
       "https://github.com/supabase-community/postgres-language-server/releases/latest/download/postgres-language-server_$target"; then
    echo "  download failed; get it later from the project's GitHub releases page"
    rm -rf "$tmpd"; return 0
  fi
  install -m 0755 "$tmpd/pls" "$dest"; rm -rf "$tmpd"
  if lsp_parser_ok "$dest"; then echo "  installed $("$dest" --version 2>/dev/null | head -n1) · parser OK"
  else echo "  ⚠ installed, but its parser self-check failed"; fi
}

BEGIN_MARK="-- >>> pgide >>> (managed by pgide's install.sh; remove with ./install.sh --uninstall)"
END_MARK="-- <<< pgide <<<"

wezterm_config() {  # the wezterm.lua that WezTerm will actually load
  if [ -n "${WEZTERM_CONFIG_FILE:-}" ]; then printf '%s' "$WEZTERM_CONFIG_FILE"
  elif [ -f "$HOME/.wezterm.lua" ]; then printf '%s' "$HOME/.wezterm.lua"
  else printf '%s' "$cfg/wezterm/wezterm.lua"; fi
}

strip_block() {  # strip_block FILE — print FILE without the pgide block
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '$0 == b { skip = 1 } !skip && !(drop && $0 == "") { print } { drop = 0 } $0 == e { skip = 0; drop = 1 }' "$1"
}

patch_wezterm() {
  local f tmp; f="$(wezterm_config)"
  if [ ! -f "$f" ]; then
    mkdir -p "$(dirname "$f")"
    printf "local wezterm = require 'wezterm'\nlocal config = wezterm.config_builder()\n\nreturn config\n" > "$f"
    echo "  created $f"
  fi
  if ! grep -q '^return config' "$f"; then
    echo "  ⚠ no 'return config' line in $f; add this yourself:  require('pgide').apply(config)"; return 0
  fi
  cp "$f" "$f.pgide.bak"
  tmp="$(mktemp)"
  strip_block "$f" > "$tmp"
  # insert the block before the last 'return config'
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    { line[NR] = $0 } /^return config/ { last = NR }
    END { for (i = 1; i <= NR; i++) {
            if (i == last) { print b; print "require('"'"'pgide'"'"').apply(config)"; print e; print "" }
            print line[i] } }' "$tmp" > "$f"
  rm -f "$tmp"
  echo "  $f: pgide block added (backup: $f.pgide.bak)"
}

if [ "$uninstall" = 1 ]; then
  f="$(wezterm_config)"
  if [ -f "$f" ] && grep -qF -- "$BEGIN_MARK" "$f"; then
    tmp="$(mktemp)"; strip_block "$f" > "$tmp"; cat "$tmp" > "$f"; rm -f "$tmp"
    echo "removed the pgide block from $f"
  fi
  rm -f "$HOME/.local/bin/pgide" "$cfg/wezterm/pgide.lua" "$cfg/pgide/psqlrc"
  rm -rf "$cfg/pgide/helix"
  echo "removed pgide's files. Left in place: $cfg/pgide/connections, ~/sql, ~/.local/state/pgide"
  exit 0
fi

if [ "$brew" = 1 ]; then
  command -v brew >/dev/null || { echo "Homebrew is required (or use --no-brew): https://brew.sh" >&2; exit 1; }
  echo "→ Homebrew packages"
  brew install helix libpq pspg jq fzf rainfrog
  echo "  optional: brew install visidata    # :vd macro, results in VisiData"
  echo "  optional: brew install harlequin   # PGIDE_BROWSER=harlequin"
fi

if [ "$lsp" = 1 ]; then
  echo "→ postgres-language-server (official release binary → ~/.local/bin)"
  mkdir -p "$HOME/.local/bin"
  if [ -x "$HOME/.local/bin/postgres-language-server" ] && [ "$update_lsp" = 0 ]; then
    echo "  already installed; use --update-lsp to fetch the latest release"
  else
    install_lsp
  fi
  if command -v brew >/dev/null && brew list --versions postgres-language-server >/dev/null 2>&1; then
    echo "  ⚠ Homebrew's postgres-language-server is also installed and may shadow this one."
    echo "    Its build can't decode libpg_query's output; remove it: brew uninstall postgres-language-server"
  fi
fi

echo "→ pgide"
mkdir -p "$HOME/.local/bin" "$cfg/pgide/connections" "$cfg/pgide/helix" "$HOME/sql/_snippets"
chmod 700 "$cfg/pgide" "$cfg/pgide/connections"
chmod +x "$here/bin/pgide"
place "$here/bin/pgide"    "$HOME/.local/bin/pgide" 0755
place "$here/config/psqlrc" "$cfg/pgide/psqlrc"      0644
for f in "$here"/snippets/*.sql; do
  [ -e "$HOME/sql/_snippets/$(basename "$f")" ] || cp "$f" "$HOME/sql/_snippets/"
done
place "$here/config/helix/config.toml"    "$cfg/pgide/helix/config.toml"    0644
place "$here/config/helix/languages.toml" "$cfg/pgide/helix/languages.toml" 0644
mkdir -p "$cfg/wezterm"
place "$here/config/wezterm/pgide.lua" "$cfg/wezterm/pgide.lua" 0644
if [ "$wez" = 1 ]; then patch_wezterm; fi

libpq_bin="/opt/homebrew/opt/libpq/bin"
if command -v brew >/dev/null; then libpq_bin="$(brew --prefix libpq)/bin"; fi

cat <<EOF

Installed $("$HOME/.local/bin/pgide" --version)$([ "$link" = 1 ] && echo " (symlinked to $here)").

Remaining steps:

  1. WezTerm — reload its config (CMD+SHIFT+R) to pick up the pgide key.$([ "$wez" = 0 ] && printf "\n     Add to wezterm.lua before 'return config':  require('pgide').apply(config)")
     Helix needs no setup: pgide starts it with its own merged config.

  2. Shell — make sure these are on PATH:
       export PATH="\$HOME/.local/bin:$libpq_bin:\$PATH"
     Optional, for plain psql outside pgide:
       export PSQL_PAGER='pspg -X -F --ignore-case --bold-labels --no-commandbar'
       echo '\\i ~/.config/pgide/psqlrc' >> ~/.psqlrc

  3. Connect (from a WezTerm pane). Nothing is saved:
       pgide postgres://user:pass@host:5432/db
     Or save one for next time:  pgide add mydb

  'pgide doctor' checks the toolchain at any time.
EOF
