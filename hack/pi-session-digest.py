#!/usr/bin/env python3
"""Turn a Pi session JSONL into a compact, model-readable digest.

A Pi session file is JSON lines with a lot of framing (ids, usage, timestamps,
custom events). Loading it whole into a model costs prefill tokens for every byte
of that framing. This tool keeps only what a summarizer needs:

    ROLE: the text of the turn
    tool <name>: a short argument summary
    -> <first lines of the tool result>

Usage:
    pi-session-digest.py <session.jsonl> [-o out.md] [--max-result-chars N]
    pi-session-digest.py --latest [-o out.md]      # newest session for the current dir

`--latest` lets an agent digest the session it is running in without knowing the
path: Pi stores sessions under <agent-dir>/sessions/--<cwd with / and _ as ->--/.

It prints the byte size, the estimated token count, and the compression ratio,
so the caller can decide whether the digest fits a small model or must be sliced.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# Rough characters-per-token for English/code. Deliberately conservative.
CHARS_PER_TOKEN = 3.2


def _text(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                parts.append(item.get("text") or "")
            elif isinstance(item, str):
                parts.append(item)
        return "\n".join(p for p in parts if p)
    return ""


def _tool_args(args) -> str:
    if not isinstance(args, dict):
        return ""
    # Keep the keys a summarizer cares about; drop long free text beyond a hint.
    keep = ("path", "offset", "limit", "agent", "model", "slice", "command", "pattern")
    bits = []
    for key in keep:
        if key in args and args[key] not in (None, ""):
            value = args[key]
            if isinstance(value, str) and len(value) > 120:
                value = value[:117] + "..."
            bits.append(f"{key}={value}")
    return " ".join(bits)


def digest(path: Path, max_result_chars: int) -> str:
    out: list[str] = []
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not raw.strip():
            continue
        try:
            event = json.loads(raw)
        except json.JSONDecodeError:
            continue
        etype = event.get("type")
        message = event.get("message") or {}

        if etype == "message":
            role = message.get("role")
            if role == "assistant":
                thinking = " ".join(
                    c.get("thinking", "")
                    for c in (message.get("content") or [])
                    if isinstance(c, dict) and c.get("type") == "thinking"
                )
                text = _text(message.get("content"))
                if thinking.strip():
                    out.append(f"THINK: {thinking.strip()[:400]}")
                if text.strip():
                    out.append(f"ASSISTANT: {text.strip()}")
                for c in message.get("content") or []:
                    if isinstance(c, dict) and c.get("type") == "toolCall":
                        out.append(f"CALL {c.get('toolName')}: {_tool_args(c.get('arguments'))}")
            elif role == "user":
                text = _text(message.get("content"))
                if text.strip():
                    out.append(f"USER: {text.strip()}")
            elif role == "toolResult":
                body = _text(message.get("content"))
                body = body.strip()
                if len(body) > max_result_chars:
                    body = body[:max_result_chars] + f"\n... [{len(body) - max_result_chars} chars omitted]"
                if body:
                    out.append(f"RESULT {message.get('toolName')}: {body}")
        elif etype == "custom" and event.get("customType") in ("compaction", "context_edit"):
            out.append(f"[{event.get('customType')}]")
    return "\n".join(out) + "\n"


def sessions_dir() -> Path:
    base = os.environ.get("PI_CODING_AGENT_SESSION_DIR")
    if not base:
        agent_dir = os.environ.get("PI_CODING_AGENT_DIR") or os.path.expanduser("~/.pi/agent")
        base = str(Path(agent_dir) / "sessions")
    return Path(base)


def latest_session(cwd: Path) -> Path | None:
    """The newest session file for `cwd`, matching Pi's directory slug."""
    slug = "--" + str(cwd.resolve()).strip("/").replace("/", "-") + "--"
    directory = sessions_dir() / slug
    if not directory.is_dir():
        return None
    files = sorted(directory.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
    return files[0] if files else None


def main() -> int:
    ap = argparse.ArgumentParser(description="Digest a Pi session JSONL for summarization.")
    ap.add_argument("session", type=Path, nargs="?")
    ap.add_argument("--latest", action="store_true", help="digest the newest session for the current directory")
    ap.add_argument("-o", "--output", type=Path)
    ap.add_argument("--max-result-chars", type=int, default=800)
    args = ap.parse_args()

    if args.latest:
        resolved = latest_session(Path.cwd())
        if resolved is None:
            print(f"no session found for {Path.cwd()}", file=sys.stderr)
            return 1
        args.session = resolved
        print(f"# session: {resolved}", file=sys.stderr)
    if args.session is None or not args.session.is_file():
        print(f"not a file: {args.session}", file=sys.stderr)
        return 1

    text = digest(args.session, args.max_result_chars)
    size = len(text.encode())
    tokens = int(size / CHARS_PER_TOKEN)
    original = args.session.stat().st_size

    if args.output:
        args.output.write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)

    print(
        f"# digest: {original / 1024:.0f} KiB -> {size / 1024:.0f} KiB "
        f"({original / max(size, 1):.1f}x), ~{tokens} tokens",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
