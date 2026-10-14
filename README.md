# etc

Personal Arch Linux dotfiles managed with **GNU Stow**.

Includes:

- Zsh
- Starship
- Alacritty (Plasma-Terminal, Meta+Return)
- Fastfetch
- KDE: globale Shortcuts (`kglobalshortcutsrc`) und KWin (`kwinrc`: Arbeitsflächen, Effekte)

## Install

```bash
git clone git@github.com:buchhwin/etc.git ~/etc
cd ~/etc
chmod +x install.sh
./install.sh
```

The installer sets up the required packages, configures Zsh, installs Oh My Zsh and plugins, backs up conflicting config files, and stows the dotfiles into `$HOME`.

## Manual Stow

```bash
cd ~/etc
stow -t ~ zsh starship alacritty fastfetch kde
```

KDE schreibt Änderungen an Shortcuts und KWin-Einstellungen durch die Symlinks
direkt in dieses Repo; `git diff` zeigt sie, committen wie gewohnt. Neue
Einstellungen wirken nach dem nächsten Login.

Remove symlinks:

```bash
stow -D -t ~ zsh starship alacritty fastfetch kde
```

## Update

```bash
cd ~/etc
git add .
git commit -m "Update configs"
git push
```

> Keep passwords, SSH keys, tokens and other credentials out of this repository.
