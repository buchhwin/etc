#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

PACKAGES=(
  git
  stow
  zsh
  starship
  alacritty
  fastfetch
  ttf-jetbrains-mono-nerd
)

STOW_PACKAGES=(
  zsh
  starship
  alacritty
  fastfetch
)

echo "================================================="
echo "              buchhwin dotfiles"
echo "================================================="
echo
echo "Repository: $REPO_DIR"
echo

# Arch Linux prüfen
if ! command -v pacman >/dev/null 2>&1; then
  echo "Fehler: Dieses Setup-Skript ist aktuell für Arch Linux vorgesehen."
  exit 1
fi

echo "Installiere benötigte Pakete..."
sudo pacman -S --needed "${PACKAGES[@]}"

echo
echo "Richte Zsh ein..."

ZSH_PATH="$(command -v zsh)"

if [[ "${SHELL:-}" != "$ZSH_PATH" ]]; then
  echo "Setze Zsh als Standardshell..."
  chsh -s "$ZSH_PATH"
else
  echo "Zsh ist bereits die Standardshell."
fi

# Oh My Zsh
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  echo "Installiere Oh My Zsh..."
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  echo "Oh My Zsh ist bereits installiert."
fi

ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

if [[ ! -d "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions" ]]; then
  echo "Installiere zsh-autosuggestions..."
  git clone https://github.com/zsh-users/zsh-autosuggestions \
    "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions"
fi

if [[ ! -d "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting" ]]; then
  echo "Installiere zsh-syntax-highlighting..."
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
    "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting"
fi

backup_if_real_file() {
  local path="$1"

  # Bereits korrekt verlinkte Dateien nicht anfassen
  if [[ -L "$path" ]]; then
    return
  fi

  if [[ -e "$path" ]]; then
    local relative="${path#$HOME/}"
    local destination="$BACKUP_DIR/$relative"

    echo "Sichere bestehende Datei: $path"
    mkdir -p "$(dirname "$destination")"
    mv "$path" "$destination"
  fi
}

echo
echo "Prüfe vorhandene Konfigurationen..."

backup_if_real_file "$HOME/.zshrc"
backup_if_real_file "$HOME/.config/starship.toml"
backup_if_real_file "$HOME/.config/alacritty/alacritty.toml"
backup_if_real_file "$HOME/.config/fastfetch/config.jsonc"

mkdir -p "$HOME/.config"

echo
echo "Erzeuge Symlinks mit GNU Stow..."

cd "$REPO_DIR"

for package in "${STOW_PACKAGES[@]}"; do
  if [[ -d "$REPO_DIR/$package" ]]; then
    echo "  -> $package"
    stow -R -t "$HOME" "$package"
  else
    echo "Warnung: Paket '$package' fehlt im Repository."
  fi
done

echo
echo "================================================="
echo "                  Fertig"
echo "================================================="
echo
echo "Gestowte Pakete:"
printf '  - %s\n' "${STOW_PACKAGES[@]}"
echo

if [[ -d "$BACKUP_DIR" ]]; then
  echo "Vorhandene Configs wurden gesichert unter:"
  echo "  $BACKUP_DIR"
  echo
fi

echo "Starte ein neues Terminal oder führe aus:"
echo "  exec zsh"
echo
