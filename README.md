<p align="center">
  <img src="https://github.com/user-attachments/assets/5dae9c9f-5cfd-4b56-9037-aca644bf710a" alt="A little AI magic in the terminal" />
</p>

# zsh-opencode-tab: a little AI magic in the terminal

Turn a comment into a command by pressing TAB.

It feels like talking to your terminal.
You type what you want as a quick note to yourself, hit TAB, and your prompt fills with a real command you can review.
Sometimes you tweak it. Sometimes you just run it.
Either way, you stay in control.

This is a zsh plugin, and it plays nicely with Oh My Zsh.
Most importantly: it keeps your normal TAB completion. It only steps in when you ask for it.

## Quick Look

Type a comment and press TAB:

```zsh
# list commits between 869b1373 and f1b8edd0, oldest first
```

After TAB, your prompt keeps your request and adds command(s) below:

```zsh
# list commits between 869b1373 and f1b8edd0, oldest first
git rev-list --reverse 869b1373..f1b8edd0
```

Safety line (worth repeating): it never runs anything.
It only inserts text into your prompt.

## How It Works (From A User's Point Of View)

- If the current line starts with `#`, TAB treats it as a request and generates zsh command(s).
- If it does not start with `#`, TAB behaves exactly like it did before.

Pick a prefix:

- `# <request><TAB>` generate command(s); by default your request stays above the result (unless you change `Z_OC_TAB_PERSIST_DEFAULT`)
- `#+ <request><TAB>` force persistence (keep your request line above the generated command)
- `#- <request><TAB>` force non-persistence (replace the buffer with the generated command)
- `#? <question><TAB>` explanation mode; prints an answer to your terminal (does not edit your prompt)

The persistence behavior is what makes iteration feel nice: edit the first line and press TAB again.

<details>
<summary><strong>Click to expand the TLDR section on how it works internally</strong></summary>

- ZLE widget: intercepts TAB and triggers only on `# ...` lines.
- Controller (`src/controller.zsh`):
  - starts the worker process
  - shows the Knight Rider spinner while the worker runs
  - updates `BUFFER` with the generated result on success
- Worker (`src/opencode_generate_command.py`):
  - sets `OPENCODE_CONFIG_DIR` for the opencode subprocess (default: `${plugin_dir}/opencode`)
  - runs `opencode run --format json` and parses NDJSON events
  - returns `sessionID<US>text` (US = ASCII Unit Separator, 0x1f) so the controller can split it; `sessionID` may be empty
- Spinner (`src/spinner.zsh`): rendering-only; draws via `BUFFER` + `region_highlight`.
</details>

## Requirements

- zsh >= 5.1
- `python3`
- `opencode` CLI in `PATH`
- (Optional) an opencode server running on your machine or on your premises for attach/warm-start mode

## Installation

Note: the `export` configurations shown below are just examples. For the full list, see _Configuration_.

**Oh My Zsh:**

1) Clone this repo into your custom plugins directory:

```zsh
git clone https://github.com/alberti42/zsh-opencode-tab.git "$ZSH_CUSTOM/plugins/zsh-opencode-tab"
```

2) Add it to your `.zshrc`:

```zsh
export \
	Z_OC_TAB_OPENCODE_MODEL="anthropic/claude-3-5-haiku-latest" \
  Z_OC_TAB_EXPLAIN_PRINT_CMD='bat --plain --color=always --decorations=always --language=markdown --paging=never {}'

plugins+=(zsh-opencode-tab)
```

3) Reload your shell:

```zsh
exec zsh
```

**Do-it-yourself:**

1) Clone this repo into your desired location (e.g., "$HOME/local/share/my-zsh-plugins")

2) Source it from your `.zshrc`:

```zsh
Z_OC_TAB_OPENCODE_MODEL="anthropic/claude-3-5-haiku-latest"
source "$HOME/local/share/my-zsh-plugins/zsh-opencode-tab/zsh-opencode-tab.plugin.zsh"
```

**zinit:**

```zsh
wait'0c' atinit'
  export Z_OC_TAB_OPENCODE_MODEL="google/gemini-2.5-flash" \
  Z_OC_TAB_EXPLAIN_PRINT_CMD='bat --plain --color=always --decorations=always --language=markdown --paging=never {}' \
  $__local_plugin_path/zsh-opencode-tab
```

## Usage

Write a request preceded by `#` and press TAB. The plugin updates your prompt with generated command(s), ready to edit/run.

- If the line does not start with `#`, TAB behaves as usual (your original widget is preserved).
- Only the first line's `#` prefix is stripped.
  Any extra lines in your prompt are kept and sent as context when you press TAB again.
- Magic prefixes:
  - `# <request><TAB>`: generate command(s). By default, the request stays above the generated output.
  - `#+ <request><TAB>`: force persistence (keep your exact request line above the generated output).
  - `#- <request><TAB>`: force non-persistence (replace the whole buffer with generated output only).
  - `#? <request><TAB>`: explanation mode; prints the explanation to the terminal via `Z_OC_TAB_EXPLAIN_PRINT_CMD` (default: `cat`).
    - It does not insert the explanation into the buffer.
    - If you configure it to use `bat`, make sure `bat` is installed and in `PATH`.

## Mini Demo

Type each request line (starting with `#`) and press TAB.
The plugin inserts text into your prompt so you can review it; it does not execute anything.

Demo clip:

<https://github.com/user-attachments/assets/50318e0b-f945-4058-b446-2a04abbc8142>

<b>Example:</b> list commits in a SHA range (in chronological order):

```zsh
# give me the git command to list (using rev-list) the commits between 869b1373 and f1b8edd0, oldest first
git rev-list --reverse 869b1373..f1b8edd0
```

<b>Example:</b> iterate over `fd` results and print resolved paths:

```zsh
# give me a for-loop to iterate over `fd -e zsh`; print the resolved path for each file
for file in $(fd -e zsh); do print "$(realpath "$file")"; done
```

## Configuration

All settings are resolved once when the plugin is loaded.
To change them, update your `.zshrc` and reload your shell (`exec zsh`).

### Common Settings

For the best-looking "Knight Rider" fade effect, set the spinner background color to match your terminal background.

```zsh
# Default behavior for plain `# ...` requests.
# 1: keep the request line above the generated command(s) (default)
# 0: replace the buffer with generated command(s)
export Z_OC_TAB_PERSIST_DEFAULT='1'

# Optional: attach to a running opencode server (warm-start)
# NOTE: upstream currently does not support using --attach and --agent together.
# Track: https://github.com/anomalyco/opencode/pull/11812
# Until that is fixed, keep this empty (default) or you may not be able to select the agent.
export Z_OC_TAB_OPENCODE_ATTACH=''

# Debug: bypass opencode and return a dummy reply immediately.
# Useful to iterate on UI/integration without making remote calls.
export Z_OC_TAB_OPENCODE_DUMMY=0
# Optional: what to insert into the prompt when dummy mode is enabled.
export Z_OC_TAB_OPENCODE_DUMMY_TEXT="echo 'hello from dummy mode'"

# Speed (seconds per frame)
export Z_OC_TAB_SPINNER_INTERVAL='0.03'

# Message shown after the bar
export Z_OC_TAB_SPINNER_MESSAGE='Please wait for the agent ...'

# IMPORTANT: set this to your terminal background color.
# Tip: use a color picker / eyedropper to measure the hex color of your terminal background.
export Z_OC_TAB_SPINNER_BG_HEX='#24273A'

# Explanation mode output command (printed to the terminal).
# Use '{}' as the placeholder for the temporary file path.
export Z_OC_TAB_EXPLAIN_PRINT_CMD='bat --plain --color=always --decorations=always --language=markdown --paging=never {}'
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
- `Z_OC_TAB_PERSIST_DEFAULT` (default: `1`)
  - Default persistence for plain `# ...` requests.
  - `1`: keep the request line above the generated output.
  - `0`: replace the buffer with the generated output.
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
  - Where this plugin looks for its agent/prompt files when it runs `opencode` in cold-start mode.
  - This setting is ignored in warm-start mode, when you attach to a running opencode server.
  - If on your system you already configured opencode official environment variable `OPENCODE_CONFIG_DIR`, a sensible configuration is `export Z_OC_TAB_OPENCODE_CONFIG_DIR=OPENCODE_CONFIG_DIR` to rely this variable. The name is kept separate so that you more flexibility in principle to choose different directories for each of them; though likely you will not want/need to.
- `Z_OC_TAB_OPENCODE_GNU` (`0` or `1`; default: `1`)
  - Passed to the agent whether to prefer GNU tools over macOS/freeBSD.

</details>

## Agent + Prompt

This plugin ships with an opencode agent that is tuned for one job: turning your request into zsh commands.

- Default agent: `shell_cmd_generator` (definition: `opencode/agents/shell_cmd_generator.md`).
- Custom agents: set `Z_OC_TAB_OPENCODE_AGENT` to any primary agent name that opencode can resolve.
- Custom prompts (cold start): point `Z_OC_TAB_OPENCODE_CONFIG_DIR` at your own opencode config directory and provide `agents/<agent>.md` with your preferred instruction set.

Tip: when you are iterating on the agent prompt, use cold start (leave `Z_OC_TAB_OPENCODE_ATTACH` empty). It's the least confusing setup: you edit a file, reload your shell, and the next TAB uses it.

## Cold Start vs Attach Mode

- Cold start (default): simplest and most reliable.
  - You do not run/attach to any server.
  - Each TAB request starts `opencode` with this plugin's bundled config (`OPENCODE_CONFIG_DIR=${plugin_dir}/opencode`).

- Attach mode (optional): faster if you already run an opencode backend server.
  - Important mental model: the server decides which agents exist. This plugin cannot "upload" an agent to a running server.
  - That means: if you want to use a custom agent while attached, the agent file must already be on disk in the server's config directory when the server starts.
    - Typical location: `~/.config/opencode/agents/` (or `$XDG_CONFIG_HOME/opencode/agents/`).
    - If you want the same agent this plugin ships with, copy `opencode/agents/shell_cmd_generator.md` into that directory (or write your own `agents/<name>.md`). Then restart the opencode server.
  - Note: upstream currently has a limitation where `opencode run --attach ... --agent ...` may not reliably select the agent you request.
    - Track: https://github.com/anomalyco/opencode/pull/11812
    - If agent selection seems "ignored", switch back to cold start while you customize prompts.

## Troubleshooting

- Nothing happens on TAB:
  - The plugin only triggers when the line starts with `#`.
- The spinner runs but the buffer does not change:
  - Ensure `opencode` is in `PATH`.
  - If using attach mode, ensure the opencode server is running at `Z_OC_TAB_OPENCODE_ATTACH`.
  - Temporarily set `Z_OC_TAB_OPENCODE_LOG_LEVEL=DEBUG` and `Z_OC_TAB_OPENCODE_PRINT_LOGS=1`.

## Credits

Idea inspired by `https://github.com/verlihirsh/zsh-opencode-plugin`.

## Author
- **Author:** Andrea Alberti
- **GitHub Profile:** [alberti42](https://github.com/alberti42)
- **Donations:** [![Buy Me a Coffee](https://img.shields.io/badge/Donate-Buy%20Me%20a%20Coffee-orange)](https://buymeacoffee.com/alberti)

Feel free to contribute to the development of this plugin or report any issues in the [GitHub repository](https://github.com/alberti42/Zsh-Opencode-Tab/issues).

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Gentle CTA

If you want to get a feel for it in 10 seconds: install it, open a new terminal, type a line starting with `#`, and press TAB.
If it clicks, consider starring the repo: https://github.com/alberti42/zsh-opencode-tab
