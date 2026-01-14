# speak

Make OpenAI Codex CLI speak the last assistant response on turn completion (macOS), with a SwiftBar menu bar play/stop toggle.

## What it installs

- `~/.codex/say.sh`: notifier script invoked by Codex (`notify = ["~/.codex/say.sh"]`)
- SwiftBar plugin: `~/Documents/SwiftBar/codex-say.5s.sh` (configurable)
- Runtime state (no secrets): `~/Library/Caches/codex-say/`

## Install

```bash
./install.sh
```

Options:

```bash
# Choose a different SwiftBar plugins folder
SWIFTBAR_PLUGIN_DIR="$HOME/Documents/SwiftBar" ./install.sh

# Skip installing SwiftBar (installer prints instructions instead)
INSTALL_SWIFTBAR=0 ./install.sh
```

## SwiftBar Install

If you don’t have SwiftBar yet:

```bash
brew install --cask swiftbar
```

Or download from:
- https://github.com/swiftbar/SwiftBar/releases/latest

## Usage

Terminal controls:

```bash
~/.codex/say.sh toggle        # enable/disable auto-speak
~/.codex/say.sh replay        # replay last spoken summary
~/.codex/say.sh replay-full   # replay full last response
~/.codex/say.sh stop          # stop speech
```

SwiftBar:
- Menu bar title shows `Off` / `Ready` / `Speaking`
- Click the title to Play/Stop

## Notes

- Speech reads an intelligent summary by default: skips code blocks, truncates very long IDs/identifiers, and stops before a `Test/Tests/Testing` section.
- No credentials are stored; only the last response text and playback state.

## License

Apache-2.0 (see `LICENSE`).
