#!/bin/sh
# Spins down idle HDDs by putting them into standby via smartctl.
# A drive is put to sleep when its I/O counters (/sys/block/<dev>/stat)
# have not changed for IDLE_MINUTES. Drives already in standby are never
# woken up: state is checked with `smartctl -n standby`.

DRIVES="${DRIVES:-sda sdb}"
IDLE_MINUTES="${IDLE_MINUTES:-10}"
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

idle_limit=$(( IDLE_MINUTES * 60 / CHECK_INTERVAL ))

# Per-drive state kept in a temp dir (POSIX sh has no arrays/assoc arrays).
STATE_DIR="$(mktemp -d)"
trap 'rm -rf "$STATE_DIR"' EXIT

is_standby() {
    smartctl -n standby -i "/dev/$1" >/dev/null 2>&1
    [ $? -eq 2 ]
}

log "Starting autosleep: drives='$DRIVES' idle=${IDLE_MINUTES}m interval=${CHECK_INTERVAL}s"

while true; do
    for d in $DRIVES; do
        [ -b "/dev/$d" ] || { log "$d: not present, skipping"; continue; }

        if is_standby "$d"; then
            echo 0 > "$STATE_DIR/$d.idle"
            continue
        fi

        stat_now="$(cat "/sys/block/$d/stat" 2>/dev/null)"
        stat_prev="$(cat "$STATE_DIR/$d.stat" 2>/dev/null)"
        idle_count="$(cat "$STATE_DIR/$d.idle" 2>/dev/null || echo 0)"

        if [ "$stat_now" = "$stat_prev" ]; then
            idle_count=$(( idle_count + 1 ))
        else
            idle_count=0
        fi
        echo "$stat_now" > "$STATE_DIR/$d.stat"
        echo "$idle_count" > "$STATE_DIR/$d.idle"

        if [ "$idle_count" -ge "$idle_limit" ]; then
            log "$d: idle for ${IDLE_MINUTES}m, entering standby"
            smartctl -s standby,now "/dev/$d" >/dev/null 2>&1 \
                || hdparm -y "/dev/$d" >/dev/null 2>&1 \
                || log "$d: failed to enter standby"
            echo 0 > "$STATE_DIR/$d.idle"
        fi
    done
    sleep "$CHECK_INTERVAL"
done
