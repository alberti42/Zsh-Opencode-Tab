# Agent Notes (zsh-opencode-tab)

This repo contains an Oh-My-Zsh plugin that turns a natural-language request into a shell command when the user presses TAB, while showing a ZLE-safe "Knight Rider" spinner animation.

## Behavior

- Trigger: only activates when the current ZLE buffer begins with a comment request (`# ...`).
- If it matches: send the current buffer to the generator agent. The agent decides whether to echo the user's `# ...` prompt lines (persistence) and may add its own `## ...` notes.
- If it does not match: fall back to the original TAB completion widget.
- No worker output is printed to the terminal during ZLE.

## ZLE Rendering / Spinner

- ZLE-safe rendering: never print to `/dev/tty` while ZLE is active.
- Spinner overlay is rendered by updating the editor line (`BUFFER`) + `region_highlight` (colors), not by terminal output.
- Colors: ported opencode's `spinner.ts` "Knight Rider" trail algorithm.
  - Terminals lack alpha, so alpha is simulated by blending against a configured background hex.
- Timing: uses `EPOCHREALTIME`; one knob controls frame interval.

## Configuration Model

- All user-facing config is resolved once at plugin load time in `zsh-opencode-tab.plugin.zsh` into:
  - `typeset -gA _zsh_opencode_tab`
- Controller/spinner read from `_zsh_opencode_tab[...]`.
- Spinner writes only runtime state under `spinner.state.*` keys (palette, inactive fg, base/bg rgb floats).

## Opencode Integration

- Uses `opencode run --format json` (NDJSON events) so we can parse a `sessionID`.
- Default run mode is cold-start (no server attach).
- Configurable: `agent` (default `shell_cmd_generator`), optional `variant`, `title` (default `zsh shell assistant`), log level mapping.
- Disposable sessions: optional `DELETE /session/<id>` after collecting output (requires backend URL).

- `OPENCODE_CONFIG_DIR` is set for the opencode subprocess (default: `${plugin_dir}/opencode`).
- Default agent is `shell_cmd_generator` (loaded from `OPENCODE_CONFIG_DIR/agents/shell_cmd_generator.md`).

### Cold Start vs Attach Mode

- Default (safe): do not attach; each TAB request starts opencode as needed and uses `OPENCODE_CONFIG_DIR=${plugin_dir}/opencode`, so the bundled agent works out of the box.
- Optional (fast): attach to a running opencode server to avoid warmup overhead.
  - Current upstream limitation: `opencode run --attach ... --agent ...` is broken upstream, so attach mode cannot reliably select an agent until that PR lands.
  - Track: https://github.com/anomalyco/opencode/pull/11812
- When attach mode becomes usable: agents must be available to the server at server start time (agents are not hot-loadable later), so users must install `shell_cmd_generator` / `shell_cmd_explainer` (or their chosen `Z_OC_TAB_OPENCODE_AGENT_GENERATOR` / `Z_OC_TAB_OPENCODE_AGENT_EXPLAINER`) where the server can find them.

### Worker -> Zsh Output Protocol

- Implemented in `src/opencode_generate_command.py`, parsed in `src/controller.zsh`.
- Format: `session_id + US + repro_cmd + US + agent_reply + "\n"`
  - `US` is ASCII Unit Separator (0x1f).
  - `session_id` may be empty.
  - `repro_cmd` is a copy/pasteable command line for debugging (only logged when `Z_OC_TAB_DEBUG=1`).
  - `agent_reply` is inserted into `BUFFER` (or printed in explain mode).

### User Prompt Format (Worker -> Opencode)

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

## Key Files

- Plugin entry/binding: `zsh-opencode-tab.plugin.zsh`
- TAB interception + fallback: `src/zsh-opencode-tab.zsh`
- Controller (process lifecycle + spinner loop): `src/controller.zsh`
- Spinner renderer (render-only): `src/spinner.zsh`
- Opencode worker: `src/opencode_generate_command.py`
- Opencode agent definition: `opencode/agents/shell_cmd_generator.md`
- Legacy/old: `long_command.sh` still exists; intended to be replaced/removed later
- Legacy docs: `docs/KnightRiderBar.zsh` (intentionally ignored for now)

## Notable Implementation Decisions

- Dot-based function naming is used (zsh supports dots) for module grouping.
- Underscore wrappers exist for backward compatibility; planned removal later.
- Spinner module stays render-only; controller owns worker lifecycle, pacing, Ctrl-C handling.
- The TAB dispatcher `_zsh_opencode_tab_or_fallback` must not use `emulate -LR` or change shell options; it must behave like a transparent passthrough for third-party completion widgets (e.g. fzf-tab).

## What To Verify Next

1) Remove/replace `long_command.sh` after confirming it's unused.
2) End-to-end ZLE test:
   - In interactive zsh, type `# list all files larger than 100MB` then press TAB.
   - Confirm spinner runs and `BUFFER` is replaced with generated command.
   - Confirm normal TAB completion still works for non-`#` lines.
3) Cleanup (later): remove underscore wrappers; improve error surfacing via `zle -M` or `# ERROR: ...` insertion.

## Constraints / Preferences

- Prefer simple, readable code; keep config commentary near definitions in `zsh-opencode-tab.plugin.zsh`.
- Configuration should be immutable at runtime (resolved once at plugin load).
- Avoid "safeguards" unless truly needed.
