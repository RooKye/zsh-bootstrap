# ZSH Bootstrap (Debian / Kali / Ubuntu / WSL)

Installe automatiquement :
- zsh + oh-my-zsh
- powerlevel10k
- plugins (autosuggestions, syntax-highlighting, autocomplete)
- outils réseau (net-tools / `ifconfig`, dnsutils, tcpdump, iproute2)
- wireshark + tshark, **activés** : capture sans sudo (ton utilisateur est ajouté au groupe `wireshark`, actif après reconnexion)
- openssh (client + serveur), **serveur désactivé** : `sshd` arrêté et non lancé au démarrage (s'il était déjà installé avant, son état n'est pas modifié)
- importe la config `.zshrc` + `.p10k.zsh`

## One-liner
```bash
curl -fsSL https://raw.githubusercontent.com/RooKye/zsh-bootstrap/main/install.sh | bash
```

Le script est idempotent : on peut le relancer sans dupliquer la config.

Sans wireshark / openssh :
```bash
curl -fsSL https://raw.githubusercontent.com/RooKye/zsh-bootstrap/main/install.sh | ZSH_BOOTSTRAP_TOOLS=0 bash
```

### Activer SSH plus tard

```bash
sudo systemctl enable --now ssh        # WSL sans systemd : sudo service ssh start
```

## Réparer une install existante

Si tu as des erreurs du type :
```
autocomplete:_main_complete:new:post:3: command not found: _autocomplete__unambiguous
.autocomplete__complete-word__post:59: command not found: _autocomplete__should_add_space
```
lance :
```bash
curl -fsSL https://raw.githubusercontent.com/RooKye/zsh-bootstrap/main/zsh-repair.sh | bash
exec zsh
```

Sous WSL, avec le fichier téléchargé côté Windows :
```bash
tr -d '\r' < /mnt/c/Users/<toi>/Downloads/zsh-repair.sh | bash
exec zsh
```

### Pourquoi c'est cassé depuis fin août 2026

Le bug vient de zsh-autocomplete lui-même : le commit
[`b07922e`](https://github.com/marlonrichert/zsh-autocomplete/commit/b07922e84ce9a5d8401425235954ce9ce185a770)
du 26/08/2026 empêche le plugin d'enregistrer ses fonctions `_autocomplete__*`
quand un autre `compinit` (Oh My Zsh, `/etc/zsh/zshrc`) passe avant lui
([issue #896](https://github.com/marlonrichert/zsh-autocomplete/issues/896),
[PR #903](https://github.com/marlonrichert/zsh-autocomplete/pull/903) pas encore fusionnée).
Comme le bootstrap clonait la branche `main`, toutes les machines installées ou
mises à jour depuis sont touchées (Kali, Ubuntu, WSL...).

Le bootstrap fige donc zsh-autocomplete sur `027cdab` (05/08/2026), le dernier
commit avant ces changements, et ajoute le correctif de la PR #903 dans le `.zshrc`.

`zsh-repair.sh` :
- installe les plugins, avec zsh-autocomplete figé sur une version qui marche
- nettoie les anciens blocs du bootstrap (et leurs doublons)
- charge `zsh-autocomplete` **avant** oh-my-zsh (qui appelle `compinit`)
- charge `zsh-syntax-highlighting` en dernier
- ajoute `skip_global_compinit=1` dans `~/.zshenv` (Debian/Ubuntu/Kali)
- neutralise les appels à `compinit` du `.zshrc`
- vide les caches de complétion
- WSL : corrige les fins de ligne Windows (CRLF) des dotfiles et des plugins
- teste un démarrage de zsh et vérifie que les fonctions du plugin sont enregistrées
- sauvegarde le `.zshrc` et le restaure si le résultat est invalide

## Options

À mettre dans `~/.zshenv` :

| Variable | Effet |
|---|---|
| `ZSH_BOOTSTRAP_AUTOCOMPLETE=0` | désactive zsh-autocomplete |
| `ZSH_BOOTSTRAP_AUTOCOMPLETE=1` | force zsh-autocomplete même sur TERM `dumb` / `linux` |

Pour `install.sh` / `bootstrap-deb-zsh.sh` :
- `ZSH_BOOTSTRAP_TOOLS=0` n'installe pas wireshark / tshark / openssh

Pour `zsh-repair.sh` :
- `ZSH_BOOTSTRAP_NO_UPDATE=1` évite le `git pull` des autres plugins
- `ZSH_BOOTSTRAP_AUTOCOMPLETE_REF=main` (ou un tag / sha) choisit une autre version de zsh-autocomplete, par exemple une fois le bug corrigé en amont
