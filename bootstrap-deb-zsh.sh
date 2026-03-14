#!/usr/bin/env bash
set -euo pipefail

ARCHIVE="${1:-}"

log(){ printf "\n\033[1;34m[+]\033[0m %s\n" "$*"; }
warn(){ printf "\n\033[1;33m[!]\033[0m %s\n" "$*"; }
die(){ printf "\n\033[1;31m[x]\033[0m %s\n" "$*"; exit 1; }

command -v sudo >/dev/null 2>&1 || die "sudo requis"
command -v apt-get >/dev/null 2>&1 || die "Debian/Ubuntu requis (apt)."

# -----------------------------
# Packages
# -----------------------------
log "Packages (Debian) + workflow réseau"
sudo apt-get update -y
sudo apt-get install -y \
  zsh git curl wget unzip fontconfig tar \
  net-tools dnsutils tcpdump iproute2

# -----------------------------
# Oh My Zsh
# -----------------------------
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  log "Installation Oh My Zsh (non-interactif)"
  export RUNZSH=no
  export CHSH=no
  export KEEP_ZSHRC=yes
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  warn "Oh My Zsh déjà présent"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# -----------------------------
# Powerlevel10k
# -----------------------------
if [[ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]]; then
  log "Installation Powerlevel10k"
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
    "$ZSH_CUSTOM/themes/powerlevel10k"
else
  warn "Powerlevel10k déjà présent"
fi

# -----------------------------
# Plugins
# -----------------------------
clone(){ [[ -d "$2" ]] || git clone --depth=1 "$1" "$2"; }

log "Installation plugins"
clone https://github.com/zsh-users/zsh-autosuggestions.git \
  "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
  "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
clone https://github.com/marlonrichert/zsh-autocomplete.git \
  "$ZSH_CUSTOM/plugins/zsh-autocomplete"

# -----------------------------
# Nerd Font (Meslo)
# -----------------------------
log "Installation Meslo Nerd Font (p10k)"
FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"
base="https://raw.githubusercontent.com/romkatv/powerlevel10k-media/master"
curl -fsSL "$base/MesloLGS%20NF%20Regular.ttf"      -o "$FONT_DIR/MesloLGS NF Regular.ttf"      || true
curl -fsSL "$base/MesloLGS%20NF%20Bold.ttf"         -o "$FONT_DIR/MesloLGS NF Bold.ttf"         || true
curl -fsSL "$base/MesloLGS%20NF%20Italic.ttf"       -o "$FONT_DIR/MesloLGS NF Italic.ttf"       || true
curl -fsSL "$base/MesloLGS%20NF%20Bold%20Italic.ttf" -o "$FONT_DIR/MesloLGS NF Bold Italic.ttf" || true
fc-cache -f >/dev/null 2>&1 || true

# -----------------------------
# Backup helper
# -----------------------------
backup() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local ts; ts="$(date +%Y%m%d-%H%M%S)"
  cp "$f" "${f}.bak-${ts}"
  warn "Backup: ${f}.bak-${ts}"
}

# -----------------------------
# Import archive (your prefs)
# -----------------------------
if [[ -n "$ARCHIVE" ]]; then
  [[ -f "$ARCHIVE" ]] || die "Archive introuvable: $ARCHIVE"

  log "Import config depuis: $ARCHIVE"
  backup "$HOME/.zshrc"
  backup "$HOME/.p10k.zsh"

  tmp="$(mktemp -d)"
  tar -xzf "$ARCHIVE" -C "$tmp"

SRC_ZSHRC=""
SRC_P10K=""

# 1) current user path
[[ -f "$tmp/home/$USER/.zshrc" ]] && SRC_ZSHRC="$tmp/home/$USER/.zshrc"
[[ -f "$tmp/home/$USER/.p10k.zsh" ]] && SRC_P10K="$tmp/home/$USER/.p10k.zsh"

# 2) direct root of archive
[[ -z "$SRC_ZSHRC" && -f "$tmp/.zshrc" ]] && SRC_ZSHRC="$tmp/.zshrc"
[[ -z "$SRC_P10K"  && -f "$tmp/.p10k.zsh" ]] && SRC_P10K="$tmp/.p10k.zsh"

# 3) fallback: any archived home user
if [[ -z "$SRC_ZSHRC" ]]; then
  SRC_ZSHRC="$(find "$tmp" -type f -name '.zshrc' | head -n 1 || true)"
fi

if [[ -z "$SRC_P10K" ]]; then
  SRC_P10K="$(find "$tmp" -type f -name '.p10k.zsh' | head -n 1 || true)"
fi

  [[ -n "$SRC_ZSHRC" ]] && cp "$SRC_ZSHRC" "$HOME/.zshrc" || warn "Pas de .zshrc dans l’archive"
  [[ -n "$SRC_P10K"  ]] && cp "$SRC_P10K"  "$HOME/.p10k.zsh" || warn "Pas de .p10k.zsh dans l’archive"

  rm -rf "$tmp"
else
  warn "Aucune archive fournie: je n’importe pas ta conf perso"
fi

# -----------------------------
# Patch .zshrc (force p10k)
# -----------------------------
log "Patch .zshrc (force p10k + auto-complete ON)"
[[ -f "$HOME/.zshrc" ]] || touch "$HOME/.zshrc"

# export ZSH
grep -q '^export ZSH=' "$HOME/.zshrc" || printf '\nexport ZSH="$HOME/.oh-my-zsh"\n' >> "$HOME/.zshrc"

# force theme
if grep -q '^ZSH_THEME=' "$HOME/.zshrc"; then
  sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$HOME/.zshrc"
else
  printf 'ZSH_THEME="powerlevel10k/powerlevel10k"\n' >> "$HOME/.zshrc"
fi

# source OMZ
grep -q 'source \$ZSH/oh-my-zsh\.sh' "$HOME/.zshrc" || printf '\nsource $ZSH/oh-my-zsh.sh\n' >> "$HOME/.zshrc"

# source p10k config
grep -q 'source ~/.p10k\.zsh' "$HOME/.zshrc" || printf '\n[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh\n' >> "$HOME/.zshrc"

# Stable block (idempotent)
if ! grep -q '### VICTOR_BOOTSTRAP_BLOCK ###' "$HOME/.zshrc"; then
cat >> "$HOME/.zshrc" <<'EOF'

### BOOTSTRAP_BLOCK ###
# Plugins custom (avec garde-fou affichage)
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# Auto-complete ON par défaut, mais désactivé sur terminaux "à risque"
# Override: FORCE_AUTOCOMPLETE=1 pour forcer l'activation
_term_ok=1
case "${TERM:-}" in
  ""|dumb|linux) _term_ok=0 ;;
esac

if [[ "${FORCE_AUTOCOMPLETE:-0}" == "1" ]]; then
  _term_ok=1
fi

if [[ "$_term_ok" == "1" ]] && [[ -f "${ZSH_CUSTOM}/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh" ]]; then
  source "${ZSH_CUSTOM}/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh"
fi

[[ -f "${ZSH_CUSTOM}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && \
  source "${ZSH_CUSTOM}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"

# syntax-highlighting DOIT être chargé en dernier
[[ -f "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && \
  source "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
### END VICTOR_BOOTSTRAP_BLOCK ###
EOF
fi

# -----------------------------
# Default shell
# -----------------------------
if [[ "${SHELL:-}" != "$(command -v zsh)" ]]; then
  log "Définition zsh comme shell par défaut"
  chsh -s "$(command -v zsh)" "$USER" || warn "chsh a échoué (fais-le manuellement)."
fi

log "OK ✅"
warn "Redémarre ton terminal ou fais: exec zsh"
warn "Si autocomplete bug l’affichage: export FORCE_AUTOCOMPLETE=0 (ou commente dans .zshrc)"
