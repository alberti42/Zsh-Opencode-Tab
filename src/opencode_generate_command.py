#!/usr/bin/env python3

import argparse
import json
import os
import re
import shutil
import sys
import urllib.error
import urllib.request
from subprocess import PIPE, Popen


US = "\x1f"  # ASCII Unit Separator

ANSI_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def _parse_json_events(text: str) -> tuple[str, str]:
    """Parse `opencode run --format json` newline-delimited JSON events.

    Returns: (combined_text, session_id)
    """
    chunks: list[str] = []
    session_id = ""

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

        sid = evt.get("sessionID")
        if isinstance(sid, str) and sid:
            session_id = sid

        if evt.get("type") != "text":
            continue

        part = evt.get("part")
        if not isinstance(part, dict):
            continue

        t = part.get("text")
        if isinstance(t, str) and t:
            chunks.append(t)

    return ("".join(chunks), session_id)


def _render_prompt(user_request: str, ostype: str, gnu: str, mode: str) -> str:
    # Keep this intentionally small and explicit. The agent definition lives in
    # OPENCODE_CONFIG_DIR/agents/<agent>.md, loaded by opencode.
    mode = (mode or "").strip() or "1"
    return (
        "<user>\n"
        "<config>\n"
        f"{{OSTYPE}}={ostype}\n"
        f"{{GNU}}={gnu}\n"
        f"{{MODE}}={mode}\n"
        "</config>\n"
        "<request>\n"
        f"{user_request}\n"
        "</request>\n"
        "</user>"
    )


def _delete_session(backend: str, session_id: str) -> None:
    backend = (backend or "").strip().rstrip("/")
    session_id = (session_id or "").strip()
    if not backend or not session_id:
        return

    url = f"{backend}/session/{session_id}"
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
    ap.add_argument("--mode", default="1")
    ap.add_argument("--config-dir", default="")
    ap.add_argument("--model", default="")
    ap.add_argument("--backend", default="")
    ap.add_argument("--agent", default="")
    ap.add_argument("--variant", default="")
    ap.add_argument("--title", default="")
    ap.add_argument("--log-level", default="")
    ap.add_argument("--print-logs", action="store_true")
    ap.add_argument("--delete-session", action="store_true")
    args, _ = ap.parse_known_args()

    prompt = _render_prompt(args.user_request, args.ostype, args.gnu, args.mode)

    opencode_bin = shutil.which("opencode")
    if not opencode_bin:
        sys.stderr.write("opencode not found in PATH\n")
        return 1

    cmd = [opencode_bin, "run", "--format", "json"]
    if args.print_logs:
        cmd.append("--print-logs")
    if args.log_level:
        cmd += ["--log-level", args.log_level]
    if args.model:
        cmd += ["--model", args.model]
    if args.backend:
        cmd += ["--attach", args.backend]
    if args.agent:
        cmd += ["--agent", args.agent]
    if args.variant:
        cmd += ["--variant", args.variant]
    if args.title:
        cmd += ["--title", args.title]
    cmd.append(prompt)

    env = dict(os.environ)
    if args.config_dir:
        env["OPENCODE_CONFIG_DIR"] = args.config_dir

    p = Popen(cmd, stdout=PIPE, stderr=PIPE, text=True, env=env)
    out, _err = p.communicate()

    out = ANSI_RE.sub("", out or "").replace("\r", "")

    combined_text, session_id = _parse_json_events(out)
    # If opencode didn't produce JSON events for some reason, fall back.
    text = (combined_text or out).strip()

    if args.delete_session and args.backend and session_id:
        _delete_session(args.backend, session_id)

    # Output protocol for the zsh controller:
    # - Always emit: session_id + US + text + "\n"
    # - US is ASCII Unit Separator (0x1f), chosen because it's very unlikely to
    #   appear in normal shell commands.
    # - session_id may be an empty string; today the zsh side does not use it,
    #   but it is future-proof metadata (and a useful integrity signal).
    sys.stdout.write((session_id or "") + US + text + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
