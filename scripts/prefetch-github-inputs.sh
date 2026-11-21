#!/usr/bin/env bash
# Claude cloud sessions block GitHub tarball downloads for repos not attached
# to the session, but allow git fetches. Add every github: input locked in
# flake.lock, and every catppuccin/nix port enabled under modules/, to the Nix
# store from git, so plain nix/nh never download them.
set -euo pipefail
lock=${1:-flake.lock}
root=$(dirname "$lock")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
status=0

# fetchFromGitHub and github: inputs both produce a fixed-output path named
# "source" whose NAR hash is the locked hash, so adding it from git suffices.
prefetch() {
  local owner=$1 repo=$2 rev=$3 hash=$4 path src got
  path=$(nix-store --print-fixed-path --recursive sha256 "$hash" source)
  nix path-info "$path" >/dev/null 2>&1 && return 0
  src=$work/$rev
  git init -q "$src.git"
  if ! git -C "$src.git" fetch -q --depth 1 "https://github.com/$owner/$repo" "$rev"; then
    echo "fetch failed: $owner/$repo@$rev" >&2
    status=1
    return 0
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
}

while read -r owner repo rev hash; do
  prefetch "$owner" "$repo" "$rev" "$hash"
done < <(jq -r '[.nodes[] | .locked? | select(.type == "github")] | unique[]
  | "\(.owner) \(.repo) \(.rev) \(.narHash)"' "$lock")

# catppuccin/nix fetches each port from its own catppuccin/<port> repo, pinned
# in pkgs/sources.json. Ports are found by `catppuccin.<port>.enable = true`.
catppuccin_hash=$(jq -r '.nodes.catppuccin.locked.narHash // empty' "$lock")
if [ -n "$catppuccin_hash" ] && [ -d "$root/modules" ]; then
  sources=$(nix-store --print-fixed-path --recursive sha256 "$catppuccin_hash" source)/pkgs/sources.json
  if [ -f "$sources" ]; then
    ports=$(grep -rhoE 'catppuccin\.[a-z0-9-]+\.enable = true' "$root/modules" |
      cut -d. -f2 | sort -u | jq -Rsc 'split("\n") | map(select(. != ""))')
    while read -r port rev hash; do
      prefetch catppuccin "$port" "$rev" "$hash"
    done < <(jq -r --argjson ports "$ports" \
      'to_entries[] | select(.key | IN($ports[])) | "\(.key) \(.value.rev) \(.value.hash)"' "$sources")
  else
    echo "catppuccin/nix source missing, skipped its ports" >&2
    status=1
  fi
fi
exit "$status"
