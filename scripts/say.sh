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

VOICE="${CODEX_SAY_VOICE:-Samantha}"
RATE="${CODEX_SAY_RATE:-210}"
MAX_CHARS="${CODEX_SAY_MAX_CHARS:-8000}"
SUMMARY_MAX_CHARS="${CODEX_SAY_SUMMARY_MAX_CHARS:-2400}"
SUMMARY_MAX_BULLETS="${CODEX_SAY_SUMMARY_MAX_BULLETS:-15}"
MODE="${CODEX_SAY_MODE:-summary}" # summary|full

DEBUG="${CODEX_SAY_DEBUG:-0}"
KILL_ALL_SAY="${CODEX_SAY_KILL_ALL:-0}"

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

set_state() {
  printf '%s\n' "$1" > "$STATE_FILE" 2>/dev/null || true
}

stop_speech() {
  local pid=""
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  pid="${pid//[[:space:]]/}"
  if [[ "$pid" =~ ^[0-9]+$ ]]; then
    kill "$pid" 2>/dev/null || true
  fi
  if [[ "$KILL_ALL_SAY" == "1" ]]; then
    pkill -x say 2>/dev/null || true
  fi
  : > "$PID_FILE" 2>/dev/null || true
  : > "$UNTIL_FILE" 2>/dev/null || true
}

is_playing() {
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
    set_playing_until_for_words 6
    (say -v "$VOICE" -r "$RATE" "Codex finished." & echo $! > "$PID_FILE") >/dev/null 2>&1 || true
    exit 0
  fi
  local target_words=""
  target_words="$(wc -w < "$target" 2>/dev/null | tr -d ' ' || true)"
  if [[ "$target_words" =~ ^[0-9]+$ ]]; then
    set_playing_until_for_words "$target_words"
  else
    set_playing_until_for_words 40
  fi
  (say -v "$VOICE" -r "$RATE" -f "$target" & echo $! > "$PID_FILE") >/dev/null 2>&1 || true
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
    if re.match(r"^(\-|\*|\d+[\.\)])\s+", s) and not looks_like_code_line(s):
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
  playing) is_playing && echo "playing" || echo "idle"; exit 0 ;;
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
summary_text="$(printf '%s' "$summary_text" | tr '\r' '\n' | sed -E 's/[[:space:]]+/ /g')"

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

stop_speech
if ! is_enabled; then
  exit 0
fi

if [[ "$MODE" == "full" ]]; then
  set_playing_until_for_text "$full_text"
  (say -v "$VOICE" -r "$RATE" "$full_text" & echo $! > "$PID_FILE") >/dev/null 2>&1 || true
else
  set_playing_until_for_text "$summary_text"
  (say -v "$VOICE" -r "$RATE" "$summary_text" & echo $! > "$PID_FILE") >/dev/null 2>&1 || true
fi

