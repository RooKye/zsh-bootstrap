#!/usr/bin/env bash
set -euo pipefail

REPO_RAW_BASE="https://raw.githubusercontent.com/RooKye/zsh-bootstrap/main"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

echo "[+] Download bootstrap + repair + config..."
curl -fsSL "$REPO_RAW_BASE/bootstrap-deb-zsh.sh" -o bootstrap-deb-zsh.sh
curl -fsSL "$REPO_RAW_BASE/zsh-repair.sh"        -o zsh-repair.sh
curl -fsSL "$REPO_RAW_BASE/zsh-config.tar.gz"    -o zsh-config.tar.gz

chmod +x bootstrap-deb-zsh.sh zsh-repair.sh

echo "[+] Run bootstrap..."
# Le bootstrap définit lui-même zsh comme shell par défaut si besoin
./bootstrap-deb-zsh.sh ./zsh-config.tar.gz

echo "[!] IMPORTANT: Log out/in (or restart terminal) for default shell to switch to zsh."
