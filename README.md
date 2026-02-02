# zsh-opencode-tab

Turn natural language into a zsh command by pressing TAB.

This is an Oh My Zsh plugin that:

- Keeps your normal TAB completion.
- When your current command line starts with `#` (a comment), it treats that line as a request to an AI agent.
- Calls `opencode run --format json` (attached to a running server).
- Inserts the generated shell command(s) back into your ZLE buffer (it does not execute them).

## Requirements

- zsh >= 5.1 (uses `EPOCHREALTIME`)
- `python3`
- `opencode` CLI in `PATH`
- An opencode server running (default: `http://localhost:4096`)

## Installation (Oh My Zsh)

1) Clone this repo into your custom plugins directory:

```zsh
git clone <this-repo-url> "$ZSH_CUSTOM/plugins/zsh-opencode-tab"
```

2) Add it to your `.zshrc`:

```zsh
plugins+=(zsh-opencode-tab)
```

3) Reload your shell:

```zsh
exec zsh
```

## Usage

1) Type a comment request:

```zsh
# find all large files in this directory
```

2) Press TAB.

3) The plugin replaces your buffer with the generated command(s), ready to edit/run.

Notes:

- If the line does not start with `#`, TAB behaves as usual (your original widget is preserved).
- The leading `#` (and surrounding whitespace) is stripped before sending the request to the agent.

## How It Works

- ZLE widget: intercepts TAB and triggers only on `# ...` lines.
- Controller (`src/controller.zsh`):
  - starts the worker process
  - shows the Knight Rider spinner while the worker runs
  - replaces `BUFFER` with the generated command on success
- Worker (`src/opencode_generate_command.py`):
  - sets `OPENCODE_CONFIG_DIR` for the opencode subprocess (default: `${plugin_dir}/opencode`)
  - runs `opencode run --format json` and parses NDJSON events
  - returns `sessionID<US>text` (US = ASCII Unit Separator, 0x1f) so the controller can split it; `sessionID` may be empty
- Spinner (`src/spinner.zsh`): rendering-only; draws via `BUFFER` + `region_highlight`.

## Configuration

All settings are resolved once when the plugin is loaded.
To change them, update your `.zshrc` and reload your shell (`exec zsh`).

### Common Settings

```zsh
# Where to attach (reuse server; avoids cold-start per request)
export Z_OC_TAB_OPENCODE_ATTACH='http://localhost:4096'

# Speed (seconds per frame)
export Z_OC_TAB_SPINNER_INTERVAL='0.03'

# Message shown after the bar
export Z_OC_TAB_SPINNER_MESSAGE='Please wait for the agent ...'
```

### Advanced: All Customizable Settings

The plugin reads these environment variables at load time:

#### Core

- `Z_OC_TAB_DEBUG` (default: `0`)
  - Enable debug behavior (internal).

#### Spinner

- `Z_OC_TAB_SPINNER_MESSAGE` (default: `AI agent is busy ...`)
  - Message shown after the spinner bar.
- `Z_OC_TAB_SPINNER_MESSAGE_FG` (default: empty)
  - Truecolor hex foreground for the message, e.g. `#cfcfcf`.

- `Z_OC_TAB_SPINNER_HUE` (default: `280`)
  - Base hue (0..360).
- `Z_OC_TAB_SPINNER_SATURATION` (default: `0.30`)
  - Base saturation (0..1).
- `Z_OC_TAB_SPINNER_VALUE` (default: `1.0`)
  - Base brightness (0..1).

- `Z_OC_TAB_SPINNER_INACTIVE_FACTOR` (default: `0.4`)
  - Dim factor for inactive dots (0..1). This is "alpha-like" via background blending.
- `Z_OC_TAB_SPINNER_ENABLE_FADING` (default: `1`)
  - Enable global dot fading (1/0).
- `Z_OC_TAB_SPINNER_MIN_ALPHA` (default: `0.0`)
  - Minimum fade factor for dots (0..1).

- `Z_OC_TAB_SPINNER_BG_HEX` (default: `#24273A`)
  - Background used for blending and as the bar background. Set it to your terminal background for best results.

- `Z_OC_TAB_SPINNER_INTERVAL` (default: `0.03`)
  - Seconds per frame (single speed knob).
- `Z_OC_TAB_SPINNER_POLL_S` (default: `0.005`)
  - Poll interval (seconds) for reading the worker status FIFO.

#### Opencode

- `Z_OC_TAB_OPENCODE_ATTACH` (default: `http://localhost:4096`)
  - Attach to an existing server.
- `Z_OC_TAB_OPENCODE_MODEL` (default: empty)
  - Model in `provider/model` form.
- `Z_OC_TAB_OPENCODE_AGENT` (default: `shell_cmd_generator`)
  - Agent name.
- `Z_OC_TAB_OPENCODE_VARIANT` (default: empty)
  - Optional model variant.
- `Z_OC_TAB_OPENCODE_TITLE` (default: `zsh shell assistant`)
  - Session title.

- `Z_OC_TAB_OPENCODE_LOG_LEVEL` (default: empty)
  - Passes `--log-level` to opencode (`DEBUG`, `INFO`, `WARN`, `ERROR`).
- `Z_OC_TAB_OPENCODE_PRINT_LOGS` (default: `0`)
  - If set to `1`, passes `--print-logs`.
- `Z_OC_TAB_OPENCODE_DELETE_SESSION` (default: `1`)
  - If set to `1`, deletes the created session via the server API after receiving the answer.

- `Z_OC_TAB_OPENCODE_CONFIG_DIR` (default: `${plugin_dir}/opencode`)
  - Sets `OPENCODE_CONFIG_DIR` for the opencode subprocess.
  - Keep this separate from `OPENCODE_CONFIG_DIR` on purpose: users must opt-in explicitly if they want to point the plugin at their own opencode config.
- `Z_OC_TAB_OPENCODE_GNU` (default: `1`)
  - Passed through to the agent as `GNU=...` (no validation/clamping).

## Agent + Prompt

- Agent definition (used by opencode): `opencode/agents/shell_cmd_generator.md` (resolved via `OPENCODE_CONFIG_DIR`).
- User prompt format passed to opencode by the worker:

```text
<user>
<config>
OSTYPE=...
GNU=...
</config>
<request>
...
</request>
</user>
```

## Troubleshooting

- Nothing happens on TAB:
  - The plugin only triggers when the line starts with `#`.
- The spinner runs but the buffer does not change:
  - Ensure `opencode` is in `PATH`.
  - Ensure the opencode server is running at `Z_OC_TAB_OPENCODE_ATTACH`.
  - Temporarily set `Z_OC_TAB_OPENCODE_LOG_LEVEL=DEBUG` and `Z_OC_TAB_OPENCODE_PRINT_LOGS=1`.

## License

MIT (see `LICENSE`).
