#!/usr/bin/env bash
# Activates `homeConfigurations.claude` in a Claude cloud session. Run from the
# environment's setup script; it needs only the flake, not a checkout:
#   src=$(nix flake prefetch --json git+https://github.com/stijnveenman/nixconf?ref=main | jq -r .storePath)
#   bash "$src/scripts/activate-claude-host.sh" "$src"
set -euo pipefail
src=${1:?usage: activate-claude-host.sh <flake source path>}
export USER=${USER:-$(id -un)} HOME=${HOME:-/root}
# GitHub tarball downloads are blocked; add the locked inputs from git instead.
bash "$src/scripts/prefetch-github-inputs.sh" "$src/flake.lock" || true
generation=$(nix build --no-link --print-out-paths "path:$src#homeConfigurations.claude.activationPackage")
"$generation/activate"
