# zsh-opencode-tab

Turn natural language into a zsh command by pressing TAB.

This is an Oh My Zsh plugin that:

- Keeps your normal TAB completion.
- When your current command line starts with `#` (a comment), it treats that line as a request to an AI agent.
- Calls `opencode run --format json`.
- Inserts the generated shell command(s) back into your ZLE buffer (it does not execute them).

## Requirements

- zsh >= 5.1 (uses `EPOCHREALTIME`)
- `python3`
- `opencode` CLI in `PATH`
- (Optional) an opencode server running for attach/warm-start mode

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

## Mini Demo (Examples)

Type each request line (starting with `#`) and press TAB. The plugin inserts the generated command into your prompt; it does not execute it.

Demo video: https://github.com/alberti42/zsh-opencode-tab/releases/download/1.0.0/demo.mov

<video src="https://github.com/alberti42/zsh-opencode-tab/releases/download/1.0.0/demo.mov" controls muted playsinline></video>

Example: list commits in a SHA range (in chronological order):

```zsh
# give me the git command to list in reverse order using rev-list the commits between 869b1373 and f1b8edd0
```

Generated command:

```zsh
git rev-list --reverse 869b1373..f1b8edd0
```

Example: iterate over `fd` results and print resolved paths:

```zsh
# give me a for-loop command to iterate over the result of `fd -e zsh`; as a dummy action, we print the full resolved path of these files.
```

Generated command:

```zsh
for file in $(fd -e zsh); do print "$(realpath "$file")"; done
```

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
# Optional: attach to a running opencode server (warm-start)
# NOTE: upstream currently does not support using --attach and --agent together.
# Track: https://github.com/anomalyco/opencode/pull/11812
# Until that is fixed, keep this empty (default) or you may not be able to select the agent.
export Z_OC_TAB_OPENCODE_ATTACH=''

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

- `Z_OC_TAB_OPENCODE_ATTACH` (default: empty)
  - Attach to an existing server (warm-start). See notes below.
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

## Cold Start vs Attach Mode

- Default (safe): do not attach; each TAB request uses the bundled agent via `OPENCODE_CONFIG_DIR=${plugin_dir}/opencode`.
- Optional (fast): attach to a running opencode server to avoid warmup overhead.
  - Current upstream limitation: `opencode run --attach ... --agent ...` is broken upstream, so attach mode cannot reliably select an agent until that PR lands.
  - Track: https://github.com/anomalyco/opencode/pull/11812
  - Once fixed: the agent must be available to the server at server start time (agents are not hot-loadable later).

## Troubleshooting

- Nothing happens on TAB:
  - The plugin only triggers when the line starts with `#`.
- The spinner runs but the buffer does not change:
  - Ensure `opencode` is in `PATH`.
  - If using attach mode, ensure the opencode server is running at `Z_OC_TAB_OPENCODE_ATTACH`.
  - Temporarily set `Z_OC_TAB_OPENCODE_LOG_LEVEL=DEBUG` and `Z_OC_TAB_OPENCODE_PRINT_LOGS=1`.

## Credits

Idea inspired by `https://github.com/verlihirsh/zsh-opencode-plugin`. This plugin, `zsh-opencode-tab`, goes beyond the initial idea by providing:

- Real agent support: a dedicated `shell_cmd_generator` agent with a well-crafted prompt format; you can override the agent name and point to your own opencode config.
- Two operating modes: safe default cold-start (works out of the box) plus an optional attach-to-server mode for warm-start performance (documented with current upstream limitations).
- Better UX: a polished "Knight Rider" progress bar animation while the agent works.
- Plays nicely with your shell: keeps normal TAB completion and works with other TAB-binding plugins (e.g. fzf-tab).
- Clean session hygiene: supports disposable sessions and auto-cleans them so you don't accumulate hundreds of useless sessions.
- Fully configurable: customize animation look (colors/background/behavior) and opencode options (model/variant/logging/config dir, etc.) via `Z_OC_TAB_*` variables.
- Solid engineering: fast lazy loading, clear namespacing for variables, and a robust worker/IPC design so the UI stays responsive.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
