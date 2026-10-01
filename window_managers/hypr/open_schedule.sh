#!/usr/bin/env bash
# Open today's schedule/task file in Neovim so Hyprland can place it on
# workspace 2 (see the "schedule-to-ws2" window rule in hyprland.lua).
#
# Files live in month folders, e.g.
#   ~/Desktop/notes/daily/oct_2026/oct_1.txt
#   ~/Desktop/notes/daily/sept_2026/sept30.txt
#
# If there is no file for today, this exits 0 silently - no error, no window.

set -u

BASE="${SCHEDULE_DIR:-$HOME/Desktop/notes/daily}"

year=$(date +%Y)                                     # 2026
mon=$(date +%b | tr '[:upper:]' '[:lower:]')         # oct, sep, ...
day=$(date +%-d)                                     # 1..31, no padding

find_today() {
    local dir name cand

    # Month folders: oct_2026, sept_2026, ...
    for dir in "$BASE"/*_"$year"; do
        [ -d "$dir" ] || continue
        name=${dir##*/}
        name=${name%_*}
        case "$name" in
            "$mon"*) ;;   # oct matches Oct, sept matches Sep, ...
            *) continue ;;
        esac
        # Handle both "oct_1.txt" and "sept30.txt" styles (and zero padding).
        for cand in "$dir/${name}_${day}.txt" \
                    "$dir/${name}${day}.txt" \
                    "$dir/${name}_0${day}.txt" \
                    "$dir/${name}0${day}.txt"; do
            if [ -f "$cand" ]; then
                printf '%s\n' "$cand"
                return 0
            fi
        done
    done

    # Fall back to a file sitting directly in the base folder.
    for cand in "$BASE/${mon}_${day}.txt" "$BASE/${mon}${day}.txt"; do
        if [ -f "$cand" ]; then
            printf '%s\n' "$cand"
            return 0
        fi
    done

    return 1
}

file=$(find_today) || exit 0

exec ghostty --title="daily-schedule" -e nvim "$file"
