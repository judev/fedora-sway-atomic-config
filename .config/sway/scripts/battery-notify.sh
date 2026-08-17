#!/usr/bin/env bash
# Low-battery notifier.
#
# The T480 has two batteries: BAT0 (internal) and BAT1 (hot-swappable). They
# discharge one at a time, so reading a single battery misreports badly -- BAT1
# can sit at 4% while BAT0 is untouched and the machine has hours left. This
# sums both packs and reports the combined charge.
#
# Started from ~/.config/sway/config.d/45-autostart.conf.

set -uo pipefail

WARN=15
CRIT=5
INTERVAL=60

# Combined charge across every battery present, as a whole percentage.
# Returns non-zero if no battery could be read (desktop, or all packs removed).
battery_percent() {
    local now=0 full=0 n f bat

    for bat in /sys/class/power_supply/BAT*; do
        if [[ -r "$bat/energy_now" && -r "$bat/energy_full" ]]; then
            n=$(<"$bat/energy_now")
            f=$(<"$bat/energy_full")
        elif [[ -r "$bat/charge_now" && -r "$bat/charge_full" ]]; then
            n=$(<"$bat/charge_now")
            f=$(<"$bat/charge_full")
        else
            # Bay is empty or the pack is not reporting -- skip it rather than
            # counting it as zero, which would drag the average down.
            continue
        fi
        (( now += n ))
        (( full += f ))
    done

    (( full > 0 )) || return 1
    echo $(( now * 100 / full ))
}

on_ac() {
    local ac
    for ac in /sys/class/power_supply/A{C,DP}*; do
        [[ -r "$ac/online" ]] || continue
        [[ "$(<"$ac/online")" == 1 ]] && return 0
    done
    return 1
}

# Which threshold we have already fired for, so a warning is not repeated every
# minute. Cleared when charge recovers or the charger goes in.
notified=""

# Sleep first: at login the battery reading is settled and we avoid firing a
# warning into a session that has not drawn its bar yet.
while sleep "$INTERVAL"; do
    pct=$(battery_percent) || continue

    if on_ac; then
        notified=""
        continue
    fi

    if (( pct <= CRIT )) && [[ "$notified" != crit ]]; then
        notify-send -u critical -i battery-caution \
            "Battery critically low" "${pct}% remaining -- save your work."
        notified=crit
    elif (( pct <= WARN )) && [[ -z "$notified" ]]; then
        notify-send -u normal -i battery-low \
            "Battery low" "${pct}% remaining."
        notified=warn
    elif (( pct > WARN )); then
        notified=""
    fi
done
