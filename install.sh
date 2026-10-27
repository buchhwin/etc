#!/usr/bin/env bash
# Bring this machine's user setup back on a fresh Arch install. Dry run by
# default: every step is printed, in order, and nothing changes.
#
#   ./install.sh                     dry run
#   ./install.sh --apply             do it (asks for sudo where it must)
#   ./install.sh --apply --no-packages   only links, shell and settings
#   ./install.sh --apply --no-shell      leave buchhwin-shell alone
#   ./install.sh --checklist         print the private checklist and exit
#
# Run it as yourself, not as root. Re-running is safe: pacman/paru/flatpak
# skip what is there, stow re-links, a step that is done says so.
# The system part (/etc, units, groups, ufw, snapper) is system/apply.sh,
# run with sudo by you - see README.md "Restore".
set -euo pipefail
export LC_COLLATE=C   # comm and sort agree on the order

repo_dir=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
shell_dir=${BUCHHWIN_SHELL_DIR:-$(dirname -- "$repo_dir")/buchhwin-shell}
shell_url=https://github.com/buchhwin/buchhwin-shell.git
apply=false packages=true shell=true
for arg in "$@"; do
  case $arg in
    --apply) apply=true ;;
    --no-packages) packages=false ;;
    --no-shell) shell=false ;;
    --checklist) sed -n '/<!-- checklist -->/,/<!-- \/checklist -->/p' "$repo_dir/README.md" | sed '1d;$d'; exit 0 ;;
    -h|--help) sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$arg" >&2; exit 2 ;;
  esac
done
(( EUID == 0 )) && { printf 'Run this as yourself; it calls sudo where it must.\n' >&2; exit 2; }
command -v pacman >/dev/null || { printf 'Arch Linux only (no pacman).\n' >&2; exit 2; }

# Stowed with --no-folding: a folder an app writes into (~/.config/alacritty)
# stays a real folder, so nothing the app adds lands in this repo. The one
# exception is wallpapers: there the FOLDER is linked on purpose.
stow_packages=(zsh starship alacritty fastfetch kde makepkg)
backup_dir=$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)

step() { printf '\n== %s\n' "$*"; }
run() {
  if $apply; then printf '+ %s\n' "$*"; "$@"; else printf '  %s\n' "$*"; fi
}
names() { grep -v '^\s*\(#\|$\)' -- "$1" 2>/dev/null || true; }

step "Tools this script needs"
run sudo pacman -S --needed git stow zsh

step "Nested btrfs subvolumes (kept out of /home snapshots)"
# A folder becomes a subvolume only while it is new or empty; a full one is
# left alone and named. Unprivileged: btrfs lets a user create a subvolume.
for dir in "$HOME/.cache" "$HOME/.local/share/Steam/steamapps"; do
  if [[ $(stat -f -c %T -- "$(dirname -- "$dir")" 2>/dev/null) != btrfs ]]; then continue; fi
  if [[ -d $dir && $(stat -c %i -- "$dir") == 256 ]]; then printf '  %s: a subvolume already\n' "$dir"; continue; fi
  if [[ -d $dir ]] && [[ -n $(ls -A -- "$dir") ]]; then
    printf '  %s has files: make it a subvolume by hand (mv, btrfs subvolume create, cp -a --reflink)\n' "$dir"; continue
  fi
  [[ -d $dir ]] && run rmdir -- "$dir"
  run mkdir -p -- "$(dirname -- "$dir")"
  run btrfs subvolume create -- "$dir"
done

if $packages; then
  step "Packages: official repositories (pkglists/native.txt)"
  mapfile -t wanted < <(names "$repo_dir/pkglists/native.txt")
  mapfile -t known < <(pacman -Slq core extra multilib 2>/dev/null | sort -u)
  mapfile -t missing < <(comm -23 <(printf '%s\n' "${wanted[@]}" | sort -u) <(printf '%s\n' "${known[@]}"))
  ((${#missing[@]})) && printf '  not in the repositories any more (left out): %s\n' "${missing[*]}"
  mapfile -t install < <(comm -12 <(printf '%s\n' "${wanted[@]}" | sort -u) <(printf '%s\n' "${known[@]}"))
  ((${#install[@]})) && run sudo pacman -S --needed -- "${install[@]}"

  step "Packages: vendor repositories (pkglists/other-repos.txt) - by hand"
  while IFS=/ read -r repo name; do
    printf '  %s from [%s]: add that repository with its vendor installer, then: sudo pacman -S %s\n' "$name" "$repo" "$name"
  done < <(names "$repo_dir/pkglists/other-repos.txt")

  step "Packages: AUR (pkglists/aur.txt)"
  kept=$HOME/.local/share/aur-packages
  run mkdir -p -- "$kept"
  if ! command -v paru >/dev/null; then
    tmp=$(mktemp -d)
    run git clone https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
    if $apply; then (cd "$tmp/paru-bin" && makepkg -si --noconfirm); else printf '  (cd %s/paru-bin && makepkg -si)\n' "$tmp"; fi
  fi
  mapfile -t aur < <(names "$repo_dir/pkglists/aur.txt" | grep -vx 'paru\|paru-bin')
  # Packages kept from an earlier build (PKGDEST, makepkg package) go in
  # first: a big AUR package is hours of compiling otherwise.
  shopt -s nullglob
  prebuilt=()
  for name in "${aur[@]}"; do
    for file in "$kept/$name"-[0-9]*.pkg.tar.zst; do prebuilt+=("$file"); done
  done
  shopt -u nullglob
  ((${#prebuilt[@]})) && run sudo pacman -U --needed -- "${prebuilt[@]}"
  ((${#aur[@]})) && run paru -S --needed -- "${aur[@]}"

  step "Flatpaks (pkglists/flatpak.txt)"
  run flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  mapfile -t apps < <(names "$repo_dir/pkglists/flatpak.txt" | cut -f1)
  ((${#apps[@]})) && run flatpak install --system --noninteractive flathub "${apps[@]}"

  step "VS Code extensions (pkglists/vscode-extensions.txt)"
  mapfile -t extensions < <(names "$repo_dir/pkglists/vscode-extensions.txt")
  if command -v code >/dev/null; then
    ext_args=(); for ext in "${extensions[@]}"; do ext_args+=(--install-extension "$ext"); done
    ((${#ext_args[@]})) && run code "${ext_args[@]}"
  else
    printf '  code is not installed yet - re-run after the AUR step\n'
  fi
fi

step "Dotfiles (GNU stow into $HOME)"
run mkdir -p -- "$HOME/.config" "$HOME/Pictures/Desktop"
for package in "${stow_packages[@]}"; do
  [[ -d $repo_dir/$package ]] || { printf '  %s: not in the repo, skipped\n' "$package"; continue; }
  # A real file where a link goes is moved aside, never overwritten.
  while IFS= read -r -d '' file; do
    target=$HOME/${file#"$repo_dir/$package/"}
    # Already this repo's file (a link, or reached through a folded folder
    # link from an earlier stow): moving it would move the repo's own file.
    [[ $(readlink -f -- "$target" 2>/dev/null) == "$repo_dir"/* ]] && continue
    if [[ -e $target && ! -L $target ]]; then
      run mkdir -p -- "$(dirname -- "$backup_dir/${target#"$HOME/"}")"
      run mv -- "$target" "$backup_dir/${target#"$HOME/"}"
    fi
  done < <(find "$repo_dir/$package" -type f -print0)
  run stow --no-folding -d "$repo_dir" -t "$HOME" -R "$package"
done

wall=$HOME/Pictures/Desktop/Wallhaven
if [[ -d $repo_dir/wallpapers ]]; then
  if [[ -d $wall && ! -L $wall ]]; then
    printf '  %s is a real folder: move its pictures into the repo first (README.md "Wallpapers"); skipped\n' "$wall"
  else
    # ~/Pictures/Desktop exists (above), so stow links the Wallhaven folder
    # itself and never a parent: Bog/ and Screenshots stay out of the repo.
    run stow -d "$repo_dir" -t "$HOME" -R wallpapers
    if $apply && { [[ -L $HOME/Pictures || -L $HOME/Pictures/Desktop || ! -L $wall ]]; }; then
      printf 'Wallpapers linked at the wrong level - undo: stow -D -d %s -t %s wallpapers\n' "$repo_dir" "$HOME" >&2
      exit 1
    fi
  fi
fi

step "zsh and Oh My Zsh"
zsh_path=$(command -v zsh || echo /usr/bin/zsh)
[[ $(getent passwd "$USER" | cut -d: -f7) == "$zsh_path" ]] || run chsh -s "$zsh_path"
if [[ ! -d $HOME/.oh-my-zsh ]]; then
  if $apply; then
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  else
    printf '  Oh My Zsh installer (RUNZSH=no CHSH=no KEEP_ZSHRC=yes)\n'
  fi
fi
custom=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}
for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
  [[ -d $custom/plugins/$plugin ]] || run git clone "https://github.com/zsh-users/$plugin" "$custom/plugins/$plugin"
done

if $shell; then
  step "buchhwin-shell (its own installer, dry run unless --apply)"
  [[ -d $shell_dir/.git ]] || run git clone "$shell_url" "$shell_dir"
  shell_args=(); $apply && shell_args=(--apply)
  if [[ -x $shell_dir/install/bootstrap.sh ]]; then
    # Called in both modes: without --apply it is its own dry run and lists
    # every step it would take.
    "$shell_dir/install/bootstrap.sh" "${shell_args[@]}"
    [[ -L $HOME/.local/share/buchhwin-shell ]] && [[ $(readlink -f "$HOME/.local/share/buchhwin-shell") == */buchhwin-shell-stable ]] \
      || run "$shell_dir/scripts/deploy.sh" --init
  else
    printf '  %s/install/bootstrap.sh after the clone\n' "$shell_dir"
  fi
fi

step "Plasma and desktop settings"
if command -v kwriteconfig6 >/dev/null; then
  run kwriteconfig6 --file kdeglobals --group General --key TerminalApplication alacritty
  run kwriteconfig6 --file kdeglobals --group General --key TerminalService Alacritty.desktop
fi
command -v xdg-settings >/dev/null && run xdg-settings set default-web-browser brave-browser.desktop
command -v xdg-mime >/dev/null && run xdg-mime default org.kde.gwenview.desktop image/jpeg image/png image/webp
command -v syncthing >/dev/null && run systemctl --user enable --now syncthing.service
run git -C "$repo_dir" config core.hooksPath .githooks

step "Private things (by hand, from the private backup - ./install.sh --checklist)"
"${BASH_SOURCE[0]}" --checklist
$apply || printf '\nDry run: nothing changed. Run %s --apply to do it.\n' "${BASH_SOURCE[0]}"
