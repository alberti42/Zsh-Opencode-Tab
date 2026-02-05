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

- `# <request><TAB>` generate command(s)
- `#? <question><TAB>` explanation mode; prints an answer to your terminal (does not edit your prompt)

The persistence behavior is what makes iteration feel nice: keep your draft in the prompt and press TAB again.

## Pro Tip: Iterate In Place

When you use persistence, your prompt becomes a tiny scratchpad. You're not "chatting". You're drafting a command.

- First TAB gets you a rough draft.
- Next TAB is a revision pass: you tweak your notes (add another `# ...` line, or edit an existing one) and press TAB again.
- Because the old draft stays in the buffer, the agent can refine it instead of reinventing it.

That means you can do this:

1) Ask for a rough draft:

```zsh
# list all .py files under this folder, one per line<TAB>
```

2) Refine the request and press TAB again (add another `# ...` line anywhere you like):

```zsh
# but exclude files with _test_ in the filename<TAB>
```

3) Add the action you actually want:

```zsh
# now show line counts for each file and sort biggest first<TAB>
```

If you ever want to override the default behavior:

- Use `#+` to force persistence for a single request.
- Use `#-` to force a "commands only" reply (no echoed `# ...` prompt lines).

You can keep iterating until it looks right, then run it.
Still safe: it never runs anything for you.

<details>
<summary><strong>Click to expand the TLDR section on how it works internally</strong></summary>

- ZLE widget: intercepts TAB and triggers only on `# ...` lines.
- Controller (`src/controller.zsh`):
  - starts the worker process
  - shows the Knight Rider spinner while the worker runs
  - updates `BUFFER` with the generated result on success
- Worker (`src/opencode_generate_command.py`):
  - runs `opencode run --format json` and parses NDJSON events
  - returns `sessionID<US>repro_cmd<US>agent_reply` (US = ASCII Unit Separator, 0x1f) so the controller can split it
- Spinner (`src/spinner.zsh`): rendering-only; draws via `BUFFER` + `region_highlight`.
</details>

## Requirements

- zsh >= 5.1
- `python3`
- `opencode` CLI in `PATH`
- (Optional) an opencode server running on your machine or on your premises for attach/warm-start mode

Note: this plugin targets macOS and Linux. If you use Windows, run it under WSL.

## Installation

Note: the `export` configurations shown below are just examples. For the full list, see _Configuration_.

> [!IMPORTANT]
> If you use other plugins that customize TAB completion (especially `fzf-tab`), you have two options:
> 
> 1) Load `zsh-opencode-tab` **last** (after `fzf-tab` and anything else that re-binds TAB).
> 2) Or keep TAB fully owned by your completion plugin and bind this plugin to another key via `Z_OC_TAB_BINDKEY`.
>
> <details>
> <summary><strong>Non-technical explanation (TL;DR)</strong></summary>
>
> In zsh, a key press can only call one thing.
>
> This plugin respects what is already bound to the chosen key (`Z_OC_TAB_BINDKEY`): it steps in only when the prompt line begins with `# ...`; in all other cases, it calls the original widget that was bound to that key.
>
> If another plugin grabs the same key *after* this one loads (common with `fzf-tab`), zsh will call that newer binding directly and this plugin will never see the key press.
>
> On this basis, we recommend option 1) because the binding of this plugin is triggered on a very specific criterion and is unlikely to interfere with any other plugins already installed on your system.
> </details>

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

# IMPORTANT: keep this after plugins like fzf-tab that re-bind TAB.
plugins+=(zsh-opencode-tab)

# Alternative: bind to a different key (example: Ctrl-G) to avoid TAB conflicts.
# export Z_OC_TAB_BINDKEY='^G'
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
# Optional: bind to a different key than TAB (example: Ctrl-G)
# export Z_OC_TAB_BINDKEY='^G'
source "$HOME/local/share/my-zsh-plugins/zsh-opencode-tab/zsh-opencode-tab.plugin.zsh"
```

**zinit:**

Optional: if you want to bind this plugin to a different key than TAB, add e.g. `Z_OC_TAB_BINDKEY="^G"` to the `atinit` export list.

```zsh
zinit lucid wait depth=1 from'gh' compile for \
  wait'0c' atinit'export Z_OC_TAB_OPENCODE_MODEL="anthropic/claude-3-5-haiku-latest" \
    Z_OC_TAB_SPINNER_BG_HEX="#24273A" \
    Z_OC_TAB_OPENCODE_RUN_MODE="cold" \
    Z_OC_TAB_EXPLAIN_PRINT_CMD="bat --plain --color=always --decorations=always --language markdown --paging=never {}"' \
  @alberti42/zsh-opencode-tab
```

## Usage

Write a request preceded by `#` and press TAB (or your configured key via `Z_OC_TAB_BINDKEY`). The plugin updates your prompt with generated command(s), ready to edit/run.

- If the line does not start with `#`, TAB behaves as usual (your original widget is preserved).
- When you press TAB, the generator agent receives your whole prompt buffer (including any previous draft you kept there).
  This is what makes iteration work: you can refine the request without losing context.
- Magic prefixes:
  - `# <request><TAB>`: generate command(s).
    - By default, your `# ...` prompt stays in the buffer above the output.
  - `#? <request><TAB>`: explanation mode; prints the explanation to the terminal via `Z_OC_TAB_EXPLAIN_PRINT_CMD` (default: `cat`).
    - It does not insert the explanation into the buffer.
    - If you configure it to use `bat`, make sure `bat` is installed and in `PATH`.

One small convention that makes iteration nice:

- Lines that start with a single `#` are treated as *your* prompt notes.
- If the agent needs to add notes, it uses `## ...` (double hash).
  That makes it easy to tell what you wrote vs what the agent added.

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

# Backend server URL (optional).
# Used for:
# - attach mode (warm-start), if you want it
# - deleting sessions in attach mode (cold mode deletes locally)
export Z_OC_TAB_OPENCODE_BACKEND_URL=''

# How to run opencode:
# - cold (default): run `opencode run` locally (most reliable)
# - attach: run against the backend server (faster if your server is warm)
export Z_OC_TAB_OPENCODE_RUN_MODE='cold'

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

Most people never need these. They are here if you want to fine-tune the feel of the spinner (speed, colors, fading), or control how opencode is invoked (model, logging).

<details>
<summary><strong>Click to expand the full list</strong></summary>

The plugin reads these environment variables at load time:

#### Core

- `Z_OC_TAB_DEBUG` (default: `0`)
  - Enable debug behavior (internal).
- `Z_OC_TAB_DEBUG_LOG` (default: `/tmp/zsh-opencode-tab.log`)
  - Path to append debug logs to when `Z_OC_TAB_DEBUG=1`.
- `Z_OC_TAB_BINDKEY` (default: `^I`)
  - Which key sequence triggers this plugin (bindkey notation).
  - Default is TAB (i.e., `^I`). Example alternative: `^G` (Ctrl-G).
  - If another plugin re-binds TAB (e.g. `fzf-tab`), set this to a different key to avoid conflicts.
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

 - `Z_OC_TAB_OPENCODE_BACKEND_URL` (default: empty)
   - URL of your opencode server.
    - Used for attach mode.
 - `Z_OC_TAB_OPENCODE_WORKDIR` (default: `$XDG_DATA_HOME/zsh-opencode-tab`)
   - Working directory used for the `opencode` subprocess.
   - If `XDG_DATA_HOME` is empty, it falls back to `${TMPDIR:-/tmp}/zsh-opencode-tab`.
   - The plugin keeps sessions in the global workspace (not inside whatever git repo you happen to be in).
   - The plugin writes its two bundled agents into `${Z_OC_TAB_OPENCODE_WORKDIR}/.opencode/agents/`.
 - `Z_OC_TAB_OPENCODE_RUN_MODE` (default: `cold`)
   - `cold`: run `opencode run` locally (no server attach).
   - `attach`: run `opencode run --attach <backend_url>`.
   - If you set `attach` but leave `Z_OC_TAB_OPENCODE_BACKEND_URL` empty, the plugin falls back to `cold` and shows a warning.
- `Z_OC_TAB_OPENCODE_MODEL` (default: empty)
  - Model in `provider/model` form.
  - Comprehensive list of providers/models: https://models.dev/
  - Recommended: first try the model in a regular `opencode` session (outside this plugin) to confirm your provider credentials are set up and your account has credits/billing to use it.
  - This sets the model for both generation and explanation.
- `Z_OC_TAB_OPENCODE_MODEL_GENERATOR` (default: empty)
  - Optional: model override for command generation.
- `Z_OC_TAB_OPENCODE_MODEL_EXPLAINER` (default: empty)
  - Optional: model override for explanation mode.
- `Z_OC_TAB_OPENCODE_AGENT_GENERATOR` (default: `shell_cmd_generator`)
  - Agent name for command generation.
- `Z_OC_TAB_OPENCODE_AGENT_EXPLAINER` (default: `shell_cmd_explainer`)
  - Agent name for explanation mode.
- `Z_OC_TAB_OPENCODE_VARIANT` (default: empty)
  - Optional model variant.
- `Z_OC_TAB_OPENCODE_TITLE` (default: `zsh shell assistant`)
  - Session title.

- `Z_OC_TAB_OPENCODE_LOG_LEVEL` (default: empty)
  - Passes `--log-level` to opencode (`DEBUG`, `INFO`, `WARN`, `ERROR`).
- `Z_OC_TAB_OPENCODE_PRINT_LOGS` (default: `0`)
  - If set to `1`, passes `--print-logs`.
- `Z_OC_TAB_OPENCODE_DELETE_SESSION` (default: `1`)
  - If set to `1`, deletes the created session after receiving the answer.
  - In `attach` mode: deletes via the server API (requires `Z_OC_TAB_OPENCODE_BACKEND_URL`).
  - In `cold` mode: deletes locally on disk (no server needed).

- `Z_OC_TAB_OPENCODE_GNU` (`0` or `1`; default: `1`)
  - Passed to the agent whether to prefer GNU tools over macOS/freeBSD.

</details>

## Agent + Prompt

This plugin bundles two agent definitions (prompt files) for opencode:

- One tuned for generating zsh command(s).
- One tuned for explaining commands and shell workflows.

- Default generator agent: `shell_cmd_generator` (definition: `opencode/agents/shell_cmd_generator.md`).
- Default explainer agent: `shell_cmd_explainer` (definition: `opencode/agents/shell_cmd_explainer.md`).
- Custom agents: set `Z_OC_TAB_OPENCODE_AGENT_GENERATOR` and/or `Z_OC_TAB_OPENCODE_AGENT_EXPLAINER`.
- Custom prompts: copy the agent file under `${Z_OC_TAB_OPENCODE_WORKDIR}/.opencode/agents/` to a new filename and select it using `Z_OC_TAB_OPENCODE_AGENT_GENERATOR` and `Z_OC_TAB_OPENCODE_AGENT_EXPLAINER`. Note that the plugin overwrites its own bundled filenames `shell_cmd_generator.md` and `shell_cmd_explainer.md` to keep upgrades deterministic; thus, avoid modifying the bundled agents.

Tip: when you are iterating on the agent prompt, use cold start (`Z_OC_TAB_OPENCODE_RUN_MODE=cold`). It's the least confusing setup: you edit a file, reload your shell, and the next TAB uses it.

## Cold Start vs Attach Mode

- Cold start (default): simplest and most reliable.
  - You do not run/attach to any server.
  - Each TAB request runs `opencode` from `Z_OC_TAB_OPENCODE_WORKDIR`, which keeps sessions in the global workspace.

- Attach mode (optional): same experience, less startup overhead.
  - Run an opencode server and set:
    - `Z_OC_TAB_OPENCODE_RUN_MODE='attach'`
    - `Z_OC_TAB_OPENCODE_BACKEND_URL='http://127.0.0.1:4096'`
  - The plugin already keeps its two agent files under `${Z_OC_TAB_OPENCODE_WORKDIR}/.opencode/agents/`, and attach mode can use those too.

> [!WARNING]
> Known upstream rough edges (so you're not surprised):
> 
> - Attach mode may ignore *which helper* you asked for.
>   - Under the hood, opencode is supposed to honor `--agent shell_cmd_generator` or `--agent shell_cmd_explainer` when you attach to a server.
>   - Upstream status: broken right now; a fix exists but is not merged yet: https://github.com/anomalyco/opencode/pull/11812
>   - For now, we recommend using cold start (default).
> - Password-protected server can be buggy upstream ("Unauthorized" on attach even with the right password): https://github.com/anomalyco/opencode/pull/9095

## Troubleshooting

- Nothing happens on TAB:
  - The plugin only triggers when the line starts with `#`.
  - If you use `fzf-tab` (or any plugin that re-binds TAB), load `zsh-opencode-tab` last or set `Z_OC_TAB_BINDKEY` to another key.
  - Quick check (default TAB): `bindkey -M emacs '^I'` should point to `_zsh_opencode_tab_or_fallback`.
  - Quick check (example Ctrl-G): `bindkey -M emacs '^G'` should point to `_zsh_opencode_tab_or_fallback`.
- The spinner runs but the buffer does not change:
  - Ensure `opencode` is in `PATH`.
  - If using attach mode, ensure the opencode server is running at `Z_OC_TAB_OPENCODE_BACKEND_URL`.
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
