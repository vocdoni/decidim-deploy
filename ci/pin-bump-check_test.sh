#!/usr/bin/env bash
# Tests for pin-bump-check.sh. Run: bash ci/pin-bump-check_test.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
check=$here/pin-bump-check.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT

old=1111111111111111111111111111111111111111
new=2222222222222222222222222222222222222222
fork=3333333333333333333333333333333333333333

gemr=https://github.com/vocdoni/decidim-secure_elections.git
decr=https://github.com/vocdoni/decidim.git

lock() { # $1 = gem revision, $2 = extra spec line (optional), $3 = decidim revision (optional)
  cat <<EOF
GIT
  remote: https://github.com/vocdoni/decidim-secure_elections.git
  revision: $1
  branch: main
  specs:
    decidim-elections-vocdoni (0.1.0)
      faraday (~> 2.9)${2:-}

GIT
  remote: https://github.com/vocdoni/decidim.git
  revision: ${3:-$fork}
  branch: develop
  specs:
    decidim (0.33.0.dev)

BUNDLED WITH
   2.6.9
EOF
}

mkdir -p "$t/app"
touch "$t/app/20261106114202_add_deleted_fields_to_users.decidim.rb" \
      "$t/app/20261106114001_create_active_storage_tables.active_storage.rb" \
      "$t/app/20261116163555_add_live_results_sync_to_vocdoni_processes.decidim_elections_vocdoni.rb"
lock "$old" > "$t/base.lock"
lock "$new" > "$t/new.lock"
lock "$new" $'\n      faraday-retry (~> 2.2)' > "$t/extra.lock"
lock "$fork" > "$t/forkrev.lock"
lock "$old" "" "$new" > "$t/decnew.lock"
printf '%s\n' 20261111120001_add_live_results_sync_to_vocdoni_processes.rb > "$t/gem.list"
printf '%s\n' 20261111120001_add_live_results_sync_to_vocdoni_processes.rb 20261201000000_add_tally_column.rb > "$t/gem-new.list"
# shellcheck disable=SC2016 # a literal, hostile-looking file name
printf '%s\n' 'evil$(id).rb' > "$t/gem-odd.list"
printf '%s\n' 20240101000000_add_deleted_fields_to_users.rb 20210309190009_create_active_storage_tables.active_storage.rb > "$t/dec.list"
: > "$t/nopkg.list"
printf '%s\n' packages/core/package.json > "$t/pkg.list"

fails=0
expect() { # $1 = name, $2 = want exit, $3 = want stdout substring, rest = args
  local name=$1 want=$2 grepfor=$3; shift 3
  local out code
  out=$("$check" "$@" 2>&1); code=$?
  if [ "$code" != "$want" ] || ! grep -qF -- "$grepfor" <<<"$out"; then
    echo "FAIL $name: exit $code (want $want), output: $out"
    fails=$((fails + 1))
  else
    echo "ok   $name"
  fi
}

expect mechanical          0 "mechanical"            "$t/base.lock" "$t/new.lock"     "$gemr" "$new" "$t/app" "$t/gem.list"
expect extra-lock-change   1 "beyond the"            "$t/base.lock" "$t/extra.lock"   "$gemr" "$new" "$t/app" "$t/gem.list"
expect wrong-block-changed 1 "beyond the"            "$t/base.lock" "$t/forkrev.lock" "$gemr" "$new" "$t/app" "$t/gem.list"
expect new-migration       1 "add_tally_column"      "$t/base.lock" "$t/new.lock"     "$gemr" "$new" "$t/app" "$t/gem-new.list"
expect odd-entry           1 "unexpected name"       "$t/base.lock" "$t/new.lock"     "$gemr" "$new" "$t/app" "$t/gem-odd.list"
expect already-pinned      1 "already pins"          "$t/base.lock" "$t/base.lock"    "$gemr" "$old" "$t/app" "$t/gem.list"
expect bad-sha             2 "40-char"               "$t/base.lock" "$t/new.lock"     "$gemr" "abc"  "$t/app" "$t/gem.list"
expect unknown-remote      2 "unknown remote"        "$t/base.lock" "$t/new.lock"     "https://example.com/x.git" "$new" "$t/app" "$t/gem.list"
expect decidim-mechanical  0 "mechanical"            "$t/base.lock" "$t/decnew.lock"  "$decr" "$new" "$t/app" "$t/dec.list" "$t/nopkg.list"
expect decidim-gem-block   1 "beyond the"            "$t/base.lock" "$t/new.lock"     "$decr" "$new" "$t/app" "$t/dec.list" "$t/nopkg.list"
expect decidim-migration   1 "add_tally_column"      "$t/base.lock" "$t/decnew.lock"  "$decr" "$new" "$t/app" "$t/gem-new.list" "$t/nopkg.list"
expect decidim-packages    1 "package-lock.json"     "$t/base.lock" "$t/decnew.lock"  "$decr" "$new" "$t/app" "$t/dec.list" "$t/pkg.list"
if [ "$fails" -ne 0 ]; then
  echo "$fails failed"
  exit 1
fi
echo "all passed"
