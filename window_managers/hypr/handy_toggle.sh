#!/usr/bin/env bash
# Toggle Handy transcription from a Hyprland keybind.
#
# Why this wrapper exists: `handy --toggle-transcription` is a *remote control*
# flag, not a startup flag. Handy only acts on it inside the
# tauri_plugin_single_instance callback, which by construction fires only when
# another Handy instance is already running (src-tauri/src/lib.rs). On a cold
# start the flag lands in `cli_args`, is never read, and is dropped - so the app
# boots with its window up but transcription off. Pressing the key a second time
# works, because by then there is an instance to forward the flag to.
#
# So: make sure a Handy instance is up and able to *receive* the toggle before
# sending it. Presses against an already-running instance skip straight to the
# toggle, so they stay as fast as they were.
#
# The Handy window itself is pinned to workspace 1 by the "handy-to-ws1"
# window rule in hyprland.lua - nothing to do here.

set -u

HANDY_BIN="${HANDY_BIN:-handy}"
# D-Bus name that tauri_plugin_single-instance owns for as long as the app runs.
BUS_NAME="${HANDY_BUS_NAME:-com.pais.handy.SingleInstance}"

# The plugin claims BUS_NAME during plugin setup, which is *before* the webview
# is built and before Handy manages its TranscriptionCoordinator. A toggle that
# arrives in that gap is dropped with "TranscriptionCoordinator not
# initialized". So wait for the window to map, then give the coordinator a beat.
READY_TIMEOUT="${HANDY_READY_TIMEOUT:-20}"   # seconds to wait for boot
READY_SETTLE="${HANDY_READY_SETTLE:-1}"      # extra seconds once the window is up

log() { printf 'handy_toggle: %s\n' "$*" >&2; }

# --- serialise presses ---------------------------------------------------
# Handy takes ~1.5s to come up. A second press landing in that window would see
# a half-booted instance and get lost, so queue behind the first: two presses
# still mean "start, then stop".
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/handy-toggle.lock"
exec 9>"$LOCK_FILE"
if ! flock -w 5 9; then
    log "a previous toggle is still in flight, skipping this press"
    exit 0
fi

# Is an instance already up? BUS_NAME ownership is the authoritative answer -
# it is exactly what the single-instance plugin arbitrates on. Fall back to a
# process check so a missing busctl degrades to "probably running" instead of
# spawning a duplicate instance on every press.
has_instance() {
    if command -v busctl >/dev/null 2>&1; then
        busctl --user status "$BUS_NAME" >/dev/null 2>&1
    else
        pgrep -x handy >/dev/null 2>&1
    fi
}

window_mapped() {
    # Only a progress signal: the wait is bounded, so if this cannot be checked
    # just carry on rather than stalling the toggle.
    command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 0
    hyprctl clients -j 2>/dev/null | jq -e 'any(.[]; .class == "Handy")' >/dev/null 2>&1
}

# Poll `check` every 0.1s up to a timeout in tenths of a second.
wait_until() {
    local check=$1 tenths=$2
    while ! "$check"; do
        [ "$tenths" -le 0 ] && return 1
        tenths=$((tenths - 1))
        sleep 0.1
    done
}

if has_instance; then
    : # warm: instance is already able to receive the toggle
else
    log "no Handy instance, starting one"
    # 9>&- closes the lock fd in the child: handy is long-lived, and inheriting
    # it would hold the flock for the app's whole lifetime, locking out every
    # later press.
    setsid "$HANDY_BIN" >/dev/null 2>&1 9>&- &

    if ! wait_until has_instance "$((READY_TIMEOUT * 10))"; then
        log "Handy never claimed $BUS_NAME within ${READY_TIMEOUT}s"
    elif ! wait_until window_mapped "$((READY_TIMEOUT * 10))"; then
        log "Handy claimed $BUS_NAME but its window never mapped"
    else
        log "Handy is up, settling ${READY_SETTLE}s"
        sleep "$READY_SETTLE"
    fi
fi

# The forwarding process hands the flag over and exits, so this returns quickly
# whenever an instance is listening.
if "$HANDY_BIN" --toggle-transcription; then
    log "toggle delivered"
else
    log "toggle failed"
    exit 1
fi