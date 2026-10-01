# etc

Personal Arch Linux dotfiles managed with **GNU Stow**.

Includes:

- Zsh
- Starship
- Alacritty
- Fastfetch

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
stow zsh starship alacritty fastfetch
```

Remove symlinks:

```bash
stow -D zsh starship alacritty fastfetch
```

## Update

```bash
cd ~/etc
git add .
git commit -m "Update configs"
git push
```

> Keep passwords, SSH keys, tokens and other credentials out of this repository.
