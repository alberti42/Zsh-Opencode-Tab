# TODO

This file tracks remaining work items. It is intentionally short and technical.

## Prompt Memory / Recall

- [ ] Store the last used prompt buffer (verbatim) after a successful request.
- [ ] (Optional) Ring buffer for recent prompts.
- [ ] Add a recall widget + key binding (pick a key that works reliably across terminals).

## Authenticated Backends (Optional)

- [ ] Support deleting sessions when the opencode server is protected with HTTP basic auth.
  - Add config for backend username/password (or reuse opencode env vars if reliable).
  - Implement auth header for `DELETE /session/<id>`.
  - Test end-to-end against a password-protected `opencode serve`.

## Manual Verification Checklist

- [x] Normal completion unchanged: `ls /App<TAB>` still uses the original completion widget.
- [x] Generator modes:
  - [x] `# <request><TAB>` honors `Z_OC_TAB_PERSIST_DEFAULT`.
  - [x] `#+ <request><TAB>` persists (agent echoes user `# ...` lines).
  - [x] `#- <request><TAB>` non-persists (agent does not echo user `# ...` lines).
  - [x] Agent notes use `## ...` (never single `#` unless echoing user lines).
- [x] Explain mode:
  - [x] `#? <question><TAB>` prints to scrollback and returns a fresh prompt.
- [x] Cancellation: `Ctrl-C` interrupts the worker cleanly.
- [x] Session deletion:
  - [x] With `Z_OC_TAB_OPENCODE_DELETE_SESSION=1` and `Z_OC_TAB_OPENCODE_BACKEND_URL` set, sessions are deleted.
  - [x] If deletion is enabled but backend URL is empty, a clear warning is shown.
