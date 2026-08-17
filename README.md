# Sway configuration — Fedora Sway Atomic

A sway setup for **Fedora Sway Atomic**, built as drop-ins on top of Fedora's
own config rather than as a replacement for it.

Targeted at a **ThinkPad T480**: single 1920×1080 internal panel, dual battery,
TrackPoint, UK keyboard.

**Requires zero `rpm-ostree` layering.** Everything it uses already ships in the
Sway Atomic image.

## Install

```bash
./install.sh --check    # show what would change
./install.sh            # symlink into ~/.config and reload sway
./install.sh --copy     # copy instead of symlinking
```

Existing files are moved to `~/.config-backup-<timestamp>/`, and the installer
runs `sway --validate` before reloading.

## How it fits together

Fedora's `sway-config-fedora` package puts a layered include at the end of
`/etc/sway/config`:

```
include '$(/usr/libexec/sway/layered-include \
    "/usr/share/sway/config.d/*.conf" \
    "/etc/sway/config.d/*.conf" \
    "$HOME/.config/sway/config.d/*.conf")'
```

Files are merged **by basename**, with later directories winning. So
`~/.config/sway/config.d/90-bar.conf` would replace Fedora's `90-bar.conf`,
while a uniquely-named file is simply added.

**There is deliberately no `~/.config/sway/config` in this repo.** Creating one
would replace `/etc/sway/config` wholesale, which silently disables
`sway-systemd` — and with it xdg-desktop-portal screensharing, XDG autostart,
and `sway-session.target`. Everything here is a drop-in.

### What Fedora already provides

Don't reimplement these — they're in `/usr/share/sway/config.d/`:

| File | Provides |
|---|---|
| `90-bar.conf` | Starts **waybar** as sway's bar |
| `90-swayidle.conf` | swayidle: idle lock, screen blank, lock-on-suspend |
| `95-autostart-policykit-agent.conf` | `lxqt-policykit-agent` |
| `60-bindings-volume.conf` | Volume keys, with an OSD |
| `60-bindings-brightness.conf` | Brightness keys, with an OSD |
| `60-bindings-media.conf` | Media keys via `playerctl` |
| `60-bindings-screenshot.conf` | `Print` / `Alt+Print` / `Ctrl+Print` → save |
| `50-rules-*.conf` | Browser idle-inhibit, pavucontrol, polkit floating |

`/etc/sway/config` itself defines `$mod`, `$term` (foot), `$menu` (rofi), and
all the standard bindings: `hjkl` + arrows, workspaces 1–0, splits, layouts,
fullscreen, scratchpad, resize mode.

Several of those are parameterised with sway variables that are unset by
default. `05-variables.conf` sets them, which is why this config has no
swayidle block of its own.

## Layout

```
.config/
├── sway/
│   ├── config.d/
│   │   ├── 05-variables.conf     # tunables for Fedora's drop-ins
│   │   ├── 20-appearance.conf    # borders, gaps, colours
│   │   ├── 25-input.conf         # keyboard (gb), touchpad, TrackPoint
│   │   ├── 35-bindings.conf      # additions only
│   │   ├── 45-autostart.conf     # nm-applet, battery notifier
│   │   ├── 55-rules.conf         # floating + idle-inhibit rules
│   │   └── 70-lid.conf           # lid switch
│   └── scripts/
│       └── battery-notify.sh     # dual-battery low warning
├── waybar/{config.jsonc,style.css}
├── foot/foot.ini
├── rofi/{config.rasi,neutral.rasi}
├── dunst/dunstrc
└── swaylock/config
```

Ordering note: `05-` must sort before the `60-`/`90-` files that consume its
variables, and none of these basenames may collide with Fedora's.

## Key bindings

Only the additions are listed. See `/etc/sway/config` for the rest.

| Binding | Action |
|---|---|
| `Super+Shift+X` | Lock (via `loginctl lock-session`) |
| `Super+Shift+P` | Session menu — lock / suspend / log out / reboot / shut down |
| `Super+Shift+Return` | Thunar |
| `Super+N` | Toggle waybar |
| `Super+Tab` | Last workspace |
| `Super+Ctrl+←/→` | Previous / next workspace |
| `Super+Print` | Copy screenshot of output |
| `Super+Shift+Print` | Copy screenshot of selection |
| `Super+Ctrl+Print` | Copy screenshot of active window |

## Notes

### Keyboard layout

Sway reads **neither** `/etc/vconsole.conf` nor
`/etc/X11/xorg.conf.d/00-keyboard.conf`. It falls back to XKB's built-in `us`
default, so a machine correctly set to `gb` via `localectl` still comes up US
inside sway. The layout is set explicitly in `25-input.conf`; change it there
as well as with `localectl`.

### Dual battery

The T480 has two packs (`BAT0` internal, `BAT1` hot-swap) that discharge in
sequence. Reading one in isolation misreports badly — `BAT1` can show 4% with
hours of runtime left. `battery-notify.sh` sums both, capacity-weighted.
Waybar's battery module is left on auto-detect for the same reason; verify it
against the script's figure if the numbers ever look wrong.

### Icons

Waybar's glyphs are **Font Awesome 6 Free**, which is in the base image. There
is no Nerd Font installed; Nerd-Font-only codepoints render as tofu.

### GTK theming

Not configured here — the image already ships `color-scheme=prefer-dark` and
`gtk-theme=Adwaita-dark` in gsettings, which GTK 3 and 4 both honour.

## Verifying changes

```bash
sway --validate                  # config errors
swaymsg -t get_outputs           # display names
swaymsg -t get_inputs            # input identifiers
foot --check-config              # terminal config
waybar -l debug                  # bar errors, including CSS
```
