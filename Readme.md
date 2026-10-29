# ZSH Bootstrap (Debian / Kali)

Installe automatiquement :
- zsh + oh-my-zsh
- powerlevel10k
- plugins (autosuggestions, syntax-highlighting, autocomplete)
- outils réseau (net-tools, dnsutils, tcpdump, iproute2)
- importe la config `.zshrc` + `.p10k.zsh`

## One-liner
```bash
curl -fsSL https://raw.githubusercontent.com/RooKye/zsh-bootstrap/main/install.sh | bash
```

Le script est idempotent : on peut le relancer sans dupliquer la config.

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

`zsh-repair.sh` :
- installe / met à jour les plugins
- nettoie les anciens blocs du bootstrap (et leurs doublons)
- charge `zsh-autocomplete` **avant** oh-my-zsh (qui appelle `compinit`)
- charge `zsh-syntax-highlighting` en dernier
- ajoute `skip_global_compinit=1` dans `~/.zshenv` (Debian/Ubuntu/Kali)
- vide les caches de complétion
- sauvegarde le `.zshrc` et le restaure si le résultat est invalide

## Options

À mettre dans `~/.zshenv` :

| Variable | Effet |
|---|---|
| `ZSH_BOOTSTRAP_AUTOCOMPLETE=0` | désactive zsh-autocomplete |
| `ZSH_BOOTSTRAP_AUTOCOMPLETE=1` | force zsh-autocomplete même sur TERM `dumb` / `linux` |

Pour `zsh-repair.sh` : `ZSH_BOOTSTRAP_NO_UPDATE=1` évite le `git pull` des plugins.
