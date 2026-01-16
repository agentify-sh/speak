#!/usr/bin/env bash
set -euo pipefail

SAY="$HOME/.codex/say.sh"

status="disabled"
playing="idle"
rem="0"
engine="apple"
speed="1"
vol="system"
pending="0"
apple_voice="Samantha"
pocket_voice="alba"
if [[ -x "$SAY" ]]; then
  while IFS='=' read -r k v; do
    case "$k" in
      status) status="$v" ;;
      playing) playing="$v" ;;
      rem) rem="$v" ;;
      engine) engine="$v" ;;
      speed) speed="$v" ;;
      vol) vol="$v" ;;
      pending) pending="$v" ;;
      apple_voice) apple_voice="$v" ;;
      pocket_voice) pocket_voice="$v" ;;
    esac
  done < <("$SAY" snapshot 2>/dev/null || true)
fi

engine_label="Fast"
if [[ "$engine" == "pocket" ]]; then
  engine_label="Slow"
fi
vol_label="${vol:-system}"
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
for v in Alex Samantha Daniel Fred; do
  prefix=""
  if [[ "$engine" == "apple" && "$apple_voice" == "$v" ]]; then
    prefix="✓ "
  fi
  echo "${prefix}${v} (Fast) | bash=\"$SAY\" param1=\"select\" param2=\"apple\" param3=\"$v\" terminal=false refresh=true"
done

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
echo "Vol 100% | bash=\"$SAY\" param1=\"volume\" param2=\"100\" terminal=false refresh=true"
echo "Vol 80% | bash=\"$SAY\" param1=\"volume\" param2=\"80\" terminal=false refresh=true"
echo "Vol 60% | bash=\"$SAY\" param1=\"volume\" param2=\"60\" terminal=false refresh=true"
echo "Vol 40% | bash=\"$SAY\" param1=\"volume\" param2=\"40\" terminal=false refresh=true"
echo "Vol 20% | bash=\"$SAY\" param1=\"volume\" param2=\"20\" terminal=false refresh=true"

echo "---"
echo "0.75x | bash=\"$SAY\" param1=\"speed\" param2=\"0.75\" terminal=false refresh=true"
echo "1.0x | bash=\"$SAY\" param1=\"speed\" param2=\"1.0\" terminal=false refresh=true"
echo "1.25x | bash=\"$SAY\" param1=\"speed\" param2=\"1.25\" terminal=false refresh=true"
echo "1.5x | bash=\"$SAY\" param1=\"speed\" param2=\"1.5\" terminal=false refresh=true"
echo "1.75x | bash=\"$SAY\" param1=\"speed\" param2=\"1.75\" terminal=false refresh=true"
echo "2.0x | bash=\"$SAY\" param1=\"speed\" param2=\"2.0\" terminal=false refresh=true"
