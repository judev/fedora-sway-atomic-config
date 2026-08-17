#!/usr/bin/env bash
# Screen recording, wrapping wf-recorder.
#
#   record.sh start <region|output|screen> [none|system|narrate]
#   record.sh stop
#   record.sh toggle <region|output|screen> [none|system|narrate]
#   record.sh status          # emits waybar JSON
#
# Driven by ~/.config/sway/config.d/62-bindings-record.conf and surfaced in the
# bar by waybar's custom/recording module.
#
# CODECS -- why these are pinned explicitly:
# wf-recorder defaults to libx264, which does not exist on Fedora Sway Atomic:
# the base image ships ffmpeg-free (no libx264/libx265), Fedora strips H.264
# encode out of libva-intel-media-driver, and this laptop's UHD 620 has no VP9
# encode silicon. So there is no hardware encode path at all, and the default
# would simply fail. H.264 comes from the layered openh264 package instead.
# Check what is actually available with:  ffmpeg -encoders

set -uo pipefail

RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
PIDFILE="$RUNTIME/wf-recorder.pid"
OUTFILE="$RUNTIME/wf-recorder.output"
MODFILE="$RUNTIME/wf-recorder.pamodules"

VIDEO_CODEC=libopenh264
AUDIO_CODEC=aac
PIXFMT=yuv420p

# Deliberately in XDG_RUNTIME_DIR, not /tmp: it is 0700 and user-owned, so
# there is no symlink-race on a predictable path.

die() {
    notify-send -u critical "Recording failed" "$1"
    exit 1
}

target_dir() {
    # Same resolution order grimshot uses, for consistency.
    # shellcheck disable=SC1091
    test -f "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs" &&
        . "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
    echo "${XDG_VIDEOS_DIR:-$HOME/Videos}"
}

is_recording() {
    [[ -f "$PIDFILE" ]] && kill -0 "$(<"$PIDFILE")" 2>/dev/null
}

# Nudge waybar so the indicator updates immediately rather than at the next poll.
refresh_bar() { pkill -RTMIN+9 waybar 2>/dev/null; return 0; }

### Audio ####################################################################

# wf-recorder's -a takes a SINGLE PulseAudio device. Recording the desktop and
# a microphone together therefore needs them mixed first, via a null sink fed by
# two loopbacks. The module IDs are recorded so stop() can unload them again --
# leaking them would leave a phantom output device behind.
setup_narrate_source() {
    local sink mic mods=()
    sink="$(pactl get-default-sink).monitor"
    mic="$(pactl get-default-source)"

    # A mic that is itself a monitor means there is no real capture device.
    [[ "$mic" == *.monitor ]] && { echo "$sink"; return; }

    local id
    id=$(pactl load-module module-null-sink sink_name=recmix \
            sink_properties=device.description=RecordingMix 2>/dev/null) || {
        echo "$sink"; return
    }
    mods+=("$id")
    id=$(pactl load-module module-loopback source="$sink" sink=recmix latency_msec=50 2>/dev/null) \
        && mods+=("$id")
    id=$(pactl load-module module-loopback source="$mic" sink=recmix latency_msec=50 2>/dev/null) \
        && mods+=("$id")

    printf '%s\n' "${mods[@]}" > "$MODFILE"
    echo "recmix.monitor"
}

teardown_audio() {
    [[ -f "$MODFILE" ]] || return 0
    # Unload in reverse order: loopbacks before the sink they feed.
    tac "$MODFILE" | while read -r id; do
        [[ -n "$id" ]] && pactl unload-module "$id" 2>/dev/null
    done
    rm -f "$MODFILE"
}

### Commands #################################################################

start() {
    local target="${1:-region}" audio="${2:-system}"

    # State before dependency: if something is already recording, that is the
    # useful thing to say, and it keeps this guard reachable and testable
    # regardless of whether wf-recorder is installed.
    is_recording && { notify-send "Already recording"; exit 0; }

    command -v wf-recorder >/dev/null ||
        die "wf-recorder is not installed. See 62-bindings-record.conf for the rpm-ostree command."

    local dir file
    dir="$(target_dir)"
    mkdir -p "$dir" || die "cannot create $dir"
    file="$dir/$(date +%Y-%m-%d-%H%M%S).mp4"

    local args=(-f "$file" -c "$VIDEO_CODEC" -x "$PIXFMT" -C "$AUDIO_CODEC" -y)

    case "$target" in
        region)
            local geom
            # slurp prints "x,y WxH", exactly wf-recorder's -g format.
            geom=$(slurp 2>/dev/null) || exit 0   # cancelled with Escape
            [[ -n "$geom" ]] || exit 0
            args+=(-g "$geom")
            ;;
        output)
            local out
            out=$(swaymsg -t get_outputs |
                  jq -r '.[] | select(.focused) | .name') || die "cannot determine output"
            args+=(-o "$out")
            ;;
        screen) ;;   # no geometry or output: everything
        *) die "unknown target: $target" ;;
    esac

    case "$audio" in
        none) ;;
        system)  args+=("--audio=$(pactl get-default-sink).monitor") ;;
        narrate) args+=("--audio=$(setup_narrate_source)") ;;
        *) die "unknown audio mode: $audio" ;;
    esac

    echo "$file" > "$OUTFILE"
    wf-recorder "${args[@]}" >/dev/null 2>&1 &
    echo $! > "$PIDFILE"

    # wf-recorder can still fail at startup (bad codec, busy device). Give it a
    # moment and confirm it is actually alive before claiming success.
    sleep 1
    if ! is_recording; then
        rm -f "$PIDFILE" "$OUTFILE"
        teardown_audio
        refresh_bar
        die "wf-recorder exited immediately. Run it by hand with -l to see why."
    fi

    refresh_bar
    notify-send -i media-record "Recording started" "$(basename "$file")  [$target/$audio]"
}

stop() {
    is_recording || { notify-send "Not recording"; exit 0; }

    local pid file
    pid=$(<"$PIDFILE")
    file=$(cat "$OUTFILE" 2>/dev/null)

    # SIGINT, never SIGKILL: wf-recorder must be allowed to write the trailer.
    # An MP4 killed mid-write has no moov atom and will not play.
    kill -INT "$pid" 2>/dev/null

    for _ in $(seq 1 50); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done

    rm -f "$PIDFILE" "$OUTFILE"
    teardown_audio
    refresh_bar

    if [[ -n "$file" && -f "$file" ]]; then
        local size
        size=$(du -h "$file" | cut -f1)
        notify-send -i media-record "Recording saved" "$(basename "$file")  ($size)"
    else
        notify-send -u critical "Recording stopped" "but no output file was found"
    fi
}

status() {
    # The record icon is a Font Awesome Private Use Area glyph, built here from
    # an ASCII \u escape rather than pasted in literally: this file stays pure
    # ASCII (PUA codepoints are easily lost to an editor or a locale, and they
    # fail by silently rendering nothing) while waybar still gets the glyph.
    #
    # It belongs in "text", NOT in waybar's "format". A format of "<icon> {}"
    # renders the icon even when text is empty, which leaves a stray dot sitting
    # in the bar while idle. With the icon in "text", the empty string collapses
    # the module completely.
    if is_recording; then
        local file icon
        icon=$(printf '\uf111')
        file=$(basename "$(cat "$OUTFILE" 2>/dev/null)" 2>/dev/null)
        printf '{"text":"%s REC","class":"recording","tooltip":"Recording %s - click to stop"}\n' \
            "$icon" "${file:-}"
    else
        # Empty text hides the module entirely.
        printf '{"text":"","class":"idle","tooltip":""}\n'
    fi
}

case "${1:-}" in
    start)  shift; start "$@" ;;
    stop)   stop ;;
    toggle) shift; if is_recording; then stop; else start "$@"; fi ;;
    status) status ;;
    *) echo "usage: $0 {start <region|output|screen> [none|system|narrate]|stop|toggle|status}" >&2; exit 2 ;;
esac
