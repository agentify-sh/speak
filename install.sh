#!/usr/bin/env bash
set -euo pipefail

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing dependency: $1" >&2; exit 1; }
}

need_cmd bash
need_cmd python3
need_cmd defaults

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CODEX_HOME="${CODEX_HOME:-"$HOME/.codex"}"
SAY_DST="$CODEX_HOME/say.sh"
CONFIG_TOML="$CODEX_HOME/config.toml"

SWIFTBAR_APP="/Applications/SwiftBar.app"
SWIFTBAR_PLUGIN_DIR="${SWIFTBAR_PLUGIN_DIR:-"${SWIFTBAR_PLUGIN_DIR:-"$HOME/Documents/SwiftBar"}"}"
PLUGIN_DST="$SWIFTBAR_PLUGIN_DIR/codex-say.5s.sh"
INSTALL_SWIFTBAR="${INSTALL_SWIFTBAR:-1}"
INSTALL_UV="${INSTALL_UV:-1}"
WARM_POCKET_TTS="${WARM_POCKET_TTS:-0}"

mkdir -p "$CODEX_HOME"
mkdir -p "$SWIFTBAR_PLUGIN_DIR"

cp -f "$ROOT_DIR/scripts/say.sh" "$SAY_DST"
chmod +x "$SAY_DST"

cp -f "$ROOT_DIR/plugins/codex-say.5s.sh" "$PLUGIN_DST"
chmod +x "$PLUGIN_DST"

ensure_brew() {
  command -v brew >/dev/null 2>&1
}

install_swiftbar_if_missing() {
  if [[ -d "$SWIFTBAR_APP" ]]; then
    return 0
  fi
  if [[ "$INSTALL_SWIFTBAR" != "1" ]]; then
    return 0
  fi
  if ensure_brew; then
    echo "SwiftBar not found; installing via Homebrew..."
    brew install --cask swiftbar || true
  else
    echo "SwiftBar not found and Homebrew is missing." >&2
    echo "Install SwiftBar: brew install --cask swiftbar" >&2
  fi
}

install_uv_if_missing() {
  if command -v uvx >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$INSTALL_UV" != "1" ]]; then
    return 0
  fi
  if ensure_brew; then
    echo "uv not found; installing via Homebrew..."
    brew install uv || true
  else
    echo "uv not found and Homebrew is missing." >&2
    echo "Install uv: https://docs.astral.sh/uv/" >&2
  fi
}

# Install SwiftBar if missing (best effort).
install_swiftbar_if_missing
install_uv_if_missing

if [[ "$WARM_POCKET_TTS" == "1" ]] && command -v uvx >/dev/null 2>&1; then
  # Best-effort warmup (downloads deps into uv cache). Safe to skip.
  uvx pocket-tts generate --help >/dev/null 2>&1 || true
fi

# Configure SwiftBar plugin directory (so the effect is immediate).
defaults write com.ameba.SwiftBar PluginDirectory -string "$SWIFTBAR_PLUGIN_DIR" || true

# Ensure Codex notify points at ~/.codex/say.sh (merge with existing notify list if present).
python3 - "$CONFIG_TOML" "$SAY_DST" <<'PY'
import os
import re
import sys
from pathlib import Path

config_path = Path(sys.argv[1]).expanduser()
say_path = sys.argv[2]

config_path.parent.mkdir(parents=True, exist_ok=True)
text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""

lines = text.splitlines()

notify_line_idx = None
for i, ln in enumerate(lines):
    if re.match(r"^\s*notify\s*=", ln):
        notify_line_idx = i
        break

def format_notify(paths):
    paths = list(dict.fromkeys(paths))
    inner = ", ".join([f"\"{p}\"" for p in paths])
    return f"notify = [{inner}]"

def parse_notify_list(ln):
    m = re.match(r"^\s*notify\s*=\s*\[(.*)\]\s*$", ln)
    if not m:
        return None
    inner = m.group(1).strip()
    if not inner:
        return []
    # Best-effort parse quoted strings; ignore non-strings.
    return re.findall(r"\"([^\"]+)\"", inner)

if notify_line_idx is not None:
    current = parse_notify_list(lines[notify_line_idx])
    if current is None:
        # Replace unparseable notify with minimal safe one.
        lines[notify_line_idx] = format_notify([say_path])
    else:
        if say_path not in current:
            current.append(say_path)
        lines[notify_line_idx] = format_notify(current)
else:
    # Insert near the top (after model line if present), otherwise at top.
    insert_at = 0
    for i, ln in enumerate(lines):
        if re.match(r"^\s*model\s*=", ln):
            insert_at = i + 1
            break
    lines.insert(insert_at, format_notify([say_path]))

new_text = "\n".join(lines).rstrip() + "\n"

if config_path.exists():
    backup = config_path.with_suffix(config_path.suffix + ".bak")
    try:
        backup.write_text(text, encoding="utf-8")
    except Exception:
        pass

config_path.write_text(new_text, encoding="utf-8")
PY

if [[ -d "$SWIFTBAR_APP" ]]; then
  # Restart SwiftBar so it reloads settings/plugin directory.
  osascript -e 'tell application "SwiftBar" to quit' >/dev/null 2>&1 || true
  open -a "SwiftBar" >/dev/null 2>&1 || true
else
  echo "SwiftBar is not installed." >&2
  echo "Install it with Homebrew: brew install --cask swiftbar" >&2
  echo "Or download: https://github.com/swiftbar/SwiftBar/releases/latest" >&2
fi

echo "Installed:"
echo "- Codex notifier: $SAY_DST"
echo "- SwiftBar plugin: $PLUGIN_DST"
echo ""
echo "If you don't see it, open SwiftBar and click: Refresh All."
