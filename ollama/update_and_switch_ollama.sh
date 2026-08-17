#!/usr/bin/env bash
set -euo pipefail
if [ $# -ne 1 ]; then
  echo "Usage: $0 <ollama-version e.g. 0.32.13>"
  exit 1
fi
VERSION="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
cd "$SCRIPT_DIR"
python3 update_ollama.py "$VERSION"
cd "$REPO_DIR"
nix build .#ollama-git-rocm --no-link
home-manager switch --flake '.#alexfneves@gmktec'
