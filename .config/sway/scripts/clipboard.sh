#!/usr/bin/env bash
# Clipboard history: cliphist for storage, rofi for the picker.
#
#   clipboard.sh store    # run by `wl-paste --watch`, not by hand
#   clipboard.sh pick     # the rofi picker (Super+V)
#   clipboard.sh wipe     # clear the whole history
#
# Wired up in ~/.config/sway/config.d/64-clipboard.conf.
# Tunables (history size, preview width) live in ~/.config/cliphist/config.

set -uo pipefail

die() {
    notify-send -u critical "Clipboard" "$1"
    exit 1
}

need_cliphist() {
    command -v cliphist >/dev/null ||
        die "cliphist is not installed. See 64-clipboard.conf for the rpm-ostree command."
}

### store #####################################################################

# Called once per clipboard change by `wl-paste --watch`, with the content on
# stdin.
store() {
    # wl-paste sets CLIPBOARD_STATE for the command it spawns in --watch mode.
    #
    #   sensitive -- the offer carried x-kde-passwordManagerHint, i.e. a
    #                password manager marked this as a secret. Never persist it.
    #   nil/clear -- the clipboard is empty; stdin is /dev/null, nothing to store.
    #
    # Using this rather than shelling out to `wl-paste --list-types` is both
    # cheaper and race-free: it describes the offer that triggered *this*
    # invocation, not whatever happens to be on the clipboard a moment later.
    #
    # Caveat worth knowing: wl-clipboard only sets `sensitive` when it sees
    # x-kde-passwordManagerHint, so this protects you only from applications
    # that actually set that hint. Verify yours with:
    #   wl-paste --watch sh -c 'echo "$CLIPBOARD_STATE"'
    # then copy a password and watch the output.
    case "${CLIPBOARD_STATE:-}" in
        sensitive) exit 0 ;;
        nil|clear) exit 0 ;;
    esac

    need_cliphist
    cliphist store
}

### pick ######################################################################

pick() {
    need_cliphist

    local list idx rc row
    list=$(cliphist list)
    [[ -n "$list" ]] || { notify-send -t 1500 "Clipboard" "History is empty"; exit 0; }

    # `-format i` returns the 0-based INDEX of the chosen row, and we then look
    # that row up in the same list we just generated.
    #
    # This is deliberate rather than piping rofi's selected text straight into
    # `cliphist decode`. Each row is "<id>\t<preview>", and decode needs the id:
    # given only the preview it fails outright with
    #   extracting id: converting id: strconv.Atoi: ... invalid syntax
    # Selecting by index means it cannot matter whether `-display-columns 2`
    # returns the whole row or only the visible column -- the display and the
    # lookup are fully decoupled.
    #
    # -display-columns 2 hides the id column from view.
    # -no-custom forbids typing a value that is not in the list; there is no
    #   sensible meaning for "paste a thing that was never copied".
    # -i makes the search case-insensitive.
    #
    # Alt+Delete / Alt+Shift+Delete were chosen because both are provably free
    # among rofi's 102 default bindings. Shift+Delete would read better but is
    # already rofi's own kb-delete-entry, and duplicates are a hard error.
    # kb-delete-entry only drops the row from rofi's list -- it does not touch
    # cliphist's database, which is why these two exist at all.
    idx=$(printf '%s\n' "$list" | rofi -dmenu -i \
            -p "Clipboard" \
            -no-custom \
            -format i \
            -display-columns 2 \
            -kb-custom-1 "Alt+Delete" \
            -kb-custom-2 "Alt+Shift+Delete" \
            -mesg "Enter: copy    Alt+Del: forget entry    Alt+Shift+Del: wipe all")
    rc=$?

    # Wiping needs no selection, so handle it before resolving the index.
    if [[ "$rc" == 11 ]]; then
        wipe
        exit 0
    fi

    # 1 = cancelled; a non-numeric index means nothing was chosen.
    [[ "$rc" == 0 || "$rc" == 10 ]] || exit 0
    [[ "$idx" =~ ^[0-9]+$ ]] || exit 0

    row=$(printf '%s\n' "$list" | sed -n "$((idx + 1))p")
    [[ -n "$row" ]] || exit 0

    case "$rc" in
        0)
            printf '%s\n' "$row" | cliphist decode | wl-copy
            ;;
        10)
            printf '%s\n' "$row" | cliphist delete &&
                notify-send -t 1500 "Clipboard" "Entry forgotten"
            ;;
    esac
}

### wipe ######################################################################

wipe() {
    need_cliphist
    cliphist wipe && notify-send -t 2000 "Clipboard" "History wiped"
}

case "${1:-}" in
    store) store ;;
    pick)  pick ;;
    wipe)  wipe ;;
    *) echo "usage: $0 {store|pick|wipe}" >&2; exit 2 ;;
esac
