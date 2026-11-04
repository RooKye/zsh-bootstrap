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
# Outils réseau : installés mais DÉSACTIVÉS
#   - wireshark + tshark : capture réservée à root (pas de groupe wireshark)
#   - openssh-client + openssh-server : sshd arrêté et non lancé au démarrage
#   (ifconfig vient de net-tools, déjà installé plus haut)
# Désactiver cette étape : ZSH_BOOTSTRAP_TOOLS=0
# -----------------------------
if [[ "${ZSH_BOOTSTRAP_TOOLS:-1}" == "1" ]]; then
  log "Outils : wireshark, tshark, openssh (installés mais désactivés)"

  # sshd déjà présent avant le script : on ne touche pas à son état
  # (évite de couper l'accès à une machine qu'on administre en SSH)
  ssh_was_installed=0
  dpkg -s openssh-server >/dev/null 2>&1 && ssh_was_installed=1

  # Wireshark : répond "non" à "autoriser la capture aux non-root ?"
  echo "wireshark-common wireshark-common/install-setuid boolean false" \
    | sudo debconf-set-selections

  # Empêche apt de démarrer les services pendant l'installation
  policy_added=0
  trap 'if [[ "${policy_added:-0}" == 1 ]]; then sudo rm -f /usr/sbin/policy-rc.d; fi' EXIT
  if [[ ! -e /usr/sbin/policy-rc.d ]]; then
    printf '#!/bin/sh\nexit 101\n' | sudo tee /usr/sbin/policy-rc.d >/dev/null
    sudo chmod +x /usr/sbin/policy-rc.d
    policy_added=1
  fi

  tools_rc=0
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    wireshark tshark openssh-client openssh-server || tools_rc=$?

  if [[ "$policy_added" == 1 ]]; then
    sudo rm -f /usr/sbin/policy-rc.d
    policy_added=0
  fi
  [[ "$tools_rc" == 0 ]] || die "Installation des outils impossible (apt-get code $tools_rc)"

  # SSH : désactivé (service + socket d'activation Ubuntu 22.10+)
  if [[ "$ssh_was_installed" == 1 ]]; then
    warn "openssh-server était déjà installé : son état n'est pas modifié"
  elif [[ -d /run/systemd/system ]]; then
    for unit in ssh.socket ssh.service; do
      sudo systemctl disable --now "$unit" >/dev/null 2>&1 || true
    done
    echo "    sshd : $(systemctl is-enabled ssh.service 2>/dev/null || echo disabled)"
  else
    # WSL sans systemd / sysvinit
    sudo service ssh stop >/dev/null 2>&1 || true
    sudo update-rc.d ssh disable >/dev/null 2>&1 || true
    echo "    sshd : arrêté (pas de systemd : rien ne le relance au démarrage)"
  fi
  echo "    wireshark : capture réservée à root"
else
  warn "Outils wireshark / openssh ignorés (ZSH_BOOTSTRAP_TOOLS=0)"
fi

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
# Plugins : installés / mis à jour par zsh-repair.sh (plus bas)
# -----------------------------

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
# Plugins + patch .zshrc (idempotent)
#   zsh-repair.sh installe/met à jour les plugins, nettoie les anciens blocs,
#   charge zsh-autocomplete AVANT oh-my-zsh et syntax-highlighting en dernier.
# -----------------------------
REPAIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/zsh-repair.sh"
if [[ ! -f "$REPAIR" ]]; then
  REPAIR="$(mktemp)"
  curl -fsSL "https://raw.githubusercontent.com/RooKye/zsh-bootstrap/main/zsh-repair.sh" -o "$REPAIR" \
    || die "Téléchargement de zsh-repair.sh impossible"
fi
ZSH="$HOME/.oh-my-zsh" ZSH_CUSTOM="$ZSH_CUSTOM" bash "$REPAIR"

# -----------------------------
# Default shell
# -----------------------------
if [[ "${SHELL:-}" != "$(command -v zsh)" ]]; then
  log "Définition zsh comme shell par défaut"
  chsh -s "$(command -v zsh)" "$USER" || warn "chsh a échoué (fais-le manuellement)."
fi

log "OK ✅"
warn "Redémarre ton terminal ou fais: exec zsh"
warn "Désactiver zsh-autocomplete : echo 'ZSH_BOOTSTRAP_AUTOCOMPLETE=0' >> ~/.zshenv"
if [[ "${ZSH_BOOTSTRAP_TOOLS:-1}" == "1" ]]; then
  warn "Activer SSH       : sudo systemctl enable --now ssh   (WSL sans systemd : sudo service ssh start)"
  warn "Wireshark non-root : sudo dpkg-reconfigure wireshark-common && sudo usermod -aG wireshark \$USER  (puis reconnexion)"
fi
