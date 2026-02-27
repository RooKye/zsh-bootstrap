#!/usr/bin/env bash
set -euo pipefail

REPO_RAW_BASE="https://github.com/RooKye/zsh-bootstrap"

tmp="$(mktemp -d)"
cd "$tmp"

echo "[+] Download bootstrap + config..."
curl -fsSL "$REPO_RAW_BASE/bootstrap-deb-zsh.sh" -o bootstrap-deb-zsh.sh
curl -fsSL "$REPO_RAW_BASE/zsh-config.tar.gz" -o zsh-config.tar.gz

chmod +x bootstrap-deb-zsh.sh

echo "[+] Run bootstrap..."
./bootstrap-deb-zsh.sh ./zsh-config.tar.gz

echo "[+] Setting zsh as default shell (may require password)"
chsh -s "$(command -v zsh)" || true
echo "[!] IMPORTANT: Log out/in (or restart terminal) for default shell to switch to zsh."
