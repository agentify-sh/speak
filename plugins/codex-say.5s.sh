#!/usr/bin/env bash
set -euo pipefail

SAY="$HOME/.codex/say.sh"

status="disabled"
playing="idle"
if [[ -x "$SAY" ]]; then
  status="$("$SAY" status 2>/dev/null || echo disabled)"
  playing="$("$SAY" playing 2>/dev/null || echo idle)"
fi

if [[ "$status" == "enabled" && "$playing" == "playing" ]]; then
  echo "Codex Say: Speaking | color=green bash=\"$SAY\" param1=\"toggle-play\" terminal=false refresh=true"
elif [[ "$status" == "enabled" ]]; then
  echo "Codex Say: Ready | color=green bash=\"$SAY\" param1=\"toggle-play\" terminal=false refresh=true"
else
  echo "Codex Say: Off | color=red bash=\"$SAY\" param1=\"toggle\" terminal=false refresh=true"
fi

echo "---"
if [[ "$status" == "enabled" ]]; then
  echo "Play/Stop | bash=\"$SAY\" param1=\"toggle-play\" terminal=false refresh=true"
fi
echo "Toggle | bash=\"$SAY\" param1=\"toggle\" terminal=false refresh=true"
echo "Replay last | bash=\"$SAY\" param1=\"replay\" terminal=false"
echo "Replay full | bash=\"$SAY\" param1=\"replay-full\" terminal=false"
echo "Stop | bash=\"$SAY\" param1=\"stop\" terminal=false"

