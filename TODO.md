# TODO

## Magic Prefixes

- [ ] Add prefix parsing in `src/zsh-opencode-tab.zsh` for `#`, `#=`, `#?`.
- [ ] Keep fallback behavior intact for non-`#` buffers (delegate to original TAB widget).

## `#=` Keep-Request Mode

- [ ] Implement `#=` so the request line is preserved as a comment above the generated command(s).
- [ ] Ensure the preserved line is normalized to `# <request>` (not `#=`).

## `#?` Explain Mode (ZLE-safe)

- [ ] Add mode flag to the worker request (e.g. `MODE=1|2`) and pass it from zsh -> python.
- [ ] Update `opencode/agents/shell_cmd_generator.md` to define Mode 2 output rules (plain text explanation suitable for comment-wrapping).
- [ ] Implement `#?` so the returned text is inserted into the buffer as a comment block:
  - prefix every line with `# ` (empty line -> `#`).
- [ ] Confirm no terminal output is printed during ZLE (no `/dev/tty` writes).

## Prompt Memory

- [ ] Store `_zsh_opencode_tab[last_prompt]` on every successful trigger (`#`, `#=`, `#?`).
- [ ] (Optional) Add a small in-memory ring buffer for recent prompts.
- [ ] Decide and implement a recall widget + key binding (avoid Ctrl-Tab unless verified in target terminals).

## Manual Verification

- [ ] `ls /App<TAB>` still uses the original completion widget (e.g. fzf-tab).
- [ ] `#=<request><TAB>` results in `# <request>` + generated command(s) below.
- [ ] `#?<request><TAB>` results in a multi-line comment explanation block.
- [ ] Cancellation (`Ctrl-C`) still interrupts the worker cleanly.
