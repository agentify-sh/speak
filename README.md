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

# Skip installing uv (required for Pocket TTS via `uvx`)
INSTALL_UV=0 ./install.sh

# (Optional) warm Pocket TTS deps into uv cache
WARM_POCKET_TTS=1 ./install.sh
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

# Optional engines
~/.codex/say.sh engine apple  # use macOS `say` (default)
~/.codex/say.sh engine pocket # use Pocket TTS if installed (falls back to Apple if missing)
~/.codex/say.sh pocket-voice alba
```

SwiftBar:
- Menu bar title shows `Off` / `Ready` / `Speaking`
- Click the title to Play/Stop

## Notes

- Speech reads an intelligent summary by default: skips code blocks, truncates very long IDs/identifiers, and stops before a `Test/Tests/Testing` section.
- Volume is speech-only by default (system volume unchanged): audio is generated to a single cached file and overwritten each time (no disk growth).
- Parallel turn completions are handled: if Codex finishes again while already speaking, it queues “latest” and will replay after the current speech ends.
- No credentials are stored; only the last response text and playback state.

## Pocket TTS (optional)

This project can use Kyutai Pocket TTS as an alternative engine.

Install `uv`, then:

```bash
uvx pocket-tts generate --help
uvx pocket-tts serve
```

Then in SwiftBar (or terminal) select `Engine: pocket`.

Pocket TTS caveats:
- This project controls Pocket volume via the audio player (`afplay -v`), not system volume.
- Speed is exposed via `~/.codex/say.sh speed …` and SwiftBar. For Pocket TTS this is best-effort: the script will pass `--speed`/`--rate` only if the installed `pocket-tts` CLI supports it.

## License

Apache-2.0 (see `LICENSE`).
