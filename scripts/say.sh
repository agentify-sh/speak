#!/usr/bin/env bash
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-"$HOME/.codex"}"

DEFAULT_RUNTIME_DIR="$HOME/Library/Caches/codex-say"
if [[ -n "${CODEX_SAY_RUNTIME_DIR:-}" ]]; then
  RUNTIME_DIR="$CODEX_SAY_RUNTIME_DIR"
elif [[ -d "$HOME/Library/Caches" ]] && mkdir -p "$DEFAULT_RUNTIME_DIR" >/dev/null 2>&1; then
  RUNTIME_DIR="$DEFAULT_RUNTIME_DIR"
else
  RUNTIME_DIR="${TMPDIR:-/tmp}/codex-say"
fi

STATE_FILE="$RUNTIME_DIR/say.state"
LAST_TEXT_FILE="$RUNTIME_DIR/say.last.txt"
LAST_FULL_FILE="$RUNTIME_DIR/say.last.full.txt"
LAST_SUMMARY_FILE="$RUNTIME_DIR/say.last.summary.txt"
PID_FILE="$RUNTIME_DIR/say.pid"
UNTIL_FILE="$RUNTIME_DIR/say.until"
PENDING_FILE="$RUNTIME_DIR/say.pending"
PENDING_WATCHER_PID_FILE="$RUNTIME_DIR/say.pending_watcher.pid"
LOCK_DIR="$RUNTIME_DIR/say.lock"
VOLUME_FILE="$RUNTIME_DIR/say.volume"
PREV_VOLUME_FILE="$RUNTIME_DIR/say.prev_volume"
RESTORE_PID_FILE="$RUNTIME_DIR/say.restore.pid"
TTS_FILE="$RUNTIME_DIR/say.tts.aiff"
GEN_PID_FILE="$RUNTIME_DIR/say.gen.pid"
PLAYER_PID_FILE="$RUNTIME_DIR/say.player.pid"
VOLUME_MODE="${CODEX_SAY_VOLUME_MODE:-player}" # player|system
VOLUME_AUTO_PREVIEW="${CODEX_SAY_VOLUME_AUTO_PREVIEW:-1}"

ENGINE_FILE="$RUNTIME_DIR/say.engine"
ENGINE_DEFAULT="${CODEX_SAY_ENGINE:-apple}" # apple|pocket
ENGINE_PERSISTED="$(cat "$ENGINE_FILE" 2>/dev/null || true)"
ENGINE_PERSISTED="${ENGINE_PERSISTED//$'\n'/}"
if [[ -n "${CODEX_SAY_ENGINE:-}" ]]; then
  ENGINE="$CODEX_SAY_ENGINE"
elif [[ -n "${ENGINE_PERSISTED:-}" ]]; then
  ENGINE="$ENGINE_PERSISTED"
else
  ENGINE="$ENGINE_DEFAULT"
fi

POCKET_VOICE_FILE="$RUNTIME_DIR/pocket.voice"
POCKET_VOICE_DEFAULT="${CODEX_POCKET_TTS_VOICE:-alba}"
POCKET_VOICE_PERSISTED="$(cat "$POCKET_VOICE_FILE" 2>/dev/null || true)"
POCKET_VOICE_PERSISTED="${POCKET_VOICE_PERSISTED//$'\n'/}"
if [[ -n "${CODEX_POCKET_TTS_VOICE:-}" ]]; then
  POCKET_VOICE="$CODEX_POCKET_TTS_VOICE"
elif [[ -n "${POCKET_VOICE_PERSISTED:-}" ]]; then
  POCKET_VOICE="$POCKET_VOICE_PERSISTED"
else
  POCKET_VOICE="$POCKET_VOICE_DEFAULT"
fi

POCKET_WAV_FILE="$RUNTIME_DIR/pocket.tts.wav"
POCKET_SPEED_FLAG_FILE="$RUNTIME_DIR/pocket.speedflag"

VOICE_FILE="$RUNTIME_DIR/say.voice"
VOICE_DEFAULT="${CODEX_SAY_VOICE:-Samantha}"
VOICE_PERSISTED="$(cat "$VOICE_FILE" 2>/dev/null || true)"
VOICE_PERSISTED="${VOICE_PERSISTED//$'\n'/}"
if [[ -n "${VOICE_PERSISTED:-}" ]]; then
  VOICE="$VOICE_PERSISTED"
else
  VOICE="$VOICE_DEFAULT"
fi
BASE_RATE="${CODEX_SAY_BASE_RATE:-315}"
RATE="${CODEX_SAY_RATE:-$BASE_RATE}"
SPEED_FILE="$RUNTIME_DIR/say.speed"
SPEED_DEFAULT="${CODEX_SAY_SPEED:-1.0}"
SPEED_PERSISTED="$(cat "$SPEED_FILE" 2>/dev/null || true)"
SPEED_PERSISTED="${SPEED_PERSISTED//$'\n'/}"
if [[ -n "${CODEX_SAY_SPEED:-}" ]]; then
  SPEED="$CODEX_SAY_SPEED"
elif [[ -n "${SPEED_PERSISTED:-}" ]]; then
  SPEED="$SPEED_PERSISTED"
else
  SPEED="$SPEED_DEFAULT"
fi
SPEED_STEP="${CODEX_SAY_SPEED_STEP:-0.1}"

if [[ -z "${CODEX_SAY_RATE:-}" ]]; then
  RATE="$(python3 -c 'import sys
base=float(sys.argv[1]); speed=float(sys.argv[2])
speed=max(0.5,min(2.5,speed))
print(int(round(base*speed)))
' "$RATE" "$SPEED" 2>/dev/null || echo "$RATE")"
fi
MAX_CHARS="${CODEX_SAY_MAX_CHARS:-8000}"
SUMMARY_MAX_CHARS="${CODEX_SAY_SUMMARY_MAX_CHARS:-2400}"
SUMMARY_MAX_BULLETS="${CODEX_SAY_SUMMARY_MAX_BULLETS:-15}"
MODE="${CODEX_SAY_MODE:-summary}" # summary|full

DEBUG="${CODEX_SAY_DEBUG:-0}"
KILL_ALL_SAY="${CODEX_SAY_KILL_ALL:-0}"
INTERRUPT="${CODEX_SAY_INTERRUPT:-0}" # 0 = don't interrupt current speech on new notify; 1 = interrupt

mkdir -p "$RUNTIME_DIR" >/dev/null 2>&1 || true

if [[ "$DEBUG" != "1" ]]; then
  exec 2>/dev/null
fi

is_enabled() {
  if [[ ! -f "$STATE_FILE" ]]; then
    return 0
  fi
  [[ "$(cat "$STATE_FILE" 2>/dev/null || true)" != "disabled" ]]
}

with_lock() {
  local waited=0
  while ! mkdir "$LOCK_DIR" >/dev/null 2>&1; do
    sleep 0.05
    waited=$((waited + 1))
    if (( waited > 40 )); then
      break
    fi
  done
  trap 'rmdir "$LOCK_DIR" >/dev/null 2>&1 || true' RETURN
  "$@"
}

pending_get() {
  local n=""
  n="$(cat "$PENDING_FILE" 2>/dev/null || true)"
  n="${n//[[:space:]]/}"
  if [[ "$n" =~ ^[0-9]+$ ]]; then
    echo "$n"
  else
    echo 0
  fi
}

pending_set() {
  local n="$1"
  n="${n//[[:space:]]/}"
  if [[ ! "$n" =~ ^[0-9]+$ ]]; then
    n=0
  fi
  if (( n < 0 )); then n=0; fi
  if (( n > 9 )); then n=9; fi
  printf '%s\n' "$n" > "$PENDING_FILE" 2>/dev/null || true
}

pending_inc() {
  local n
  n="$(pending_get)"
  pending_set $((n + 1))
  ensure_pending_watcher
}

pending_dec() {
  local n
  n="$(pending_get)"
  if (( n > 0 )); then
    pending_set $((n - 1))
  fi
}

ensure_pending_watcher() {
  local pid=""
  pid="$(cat "$PENDING_WATCHER_PID_FILE" 2>/dev/null || true)"
  pid="${pid//[[:space:]]/}"
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  (
    "$0" __pending-watch >/dev/null 2>&1 || true
  ) & echo $! > "$PENDING_WATCHER_PID_FILE" 2>/dev/null || true
}

set_state() {
  printf '%s\n' "$1" > "$STATE_FILE" 2>/dev/null || true
}

get_system_volume() {
  osascript -e 'output volume of (get volume settings)' 2>/dev/null || true
}

set_system_volume() {
  local vol="$1"
  osascript -e "set volume output volume ${vol}" >/dev/null 2>&1 || true
}

get_config_volume() {
  local v=""
  v="$(cat "$VOLUME_FILE" 2>/dev/null || true)"
  v="${v//[[:space:]]/}"
  if [[ "$v" =~ ^[0-9]+$ ]] && (( v >= 0 && v <= 100 )); then
    echo "$v"
  fi
}

set_config_volume() {
  local v="$1"
  v="${v//[[:space:]]/}"
  if [[ ! "$v" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  if (( v < 0 )); then v=0; fi
  if (( v > 100 )); then v=100; fi
  printf '%s\n' "$v" > "$VOLUME_FILE" 2>/dev/null || true
}

clear_config_volume() {
  : > "$VOLUME_FILE" 2>/dev/null || true
}

cancel_restore_timer() {
  local rpid=""
  rpid="$(cat "$RESTORE_PID_FILE" 2>/dev/null || true)"
  rpid="${rpid//[[:space:]]/}"
  if [[ "$rpid" =~ ^[0-9]+$ ]]; then
    kill "$rpid" 2>/dev/null || true
  fi
  : > "$RESTORE_PID_FILE" 2>/dev/null || true
}

restore_volume_now() {
  local prev=""
  prev="$(cat "$PREV_VOLUME_FILE" 2>/dev/null || true)"
  prev="${prev//[[:space:]]/}"
  if [[ "$prev" =~ ^[0-9]+$ ]] && (( prev >= 0 && prev <= 100 )); then
    set_system_volume "$prev"
  fi
  : > "$PREV_VOLUME_FILE" 2>/dev/null || true
}

gain_from_volume() {
  local v="$1"
  v="${v//[[:space:]]/}"
  if [[ ! "$v" =~ ^[0-9]+$ ]]; then
    echo "1.0"
    return 0
  fi
  if (( v <= 0 )); then
    echo "0.0"
    return 0
  fi
  if (( v >= 100 )); then
    echo "1.0"
    return 0
  fi
  python3 -c 'import sys
v=int(sys.argv[1])
g=(max(0.0,min(100.0,float(v)))/100.0)**2
print(f"{g:.3f}")
' "$v" 2>/dev/null || echo "1.0"
}

compute_rate_from_speed() {
  if [[ -n "${CODEX_SAY_RATE:-}" ]]; then
    return 0
  fi
  RATE="$(python3 -c 'import sys
base=float(sys.argv[1]); speed=float(sys.argv[2])
speed=max(0.5,min(2.5,speed))
print(int(round(base*speed)))
' "$BASE_RATE" "$SPEED" 2>/dev/null || echo "$BASE_RATE")"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

normalize_text_one_line() {
  python3 -c 'import sys, re
t = sys.stdin.read()
t = t.replace("\r\n", "\n").replace("\r", "\n")
t = re.sub(r"\\s+", " ", t).strip()
print(t)
' 2>/dev/null
}

pocket_generate_wav() {
  local text_file="$1"
  local voice="${2:-$POCKET_VOICE}"
  local text=""
  text="$(normalize_text_one_line < "$text_file" 2>/dev/null || true)"
  if [[ -z "${text//[[:space:]]/}" ]]; then
    return 1
  fi

  (
    cd "$RUNTIME_DIR" >/dev/null 2>&1 || exit 1
    : > "$POCKET_WAV_FILE" 2>/dev/null || true
    : > "$RUNTIME_DIR/tts_output.wav" 2>/dev/null || true

    if have_cmd pocket-tts; then
      pocket-tts generate --voice "$voice" --text "$text" --output-path "$POCKET_WAV_FILE" --quiet >/dev/null 2>&1 || true
      pocket-tts generate --voice "$voice" --text "$text" --quiet >/dev/null 2>&1 || true
    elif have_cmd uvx; then
      uvx pocket-tts generate --voice "$voice" --text "$text" --output-path "$POCKET_WAV_FILE" --quiet >/dev/null 2>&1 || true
      uvx pocket-tts generate --voice "$voice" --text "$text" --quiet >/dev/null 2>&1 || true
    else
      exit 1
    fi

    if [[ ! -s "$POCKET_WAV_FILE" ]] && [[ -s "$RUNTIME_DIR/tts_output.wav" ]]; then
      cat "$RUNTIME_DIR/tts_output.wav" > "$POCKET_WAV_FILE" 2>/dev/null || true
      : > "$RUNTIME_DIR/tts_output.wav" 2>/dev/null || true
    fi

    [[ -s "$POCKET_WAV_FILE" ]] || exit 1
  ) >/dev/null 2>&1
}

speak_text_file() {
  local text_file="$1"
  local seconds="${2:-10}"
  local cfg_vol=""
  cfg_vol="$(get_config_volume)"

  local loop_file="$text_file"
  local loop_mode="$MODE"

  if [[ "$ENGINE" == "pocket" ]]; then
    local gain="1.0"
    if [[ "$VOLUME_MODE" == "system" ]]; then
      if [[ -n "${cfg_vol:-}" ]]; then
        prev="$(get_system_volume)"
        prev="${prev//[[:space:]]/}"
        if [[ "$prev" =~ ^[0-9]+$ ]]; then
          printf '%s\n' "$prev" > "$PREV_VOLUME_FILE" 2>/dev/null || true
        fi
        set_system_volume "$cfg_vol"
        ( sleep "$(( ${seconds:-10} + 2 ))"; restore_volume_now ) >/dev/null 2>&1 & echo $! > "$RESTORE_PID_FILE" 2>/dev/null || true
      fi
    else
      if [[ -n "${cfg_vol:-}" ]]; then
        gain="$(gain_from_volume "$cfg_vol")"
      fi
    fi

    (
      while true; do
      pocket_generate_wav "$loop_file" "$POCKET_VOICE" & echo $! > "$GEN_PID_FILE"
      gpid="$(cat "$GEN_PID_FILE" 2>/dev/null || true)"
      gpid="${gpid//[[:space:]]/}"
      if [[ "$gpid" =~ ^[0-9]+$ ]]; then
        wait "$gpid" 2>/dev/null || true
      fi
      if [[ ! -s "$POCKET_WAV_FILE" ]]; then
        say -v "$VOICE" -r "$RATE" -o "$TTS_FILE" -f "$loop_file" >/dev/null 2>&1 || true
        afplay -v "$gain" "$TTS_FILE" & echo $! > "$PLAYER_PID_FILE"
      else
        afplay -v "$gain" -r "$SPEED" "$POCKET_WAV_FILE" & echo $! > "$PLAYER_PID_FILE"
      fi
      ppid="$(cat "$PLAYER_PID_FILE" 2>/dev/null || true)"
      ppid="${ppid//[[:space:]]/}"
      if [[ "$ppid" =~ ^[0-9]+$ ]]; then
        wait "$ppid" 2>/dev/null || true
      fi
      : > "$POCKET_WAV_FILE" 2>/dev/null || true
      : > "$TTS_FILE" 2>/dev/null || true
      : > "$GEN_PID_FILE" 2>/dev/null || true
      : > "$PLAYER_PID_FILE" 2>/dev/null || true
      if ! is_enabled; then
        break
      fi
      if [[ "$(pending_get)" -le 0 ]]; then
        break
      fi
      pending_dec
      if [[ "$loop_mode" == "full" ]]; then
        loop_file="$LAST_FULL_FILE"
      else
        loop_file="$LAST_SUMMARY_FILE"
      fi
      words="$(wc -w < "$loop_file" 2>/dev/null | tr -d ' ' || echo 40)"
      set_playing_until_for_words "$words" >/dev/null 2>&1 || true
      done
    ) & echo $! > "$PID_FILE" 2>/dev/null || true
    return 0
  fi

  if [[ "$VOLUME_MODE" == "system" ]]; then
    if [[ -n "${cfg_vol:-}" ]]; then
      prev="$(get_system_volume)"
      prev="${prev//[[:space:]]/}"
      if [[ "$prev" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$prev" > "$PREV_VOLUME_FILE" 2>/dev/null || true
      fi
      set_system_volume "$cfg_vol"
      ( sleep "$(( ${seconds:-10} + 2 ))"; restore_volume_now ) >/dev/null 2>&1 & echo $! > "$RESTORE_PID_FILE" 2>/dev/null || true
    fi
    (say -v "$VOICE" -r "$RATE" -f "$text_file" & echo $! > "$PID_FILE") >/dev/null 2>&1 || true
    return 0
  fi

  local gain="1.0"
  if [[ -n "${cfg_vol:-}" ]]; then
    gain="$(gain_from_volume "$cfg_vol")"
  fi

  (
    while true; do
    say -v "$VOICE" -r "$RATE" -o "$TTS_FILE" -f "$loop_file" & echo $! > "$GEN_PID_FILE"
    gpid="$(cat "$GEN_PID_FILE" 2>/dev/null || true)"
    gpid="${gpid//[[:space:]]/}"
    if [[ "$gpid" =~ ^[0-9]+$ ]]; then
      wait "$gpid" 2>/dev/null || true
    fi
    afplay -v "$gain" "$TTS_FILE" & echo $! > "$PLAYER_PID_FILE"
    ppid="$(cat "$PLAYER_PID_FILE" 2>/dev/null || true)"
    ppid="${ppid//[[:space:]]/}"
    if [[ "$ppid" =~ ^[0-9]+$ ]]; then
      wait "$ppid" 2>/dev/null || true
    fi
    : > "$TTS_FILE" 2>/dev/null || true
    : > "$GEN_PID_FILE" 2>/dev/null || true
    : > "$PLAYER_PID_FILE" 2>/dev/null || true
    if ! is_enabled; then
      break
    fi
    if [[ "$(pending_get)" -le 0 ]]; then
      break
    fi
    pending_dec
    if [[ "$loop_mode" == "full" ]]; then
      loop_file="$LAST_FULL_FILE"
    else
      loop_file="$LAST_SUMMARY_FILE"
    fi
    words="$(wc -w < "$loop_file" 2>/dev/null | tr -d ' ' || echo 40)"
    set_playing_until_for_words "$words" >/dev/null 2>&1 || true
    done
  ) & echo $! > "$PID_FILE" 2>/dev/null || true
}

volume_status() {
  local sys=""
  sys="$(get_system_volume)"
  sys="${sys//[[:space:]]/}"
  local cfg=""
  cfg="$(get_config_volume)"
  if [[ -n "${cfg:-}" ]]; then
    echo "speech=${cfg} system=${sys}"
  else
    echo "speech=system system=${sys}"
  fi
}

volume_preview_at() {
  local v="$1"
  v="${v//[[:space:]]/}"
  if [[ ! "$v" =~ ^[0-9]+$ ]]; then
    v=50
  fi
  local tmp="$RUNTIME_DIR/say.preview.txt"
  printf '%s\n' "Speech volume ${v} percent." > "$tmp" 2>/dev/null || true
  set_playing_until_for_words 8 >/dev/null 2>&1 || true
  speak_text_file "$tmp" 3 >/dev/null 2>&1 || true
}

speed_get() {
  printf '%s\n' "$SPEED"
}

speed_set() {
  local s="$1"
  s="$(python3 -c 'import sys
try:
  v=float(sys.argv[1])
except Exception:
  v=1.0
v=max(0.5,min(2.5,v))
print(f"{v:.2f}".rstrip("0").rstrip("."))
' "$s" 2>/dev/null || echo "1.0")"
  printf '%s\n' "$s" > "$SPEED_FILE" 2>/dev/null || true
  SPEED="$s"
  compute_rate_from_speed >/dev/null 2>&1 || true
  echo "$s"
}

speed_preview() {
  local s="$1"
  local tmp="$RUNTIME_DIR/say.speed.preview.txt"
  printf '%s\n' "Speech speed ${s} times." > "$tmp" 2>/dev/null || true
  local saved_engine="$ENGINE"
  printf '%s\n' "apple" > "$ENGINE_FILE" 2>/dev/null || true
  ENGINE="apple"
  set_playing_until_for_words 8 >/dev/null 2>&1 || true
  speak_text_file "$tmp" 3 >/dev/null 2>&1 || true
  printf '%s\n' "$saved_engine" > "$ENGINE_FILE" 2>/dev/null || true
  ENGINE="$saved_engine"
}

preview_pocket_voice() {
  local v="$1"
  local tmp="$RUNTIME_DIR/say.voice.preview.txt"
  local label="$v"
  label="$(printf '%s' "$label" | python3 -c 'import sys
s=sys.stdin.read().strip()
if not s:
  print("Pocket voice")
  raise SystemExit
print(s[:1].upper()+s[1:])
')"
  printf '%s\n' "Hello, this is ${label}." > "$tmp" 2>/dev/null || true
  pending_set 0
  stop_speech
  set_playing_until_for_words 8 >/dev/null 2>&1 || true
  local saved_engine="$ENGINE"
  local saved_pocket_voice="$POCKET_VOICE"
  ENGINE="pocket"
  POCKET_VOICE="$v"
  speak_text_file "$tmp" 3 >/dev/null 2>&1 || true
  ENGINE="$saved_engine"
  POCKET_VOICE="$saved_pocket_voice"
}

stop_speech() {
  local pid=""
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  pid="${pid//[[:space:]]/}"
  if [[ "$pid" =~ ^[0-9]+$ ]]; then
    kill "$pid" 2>/dev/null || true
  fi
  local gpid=""
  gpid="$(cat "$GEN_PID_FILE" 2>/dev/null || true)"
  gpid="${gpid//[[:space:]]/}"
  if [[ "$gpid" =~ ^[0-9]+$ ]]; then
    kill "$gpid" 2>/dev/null || true
  fi
  local ppid=""
  ppid="$(cat "$PLAYER_PID_FILE" 2>/dev/null || true)"
  ppid="${ppid//[[:space:]]/}"
  if [[ "$ppid" =~ ^[0-9]+$ ]]; then
    kill "$ppid" 2>/dev/null || true
  fi
  if [[ "$KILL_ALL_SAY" == "1" ]]; then
    pkill -x say 2>/dev/null || true
  fi
  : > "$PID_FILE" 2>/dev/null || true
  : > "$UNTIL_FILE" 2>/dev/null || true
  : > "$GEN_PID_FILE" 2>/dev/null || true
  : > "$PLAYER_PID_FILE" 2>/dev/null || true
  cancel_restore_timer
  restore_volume_now
}

is_playing() {
  local pid=""
  pid="$(cat "$PLAYER_PID_FILE" 2>/dev/null || true)"
  pid="${pid//[[:space:]]/}"
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  pid="$(cat "$GEN_PID_FILE" 2>/dev/null || true)"
  pid="${pid//[[:space:]]/}"
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  pid="${pid//[[:space:]]/}"
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  local until=""
  until="$(cat "$UNTIL_FILE" 2>/dev/null || true)"
  until="${until//[[:space:]]/}"
  if [[ ! "$until" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  local now=""
  now="$(date +%s 2>/dev/null || echo 0)"
  if [[ "$now" =~ ^[0-9]+$ ]] && (( now < until )); then
    return 0
  fi
  return 1
}

remaining_seconds() {
  local until=""
  until="$(cat "$UNTIL_FILE" 2>/dev/null || true)"
  until="${until//[[:space:]]/}"
  if [[ ! "$until" =~ ^[0-9]+$ ]]; then
    echo 0
    return 0
  fi
  local now=""
  now="$(date +%s 2>/dev/null || echo 0)"
  if [[ ! "$now" =~ ^[0-9]+$ ]]; then
    echo 0
    return 0
  fi
  local rem=$(( until - now ))
  if (( rem < 0 )); then rem=0; fi
  echo "$rem"
}

set_playing_until_for_words() {
  local words="$1"
  local rate="${RATE}"
  if [[ ! "$rate" =~ ^[0-9]+$ ]] || (( rate <= 0 )); then
    rate=210
  fi
  local seconds=""
  seconds="$(python3 -c 'import math,sys
words=int(sys.argv[1]); rate=int(sys.argv[2])
secs=int(math.ceil((words*60)/max(rate,1))) + 1
print(min(max(secs,2), 600))
' "$words" "$rate" 2>/dev/null || echo 10)"
  local now=""
  now="$(date +%s 2>/dev/null || echo 0)"
  if [[ ! "$now" =~ ^[0-9]+$ ]]; then now=0; fi
  if [[ ! "$seconds" =~ ^[0-9]+$ ]]; then seconds=10; fi
  printf '%s\n' "$(( now + seconds ))" > "$UNTIL_FILE" 2>/dev/null || true
  echo "$seconds"
}

set_playing_until_for_text() {
  local text="$1"
  local words=""
  words="$(printf '%s' "$text" | wc -w | tr -d ' ')"
  if [[ ! "$words" =~ ^[0-9]+$ ]]; then
    words=20
  fi
  set_playing_until_for_words "$words"
}

say_last() {
  stop_speech
  local target="$LAST_TEXT_FILE"
  if [[ "$MODE" == "full" ]]; then
    target="$LAST_FULL_FILE"
  fi
  if [[ ! -s "$target" ]]; then
    set_playing_until_for_words 6 >/dev/null 2>&1 || true
    (say -v "$VOICE" -r "$RATE" "Codex finished." & echo $! > "$PID_FILE") >/dev/null 2>&1 || true
    exit 0
  fi
  local target_words=""
  target_words="$(wc -w < "$target" 2>/dev/null | tr -d ' ' || true)"
  if [[ "$target_words" =~ ^[0-9]+$ ]]; then
    seconds="$(set_playing_until_for_words "$target_words" 2>/dev/null || echo 10)"
  else
    seconds="$(set_playing_until_for_words 40 2>/dev/null || echo 10)"
  fi
  speak_text_file "$target" "${seconds:-10}" >/dev/null 2>&1 || true
}

say_full() {
  local prev="$MODE"
  MODE="full"
  say_last
  MODE="$prev"
}

toggle() {
  if is_enabled; then
    set_state "disabled"
    stop_speech
  else
    set_state "enabled"
  fi
}

toggle_play() {
  if is_playing; then
    stop_speech
  else
    say_last
  fi
}

status() {
  if is_enabled; then
    echo "enabled"
  else
    echo "disabled"
  fi
}

trim_to_max_chars() {
  python3 -c 'import sys
max_chars = int(sys.argv[1])
text = sys.stdin.read()
if len(text) <= max_chars:
    sys.stdout.write(text)
else:
    sys.stdout.write(text[:max_chars].rstrip() + "\n\n[truncated]\n")
' "$MAX_CHARS"
}

extract_text_best_effort() {
  python3 -c 'import json, sys
raw = sys.stdin.read()
raw_stripped = raw.strip()
if not raw_stripped:
    sys.exit(0)

PREFERRED_KEYS = (
    "last-assistant-message",
    "last_assistant_message",
    "assistant_message",
    "assistant",
    "text",
    "message",
    "content",
    "response",
    "output",
)

def first_string(o):
    if isinstance(o, str):
        return o
    if isinstance(o, dict):
        for k in PREFERRED_KEYS:
            v = o.get(k)
            if isinstance(v, str) and v.strip():
                return v
        for v in o.values():
            s = first_string(v)
            if s and s.strip():
                return s
    if isinstance(o, list):
        for it in o:
            s = first_string(it)
            if s and s.strip():
                return s
    return None

if raw_stripped[:1] in "{[":
    try:
        obj = json.loads(raw_stripped)
        s = first_string(obj)
        if s and s.strip():
            sys.stdout.write(s)
            sys.exit(0)
    except Exception:
        pass

sys.stdout.write(raw)
'
}

summarize_for_speech() {
  python3 -c 'import re, sys
text = sys.stdin.read()
if not text.strip():
    sys.exit(0)

text = text.replace("\r\n", "\n").replace("\r", "\n")
text = re.sub(r"```.*?```", "", text, flags=re.S)
text = re.sub(r"(?:^|\n)(?:[ \t]{4,}.*(?:\n|$))+", "\n", text)

lines = [ln.rstrip() for ln in text.split("\n")]

def is_test_heading(ln):
    s = ln.strip()
    if not s:
        return False
    return re.match(r"^(?:#{1,6}\s*)?(?:\*\*)?\s*Test(?:s|ing)?\s*(?:\*\*)?\s*:?\s*$", s, flags=re.I) is not None

cut_idx = None
for i, ln in enumerate(lines):
    if is_test_heading(ln):
        cut_idx = i
        break
if cut_idx is not None:
    lines = lines[:cut_idx]

def looks_like_code_line(ln):
    s = ln.strip()
    if not s:
        return False
    s = s.replace("`", "")
    if s.startswith(("diff ", "@@", "+++ ", "--- ")):
        return True
    if s.startswith(("#include", "import ", "from ", "class ", "def ", "fn ", "package ", "use ")):
        return True
    if s.startswith(("const ", "let ", "var ", "function ", "public ", "private ", "protected ")):
        return True
    symbols = sum((ch in "{}[]();=<>$#&|*`") for ch in s)
    if len(s) >= 20 and (float(symbols) / float(len(s))) > 0.18:
        return True
    if len(s) > 160:
        return True
    return False

max_bullets = int(sys.argv[1])
max_chars = int(sys.argv[2])

bullets = []
for ln in lines:
    s = ln.strip()
    if not s:
        continue
    if re.match(r"^(\-|\*|\d+[\.\)])\s+", s):
        content = re.sub(r"^(\-|\*|\d+[\.\)])\s+", "", s).strip()
        if content and not looks_like_code_line(content):
            bullets.append(s)

if bullets:
    out = "\n".join(bullets[:max_bullets])
else:
    filtered = [ln for ln in lines if not looks_like_code_line(ln)]
    out = "\n".join(filtered)

out = out.replace("`", " ")
out = re.sub(r"[ \t]+", " ", out)
out = re.sub(r"\n{3,}", "\n\n", out).strip()

def shorten_tokens(s):
    # Turn paths like app/foo/bar/file.dart:123 into just "file"
    exts = r"(?:dart|ts|tsx|js|jsx|py|go|rs|java|kt|swift|m|mm|c|cc|cpp|h|hpp|html|css|json|yml|yaml|toml|md)"
    s = re.sub(r"(?<![A-Za-z0-9_])(?:~?/)?(?:[A-Za-z0-9_.-]+/)+([A-Za-z0-9_.-]+)\.(" + exts + r")(?::\d+)?", r"\1", s)
    # Also handle bare filenames like file.dart:123 (drop extension + line)
    s = re.sub(r"\b([A-Za-z0-9_.-]+)\.(" + exts + r")(?::\d+)?\b", r"\1", s)
    # If a generated/test suffix remains (e.g. foo.g), drop it.
    s = re.sub(r"\b([A-Za-z0-9_-]+)\.(?:g|gen|test|spec|mock|mocks|stories|story)\b", r"\1", s)
    # Drop small line numbers after colons (e.g. foo:123 -> foo)
    s = re.sub(r"\b([A-Za-z0-9_-]{2,})\s*:\s*\d{1,6}\b", r"\1", s)
    s = re.sub(r"\b\d{7,}\b", "number", s)
    s = re.sub(r"\d{7,}", "number", s)
    s = re.sub(r"\b[0-9a-fA-F]{16,}\b", "hex", s)
    s = re.sub(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b", "id", s)
    def repl(m):
        t = m.group(0)
        return t[:12] + "…" + t[-6:]
    s = re.sub(r"\b[A-Za-z_][A-Za-z0-9_]{30,}\b", repl, s)
    return s

out = shorten_tokens(out)
if len(out) > max_chars:
    out = out[:max_chars].rstrip() + "\n\n[summary truncated]\n"

sys.stdout.write(out)
' "$SUMMARY_MAX_BULLETS" "$SUMMARY_MAX_CHARS"
}

subcmd="${1:-}"
case "$subcmd" in
  stop) stop_speech; exit 0 ;;
  __pending-watch)
    for ((i=0; i<2400; i++)); do
      if is_playing; then
        sleep 0.25
        continue
      fi
      break
    done
    if is_enabled && [[ "$(pending_get)" -gt 0 ]]; then
      pending_set 0
      "$0" replay >/dev/null 2>&1 || true
    fi
    : > "$PENDING_WATCHER_PID_FILE" 2>/dev/null || true
    exit 0
    ;;
  pending)
    action="${2:-get}"
    if [[ "$action" == "clear" ]]; then
      pending_set 0
      echo 0
      exit 0
    fi
    pending_get
    exit 0
    ;;
  pocket-speed|pocket_speed)
    action="${2:-get}"
    if [[ "$action" == "reset" ]]; then
      echo "reset"
      exit 0
    fi
    echo "afplay"
    exit 0
    ;;
  speed)
    action="${2:-}"
    if [[ -z "${action:-}" ]] || [[ "$action" == "get" ]]; then
      speed_get
      exit 0
    fi
    if [[ "$action" == "set" ]]; then
      v="${3:-}"
    else
      v="$action"
    fi
    if [[ "$v" == "up" || "$v" == "down" ]]; then
      cur="$(speed_get)"
      step="$SPEED_STEP"
      if [[ "$v" == "down" ]]; then
        step="$(python3 -c 'import sys; print(-abs(float(sys.argv[1])))' "$SPEED_STEP" 2>/dev/null || echo "-0.1")"
      fi
      next="$(python3 -c 'import sys
cur=float(sys.argv[1]); step=float(sys.argv[2])
print(cur+step)
' "$cur" "$step" 2>/dev/null || echo "$cur")"
      out="$(speed_set "$next")"
      if [[ "${CODEX_SAY_SPEED_AUTO_PREVIEW:-1}" == "1" ]]; then
        speed_preview "$out" >/dev/null 2>&1 || true
      fi
      exit 0
    fi
    if [[ "$v" == "preview" ]]; then
      cur="$(speed_get)"
      speed_preview "$cur" >/dev/null 2>&1 || true
      exit 0
    fi
    out="$(speed_set "$v")"
    if [[ "${CODEX_SAY_SPEED_AUTO_PREVIEW:-1}" == "1" ]]; then
      speed_preview "$out" >/dev/null 2>&1 || true
    fi
    exit 0
    ;;
  select)
    eng="${2:-}"
    v="${3:-}"
    if [[ "$eng" == "apple" ]]; then
      if [[ -z "${v:-}" ]]; then exit 1; fi
      printf '%s\n' "apple" > "$ENGINE_FILE" 2>/dev/null || true
      printf '%s\n' "$v" > "$VOICE_FILE" 2>/dev/null || true
      ENGINE="apple"
      VOICE="$v"
      echo "apple:$v"
      exit 0
    fi
    if [[ "$eng" == "pocket" ]]; then
      if [[ -z "${v:-}" ]]; then exit 1; fi
      printf '%s\n' "pocket" > "$ENGINE_FILE" 2>/dev/null || true
      printf '%s\n' "$v" > "$POCKET_VOICE_FILE" 2>/dev/null || true
      ENGINE="pocket"
      POCKET_VOICE="$v"
      if [[ "${4:-}" == "--preview" ]]; then
        preview_pocket_voice "$v" >/dev/null 2>&1 || true
      fi
      echo "pocket:$v"
      exit 0
    fi
    exit 1
    ;;
  engine)
    action="${2:-}"
    if [[ -z "${action:-}" ]] || [[ "$action" == "get" ]]; then
      echo "$ENGINE"
      exit 0
    fi
    if [[ "$action" == "set" ]]; then
      v="${3:-}"
    else
      v="$action"
    fi
    if [[ "$v" != "apple" && "$v" != "pocket" ]]; then
      exit 1
    fi
    printf '%s\n' "$v" > "$ENGINE_FILE" 2>/dev/null || true
    echo "$v"
    exit 0
    ;;
  pocket-voice|pocket_voice)
    action="${2:-}"
    if [[ -z "${action:-}" ]] || [[ "$action" == "get" ]]; then
      echo "$POCKET_VOICE"
      exit 0
    fi
    if [[ "$action" == "set" ]]; then
      v="${3:-}"
    else
      v="$action"
    fi
    if [[ -z "${v:-}" ]]; then
      exit 1
    fi
    printf '%s\n' "$v" > "$POCKET_VOICE_FILE" 2>/dev/null || true
    echo "$v"
    exit 0
    ;;
  voices) say -v '?' 2>/dev/null || true; exit 0 ;;
  voice)
    action="${2:-}"
    if [[ -z "${action:-}" ]] || [[ "$action" == "get" ]]; then
      v="$(cat "$VOICE_FILE" 2>/dev/null || true)"
      v="${v//$'\n'/}"
      if [[ -n "${v:-}" ]]; then
        echo "$v"
      else
        echo "$VOICE"
      fi
      exit 0
    fi
    if [[ "$action" == "list" ]]; then
      say -v '?' 2>/dev/null || true
      exit 0
    fi
    if [[ "$action" == "set" ]]; then
      v="${3:-}"
    else
      v="$action"
    fi
    if [[ -z "${v:-}" ]]; then
      exit 1
    fi
    printf '%s\n' "$v" > "$VOICE_FILE" 2>/dev/null || true
    echo "$v"
    exit 0
    ;;
  volume)
    arg="${2:-}"
    if [[ -z "${arg:-}" ]] || [[ "$arg" == "get" ]]; then
      cfg="$(get_config_volume)"
      if [[ -n "${cfg:-}" ]]; then
        echo "$cfg"
      else
        get_system_volume
      fi
      exit 0
    fi
    if [[ "$arg" == "status" ]]; then
      volume_status
      exit 0
    fi
    if [[ "$arg" == "preview" ]]; then
      cfg="$(get_config_volume)"
      if [[ -z "${cfg:-}" ]]; then
        cfg="50"
      fi
      cfg="${cfg//[[:space:]]/}"
      if [[ ! "$cfg" =~ ^[0-9]+$ ]]; then
        cfg=50
      fi
      set_playing_until_for_words 8 >/dev/null 2>&1 || true
      old_cfg="$(get_config_volume)"
      set_config_volume "$cfg" >/dev/null 2>&1 || true
      volume_preview_at "$cfg"
      if [[ -n "${old_cfg:-}" ]]; then
        set_config_volume "$old_cfg" >/dev/null 2>&1 || true
      else
        clear_config_volume
      fi
      exit 0
    fi
    if [[ "$arg" == "clear" ]] || [[ "$arg" == "system" ]]; then
      clear_config_volume
      cancel_restore_timer
      restore_volume_now
      echo "system"
      exit 0
    fi
    if [[ "$arg" == "up" ]] || [[ "$arg" == "down" ]]; then
      cur="$(get_config_volume)"
      if [[ -z "${cur:-}" ]]; then
        cur="$(get_system_volume)"
      fi
      cur="${cur//[[:space:]]/}"
      if [[ ! "$cur" =~ ^[0-9]+$ ]]; then
        cur=50
      fi
      step="${CODEX_SAY_VOLUME_STEP:-10}"
      if [[ ! "$step" =~ ^[0-9]+$ ]]; then step=10; fi
      if [[ "$arg" == "up" ]]; then
        new=$((cur + step))
      else
        new=$((cur - step))
      fi
      set_config_volume "$new" || true
      newv="$(get_config_volume)"
      echo "$newv"
      if [[ "$VOLUME_AUTO_PREVIEW" == "1" ]]; then
        volume_preview_at "$newv"
      fi
      exit 0
    fi
    if [[ "$arg" == "set" ]]; then
      val="${3:-}"
    else
      val="$arg"
    fi
    set_config_volume "$val" || true
    newv="$(get_config_volume)"
    echo "$newv"
    if [[ "$VOLUME_AUTO_PREVIEW" == "1" ]]; then
      volume_preview_at "$newv"
    fi
    exit 0
    ;;
  playing) is_playing && echo "playing" || echo "idle"; exit 0 ;;
  remaining) remaining_seconds; exit 0 ;;
  toggle-play) toggle_play; exit 0 ;;
  play-full|replay-full|full) say_full; exit 0 ;;
  play|replay) say_last; exit 0 ;;
  toggle) toggle; exit 0 ;;
  status) status; exit 0 ;;
  *) ;;
esac

raw_payload=""
if [[ "$#" -gt 0 ]]; then
  raw_payload="$1"
elif [[ ! -t 0 ]]; then
  raw_payload="$(cat 2>/dev/null || true)"
elif [[ -n "${CODEX_NOTIFY_TEXT:-}" ]]; then
  raw_payload="$CODEX_NOTIFY_TEXT"
elif [[ -n "${CODEX_TEXT:-}" ]]; then
  raw_payload="$CODEX_TEXT"
elif [[ -n "${CODEX_MESSAGE:-}" ]]; then
  raw_payload="$CODEX_MESSAGE"
else
  raw_payload="Codex finished."
fi

full_text="$(printf '%s' "$raw_payload" | extract_text_best_effort | trim_to_max_chars)"
summary_text="$(printf '%s' "$full_text" | summarize_for_speech)"
if [[ -z "${summary_text//[[:space:]]/}" ]]; then
  summary_text="Codex finished."
fi

full_text="$(printf '%s' "$full_text" | tr '\r' '\n')"
summary_text="$(printf '%s' "$summary_text" | tr '\r' '\n')"

printf '%s\0%s' "$full_text" "$summary_text" | python3 -c 'import sys
from pathlib import Path
full_path, summary_path, compat_path = sys.argv[1:4]
data = sys.stdin.buffer.read()
parts = data.split(b"\0", 1)
full = parts[0].decode("utf-8", "ignore")
summary = (parts[1].decode("utf-8", "ignore") if len(parts) > 1 else "")
for p, v in ((full_path, full), (summary_path, summary), (compat_path, summary)):
    try:
        Path(p).write_text(v + "\n", encoding="utf-8")
    except Exception:
        pass
' "$LAST_FULL_FILE" "$LAST_SUMMARY_FILE" "$LAST_TEXT_FILE" >/dev/null 2>&1 || true

notifier_maybe_speak() {
  if is_playing && [[ "$INTERRUPT" != "1" ]]; then
    pending_inc
    return 0
  fi
  pending_set 0
  stop_speech
  if ! is_enabled; then
    return 0
  fi
  if [[ "$MODE" == "full" ]]; then
    seconds="$(set_playing_until_for_words "$(printf '%s' "$full_text" | wc -w | tr -d ' ')" 2>/dev/null || echo 10)"
    speak_text_file "$LAST_FULL_FILE" "${seconds:-10}" >/dev/null 2>&1 || true
  else
    seconds="$(set_playing_until_for_words "$(printf '%s' "$summary_text" | wc -w | tr -d ' ')" 2>/dev/null || echo 10)"
    speak_text_file "$LAST_SUMMARY_FILE" "${seconds:-10}" >/dev/null 2>&1 || true
  fi
}

with_lock notifier_maybe_speak >/dev/null 2>&1 || true
