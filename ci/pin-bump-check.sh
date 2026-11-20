#!/usr/bin/env bash
# Mechanical-bump check for a lock pin bump (workflow pin-bump-target.yml): the
# Vocdoni module (vocdoni/decidim-secure_elections) or Decidim (vocdoni/decidim).
# Reads files only; never runs code from either repository.
#
# usage: pin-bump-check.sh <base Gemfile.lock> <new Gemfile.lock> <git remote> \
#          <new sha> <app db/migrate dir> <file listing the pinned repo's migrations> \
#          [<file listing changed npm package manifests>]
#
# Exit 0: the bump is mechanical. Exit 1: it is not; one reason per line on
# stdout. Exit 2: bad arguments or input.
set -euo pipefail

if [ $# -ne 6 ] && [ $# -ne 7 ]; then
  echo "usage: $0 <base-lock> <new-lock> <remote> <sha> <app-migrate-dir> <migrations-list> [<packages-list>]" >&2
  exit 2
fi
base_lock=$1 new_lock=$2 remote=$3 sha=$4 app_migrate=$5 mig_list=$6 pkg_list=${7:-}

case $remote in
  https://github.com/vocdoni/decidim-secure_elections.git | https://github.com/vocdoni/decidim.git) ;;
  *) echo "unknown remote: $remote" >&2; exit 2 ;;
esac
if ! [[ "$sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "sha is not a 40-char hex commit" >&2
  exit 2
fi
for f in "$base_lock" "$new_lock" "$mig_list" ${pkg_list:+"$pkg_list"}; do
  [ -f "$f" ] || { echo "missing file: $f" >&2; exit 2; }
done
[ -d "$app_migrate" ] || { echo "missing dir: $app_migrate" >&2; exit 2; }

reasons=()

# 1. The lock differs from the base in exactly the `revision:` line of the GIT
# block for $remote. Build the expected lock (base with only that line
# replaced) and compare bytes.
expected=$(mktemp)
trap 'rm -f "$expected"' EXIT
awk -v sha="$sha" -v remote="  remote: $remote" '
  /^GIT$/ { in_git = 1; hit = 0 }
  /^$/ { in_git = 0; hit = 0 }
  in_git && $0 == remote { hit = 1 }
  hit && $1 == "revision:" && !done { print "  revision: " sha; done = 1; next }
  { print }
  END { if (!done) exit 3 }
' "$base_lock" > "$expected" || { echo "base lock has no revision line for $remote" >&2; exit 2; }

if cmp -s "$base_lock" "$expected"; then
  reasons+=("the base lock already pins $sha")
elif ! cmp -s "$expected" "$new_lock"; then
  reasons+=("Gemfile.lock changes beyond the revision line of $remote")
fi

# 2. Every migration of the pinned repository is already in the app, by base
# name: the timestamp prefix and the engine suffix (.decidim_elections_vocdoni)
# that install:migrations adds are ignored, on both sides (decidim-core ships
# copies of Active Storage migrations with their .active_storage suffix).
app_names=$(find "$app_migrate" -maxdepth 1 -type f -name '*.rb' -printf '%f\n' \
  | sed -nE 's/^[0-9]+_([a-z0-9_]+)(\.[a-z0-9_]+)?\.rb$/\1/p' | sort -u)
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  if [[ "$entry" =~ ^[0-9]+_([a-z0-9_]+)(\.[a-z0-9_]+)?\.rb$ ]]; then
    name=${BASH_REMATCH[1]}
    if ! grep -qxF "$name" <<<"$app_names"; then
      reasons+=("migration $name is not in railway/db/migrate (copy it with install:migrations)")
    fi
  else
    reasons+=("the pinned repository has a migration with an unexpected name")
  fi
done < "$mig_list"

# 3. Decidim's npm packages (file:packages/*) are unchanged, so package-lock.json still holds.
if [ -n "$pkg_list" ] && [ -s "$pkg_list" ]; then
  reasons+=("Decidim's npm package manifests changed: refresh railway/package-lock.json")
fi

if [ ${#reasons[@]} -gt 0 ]; then
  printf '%s\n' "${reasons[@]}"
  exit 1
fi
echo "mechanical: one revision line, no new migrations"
