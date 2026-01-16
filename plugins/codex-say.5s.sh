#!/usr/bin/env bash
set -euo pipefail

SAY="$HOME/.codex/say.sh"

status="disabled"
playing="idle"
vol=""
rem="0"
vol_status=""
engine="apple"
pocket_voice="alba"
apple_voice=""
speed="1"
pending="0"
if [[ -x "$SAY" ]]; then
  status="$("$SAY" status 2>/dev/null || echo disabled)"
  playing="$("$SAY" playing 2>/dev/null || echo idle)"
  vol="$("$SAY" volume get 2>/dev/null || true)"
  vol_status="$("$SAY" volume status 2>/dev/null || true)"
  rem="$("$SAY" remaining 2>/dev/null || echo 0)"
  engine="$("$SAY" engine 2>/dev/null || echo apple)"
  pocket_voice="$("$SAY" pocket-voice 2>/dev/null || echo alba)"
  apple_voice="$("$SAY" voice 2>/dev/null || true)"
  speed="$("$SAY" speed get 2>/dev/null || echo 1)"
  pending="$("$SAY" pending get 2>/dev/null || echo 0)"
fi

engine_label="Fast"
if [[ "$engine" == "pocket" ]]; then
  engine_label="Slow"
fi
vol_label="system"
if [[ -n "${vol:-}" ]]; then
  vol_label="${vol}%"
fi
queue_label=""
if [[ "${pending:-0}" != "0" ]]; then
  queue_label=", q${pending}"
fi

if [[ "$status" == "enabled" && "$playing" == "playing" ]]; then
  echo "■ SPEAKING (${engine_label}, ${vol_label}, ${speed}x${queue_label}) | color=orange bash=\"$SAY\" param1=\"toggle-play\" terminal=false refresh=true"
elif [[ "$status" == "enabled" ]]; then
  echo "▶︎ READY (${engine_label}, ${vol_label}, ${speed}x${queue_label}) | color=yellow bash=\"$SAY\" param1=\"toggle-play\" terminal=false refresh=true"
else
  echo "SPEAK: OFF | color=red bash=\"$SAY\" param1=\"toggle\" terminal=false refresh=true"
fi

echo "---"
echo "Voice | color=gray"
if [[ "$engine" == "apple" ]]; then
  echo "Current: ${apple_voice} (Fast) | color=gray"
else
  echo "Current: ${pocket_voice} (Slow) | color=gray"
fi
echo "List Apple Voices | bash=\"$SAY\" param1=\"voice\" param2=\"list\" terminal=true"

echo "Apple | color=gray"
for v in Alex Samantha Daniel Fred; do
  prefix=""
  if [[ "$engine" == "apple" && "$apple_voice" == "$v" ]]; then
    prefix="✓ "
  fi
  echo "${prefix}${v} (Fast) | bash=\"$SAY\" param1=\"select\" param2=\"apple\" param3=\"$v\" terminal=false refresh=true"
done

echo "Slow (Pocket TTS) | color=gray"
for v in alba marius javert jean fantine cosette eponine azelma; do
  prefix=""
  if [[ "$engine" == "pocket" && "$pocket_voice" == "$v" ]]; then
    prefix="✓ "
  fi
  echo "${prefix}${v} (Slow) | bash=\"$SAY\" param1=\"select\" param2=\"pocket\" param3=\"$v\" terminal=false refresh=true"
done

echo "---"
if [[ "$status" == "enabled" ]]; then
  echo "Play/Stop | bash=\"$SAY\" param1=\"toggle-play\" terminal=false refresh=true"
fi
if [[ "${pending:-0}" != "0" ]]; then
  echo "Clear queue | bash=\"$SAY\" param1=\"pending\" param2=\"clear\" terminal=false refresh=true"
fi
echo "Toggle | bash=\"$SAY\" param1=\"toggle\" terminal=false refresh=true"
echo "Replay last | bash=\"$SAY\" param1=\"replay\" terminal=false"
echo "Replay full | bash=\"$SAY\" param1=\"replay-full\" terminal=false"
echo "Stop | bash=\"$SAY\" param1=\"stop\" terminal=false"

echo "---"
if [[ -n "${vol:-}" ]]; then
  echo "Volume: ${vol}% | color=gray"
else
  echo "Volume | color=gray"
fi
if [[ -n "${vol_status:-}" ]]; then
  echo "${vol_status} | color=gray"
fi
echo "Preview | bash=\"$SAY\" param1=\"volume\" param2=\"preview\" terminal=false refresh=true"
echo "Vol 100% | bash=\"$SAY\" param1=\"volume\" param2=\"100\" terminal=false refresh=true"
echo "Vol 80% | bash=\"$SAY\" param1=\"volume\" param2=\"80\" terminal=false refresh=true"
echo "Vol 60% | bash=\"$SAY\" param1=\"volume\" param2=\"60\" terminal=false refresh=true"
echo "Vol 40% | bash=\"$SAY\" param1=\"volume\" param2=\"40\" terminal=false refresh=true"
echo "Vol 20% | bash=\"$SAY\" param1=\"volume\" param2=\"20\" terminal=false refresh=true"
echo "Vol Up | bash=\"$SAY\" param1=\"volume\" param2=\"up\" terminal=false refresh=true"
echo "Vol Down | bash=\"$SAY\" param1=\"volume\" param2=\"down\" terminal=false refresh=true"
echo "Use System Volume | bash=\"$SAY\" param1=\"volume\" param2=\"system\" terminal=false refresh=true"

echo "---"
echo "Speed: ${speed}x | color=gray"
echo "Preview | bash=\"$SAY\" param1=\"speed\" param2=\"preview\" terminal=false refresh=true"
echo "0.75x | bash=\"$SAY\" param1=\"speed\" param2=\"0.75\" terminal=false refresh=true"
echo "1.0x | bash=\"$SAY\" param1=\"speed\" param2=\"1.0\" terminal=false refresh=true"
echo "1.25x | bash=\"$SAY\" param1=\"speed\" param2=\"1.25\" terminal=false refresh=true"
echo "1.5x | bash=\"$SAY\" param1=\"speed\" param2=\"1.5\" terminal=false refresh=true"
echo "1.75x | bash=\"$SAY\" param1=\"speed\" param2=\"1.75\" terminal=false refresh=true"
echo "2.0x | bash=\"$SAY\" param1=\"speed\" param2=\"2.0\" terminal=false refresh=true"
echo "Faster | bash=\"$SAY\" param1=\"speed\" param2=\"up\" terminal=false refresh=true"
echo "Slower | bash=\"$SAY\" param1=\"speed\" param2=\"down\" terminal=false refresh=true"
