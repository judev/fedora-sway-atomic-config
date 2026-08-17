# Sway configuration — Fedora Sway Atomic

A sway setup for **Fedora Sway Atomic**, built as drop-ins on top of Fedora's
own config rather than as a replacement for it.

Targeted at a **ThinkPad T480**: single 1920×1080 internal panel, dual battery,
TrackPoint, UK keyboard.

**Requires zero `rpm-ostree` layering** for everything except screen recording —
window management, bar, launcher, terminal, notifications, lock screen and
screenshots all use what already ships in the Sway Atomic image.

Two features need layered packages: [screen recording](#screen-recording)
(two packages, because the base image has no usable H.264 encoder) and
[clipboard history](#clipboard-history) (one).

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
| `50-rules-*.conf` | Browser idle-inhibit, pavucontrol, polkit floating |

One exception: this config **replaces** Fedora's `60-bindings-screenshot.conf`
with its own file of the same name, so all screenshot behaviour lives in one
place. See [Screenshots](#screenshots).

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
│   │   ├── 45-autostart.conf     # battery notifier
│   │   ├── 55-rules.conf         # floating + idle-inhibit rules
│   │   ├── 60-bindings-screenshot.conf   # REPLACES Fedora's
│   │   ├── 62-bindings-record.conf       # screen recording mode
│   │   ├── 64-clipboard.conf     # clipboard history + Super+V
│   │   └── 70-lid.conf           # lid switch
│   └── scripts/
│       ├── battery-notify.sh     # dual-battery low warning
│       ├── clipboard.sh          # cliphist + rofi picker
│       └── record.sh             # wf-recorder wrapper + waybar status
├── waybar/{config.jsonc,style.css}
├── foot/foot.ini
├── rofi/{config.rasi,neutral.rasi}
├── dunst/dunstrc
├── cliphist/config
└── swaylock/config
```

Ordering note: `05-` must sort before the `60-`/`90-` files that consume its
variables, and none of these basenames may collide with Fedora's.

## Key bindings

Only the additions are listed. See `/etc/sway/config` for the rest.

| Binding | Action |
|---|---|
| `Super+Shift+X` | Lock (`swaylock -f`, falling back to `loginctl lock-session`) |
| `Super+Shift+P` | Session menu — lock / suspend / log out / reboot / shut down |
| `Super+Shift+Return` | Thunar |
| `Super+N` | Toggle waybar |
| `Super+Tab` | Last workspace |
| `Super+Ctrl+←/→` | Previous / next workspace |
| `Print` | Screenshot: region → clipboard |
| `Super+Print` | [Screenshot mode](#screenshots) |
| `Super+Shift+R` | [Recording mode](#screen-recording) |
| `Super+Shift+S` | Stop recording |
| `Super+V` | [Clipboard history picker](#clipboard-history) |
| `Super+Shift+V` | `splitv` — moved off `Super+V` |

## Screenshots

All of this is [`grimshot`](https://github.com/swaywm/sway/blob/master/contrib/grimshot),
which ships with `sway-config-fedora` and wraps `grim` + `slurp` + `wl-copy`.
Nothing extra to install. Defined in `60-bindings-screenshot.conf`.

### The common case

```
Print        drag out a region  →  clipboard
```

### Everything else: `Super+Print`

That enters a **screenshot mode**. Waybar's `sway/mode` module displays
`screenshot` in the bar while it is active, so you can see you're in it. Then
one key picks the target:

| Key | Captures |
|---|---|
| `a` | **area** — drag out a region |
| `w` | **window** — click one to pick it |
| `o` | **output** — the current display, whole |
| `s` | **screen** — every visible output (same as `o` on one display) |
| `f` | **focused** — the active window, no clicking |

Modifiers compose with any of those:

| Modifier | Effect |
|---|---|
| *(none)* | clipboard only |
| `Shift` | **include the mouse pointer** (`grimshot --cursor`) |
| `Ctrl` | also write a file (`grimshot savecopy` — file *and* clipboard) |
| `Ctrl+Shift` | pointer **and** a file |

`Escape`, `Return` or `Super+Print` again leaves the mode without capturing.

So `Super+Print` then `Shift+a` is "drag a region, include the pointer, put it
on the clipboard"; `Ctrl+Shift+f` is "the focused window with its pointer, saved
to disk and copied".

### Where files go

Only the `Ctrl` variants write to disk. The target is grimshot's default —
`$XDG_SCREENSHOTS_DIR`, else `$XDG_PICTURES_DIR`, else `$HOME`, read from
`~/.config/user-dirs.dirs`. Here that resolves to `~/Pictures`.

To keep them in a subfolder, add this to `~/.config/user-dirs.dirs` and create
the directory:

```
XDG_SCREENSHOTS_DIR="$HOME/Pictures/Screenshots"
```

Filenames are grimshot's own ISO-8601 form, e.g.
`2026-08-17T14:28:54,535384572+01:00.png`. The colons and nanoseconds are
awkward but are grimshot's default, not something this config sets; changing
them means wrapping the `savecopy` bindings in a shell command that builds its
own filename.

### Note on `Print`

Fedora's default binds bare `Print` to *save the whole output to a file*. This
config rebinds it to *region → clipboard*, on the grounds that it is the far
more common action. `Super+Print` then `Ctrl+o` is the old behaviour.

Check grimshot's dependencies at any time with:

```bash
grimshot check
```

## Screen recording

Needs two layered packages — the base image has no usable H.264 encoder:

```bash
rpm-ostree override remove noopenh264 --install openh264 --install wf-recorder
# then reboot
```

`openh264` must go in as an **override**, not a plain `install`. The base image
ships `noopenh264` — a stub that satisfies the same soname but refuses to encode
(*"Unable to create encoder"*). `openh264` `Obsoletes:` it, and swapping a
base-image package is what `override remove` is for. It comes from the
`fedora-cisco-openh264` repo, enabled by default.

### Bindings

| Binding | Action |
|---|---|
| `Super+Shift+R` | Enter **recording mode** |
| `Super+Shift+S` | **Stop** recording (works anywhere, including while locked) |

Inside the mode, the target:

| Key | Records |
|---|---|
| `r` | **region** — drag one out with slurp |
| `o` | **output** — the focused display |
| `s` | **screen** — everything |

…and the modifier picks the audio:

| Modifier | Audio |
|---|---|
| *(none)* | system audio — the default sink's monitor |
| `Shift` | silent |
| `Ctrl` | **narrate** — system audio and microphone, mixed |

`Escape` leaves without recording. Output goes to `$XDG_VIDEOS_DIR`
(`~/Videos`) as `2026-08-17-143205.mp4`.

While recording, waybar shows a red **REC** indicator; click it to stop.

### Why the codecs are pinned

`wf-recorder` defaults to `libx264`, which **does not exist on this system**.
Verified on a T480 running stock Sway Atomic:

| Encoder | Status |
|---|---|
| `libx264` / `libx265` | absent — the image ships `ffmpeg-free` |
| `libopenh264` | advertised, but the `noopenh264` stub cannot encode |
| `h264_vaapi` | Fedora strips H.264 encode from `libva-intel-media-driver` |
| `vp9_vaapi` | UHD 620 has VP9 *decode* only, no encode silicon |
| `libvpx-vp9` (software) | works — 5s of 1080p30 in 1.7s, ~3× realtime |

So there is **no hardware encode path at all** here, and the default would just
fail. `record.sh` pins `-c libopenh264 -C aac -x yuv420p` explicitly. If you
skip the `openh264` override, switch `VIDEO_CODEC` in `record.sh` to
`libvpx-vp9` and the extension to `.webm` — software VP9 has ample headroom on
this CPU.

Check what your machine actually has with `ffmpeg -encoders`.

### Two things it does not do

**Recordings always show the pointer, and it cannot be turned off.**
`wf-recorder` 0.6 has no cursor option — nothing in its option list, and it
calls `zwlr_screencopy_manager_v1` with a hardcoded `overlay_cursor`. Confirmed
by recording with the pointer parked over static content and inspecting an
extracted frame: the cursor is drawn. Screenshots *can* toggle this
(`Shift` in the screenshot mode); recordings cannot.

**Mic + system audio needs a mixer.** `wf-recorder -a` takes a *single*
PulseAudio device, so `narrate` mode builds a null sink fed by two loopbacks and
records its monitor. `record.sh` tracks the module IDs and unloads them on stop;
if a recording is killed uncleanly you may be left with a stray
`RecordingMix` output device, removable with:

```bash
pactl unload-module module-null-sink
```

Audio devices are resolved at runtime via `pactl get-default-sink` rather than
hardcoded, so they survive hardware and dock changes.

## Clipboard history

Needs one layered package; `wl-clipboard` and `rofi` are already in the image:

```bash
rpm-ostree install cliphist
# then reboot
```

| Binding | Action |
|---|---|
| `Super+V` | Open the history picker |
| `Super+Shift+V` | `splitv` — **moved here** from `Super+V` |

Inside the picker:

| Key | Action |
|---|---|
| type anything | fuzzy search (case-insensitive) |
| `Enter` | copy that entry to the clipboard |
| `Alt+Delete` | forget that one entry |
| `Alt+Shift+Delete` | wipe the whole history |
| `Escape` | cancel |

Delete and wipe live *inside* the picker rather than on global bindings, so you
are always looking at what you're about to discard.

`Alt+Delete` / `Alt+Shift+Delete` were picked because both are provably free
among rofi's 102 default bindings. `Shift+Delete` would read better, but it is
already rofi's own `kb-delete-entry` and duplicate bindings are a hard error —
and note that `kb-delete-entry` only drops the row from rofi's list, it does not
touch cliphist's database.

### Secrets

`wl-paste --watch` sets `CLIPBOARD_STATE`, and `clipboard.sh` refuses to store
anything marked `sensitive`. **This only protects you from applications that set
the `x-kde-passwordManagerHint` MIME type** — wl-clipboard has no other way to
know. Check whether a given app does:

```bash
wl-paste --watch sh -c 'echo "$CLIPBOARD_STATE"'
# then copy a password in the other app and watch the output
```

If it prints `data` rather than `sensitive`, that app's secrets *are* being
stored, and `Alt+Shift+Delete` after the fact is your remedy.

The database is **plaintext** at `~/.cache/cliphist/db`, created mode `0644`.
It is protected only by `~` being `0700` — nothing about the file itself. Bear
that in mind before loosening home-directory permissions or backing up
`~/.cache`.

`~/.config/cliphist/config` bounds the exposure a little: `max-items 500` and
`min-store-length 3` (which also stops one- and two-character accidents from
crowding out real entries).

### Three implementation notes

**The watchers use `exec`, not `exec_always`.** They are long-lived daemons that
must start exactly once per session; `exec_always` would spawn another pair on
every config reload and each duplicate would re-store every copy. The trade-off
is that they start on next login rather than on `swaymsg reload` — the config
file has the one-liner to start them by hand.

**`Super+V` uses `bindsym --no-warn`.** It is the only binding in this config
that overrides one of Fedora's, and overriding one makes sway raise a swaynag
banner over the session at every login. `--no-warn` exists for exactly this
case. Worth knowing: `sway --validate` does **not** catch it — it exits 0 and
prints nothing, because the warning is raised at runtime rather than during
parsing. To find overrides, diff your bindings against `/etc/sway/config` and
`/usr/share/sway/config.d/*.conf` by hand.

**The picker selects by index, not by text.** `cliphist list` rows are
`"<id>\t<preview>"` and `cliphist decode` needs the id — given only the preview
it fails outright with `strconv.Atoi ... invalid syntax`. So the picker uses
`rofi -format i` to get the chosen row's index and looks the row up in the list
it just generated. That decouples display from lookup entirely, so it cannot
matter whether `-display-columns 2` returns the whole row or only the visible
column.

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

Waybar's glyphs come from **Font Awesome 6 Free**, which is in the base image.
There is no Nerd Font installed, so Nerd-Font-only codepoints render as tofu.

Two traps worth knowing, both of which make icons vanish *silently* rather than
erroring:

1. `style.css` must ask for the family **`Font Awesome 6 Free Solid`**, not
   `Font Awesome 6 Free`. The bare name resolves to the *Regular* face, which
   does not contain the icons used here.
2. `config.jsonc` writes the glyphs as JSON `\uXXXX` escapes, keeping the file
   pure ASCII. They are Private Use Area codepoints, easily lost to an editor or
   a copy-paste — and when they disappear they leave a plausible-looking empty
   string, so the bar just quietly loses its icons.

Check that a codepoint exists before using it:

```bash
fc-list ':charset=f240' family style
```

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
