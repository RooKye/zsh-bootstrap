#!/usr/bin/env bash
# =============================================================================
# zsh-repair.sh — Répare / (re)configure le .zshrc pour zsh-bootstrap
#
#  - installe ou met à jour les plugins (autocomplete, autosuggestions,
#    syntax-highlighting) dans $ZSH_CUSTOM/plugins
#  - nettoie les anciens blocs (y compris les doublons) et les chargements
#    de plugins mal placés
#  - charge zsh-autocomplete AVANT oh-my-zsh (qui appelle compinit)
#  - charge autosuggestions puis syntax-highlighting EN DERNIER
#  - ajoute skip_global_compinit=1 dans ~/.zshenv (Debian / Ubuntu / Kali)
#  - vide les caches de complétion
#  - vérifie la syntaxe et restaure la sauvegarde en cas de problème
#
# Idempotent : peut être relancé autant de fois que nécessaire.
#
# Usage :
#   bash zsh-repair.sh
#   curl -fsSL https://raw.githubusercontent.com/RooKye/zsh-bootstrap/main/zsh-repair.sh | bash
#
# Options (variables d'environnement) :
#   ZSH_BOOTSTRAP_NO_UPDATE=1   ne pas faire de git pull sur les plugins
# =============================================================================
set -euo pipefail

log(){  printf "\033[1;34m[+]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
die(){  printf "\033[1;31m[x]\033[0m %s\n" "$*" >&2; exit 1; }

ZDOT="${ZDOTDIR:-$HOME}"
ZSHRC="$ZDOT/.zshrc"
ZSHENV="$ZDOT/.zshenv"
OMZ_DIR="${ZSH:-$HOME/.oh-my-zsh}"
CUSTOM_DIR="${ZSH_CUSTOM:-$OMZ_DIR/custom}"

command -v git >/dev/null 2>&1 || die "git requis (sudo apt install git)"
[[ -f "$OMZ_DIR/oh-my-zsh.sh" ]] || die "Oh My Zsh introuvable dans $OMZ_DIR (lance d'abord install.sh)"

# -----------------------------------------------------------------------------
# 1. Plugins : installation / mise à jour / réparation
# -----------------------------------------------------------------------------
# nom|url|fichier attendu
PLUGINS=(
  "zsh-autocomplete|https://github.com/marlonrichert/zsh-autocomplete.git|zsh-autocomplete.plugin.zsh"
  "zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions.git|zsh-autosuggestions.zsh"
  "zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting.git|zsh-syntax-highlighting.zsh"
)

log "Plugins"
mkdir -p "$CUSTOM_DIR/plugins"
for entry in "${PLUGINS[@]}"; do
  IFS='|' read -r name url file <<<"$entry"
  dir="$CUSTOM_DIR/plugins/$name"

  if [[ -d "$dir/.git" && -f "$dir/$file" ]]; then
    if [[ "${ZSH_BOOTSTRAP_NO_UPDATE:-0}" != 1 ]]; then
      if git -C "$dir" pull --ff-only -q 2>/dev/null; then
        echo "    $name : à jour"
      else
        warn "$name : mise à jour impossible, réinstallation"
        rm -rf "$dir"
      fi
    else
      echo "    $name : présent"
    fi
  elif [[ -e "$dir" ]]; then
    warn "$name : installation incomplète, réinstallation"
    rm -rf "$dir"
  fi

  if [[ ! -d "$dir" ]]; then
    git clone -q --depth=1 "$url" "$dir" || die "Clonage de $name impossible"
    echo "    $name : installé"
  fi
done

# -----------------------------------------------------------------------------
# 2. Sauvegarde
# -----------------------------------------------------------------------------
[[ -f "$ZSHRC" ]] || touch "$ZSHRC"
BACKUP="$ZSHRC.bak-$(date +%Y%m%d-%H%M%S)"
cp "$ZSHRC" "$BACKUP"
log "Sauvegarde : $BACKUP"

# -----------------------------------------------------------------------------
# 3. Nettoyage du .zshrc
#    - anciens blocs ### BOOTSTRAP_BLOCK ### ... ### END ... ### (doublons inclus)
#    - nos propres blocs (pour rester idempotent)
#    - chargements isolés des 3 plugins (source simple, "&& \", if/then/fi)
#    - les 3 plugins dans plugins=(...) d'Oh My Zsh
#    - appels directs à compinit (gérés par zsh-autocomplete)
# -----------------------------------------------------------------------------
log "Nettoyage du .zshrc"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

awk '
  { line[NR] = $0 }
  END {
    n = NR
    plug = "zsh-(autocomplete|autosuggestions|syntax-highlighting)"
    for (i = 1; i <= n; i++) {
      l = line[i]

      # Anciens blocs du bootstrap (marqueur de fin avec ou sans VICTOR_)
      if (l ~ /^### (VICTOR_)?BOOTSTRAP_BLOCK ###/) {
        for (j = i; j <= n && line[j] !~ /^### END (VICTOR_)?BOOTSTRAP_BLOCK ###/; j++) del[j] = 1
        if (j <= n) del[j] = 1
        i = j; continue
      }
      # Nos blocs (réécrits plus bas)
      if (l ~ /^# >>> zsh-bootstrap:/) {
        for (j = i; j <= n && line[j] !~ /^# <<< zsh-bootstrap:/; j++) del[j] = 1
        if (j <= n) del[j] = 1
        i = j; continue
      }
      # Chargement isolé d un des plugins
      if (l ~ /^[[:space:]]*(source|\.)[[:space:]]/ && l ~ plug) {
        del[i] = 1
        if (i > 1 && line[i-1] ~ /&&[[:space:]]*\\?[[:space:]]*$/) del[i-1] = 1
        if (i > 1 && i < n && line[i-1] ~ /^[[:space:]]*if .*then[[:space:]]*$/ && line[i+1] ~ /^[[:space:]]*fi[[:space:]]*$/) {
          del[i-1] = 1; del[i+1] = 1
        }
        continue
      }
      if (l ~ /^[[:space:]]*\[\[.*\]\][[:space:]]*&&[[:space:]]*(source|\.)[[:space:]]/ && l ~ plug) { del[i] = 1; continue }
    }

    inplug = 0
    for (i = 1; i <= n; i++) {
      if (del[i]) continue
      l = line[i]

      # Retire les 3 plugins du tableau plugins=(...) (une ou plusieurs lignes)
      if (l ~ /^[[:space:]]*plugins=\(/) inplug = 1
      if (inplug) {
        gsub(/(^|[[:space:]])zsh-(autocomplete|autosuggestions|syntax-highlighting)([[:space:]]|$)/, " ", l)
        gsub(/\([[:space:]]+/, "(", l); gsub(/[[:space:]]+\)/, ")", l)
        if (l ~ /\)/) inplug = 0
        if (l ~ /^[[:space:]]*$/ && line[i] !~ /^[[:space:]]*$/) continue
      }

      # compinit direct -> commenté (zsh-autocomplete s en occupe)
      if (l ~ /^[[:space:]]*compinit([[:space:]]|$)/) l = "# " l "  # désactivé par zsh-bootstrap (géré par zsh-autocomplete)"

      print l
    }
  }
' "$ZSHRC" > "$TMP"

# Supprime les lignes vides en excès laissées par le nettoyage
cat -s "$TMP" > "$ZSHRC"

# -----------------------------------------------------------------------------
# 4. Base Oh My Zsh / Powerlevel10k
# -----------------------------------------------------------------------------
log "Configuration Oh My Zsh / Powerlevel10k"
export OMZ_RE='^[[:space:]]*(source|\.)[[:space:]]+"?\$\{?ZSH\}?/oh-my-zsh\.sh"?'

grep -qE '^[[:space:]]*export ZSH=' "$ZSHRC" || {
  # avant le source d oh-my-zsh s il existe, sinon en fin de fichier
  if grep -qE "$OMZ_RE" "$ZSHRC"; then
    awk '$0 ~ ENVIRON["OMZ_RE"] && !d { print "export ZSH=\"$HOME/.oh-my-zsh\""; d=1 } { print }' "$ZSHRC" > "$TMP" && cat "$TMP" > "$ZSHRC"
  else
    printf '\nexport ZSH="$HOME/.oh-my-zsh"\n' >> "$ZSHRC"
  fi
}

if grep -qE '^[[:space:]]*ZSH_THEME=' "$ZSHRC"; then
  sed -i -E 's|^([[:space:]]*)ZSH_THEME=.*|\1ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC"
else
  awk '$0 ~ ENVIRON["OMZ_RE"] && !d { print "ZSH_THEME=\"powerlevel10k/powerlevel10k\""; d=1 } { print } END { if (!d) print "ZSH_THEME=\"powerlevel10k/powerlevel10k\"" }' "$ZSHRC" > "$TMP" && cat "$TMP" > "$ZSHRC"
fi

grep -qE "$OMZ_RE" "$ZSHRC" || printf '\nsource $ZSH/oh-my-zsh.sh\n' >> "$ZSHRC"

if [[ -f "$HOME/.p10k.zsh" ]] && ! grep -qE '\.p10k\.zsh' "$ZSHRC"; then
  printf '\n[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh\n' >> "$ZSHRC"
fi

# -----------------------------------------------------------------------------
# 5. Blocs plugins
# -----------------------------------------------------------------------------
log "Ordre de chargement des plugins"

AC_BLOCK="$(cat <<'EOF'
# >>> zsh-bootstrap:autocomplete >>>
# zsh-autocomplete DOIT être chargé avant oh-my-zsh (qui appelle compinit).
# Contrôle : ZSH_BOOTSTRAP_AUTOCOMPLETE=0 (désactive) / 1 (force) dans ~/.zshenv
case "${ZSH_BOOTSTRAP_AUTOCOMPLETE:-auto}:${TERM:-dumb}" in
  0:*|auto:dumb|auto:linux) ;;
  *)
    _zb_ac="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh"
    [[ -r "$_zb_ac" ]] && source "$_zb_ac"
    unset _zb_ac
    ;;
esac
# <<< zsh-bootstrap:autocomplete <<<

EOF
)"

END_BLOCK="$(cat <<'EOF'

# >>> zsh-bootstrap:plugins >>>
_zb_plugins="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/plugins"
[[ -r "$_zb_plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] &&
  source "$_zb_plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
# zsh-syntax-highlighting doit rester le DERNIER plugin chargé
[[ -r "$_zb_plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] &&
  source "$_zb_plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
unset _zb_plugins
# <<< zsh-bootstrap:plugins <<<
EOF
)"

# autocomplete juste avant le premier "source $ZSH/oh-my-zsh.sh"
AC_BLOCK="$AC_BLOCK" awk '
  $0 ~ ENVIRON["OMZ_RE"] && !d { print ENVIRON["AC_BLOCK"]; print ""; d = 1 }
  { print }
' "$ZSHRC" > "$TMP"
# (et retire les lignes vides de fin pour rester idempotent)
cat -s "$TMP" | awk '{ a[NR] = $0 } END { n = NR; while (n > 0 && a[n] ~ /^[[:space:]]*$/) n--; for (i = 1; i <= n; i++) print a[i] }' > "$ZSHRC"

# autosuggestions + syntax-highlighting tout à la fin
printf '%s\n' "$END_BLOCK" >> "$ZSHRC"

# -----------------------------------------------------------------------------
# 6. ~/.zshenv : pas de compinit global (Debian / Ubuntu / Kali)
# -----------------------------------------------------------------------------
if ! grep -qE '^[[:space:]]*skip_global_compinit=1' "$ZSHENV" 2>/dev/null; then
  printf '\n# zsh-bootstrap : le compinit global casse zsh-autocomplete\nskip_global_compinit=1\n' >> "$ZSHENV"
  log "skip_global_compinit=1 ajouté dans $ZSHENV"
fi

# -----------------------------------------------------------------------------
# 7. Caches de complétion
# -----------------------------------------------------------------------------
log "Vidage des caches de complétion"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
rm -f "$ZDOT"/.zcompdump* "$CACHE"/zsh/compdump* "$OMZ_DIR"/cache/.zcompdump* 2>/dev/null || true
rm -rf "$CACHE"/zsh-autocomplete 2>/dev/null || true

# -----------------------------------------------------------------------------
# 8. Vérifications
# -----------------------------------------------------------------------------
if command -v zsh >/dev/null 2>&1; then
  if ! zsh -n "$ZSHRC" 2>"$TMP"; then
    cat "$TMP" >&2
    cp "$BACKUP" "$ZSHRC"
    die "Erreur de syntaxe dans le .zshrc généré : sauvegarde restaurée"
  fi
fi

ac_line="$(grep -n 'zsh-bootstrap:autocomplete >>>' "$ZSHRC" | head -1 | cut -d: -f1)"
omz_line="$(grep -nE "$OMZ_RE" "$ZSHRC" | head -1 | cut -d: -f1)"
if [[ -z "$ac_line" || -z "$omz_line" || "$ac_line" -ge "$omz_line" ]]; then
  cp "$BACKUP" "$ZSHRC"
  die "Ordre de chargement inattendu : sauvegarde restaurée"
fi

log "OK ✅  (zsh-autocomplete ligne $ac_line, oh-my-zsh ligne $omz_line)"
warn "Recharge ton shell : exec zsh"
warn "Retour arrière : cp \"$BACKUP\" \"$ZSHRC\""
