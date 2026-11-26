#!/usr/bin/env bash
# install.sh — install pgide and the tools it drives. Safe to re-run.
#
#   ./install.sh               copy pgide + psqlrc into place
#   ./install.sh --link        symlink them instead, so `git pull` updates your install
#   ./install.sh --no-brew     skip the Homebrew step
#   ./install.sh --no-lsp      skip the Postgres language server
#   ./install.sh --update-lsp  re-download the latest language server release
#
# It never edits your Helix or WezTerm config; it prints what to add instead.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
link=0; brew=1; lsp=1; update_lsp=0
for arg in "$@"; do
  case "$arg" in
    --link)       link=1 ;;
    --no-brew)    brew=0 ;;
    --no-lsp)     lsp=0 ;;
    --update-lsp) update_lsp=1 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg (try --help)" >&2; exit 1 ;;
  esac
done

place() {  # place SRC DEST MODE — copy, or symlink with --link
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
mkdir -p "$HOME/.local/bin" "$cfg/pgide/connections" "$HOME/sql/_snippets"
chmod 700 "$cfg/pgide" "$cfg/pgide/connections"
chmod +x "$here/bin/pgide"
place "$here/bin/pgide"    "$HOME/.local/bin/pgide" 0755
place "$here/config/psqlrc" "$cfg/pgide/psqlrc"      0644
for f in "$here"/snippets/*.sql; do
  [ -e "$HOME/sql/_snippets/$(basename "$f")" ] || cp "$f" "$HOME/sql/_snippets/"
done
if [ ! -e "$cfg/wezterm/pgide.lua" ]; then
  mkdir -p "$cfg/wezterm"
  place "$here/config/wezterm/pgide.lua" "$cfg/wezterm/pgide.lua" 0644
fi

libpq_bin="/opt/homebrew/opt/libpq/bin"
if command -v brew >/dev/null; then libpq_bin="$(brew --prefix libpq)/bin"; fi

cat <<EOF

Installed $("$HOME/.local/bin/pgide" --version)$([ "$link" = 1 ] && echo " (symlinked to $here)").

Remaining steps:

  1. Helix — add the keys and the language server (only adds keys under 'space ,'):
       cat "$here/config/helix/config.toml"    >> ~/.config/helix/config.toml
       cat "$here/config/helix/languages.toml" >> ~/.config/helix/languages.toml
     If languages.toml already has a [[language]] entry named "sql", merge by hand instead.
     Check with:  hx --health sql

  2. WezTerm — in wezterm.lua, before 'return config':
       require('pgide').apply(config)       -- LEADER + d opens the picker in a new tab

  3. Shell — make sure these are on PATH:
       export PATH="\$HOME/.local/bin:$libpq_bin:\$PATH"
     Optional, for plain psql outside pgide:
       export PSQL_PAGER='pspg -X -F --ignore-case --bold-labels --no-commandbar'
       echo '\\i ~/.config/pgide/psqlrc' >> ~/.psqlrc

  4. Add a connection and open it:
       pgide add mydb && pgide test mydb && pgide mydb

  'pgide doctor' checks the toolchain at any time.
EOF
