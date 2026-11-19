#!/usr/bin/env bash
# Claude cloud sessions block GitHub tarball downloads for repos not attached
# to the session, but allow git fetches. Add every github: input locked in
# flake.lock to the Nix store from git, so plain nix/nh never download them.
set -euo pipefail
lock=${1:-flake.lock}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
status=0
while read -r owner repo rev hash; do
  path=$(nix-store --print-fixed-path --recursive sha256 "$hash" source)
  nix path-info "$path" >/dev/null 2>&1 && continue
  src=$work/$rev
  git init -q "$src.git"
  if ! git -C "$src.git" fetch -q --depth 1 "https://github.com/$owner/$repo" "$rev"; then
    echo "fetch failed: $owner/$repo@$rev" >&2
    status=1
    continue
  fi
  # git archive applies export-ignore/export-subst exactly like GitHub tarballs.
  mkdir "$src"
  git -C "$src.git" archive --format=tar FETCH_HEAD | tar -x -C "$src"
  got=$(nix hash path --type sha256 --sri "$src")
  if [ "$got" = "$hash" ]; then
    nix store add --name source "$src" >/dev/null
    echo "added $owner/$repo@${rev:0:12}"
  else
    echo "hash mismatch: $owner/$repo@$rev (got $got, locked $hash)" >&2
    status=1
  fi
  rm -rf "$src" "$src.git"
done < <(jq -r '[.nodes[] | .locked? | select(.type == "github")] | unique[]
  | "\(.owner) \(.repo) \(.rev) \(.narHash)"' "$lock")
exit "$status"
