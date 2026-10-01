# etc

Meine persönlichen Dotfiles für Arch Linux, verwaltet mit **GNU Stow**.

Aktuell enthalten:

- Zsh
- Starship
- Alacritty
- Fastfetch

Die Dateien liegen im Repository in derselben Struktur, in der sie später im Home-Verzeichnis erscheinen. GNU Stow erstellt dafür Symlinks.

## Struktur

```text
etc/
├── zsh/
│   └── .zshrc
├── starship/
│   └── .config/
│       └── starship.toml
├── alacritty/
│   └── .config/
│       └── alacritty/
│           └── alacritty.toml
├── fastfetch/
│   └── .config/
│       └── fastfetch/
│           └── config.jsonc
└── install.sh
```

Nach dem Stowen zeigen die Dateien im Home-Verzeichnis auf dieses Repository, z. B.:

```text
~/.zshrc
~/.config/starship.toml
~/.config/alacritty/alacritty.toml
~/.config/fastfetch/config.jsonc
```

## Installation auf einem neuen Arch-System

Repository klonen:

```bash
git clone git@github.com:buchhwin/etc.git ~/etc
cd ~/etc
```

Installationsskript ausführbar machen und starten:

```bash
chmod +x install.sh
./install.sh
```

Das Skript:

1. installiert die benötigten Arch-Pakete,
2. richtet Zsh als Standardshell ein,
3. installiert Oh My Zsh,
4. installiert `zsh-autosuggestions` und `zsh-syntax-highlighting`,
5. sichert vorhandene kollidierende Config-Dateien,
6. stowt alle enthaltenen Dotfiles nach `$HOME`.

## Manuell stowen

Falls nur einzelne Konfigurationen aktiviert werden sollen:

```bash
cd ~/etc

stow zsh
stow starship
stow alacritty
stow fastfetch
```

Alles erneut verlinken:

```bash
stow -R zsh starship alacritty fastfetch
```

Symlinks wieder entfernen, ohne die Dateien im Repository zu löschen:

```bash
stow -D zsh starship alacritty fastfetch
```

## Änderungen

Da die Dateien im Home-Verzeichnis Symlinks auf dieses Repository sind, können sie ganz normal bearbeitet werden:

```bash
nano ~/.zshrc
nano ~/.config/starship.toml
nano ~/.config/alacritty/alacritty.toml
nano ~/.config/fastfetch/config.jsonc
```

Danach Änderungen committen:

```bash
cd ~/etc
git status
git add .
git commit -m "Update configs"
git push
```

## Hinweise

- Passwörter, SSH-Keys, Tokens und Credentials gehören **nicht** in dieses Repository.
- Das Skript überschreibt bestehende kollidierende Config-Dateien nicht kommentarlos. Sie werden vorher unter `~/.dotfiles-backup/<Zeitstempel>/` gesichert.
- KDE-Konfigurationen und Shortcuts sind derzeit bewusst nicht Bestandteil dieses Repositories.
