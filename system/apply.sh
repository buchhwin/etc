#!/usr/bin/env bash
# The public part of this machine's /etc, and the system settings that are
# commands rather than files. Run by you, with sudo. Dry run by default: a
# diff per file and every command, nothing changes.
#
#   sudo system/apply.sh            dry run
#   sudo system/apply.sh --apply    back up, install, enable
#
# Files: system/files/<path> -> /<path>, with the mode in system/manifest.
# Each replaced file is copied to /var/backups/etc-apply/<time>/<path> first;
# the run ends with the command that puts them back.
# Never here, by design: /etc/fstab and the network shares (credentials,
# dispatcher, mount drop-ins), PAM and U2F mappings, NetworkManager
# connections, WireGuard, sudoers, crypttab, the host name - they are private
# or this hardware's, and live in the private checklist (README.md).
set -euo pipefail
here=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
apply=false
case ${1:-} in
  --apply) apply=true ;;
  "") ;;
  *) printf 'Usage: sudo %s [--apply]\n' "$0" >&2; exit 2 ;;
esac
if $apply && (( EUID != 0 )); then printf 'Run --apply with sudo.\n' >&2; exit 2; fi
user=${SUDO_USER:-$(id -un)}
backup=/var/backups/etc-apply/$(date +%Y%m%d-%H%M%S)
after=()
changed=0

run() { if $apply; then printf '+ %s\n' "$*"; "$@"; else printf '  %s\n' "$*"; fi; }
refused() {
  case $1 in
    etc/fstab*|etc/crypttab*|etc/pam.d/*|etc/security/*|etc/NetworkManager/*|etc/wireguard/*|etc/samba/*|\
    etc/sudoers*|etc/hostname|etc/hosts|etc/systemd/system/mnt-*|*u2f*|*Yubico*) return 0 ;;
  esac
  return 1
}

printf '== Files\n'
while read -r mode path hint; do
  [[ -z $mode || $mode == \#* ]] && continue
  refused "$path" && { printf 'REFUSED (private or hardware-bound): %s\n' "$path" >&2; exit 1; }
  source=$here/files/$path target=/$path
  content=$(cat -- "$source")
  if [[ -e $target ]] && [[ $(cat -- "$target") == "$content" ]] && [[ $(stat -c %a -- "$target") == "${mode#0}" ]]; then
    printf '  same: /%s\n' "$path"; continue
  fi
  changed=$((changed + 1))
  diff -u --label "/$path (now)" --label "/$path (repo)" -- "$target" <(printf '%s\n' "$content") 2>/dev/null || true
  if $apply; then
    if [[ -e $target ]]; then mkdir -p -- "$(dirname -- "$backup/$path")"; cp -a -- "$target" "$backup/$path"; fi
    printf '%s\n' "$content" | install -D -m "$mode" -o root -g root /dev/stdin "$target"
    printf '+ installed /%s (%s)\n' "$path" "$mode"
  fi
  [[ -n ${hint:-} ]] && after+=("$hint")
done <"$here/manifest"

printf '\n== pacman.conf (two edits; vendor repositories it includes stay)\n'
conf=/etc/pacman.conf
edits=()
grep -qx 'Color' "$conf" || edits+=(-e 's/^#Color$/Color/')
grep -qx '\[multilib\]' "$conf" || edits+=(-e '/^#\[multilib\]$/,/^#Include/ s/^#//')
if ((${#edits[@]})); then
  if $apply; then mkdir -p -- "$backup/etc"; cp -a -- "$conf" "$backup/etc/pacman.conf"; fi
  run sed -i "${edits[@]}" "$conf"
  after+=("sudo pacman -Sy (multilib's database)")
else
  printf '  same: Color and [multilib] are on\n'
fi

printf '\n== Kernel command line (archinstall writes it; one flag is ours)\n'
grep -qw 'zswap.enabled=0' /etc/kernel/cmdline 2>/dev/null && printf '  zswap.enabled=0 is set\n' ||
  printf '  add zswap.enabled=0 to /etc/kernel/cmdline (zram is the swap), then: sudo mkinitcpio -P\n'

printf '\n== Units (enabled for the next boot; nothing is started or stopped)\n'
for unit in bluetooth.service cups.socket NetworkManager.service power-profiles-daemon.service sddm.service \
            systemd-timesyncd.service ufw.service libvirtd.socket snapper-timeline.timer snapper-cleanup.timer; do
  systemctl cat -- "$unit" >/dev/null 2>&1 || { printf '  %s: not installed\n' "$unit"; continue; }
  [[ $(systemctl is-enabled -- "$unit" 2>/dev/null) == enabled ]] && { printf '  enabled: %s\n' "$unit"; continue; }
  run systemctl enable -- "$unit"
done

printf '\n== Groups\n'
if [[ -n $user ]] && getent group libvirt >/dev/null; then
  id -nG -- "$user" | tr ' ' '\n' | grep -qx libvirt && printf '  %s is in libvirt\n' "$user" || run usermod -aG libvirt -- "$user"
fi

printf '\n== Firewall (ufw)\n'
if command -v ufw >/dev/null; then
  run ufw allow in on virbr0
  run ufw route allow in on virbr0
  run ufw route allow out on virbr0
  # Open only when wanted (README): Syncthing's LAN sync, KDE Connect.
  # run ufw allow syncthing
  # run ufw allow kdeconnect
  run ufw --force enable
fi

printf '\n== Snapper limits\n'
set_config() { # config, then KEY=VALUE...
  local config=$1; shift
  [[ -f /etc/snapper/configs/$config ]] || {
    printf '  no snapper config "%s": archinstall makes it; else see README (create-config with an existing .snapshots)\n' "$config"
    return
  }
  run snapper -c "$config" set-config "$@"
}
set_config root NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=4 TIMELINE_LIMIT_HOURLY=5 TIMELINE_LIMIT_DAILY=7 \
  TIMELINE_LIMIT_WEEKLY=0 TIMELINE_LIMIT_MONTHLY=1 TIMELINE_LIMIT_QUARTERLY=0 TIMELINE_LIMIT_YEARLY=0
set_config home NUMBER_LIMIT=50 NUMBER_LIMIT_IMPORTANT=10 TIMELINE_LIMIT_HOURLY=5 TIMELINE_LIMIT_DAILY=7 \
  TIMELINE_LIMIT_WEEKLY=0 TIMELINE_LIMIT_MONTHLY=0 TIMELINE_LIMIT_QUARTERLY=0 TIMELINE_LIMIT_YEARLY=0

printf '\n== Nested subvolume for VM images (no copy-on-write)\n'
images=/var/lib/libvirt/images
if [[ -d $images && $(stat -c %i -- "$images") == 256 ]]; then
  printf '  %s: a subvolume already\n' "$images"
elif [[ -d $images && -n $(ls -A -- "$images") ]]; then
  printf '  %s holds images: convert by hand with libvirt stopped\n' "$images"
else
  [[ -d $images ]] && run rmdir -- "$images"
  run mkdir -p -- "$(dirname -- "$images")"
  run btrfs subvolume create -- "$images"
  run chattr +C -- "$images"
fi

printf '\n== Afterwards\n'
((${#after[@]})) && printf '  %s\n' "${after[@]}" | sort -u
if $apply && [[ -d $backup ]]; then
  printf '  Undo the files: sudo cp -a %s/. / \n' "$backup"
fi
$apply || printf '\nDry run: %d file(s) differ. Nothing changed. sudo %s --apply to do it.\n' "$changed" "$0"
