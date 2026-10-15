#!/usr/bin/env bash
#
# Teleprompter engine for Waybar.
#
# Waybar 0.15 labels are single-line only (GTK3, no multi-line support), so the
# prompt is streamed across one always-centred line instead: the text is cut
# into fixed-width chunks and one chunk is shown at a time. Consecutive chunks
# follow on from each other, so reading it feels like a continuous scroll while
# the text itself never leaves the middle of the screen.
#
# Usage:
#   prompt.sh                    emit one JSON frame for Waybar (the bar calls this)
#   prompt.sh --step 1           move forward one line
#   prompt.sh --step -1          move back one line
#   prompt.sh --reset            clear the manual nudge (the wrapper re-stamps
#                                the clock, which is what restarts a session)
#   prompt.sh --toggle-pause     freeze / resume the auto-advance
#
# Tunables (override in the environment):
#   TELEPROMPTER_WPM=160         reading speed in words per minute
#   TELEPROMPTER_CHUNK=9         words shown on screen at once

set -uo pipefail

# Splitting is done with shell word splitting, so stop a stray * or ? in the
# prompt from turning into a glob.
set -f

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/waybar"
PROMPT_FILE="$CONFIG_DIR/prompt.txt"

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/teleprompter"
START_FILE="$STATE_DIR/start"    # epoch seconds when the prompt started
OFFSET_FILE="$STATE_DIR/offset"  # manual nudge, in chunks
PAUSE_FILE="$STATE_DIR/paused"  # epoch seconds at which the advance was frozen

# The bar redraws every 0.2s, so the prompt is chunked once and cached rather
# than reparsed on every frame. The cache key covers the file's mtime and size
# as well as the tunables, so editing the prompt still takes effect at once.
CHUNKS_FILE="$STATE_DIR/chunks"
CHUNKS_KEY_FILE="$STATE_DIR/chunks.key"

WPM="${TELEPROMPTER_WPM:-160}"
CHUNK="${TELEPROMPTER_CHUNK:-9}"

mkdir -p "$STATE_DIR"

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  printf '%s' "${s%"${s##*[![:space:]]}"}"
}

# Split the prompt into chunks of $CHUNK words. A source line longer than a
# chunk is split on its own so long sentences keep a clean rhythm; shorter
# lines are packed together so bullets do not leave big ragged gaps.
chunk_prompt() {
  CHUNKS=()
  local -a buf=()
  local line i

  # A missing file is reported by emit(), not by the shell's redirect.
  [[ -r "$PROMPT_FILE" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -z "$line" ]] && continue

    local -a words=()
    read -r -a words <<<"$line"

    if (( ${#words[@]} > CHUNK )); then
      (( ${#buf[@]} )) && { CHUNKS+=("${buf[*]}"); buf=(); }
      for (( i = 0; i < ${#words[@]}; i += CHUNK )); do
        CHUNKS+=("${words[*]:i:CHUNK}")
      done
    else
      buf+=("${words[@]}")
      if (( ${#buf[@]} >= CHUNK )); then
        CHUNKS+=("${buf[*]}")
        buf=()
      fi
    fi
  done < "$PROMPT_FILE"

  (( ${#buf[@]} )) && CHUNKS+=("${buf[*]}")
  return 0
}

# CHUNKS is the cached list, rebuilt only when the prompt or a tunable changes.
build_chunks() {
  local key
  key="$(stat -c '%Y:%s' "$PROMPT_FILE" 2>/dev/null):$WPM:$CHUNK"

  local cached=""
  [[ -r "$CHUNKS_KEY_FILE" ]] && read -r cached <"$CHUNKS_KEY_FILE"

  if [[ "$key" == "$cached" && -r "$CHUNKS_FILE" ]]; then
    mapfile -t CHUNKS <"$CHUNKS_FILE"
    return 0
  fi

  chunk_prompt

  local tmp="$CHUNKS_FILE.$$"
  printf '%s\n' "${CHUNKS[@]}" >"$tmp" && mv "$tmp" "$CHUNKS_FILE"
  printf '%s\n' "$key" >"$CHUNKS_KEY_FILE.$$" && mv "$CHUNKS_KEY_FILE.$$" "$CHUNKS_KEY_FILE"
}

# All of these run on every redraw, so they assign to globals rather than
# printing: a $(...) would cost a fork each time.
read_state() {
  local now="$EPOCHSECONDS"

  START=""
  [[ -r "$START_FILE" ]] && read -r START <"$START_FILE"
  [[ "$START" =~ ^[0-9]+$ ]] || START="$now"

  MANUAL=""
  [[ -r "$OFFSET_FILE" ]] && read -r MANUAL <"$OFFSET_FILE"
  [[ "$MANUAL" =~ ^-?[0-9]+$ ]] || MANUAL=0

  # While paused the clock we compare against stays frozen, so unpausing
  # resumes exactly where it left off instead of jumping forward.
  local frozen=""
  [[ -r "$PAUSE_FILE" ]] && read -r frozen <"$PAUSE_FILE"
  if [[ "$frozen" =~ ^[0-9]+$ ]]; then
    NOW="$frozen"
  else
    NOW="$now"
  fi
}

# How many whole chunks the elapsed time is worth.
auto_chunks() {
  local elapsed=$(( NOW - START ))
  (( elapsed < 0 )) && elapsed=0
  AUTO=$(( elapsed * WPM / (60 * CHUNK) ))
}

clamp_index() {  # $1 index, $2 last valid; result in CLAMPED
  CLAMPED=$1
  (( CLAMPED < 0 )) && CLAMPED=0
  (( CLAMPED > $2 )) && CLAMPED=$2
}

write_offset() {
  local tmp="$OFFSET_FILE.$$"
  printf '%s\n' "$1" >"$tmp" && mv "$tmp" "$OFFSET_FILE"
}

# Quote a string as a JSON value. The prompt is arbitrary prose, so it may well
# contain quotes or backslashes that would otherwise break the frame.
json_str() {
  local s="$1"
  s="${s//[[:cntrl:]]/}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

# Emit one JSON frame for Waybar.
emit() {
  build_chunks
  local total=${#CHUNKS[@]}
  local text idx pct

  if (( total == 0 )); then
    if [[ ! -f "$PROMPT_FILE" ]]; then
      text="no prompt.txt in ~/.config/waybar"
    else
      text="prompt.txt is empty"
    fi
    printf '{"text":%s,"tooltip":%s}\n' "$(json_str "$text")" "$(json_str "$text")"
    return 0
  fi

  read_state
  auto_chunks
  clamp_index $(( AUTO + MANUAL )) $(( total - 1 ))
  idx=$CLAMPED
  pct=$(( (idx + 1) * 100 / total ))

  printf '{"text":%s,"tooltip":"%d%% — line %d of %d"}\n' \
    "$(json_str "${CHUNKS[idx]}")" "$pct" "$(( idx + 1 ))" "$total"
}

nudge() {
  local dir="$1"
  build_chunks
  local total=${#CHUNKS[@]}
  (( total == 0 )) && return 0

  read_state
  auto_chunks
  clamp_index $(( AUTO + MANUAL )) $(( total - 1 ))
  # Manual position is stored relative to the auto-advance so that the text
  # keeps drifting forward at reading speed after a step.
  write_offset $(( CLAMPED + dir - AUTO ))
}

case "${1:-}" in
  --step)
    nudge "${2:-1}"
    ;;
  --reset)
    write_offset 0
    ;;
  --toggle-pause)
    if [[ -f "$PAUSE_FILE" ]]; then
      rm -f "$PAUSE_FILE"
    else
      printf '%s\n' "$EPOCHSECONDS" >"$PAUSE_FILE"
    fi
    ;;
  "")
    emit
    ;;
  *)
    echo "usage: ${0##*/} [--step N|--reset|--toggle-pause]" >&2
    exit 2
    ;;
esac
