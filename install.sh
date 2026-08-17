#!/usr/bin/env bash
# Install this sway configuration on Fedora Sway Atomic.
#
# It symlinks a fixed list of paths into ~/.config. It deliberately does NOT
# glob .config/* -- see the note on config.d below.
#
#   ./install.sh          install (symlink)
#   ./install.sh --copy   install as copies instead of symlinks
#   ./install.sh --check  report what would change, touch nothing

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}"

MODE=link
for arg in "$@"; do
    case "$arg" in
        --copy)  MODE=copy ;;
        --check) MODE=check ;;
        -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
warn()  { printf '\033[33m%s\033[0m\n' "$*"; }

# The exact paths this config owns. Anything not listed here is left alone.
#
# Note that we install sway/config.d/ and never sway/config: Fedora's
# /etc/sway/config is the base, and its final line layer-includes
# ~/.config/sway/config.d/*.conf. Dropping a file at ~/.config/sway/config
# would REPLACE that base entirely and silently disable sway-systemd -- which
# breaks xdg-desktop-portal screensharing, XDG autostart, and
# sway-session.target. Do not add it to this list.
PATHS=(
    sway/config.d
    sway/scripts
    waybar/config.jsonc
    waybar/style.css
    foot/foot.ini
    dunst/dunstrc
    rofi/config.rasi
    rofi/neutral.rasi
    swaylock/config
    cliphist/config
)

### Sanity checks ############################################################

if ! grep -q '^ID=fedora' /etc/os-release; then
    red "This config targets Fedora. /etc/os-release says otherwise."
    exit 1
fi

if [[ ! -f /etc/sway/config ]]; then
    red "/etc/sway/config not found -- is the sway-config-fedora package installed?"
    exit 1
fi

if ! grep -q 'layered-include' /etc/sway/config; then
    warn "/etc/sway/config has no layered-include line."
    warn "This config's drop-ins will never be read. Restore the packaged file with:"
    warn "  sudo cp /usr/share/factory/etc/sway/config /etc/sway/config"
    exit 1
fi

# Everything this config needs is already in the Sway Atomic image, so a
# successful install should require zero rpm-ostree layering.
missing=()
for cmd in sway swaymsg swaybg swayidle swaylock swaynag waybar rofi foot \
           grim slurp grimshot wl-copy brightnessctl nm-applet pactl \
           playerctl notify-send thunar pavucontrol; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done

if (( ${#missing[@]} )); then
    warn "Not found on PATH: ${missing[*]}"
    warn "Layer them with:  rpm-ostree install <pkg>   (then reboot)"
    echo
fi

# Screen recording is the one feature the stock image cannot satisfy, so it is
# checked separately: everything else above is a hard requirement, this is not.
if ! command -v wf-recorder >/dev/null 2>&1; then
    warn "Optional: wf-recorder not installed -- screen recording will not work."
    warn "  rpm-ostree override remove noopenh264 --install openh264 --install wf-recorder"
    warn "  (then reboot). openh264 must be an override, not a plain install:"
    warn "  the base image ships noopenh264, a stub that cannot encode."
    echo
elif ! ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc=size=64x64:rate=5 \
        -t 0.2 -c:v libopenh264 -f null - >/dev/null 2>&1; then
    warn "wf-recorder is installed but libopenh264 cannot encode."
    warn "The noopenh264 stub is probably still in place. Swap it with:"
    warn "  rpm-ostree override remove noopenh264 --install openh264"
    echo
fi

# Clipboard history, likewise optional rather than required.
if ! command -v cliphist >/dev/null 2>&1; then
    warn "Optional: cliphist not installed -- clipboard history will not work."
    warn "  rpm-ostree install cliphist   (then reboot)"
    echo
fi

### Install ##################################################################

BACKUP="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
backed_up=0

for rel in "${PATHS[@]}"; do
    src="$SRC/.config/$rel"
    dst="$DEST/$rel"

    if [[ ! -e "$src" ]]; then
        red "missing in repo: .config/$rel"
        exit 1
    fi

    if [[ "$MODE" == check ]]; then
        if [[ -L "$dst" && "$(readlink -f "$dst")" == "$(readlink -f "$src")" ]]; then
            green "ok       $rel"
        elif [[ -e "$dst" ]]; then
            warn  "replace  $rel"
        else
            green "create   $rel"
        fi
        continue
    fi

    # Move anything real out of the way before linking over it.
    if [[ -e "$dst" || -L "$dst" ]]; then
        if [[ -L "$dst" && "$(readlink -f "$dst")" == "$(readlink -f "$src")" ]]; then
            continue
        fi
        mkdir -p "$BACKUP/$(dirname "$rel")"
        mv "$dst" "$BACKUP/$rel"
        backed_up=1
    fi

    mkdir -p "$(dirname "$dst")"
    if [[ "$MODE" == copy ]]; then
        cp -r "$src" "$dst"
    else
        ln -s "$src" "$dst"
    fi
    green "installed $rel"
done

[[ "$MODE" == check ]] && exit 0

(( backed_up )) && warn "Previous files moved to $BACKUP"

chmod +x "$SRC"/.config/sway/scripts/*.sh

### Verify ###################################################################

echo
if sway --validate >/dev/null 2>&1; then
    green "sway --validate: clean"
else
    red "sway --validate reported errors:"
    sway --validate 2>&1 | sed 's/^/  /'
    exit 1
fi

if [[ -n "${SWAYSOCK:-}" ]] && swaymsg -t get_version >/dev/null 2>&1; then
    swaymsg reload >/dev/null && green "sway reloaded"
else
    echo "Not in a sway session -- log in to sway to pick up the changes."
fi
