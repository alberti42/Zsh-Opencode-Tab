<p align="center">
  <img src="https://github.com/user-attachments/assets/5dae9c9f-5cfd-4b56-9037-aca644bf710a" alt="A little AI magic in the terminal" />
</p>

# zsh-opencode-tab: a little AI magic in the terminal

Turn natural language into a zsh command by pressing TAB.

It has two modes, each backed by a different prompt optimized for the job:

- Generate: turns your request into zsh command(s).
- Explain: answers in plain English and explains the command/workflow.

It never executes anything. It only inserts text into your prompt so you can review/edit it and decide whether to run it.

Pick a mode with a simple prefix at the start of the line:

- `# <request><TAB>` generate command(s) (default)
- `#? <request><TAB>` explain

Generate-mode modifier:

- `#= <request><TAB>` generate, and also persist your request as a comment above the generated command(s)

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
- Magic prefixes:
  - `# <request><TAB>`: generate command(s) and replace the buffer.
  - `#= <request><TAB>`: keep your request (normalized to `# <request>`) as a comment line above the generated command(s).
  - `#? <request><TAB>`: explanation mode; prints the explanation to the terminal via `Z_OC_TAB_EXPLAIN_PRINT_CMD` (default: `cat`).
    - It does not insert the explanation into the buffer.
    - If you configure it to use `bat`, make sure `bat` is installed and in `PATH`.

## Mini Demo

Type each request line (starting with `#`) and press TAB. The plugin inserts the generated command into your prompt; it does not execute it.

Demo clip:

<https://github.com/user-attachments/assets/50318e0b-f945-4058-b446-2a04abbc8142>

<b>Example:</b> list commits in a SHA range (in chronological order):

```zsh
# give me the git command to list in reverse order using rev-list the commits between 869b1373 and f1b8edd0

# Generated command:

git rev-list --reverse 869b1373..f1b8edd0
```

<b>Example:</b> iterate over `fd` results and print resolved paths:

```zsh
# give me a for-loop command to iterate over the result of `fd -e zsh`; as a dummy action, we print the full resolved path of these files.

# Generated command:

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

For the best-looking "Knight Rider" fade effect, set the spinner background color to match your terminal background.

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

# IMPORTANT: set this to your terminal background color.
# Tip: use a color picker / eyedropper to measure the hex color of your terminal background.
export Z_OC_TAB_SPINNER_BG_HEX='#24273A'

# Explanation mode output command (printed to the terminal).
# Use '{}' as the placeholder for the temporary file path.
export Z_OC_TAB_EXPLAIN_PRINT_CMD='bat --plain --color=always --decorations=always --language markdown --paging=never {}'
```

How to pick the right color:

- Use any "eyedropper" / color picker tool, click your terminal background, and copy the hex value (like `#1e1e1e`).
- On macOS, the built-in "Digital Color Meter" app can do this.

### Advanced: All Customizable Settings

Most people never need these. They are here if you want to fine-tune the feel of the spinner (speed, colors, fading), control how opencode is invoked (model, logging), or point the plugin at your own opencode config directory.

<details>
<summary><strong>Click to expand the full list</strong></summary>

The plugin reads these environment variables at load time:

#### Core

- `Z_OC_TAB_DEBUG` (default: `0`)
  - Enable debug behavior (internal).
- `Z_OC_TAB_DEBUG_LOG` (default: `/tmp/zsh-opencode-tab.log`)
  - Path to append debug logs to when `Z_OC_TAB_DEBUG=1`.
- `Z_OC_TAB_EXPLAIN_PRINT_CMD` (default: `cat`)
  - Command used to print `#?` explanation output to the terminal.
  - Use `{}` as a placeholder for the temporary file path.
  - Keep it simple: the value is split on spaces.

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
  - Comprehensive list of providers/models: https://models.dev/
  - Recommended: first try the model in a regular `opencode` session (outside this plugin) to confirm your provider credentials are set up and your account has credits/billing to use it.
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

</details>

## Agent + Prompt

This plugin is built around an opencode agent that is optimized for generating zsh commands (and only zsh commands).

- Default agent: `shell_cmd_generator` (definition: `opencode/agents/shell_cmd_generator.md`).
- Custom agents: set `Z_OC_TAB_OPENCODE_AGENT` to any primary agent name that opencode can resolve.
- Custom prompts: point `Z_OC_TAB_OPENCODE_CONFIG_DIR` at your own opencode config directory and provide `agents/<agent>.md` with your preferred instruction set.

Tip: when iterating on an agent prompt, develop in cold-start mode (leave `Z_OC_TAB_OPENCODE_ATTACH` empty when loading this plugin). In attach mode, agents are loaded only once when the opencode server starts, so prompt edits will not be picked up until you restart the server.

## Cold Start vs Attach Mode

- Default (safe): do not attach; each TAB request uses the bundled agent via `OPENCODE_CONFIG_DIR=${plugin_dir}/opencode`.
- Optional (fast): attach to a running opencode server to avoid warmup overhead.
  - Current upstream limitation: `opencode run --attach ... --agent ...` is broken upstream, so attach mode cannot reliably select an agent until that PR lands.
  - Track: https://github.com/anomalyco/opencode/pull/11812
  - Once fixed: the agent must be available to the server at server start time (agents are not hot-loadable later).
  - Practical implication: if you want to use a custom agent in attach mode, put the agent markdown file in a directory the opencode server can see *when it starts* (e.g. `~/.config/opencode/agents/`).
    - If you want to use this plugin's bundled agent, copy `opencode/agents/shell_cmd_generator.md` into `~/.config/opencode/agents/` (or create your own `agents/<name>.md` there) and restart the server.

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

## Author
- **Author:** Andrea Alberti
- **GitHub Profile:** [alberti42](https://github.com/alberti42)
- **Donations:** [![Buy Me a Coffee](https://img.shields.io/badge/Donate-Buy%20Me%20a%20Coffee-orange)](https://buymeacoffee.com/alberti)

Feel free to contribute to the development of this plugin or report any issues in the [GitHub repository](https://github.com/alberti42/Zsh-Opencode-Tab/issues).

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
