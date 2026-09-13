#!/usr/bin/env bash

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}"
END_FILE="$STATE_DIR/waybar-timer-end"
DONE_FILE="$STATE_DIR/waybar-timer-done"
PAUSE_FILE="$STATE_DIR/waybar-timer-paused"
ALARM="/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"

GTK_CSS='
window {
  background-color: rgba(5, 12, 20, 0.96);
  color: #00e5ff;
  border: 2px solid #00e5ff;
  border-radius: 6px;
  font-family: "Orbitron", "JetBrainsMono Nerd Font";
  font-size: 12px;
}
window label {
  color: #00e5ff;
}
window button {
  background-color: rgba(0, 40, 60, 0.8);
  color: #00e5ff;
  border: 1px solid #00e5ff;
  border-radius: 4px;
  padding: 4px 12px;
  margin: 4px;
}
window button:hover {
  background-color: rgba(0, 229, 255, 0.2);
}
window spinbutton {
  background-color: rgba(0, 20, 30, 0.8);
  color: #00e5ff;
  border: 1px solid #00e5ff;
  border-radius: 4px;
  padding: 2px;
}
window spinbutton button {
  border: none;
  background-color: transparent;
  padding: 0px;
  margin: 0px;
}
window spinbutton entry {
  background-color: transparent;
  color: #00e5ff;
}
'

play_alarm() {
  {
    local dur end
    dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$ALARM" 2>/dev/null)
    dur=${dur:-1}
    end=$(( EPOCHSECONDS + 5 ))
    while (( EPOCHSECONDS < end )); do
      paplay "$ALARM" &
      sleep "$dur"
    done
    wait
  } >/dev/null 2>&1 &
}

set_timer() {
  local input h m s total end remaining ret args
  remaining=0
  if [[ -f $PAUSE_FILE ]]; then
    remaining=$(cat "$PAUSE_FILE")
  elif [[ -f $END_FILE ]]; then
    remaining=$(cat "$END_FILE")
    remaining=$(( remaining - EPOCHSECONDS ))
    (( remaining > 0 )) || remaining=0
  fi
  args=(--title="⏱ Set Timer" --form --separator=" " --center \
    --undecorated --css="$GTK_CSS" \
    --field="Hours:NUM" "0..24!$(( remaining / 3600 ))!1" \
    --field="Minutes:NUM" "0..59!$(( (remaining % 3600) / 60 ))!1" \
    --field="Seconds:NUM" "0..59!$(( remaining % 60 ))!1" \
    --button="Start:0")
  if [[ -f $PAUSE_FILE ]]; then
    args+=(--button="Resume:3")
  elif [[ -f $END_FILE ]]; then
    args+=(--button="Pause:3")
  fi
  if [[ -f $END_FILE ]]; then
    args+=(--button="Stop Timer:2")
  fi
  args+=(--button="Cancel:1")
  input=$(yad "${args[@]}" 2>/dev/null)
  ret=$?
  if (( ret == 2 )); then
    rm -f "$END_FILE" "$DONE_FILE" "$PAUSE_FILE"
    exit 0
  fi
  if (( ret == 3 )); then
    if [[ -f $PAUSE_FILE ]]; then
      remaining=$(cat "$PAUSE_FILE")
      (( remaining > 0 )) || remaining=0
      echo $(( EPOCHSECONDS + remaining )) > "$END_FILE"
      rm -f "$PAUSE_FILE"
    else
      end=$(cat "$END_FILE")
      remaining=$(( end - EPOCHSECONDS ))
      (( remaining > 0 )) || remaining=0
      echo "$remaining" > "$PAUSE_FILE"
    fi
    exit 0
  fi
  [[ $ret -ne 0 || -z "$input" ]] && exit 0
  read -r h m s <<<"$input"
  h=${h:-0}
  m=${m:-0}
  s=${s:-0}
  total=$(( h * 3600 + m * 60 + s ))
  (( total > 0 )) || exit 0
  echo $(( EPOCHSECONDS + total )) > "$END_FILE"
  rm -f "$DONE_FILE" "$PAUSE_FILE"
}

case "${1:-}" in
  --set)
    set_timer
    exit 0
    ;;
  --cancel)
    rm -f "$END_FILE" "$DONE_FILE" "$PAUSE_FILE"
    exit 0
    ;;
esac

if [[ -f $PAUSE_FILE ]]; then
  remaining=$(cat "$PAUSE_FILE")
  printf '{"text":"⏸ %02d:%02d:%02d","class":"paused"}' \
    "$(( remaining / 3600 ))" "$(( (remaining % 3600) / 60 ))" "$(( remaining % 60 ))"
  exit 0
fi

if [[ -f $END_FILE ]]; then
  end=$(cat "$END_FILE")
  if (( EPOCHSECONDS < end )); then
    remaining=$(( end - EPOCHSECONDS ))
    printf '{"text":"⏳ %02d:%02d:%02d","class":"active"}' \
      "$(( remaining / 3600 ))" "$(( (remaining % 3600) / 60 ))" "$(( remaining % 60 ))"
    exit 0
  fi
  rm -f "$END_FILE"
  echo "$EPOCHSECONDS" > "$DONE_FILE"
  play_alarm
fi

if [[ -f $DONE_FILE ]]; then
  if (( EPOCHSECONDS - $(cat "$DONE_FILE") < 10 )); then
    echo '{"text":"⏰ Done!","class":"done"}'
    exit 0
  fi
  rm -f "$DONE_FILE"
fi

echo '{"text":"⏱ Set Timer","class":"idle"}'
