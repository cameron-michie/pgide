#!/usr/bin/env bash
# tests/run.sh — offline tests for pgide. Needs no WezTerm, psql, Keychain or network.
#
#   bash tests/run.sh          # with whatever bash is first on PATH
#   /bin/bash tests/run.sh     # on macOS: exercise the stock bash 3.2 that WezTerm panes use
#
# pgide is always run with the same bash as this script ("$BASH"), so the line above really
# tests 3.2 rather than whichever bash the shebang would find.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
PGIDE="$(dirname "$here")/bin/pgide"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export PGIDE_STATE="$tmp/state" PGIDE_CONFIG="$tmp/cfg" PGIDE_HOME="$tmp/home"
unset PGIDE_CONN PGIDE_REPL_PANE PGIDE_DRYRUN

pg() { "$BASH" "$PGIDE" "$@"; }
pass=0; fail=0
ok()  { pass=$((pass + 1)); printf '  ✓ %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  ✗ %s\n%s\n' "$1" "$2"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "      expected: [$3]
      got:      [$2]"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "      missing: [$3]
      in: [$2]" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "      unexpected: [$3]" ;; *) ok "$1" ;; esac; }
last_run() { cat "$(readlink "$PGIDE_STATE/runs/last.sql")"; }
nl='
'

awk_v="$(awk --version 2>/dev/null | head -n1)"
echo "bash $BASH_VERSION · ${awk_v:-awk}"

# ------------------------------------------------------------------ URL → libpq environment
echo "URL parsing"
url_env() {
  ( . "$PGIDE"; export_pg_env "$1" >/dev/null 2>&1 || exit 1
    printf '%s|%s|%s|%s|%s|%s' "${PGHOST-}" "${PGPORT-}" "${PGUSER-}" "${PGPASSWORD-}" "${PGDATABASE-}" "${PGSSLMODE-}" )
}
eq "pooler URL with %-encoded password" \
   "$(url_env 'postgresql://postgres.abcdefgh:p%40ss%3Aw%2Fo%3Frd@aws-0-eu-west-2.pooler.supabase.com:5432/postgres?sslmode=require')" \
   "aws-0-eu-west-2.pooler.supabase.com|5432|postgres.abcdefgh|p@ss:w/o?rd|postgres|require"
eq "raw @ and / in password" \
   "$(url_env 'postgres://postgres:we@ird/pw@db.abc.supabase.co:5432/postgres')" \
   "db.abc.supabase.co|5432|postgres|we@ird/pw|postgres|"
eq "no password, no port" "$(url_env 'postgres://postgres@localhost/mydb')" "localhost||postgres||mydb|"
eq "IPv6 host" "$(url_env 'postgres://u:p@[::1]:54322/postgres')" "::1|54322|u|p|postgres|"
eq "backslash in password survives" "$(url_env 'postgres://u:a%5Cb@h/d')" 'h||u|a\b|d|'
if url_env 'mysql://x@y/z' >/dev/null; then bad "non-postgres URL rejected" ""; else ok "non-postgres URL rejected"; fi
eq "options parameter decoded" \
   "$( ( . "$PGIDE"; export_pg_env 'postgres://u@h/d?options=-c%20statement_timeout%3D5s' >/dev/null 2>&1; printf '%s' "$PGOPTIONS" ) )" \
   "-c statement_timeout=5s"

# ------------------------------------------------------------------ text extraction
echo "Block and identifier extraction"
f="$tmp/scratch.sql"
cat > "$f" <<'EOF'
-- header

select count(*)
  from public.orders o
 where o.status = 'open'

begin;
set local role authenticated;
select * from "Accounts" a join auth.users u on u.id = a.user_id;
rollback;

select auth.uid() -- trailing comment
EOF
eq "block around a line" "$( ( . "$PGIDE"; extract_block "$f" 4 ) )" \
   "select count(*)${nl}  from public.orders o${nl} where o.status = 'open'"
eq "blank line runs the block above it" "$( ( . "$PGIDE"; extract_block "$f" 6 ) )" \
   "select count(*)${nl}  from public.orders o${nl} where o.status = 'open'"
printf '\n\nselect 1;\n' > "$tmp/lead.sql"
if ( . "$PGIDE"; extract_block "$tmp/lead.sql" 1 ) >/dev/null; then bad "blank with nothing above → error" ""; else ok "blank with nothing above → error"; fi
cat > "$tmp/fn.sql" <<'EOF'
select 1;

create function f() returns int language plpgsql as $$
begin

  return 1;

end
$$;

select 2;
EOF
eq "function body with blank lines is one block" "$( ( . "$PGIDE"; extract_block "$tmp/fn.sql" 6 ) | wc -l | tr -d ' ' )" "7"
eq "cursor after the function runs the function" "$( ( . "$PGIDE"; extract_block "$tmp/fn.sql" 10 ) | head -n1 )" "create function f() returns int language plpgsql as \$\$"
eq "statement after it is separate" "$( ( . "$PGIDE"; extract_block "$tmp/fn.sql" 11 ) )" "select 2;"
if ( . "$PGIDE"; extract_block "$f" 99 ) >/dev/null; then bad "past EOF → error" ""; else ok "past EOF → error"; fi
eq "identifier mid-word"         "$( ( . "$PGIDE"; ident_at "$f" 4 13 ) )" "public.orders"
eq "identifier before ()"        "$( ( . "$PGIDE"; ident_at "$f" 12 10 ) )" "auth.uid"
eq "quoted identifier"           "$( ( . "$PGIDE"; ident_at "$f" 9 17 ) )" '"Accounts"'

# ------------------------------------------------------------------ generated run files (dry run)
echo "Run files"
export PGIDE_CONN=t PGIDE_REPL_PANE=1 PGIDE_DRYRUN=1
printf 'x' | pg run --file "$f" --line 4 --lang sql >/dev/null
r="$(last_run)"
has "sets ON_ERROR_STOP"                    "$r" '\set ON_ERROR_STOP on'
has "unterminated block gets ; on own line" "$r" "where o.status = 'open'${nl};${nl}"
printf 'x' | pg run --file "$f" --line 8 --lang sql >/dev/null
r="$(last_run)"
has "multi-statement block kept whole" "$r" "begin;${nl}set local role authenticated;"
has "terminated block: no extra ;"     "$r" "rollback;${nl}\\set ECHO none"
printf 'x' | pg run --file "$f" --line 12 --lang sql >/dev/null
has "trailing -- comment can't swallow ;" "$(last_run)" "-- trailing comment${nl};${nl}"
printf 'select 42' | pg run --file "$f" --line 8 --lang sql >/dev/null
r="$(last_run)"
has "real selection wins over block" "$r" "select 42${nl};"
hasnt "…and the block isn't run"     "$r" "rollback"
printf '\\set uid 7' | pg run --lang sql >/dev/null
hasnt "no ; after a trailing meta-command" "$(last_run)" "\\set uid 7${nl};"
out="$(pg run --file "$f" --line 4 --lang markdown </dev/null 2>&1)"
has "refuses non-SQL buffers" "$out" "not a SQL buffer"
out="$(printf 'x' | pg run --file "$f" --line 4 --lang sql)"
has "sends \\i to the psql pane" "$out" "\\\\i"

printf 'x' | pg explain --analyze --file "$f" --line 12 --lang sql >/dev/null
r="$(last_run)"
has "EXPLAIN ANALYZE rolls back"            "$r" "BEGIN;"
has "…or uses a savepoint inside a txn"     "$r" "ROLLBACK TO SAVEPOINT pgide_explain;"
has "…with ; on its own line"               "$r" "-- trailing comment${nl};${nl}ROLLBACK"
printf 'x' | pg explain --file "$f" --line 4 --lang sql >/dev/null
has "plain EXPLAIN" "$(last_run)" "EXPLAIN (VERBOSE, SETTINGS)${nl}select count(*)"

printf '"Accounts"' | pg describe >/dev/null
r="$(last_run)"
has "describe keeps quoted case for lookup" "$r" "\\set pgide_fn 'Accounts'"
has "describe uses \\d+"                    "$r" '\d+ "Accounts"'
printf 'x' | pg describe --file "$f" --line 12 --col 10 >/dev/null
has "describe falls back to \\sf+ for functions" "$(last_run)" '\sf+ auth.uid'
out="$(printf 'drop table x;' | pg describe 2>&1)"
has "describe rejects non-names" "$out" "not a table, view or function name"
unset PGIDE_CONN PGIDE_REPL_PANE PGIDE_DRYRUN

# ------------------------------------------------------------------ connections & workspace
echo "Connections and workspace"
url="postgresql://postgres.ref:it's%40secret@aws-0-eu-west-2.pooler.supabase.com:5432/postgres"
printf '%s\ny\n\nn\n' "$url" | pg add acme --plain >/dev/null 2>&1
conf="$PGIDE_CONFIG/connections/acme.conf"
has "production flag saved"          "$(cat "$conf")" "PGIDE_DANGER=1"
has "read-only defaults on for prod" "$(cat "$conf")" "PGIDE_READONLY=1"
eq  "URL with a quote round-trips"   "$( ( . "$conf"; printf '%s' "$PGIDE_URL" ) )" "$url"
eq  "connection file is private"     "$(ls -l "$conf" | cut -c1-10)" "-rw-------"
has "ls shows flags" "$(pg ls)" "⚠ prod"
ws="$( ( . "$PGIDE"; setup_workspace acme ) )"
eq  "workspace has just the scratch file" "$(ls "$ws" | tr '\n' ' ')" "scratch.sql "
ln -s ../_snippets "$ws/snippets"
( . "$PGIDE"; setup_workspace acme >/dev/null )
eq  "old per-workspace snippets symlink is removed" "$(ls "$ws" | tr '\n' ' ')" "scratch.sql "
ln -s "$tmp" "$PGIDE_HOME/snippets" 2>/dev/null; rm -f "$PGIDE_HOME/snippets"
( export PGIDE_SNIPPETS="$tmp/elsewhere"; . "$PGIDE"; setup_workspace acme >/dev/null )
eq  "a custom bank is linked at the root" "$(readlink "$PGIDE_HOME/snippets")" "$tmp/elsewhere"
rm -f "$PGIDE_HOME/snippets"
( . "$PGIDE"; write_lsp_config "$ws" "postgres://u:p@h/d" )
has "LSP config with DB"          "$(cat "$ws/postgres-language-server.jsonc")" '"connectionString": "postgres://u:p@h/d"'
eq  "LSP config is private"       "$(ls -l "$ws/postgres-language-server.jsonc" | cut -c1-10)" "-rw-------"
( . "$PGIDE"; write_lsp_config "$ws" "" )
has "LSP config without DB"       "$(cat "$ws/postgres-language-server.jsonc")" '"disableConnection": true'
has "ls shows the URL"            "$(pg ls)" "$url"
pg rm acme >/dev/null
has "rm removes the connection"   "$(pg ls)" "no connections yet"
has "version" "$(pg --version)" "pgide "
out="$(pg nope 2>&1)"
has "unknown command message" "$out" "unknown command or connection"

# ------------------------------------------------------------------ ephemeral sessions, Helix config
echo "Ephemeral sessions and Helix config"
eq "name from a Supabase pooler URL" \
   "$( ( . "$PGIDE"; ephemeral_name 'postgresql://postgres.abcdefgh:pw@aws-0-eu-west-2.pooler.supabase.com:5432/postgres' ) )" \
   "abcdefgh-postgres"
eq "name from a plain host" "$( ( . "$PGIDE"; ephemeral_name 'postgres://u@localhost:54322/app' ) )" "localhost-app"
mkdir -p "$PGIDE_STATE/ephemeral"; printf 'PGIDE_URL=x\n' > "$PGIDE_STATE/ephemeral/eph.conf"
eq "ephemeral file is found by conn_file" "$( ( . "$PGIDE"; conn_file eph ) )" "$PGIDE_STATE/ephemeral/eph.conf"
eq "saved connections still resolve"      "$( ( . "$PGIDE"; conn_file saved ) )" "$PGIDE_CONFIG/connections/saved.conf"
out="$(pg connect not-a-url --name x 2>&1)"
has "connect rejects a non-URL" "$out" "expected a postgres://"
eq "…and leaves nothing behind" "$(ls "$PGIDE_STATE/ephemeral" | grep -c '^x.conf$')" "0"
mkdir -p "$PGIDE_CONFIG/helix" "$tmp/hx"
cp "$here/../config/helix/"*.toml "$PGIDE_CONFIG/helix/"
printf 'theme = "mine"\n' > "$tmp/hx/config.toml"
ws="$tmp/ws"; mkdir -p "$ws"
gen="$( ( export HELIX_CONFIG_DIR="$tmp/hx"; . "$PGIDE"; write_helix_config "$ws" ) )"
has "generated config keeps the user's settings" "$(cat "$gen")" 'theme = "mine"'
has "…and adds the pgide keys"                   "$(cat "$gen")" '[keys.normal.space.","]'
cp "$here/../config/helix/config.toml" "$tmp/hx/legacy.toml"
{ printf 'theme = "mine"\n\n[keys.normal]\nC-g = "x"\n\n'; cat "$here/../config/helix/config.toml"; } > "$tmp/hx/config.toml"
gen="$( ( export HELIX_CONFIG_DIR="$tmp/hx"; . "$PGIDE"; write_helix_config "$ws" ) )"
eq  "legacy hand-appended block isn't duplicated" "$(grep -c '^\[keys.normal.space' "$gen")" "1"
has "…and the user's other keys survive"         "$(cat "$gen")" 'C-g = "x"'
printf 'theme = "mine"\n' > "$tmp/hx/config.toml"
eq  "user's own config is untouched"             "$(cat "$tmp/hx/config.toml")" 'theme = "mine"'
has "root gets the language server entry"        "$(cat "$ws/.helix/languages.toml")" 'postgres-language-server'

# ------------------------------------------------------------------ success-scripts + CSV
echo "success-scripts and CSV"
pref() { ( . "$PGIDE"; export_pg_env "$1" >/dev/null 2>&1; project_ref ); }
eq "ref from a pooler user"    "$(pref 'postgresql://postgres.abcdefgh:pw@aws-0-eu-west-2.pooler.supabase.com:5432/postgres')" "abcdefgh"
eq "ref from a direct host"    "$(pref 'postgresql://postgres:pw@db.zzzyyyxxx.supabase.co:5432/postgres')" "zzzyyyxxx"
if pref 'postgres://u@localhost/d' >/dev/null; then bad "no ref for localhost" ""; else ok "no ref for localhost"; fi
out="$(pg task inspect 2>&1)"; has "task needs PGIDE_SCRIPTS" "$out" "set PGIDE_SCRIPTS"
printf 'a,b\n1,2\n' > "$tmp/x.csv"; printf 'x\n' > "$tmp/x.txt"
out="$(pg view "$tmp/x.txt" 2>&1)"; has "view refuses non-CSV" "$out" "not a CSV/TSV"
out="$(pg view "$tmp/nope.csv" 2>&1)"; has "view refuses a missing file" "$out" "can't read"
mkdir -p "$tmp/scripts/customers/acme"
ws="$( ( export PGIDE_SCRIPTS="$tmp/scripts"; . "$PGIDE"; setup_workspace acme ) )"
eq "workspace links ./outputs to the customer dir" "$(readlink "$ws/outputs")" "$tmp/scripts/customers/acme"
ws="$( ( export PGIDE_SCRIPTS="$tmp/scripts"; PGIDE_CUSTOMER=other; . "$PGIDE"; setup_workspace acme2 ) )"
eq "…or to PGIDE_CUSTOMER when set"                "$(readlink "$ws/outputs")" "$tmp/scripts/customers/other"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
