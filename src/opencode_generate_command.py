#!/usr/bin/env python3

import argparse
import json
import os
import re
import shutil
import sys
import urllib.error
import urllib.request
from shlex import quote as sh_quote
from subprocess import PIPE, Popen


US = "\x1f"  # ASCII Unit Separator

ANSI_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def _zsh_dollar_quote(s: str) -> str:
    """Return a zsh-safe $'..' quoted string.

    This is used for the debug-only "repro command" we emit back to zsh,
    so users can copy/paste a single line that reconstructs the exact multi-line
    prompt payload.
    """

    out: list[str] = []
    for ch in s:
        o = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == "'":
            out.append("\\'")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif o < 32 or o == 127:
            out.append(f"\\x{o:02x}")
        else:
            out.append(ch)
    return "$'" + "".join(out) + "'"


def _build_repro_cmd(cmd: list[str], cwd: str) -> str:
    """Build a copy/pasteable single-line command for debugging."""

    prefix = ""
    if cwd:
        prefix += f"cd {sh_quote(cwd)} && "

    parts: list[str] = []
    for i, a in enumerate(cmd):
        # The final arg is the prompt payload (multi-line). Use $'..' quoting.
        if i == len(cmd) - 1:
            parts.append(_zsh_dollar_quote(a))
        else:
            parts.append(sh_quote(a))
    return prefix + " ".join(parts)


def _last_nonempty_line(text: str) -> str:
    """Return the last non-empty line of `text` (used for error messages)."""

    for line in reversed((text or "").splitlines()):
        line = line.strip()
        if line:
            return line
    return ""


def _describe_error_event(evt: dict) -> str:
    """Extract a human-readable message from an opencode `error` event."""

    err = evt.get("error")
    if not isinstance(err, dict):
        return "opencode reported an unspecified error"

    data = err.get("data")
    if isinstance(data, dict):
        msg = data.get("message")
        if isinstance(msg, str) and msg.strip():
            return msg.strip()

    name = err.get("name")
    if isinstance(name, str) and name.strip():
        return name.strip()

    return "opencode reported an unspecified error"


def _parse_json_events(text: str) -> tuple[str, str, str, int]:
    """Parse `opencode run --format json` newline-delimited JSON events.

    Returns: (combined_text, session_id, error_message, event_count)

    `error_message` is non-empty when opencode reported a failure, e.g.
    {"type":"error", ..., "error":{"name":"UnknownError",
     "data":{"message":"Model not found: ..."}}}

    `event_count` tells the caller whether this even *looked* like an event
    stream, so it can tell "opencode emitted no JSON" (fall back to raw stdout)
    apart from "opencode emitted events but no assistant text" (an empty reply,
    which must be reported rather than pasted to the command line).
    """
    chunks: list[str] = []
    session_id = ""
    error_message = ""
    event_count = 0

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        try:
            evt = json.loads(line)
        except json.JSONDecodeError:
            continue

        if not isinstance(evt, dict):
            continue

        event_count += 1

        sid = evt.get("sessionID")
        if isinstance(sid, str) and sid:
            session_id = sid

        if evt.get("type") == "error":
            # Keep the first error; later events are usually fallout from it.
            if not error_message:
                error_message = _describe_error_event(evt)
            continue

        if evt.get("type") != "text":
            continue

        part = evt.get("part")
        if not isinstance(part, dict):
            continue

        t = part.get("text")
        if isinstance(t, str) and t:
            chunks.append(t)

    return ("".join(chunks), session_id, error_message, event_count)


def _render_prompt(user_request: str, ostype: str, gnu: str, echo_prompt: str) -> str:
    # Keep this intentionally small and explicit.
    echo_prompt = (echo_prompt or "").strip() or "0"
    return (
        "<user>\n"
        "<config>\n"
        f"{{OSTYPE}}={ostype}\n"
        f"{{GNU}}={gnu}\n"
        f"{{ECHO_PROMPT}}={echo_prompt}\n"
        "</config>\n"
        "<request>\n"
        f"{user_request}\n"
        "</request>\n"
        "</user>"
    )


def _delete_session(backend_url: str, session_id: str) -> None:
    backend_url = (backend_url or "").strip().rstrip("/")
    session_id = (session_id or "").strip()
    if not backend_url or not session_id:
        return

    url = f"{backend_url}/session/{session_id}"
    req = urllib.request.Request(url, method="DELETE")
    try:
        with urllib.request.urlopen(req, timeout=2) as r:
            # Best-effort: we don't care about the response body.
            r.read(1)
    except Exception:
        return


def main() -> int:
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("--user-request", required=True)
    ap.add_argument("--ostype", default="")
    ap.add_argument("--gnu", default="1")
    ap.add_argument("--kind", default="command")
    ap.add_argument("--echo-prompt", default="0")
    ap.add_argument("--workdir", default="")
    ap.add_argument("--model", default="")
    ap.add_argument("--backend-url", default="")
    ap.add_argument("--run-mode", default="cold")
    ap.add_argument("--agent", default="")
    ap.add_argument("--variant", default="")
    ap.add_argument("--title", default="")
    ap.add_argument("--log-level", default="")
    ap.add_argument("--print-logs", action="store_true")
    ap.add_argument("--delete-session", action="store_true")
    ap.add_argument(
        "--debug-dummy",
        action="store_true",
        help="Skip opencode execution and return a mock reply.",
    )
    ap.add_argument(
        "--debug-dummy-text",
        default="",
        help="Mock reply text to emit when --debug-dummy is set.",
    )
    ap.add_argument(
        "--debug-dummy-file",
        default="",
        help="Read mock reply text from this file when --debug-dummy is set.",
    )
    args, _ = ap.parse_known_args()

    backend_url = (args.backend_url or "").strip()
    run_mode = (args.run_mode or "").strip() or "cold"
    workdir = (args.workdir or "").strip()
    if not workdir:
        workdir = os.path.join(os.environ.get("TMPDIR", "/tmp"), "zsh-opencode-tab")

    prompt = _render_prompt(
        args.user_request,
        args.ostype,
        args.gnu,
        args.echo_prompt,
    )

    opencode_bin = shutil.which("opencode") or "opencode"

    cmd = [opencode_bin, "run", "--format", "json"]
    if args.print_logs:
        cmd.append("--print-logs")
    if args.log_level:
        cmd += ["--log-level", args.log_level]
    if args.model:
        cmd += ["--model", args.model]
    if run_mode == "attach" and backend_url:
        cmd += ["--attach", backend_url]
    if args.agent:
        cmd += ["--agent", args.agent]
    if args.variant:
        cmd += ["--variant", args.variant]
    if args.title:
        cmd += ["--title", args.title]
    cmd.append(prompt)

    env = dict(os.environ)

    # Debug-only: return the exact opencode invocation so users can copy/paste and
    # reproduce what the plugin ran.
    repro_cmd = _build_repro_cmd(cmd, workdir)

    if args.debug_dummy:
        text = (args.debug_dummy_text or "").strip()

        if not text:
            if args.kind == "explain":
                text = "This is a dummy explanation,\nwhich extends over two lines."
            else:
                text = "# This is a dummy command,\nls"

        # Output protocol for the zsh controller:
        # session_id + US + repro_cmd + US + text + "\n"
        sys.stdout.write(US + repro_cmd + US + text + "\n")
        return 0

    if opencode_bin == "opencode" and not shutil.which("opencode"):
        sys.stderr.write("opencode not found in PATH\n")
        return 1

    os.makedirs(workdir, exist_ok=True)
    p = Popen(cmd, stdout=PIPE, stderr=PIPE, text=True, env=env, cwd=workdir)
    out, err = p.communicate()

    # ANSI_RE.sub("", out ...): strips ANSI escape sequences
    out = ANSI_RE.sub("", out or "").replace("\r", "")
    err = ANSI_RE.sub("", err or "").replace("\r", "")

    combined_text, session_id, error_message, event_count = _parse_json_events(out)

    if args.delete_session and backend_url and session_id:
        _delete_session(backend_url, session_id)

    # opencode failed: report it on stderr and exit non-zero. Without this the
    # raw error JSON would flow through the success path below and land in the
    # user's command line. The controller shows the first line in the ZLE
    # message area and appends the rest to the debug log.
    if p.returncode != 0 or error_message:
        detail = error_message or _last_nonempty_line(err) or _last_nonempty_line(out)
        # An error event with a zero exit status is a normal opencode outcome,
        # so only mention the status when it is itself the failure signal.
        summary = "opencode failed"
        if p.returncode != 0:
            summary += f" (exit {p.returncode})"
        if detail:
            summary += f": {detail}"

        sys.stderr.write(summary + "\n")
        sys.stderr.write("repro_cmd:\n" + repro_cmd + "\n")
        if err.strip():
            sys.stderr.write("opencode stderr:\n" + err.strip() + "\n")
        if out.strip():
            sys.stderr.write("opencode stdout:\n" + out.strip() + "\n")
        return 1

    text = combined_text.strip()

    # Only fall back to raw stdout when opencode produced no JSON events at all
    # (e.g. it ignored --format json). Falling back whenever the text is empty
    # would paste the NDJSON event stream onto the user's command line, which is
    # what happens when a model streams a reply that carries no text part.
    if not text and not event_count:
        text = out.strip()

    # A successful run that produced nothing usable is still a failure from the
    # caller's point of view: say so instead of inserting an empty reply.
    if not text:
        sys.stderr.write("opencode returned no output (empty reply)\n")
        sys.stderr.write("repro_cmd:\n" + repro_cmd + "\n")
        if err.strip():
            sys.stderr.write("opencode stderr:\n" + err.strip() + "\n")
        if out.strip():
            sys.stderr.write("opencode stdout:\n" + out.strip() + "\n")
        return 1

    # Output protocol for the zsh controller:
    # - Always emit: session_id + US + repro_cmd + US + text + "\n"
    # - US is ASCII Unit Separator (0x1f), chosen because it's very unlikely to
    #   appear in normal shell commands.
    # - session_id may be empty.
    # - repro_cmd is for debugging only (controller logs it when Z_OC_TAB_DEBUG=1).
    sys.stdout.write((session_id or "") + US + repro_cmd + US + text + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
