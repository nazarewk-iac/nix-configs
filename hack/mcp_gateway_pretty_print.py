#!/usr/bin/env python3
"""PermissionRequest hook: replace mcp-gateway's `gateway_invoke` approval dialog.

Claude Code's built-in "Tool use" confirmation dialog has no display-template or
formatter API — no PreToolUse/PermissionRequest output field can rewrite the tool
name/arguments it renders (confirmed empirically and against current docs). Since
mcp-gateway's single dispatcher tool (`gateway_invoke(server, tool, arguments)`) means
every backend call looks identical in that dialog ("Invoke Tool(server: ..., tool: ...,
arguments: {...})"), the only way to get a readable approval step is to suppress the
native dialog entirely and substitute a custom one.

This hook does that: it builds a readable preview of the call (via the same
`pretty_print_plugins` plugin package used previously — select()/get_permissions_info()),
shows it in a generic Tk dialog (title + key/value metadata rows + a plain text body +
Allow/Deny buttons), blocks until the user answers, and returns that decision as the
PermissionRequest hook's `allow`/`deny` — Claude Code never shows its own dialog for a
call this hook handles. On any failure (no display, plugin crash, etc.) it fails open to
Claude Code's normal permission flow rather than silently allowing or blocking.

Plugin contract: `get_permissions_info(ctx) -> str | (list[tuple[str, str]], str)`.
Returning a plain string is shorthand for `([], that_string)` — no metadata rows, just
body text. Returning a `(fields, body)` tuple puts `fields` above the body as key/value
rows (e.g. title, directory) so the body itself can hold just the raw content, with no
markdown fencing or other formatting glued on around it.
"""

import importlib
import json
import pkgutil
import sys
import tkinter as tk
from tkinter import ttk
from tkinter.scrolledtext import ScrolledText

TARGET = "mcp__mcp-gateway__gateway_invoke"


def discover_plugins() -> list:
    try:
        import pretty_print_plugins
    except ImportError as exc:
        print(f"mcp-gateway-pretty-print: pretty_print_plugins not importable: {exc}", file=sys.stderr)
        return []

    modules = sorted(
        pkgutil.iter_modules(pretty_print_plugins.__path__, pretty_print_plugins.__name__ + "."),
        key=lambda m: m.name,
    )
    names = [m.name.removeprefix(pretty_print_plugins.__name__ + ".") for m in modules]
    print(f"mcp-gateway-pretty-print: loaded plugins: {names}", file=sys.stderr)
    return modules


def run_plugins(ctx: dict, module_infos: list) -> tuple[list[tuple[str, str]], str]:
    for module_info in module_infos:
        try:
            plugin = importlib.import_module(module_info.name)
            if plugin.select(ctx):
                result = plugin.get_permissions_info(ctx)
                if isinstance(result, str):
                    return [], result
                return result
        except Exception as exc:  # a broken plugin must not break the hook
            print(f"mcp-gateway-pretty-print: plugin {module_info.name} failed: {exc}", file=sys.stderr)
            continue
    return [], json.dumps(ctx["arguments"], indent=2)


def ask_permission(title: str, fields: list[tuple[str, str]], body: str) -> bool:
    result = {"allowed": False}

    root = tk.Tk()
    root.title("Claude Code — MCP gateway permission")
    root.geometry("900x700")
    root.minsize(600, 400)

    heading = ttk.Label(root, text=title, font=("", 14, "bold"))
    heading.pack(anchor="w", padx=16, pady=(16, 8))

    if fields:
        metadata = ttk.Frame(root)
        metadata.pack(fill=tk.X, padx=16, pady=(0, 8))
        for row, (key, value) in enumerate(fields):
            ttk.Label(metadata, text=f"{key}:", font=("", 10, "bold")).grid(
                row=row, column=0, sticky="nw", padx=(0, 8), pady=2
            )
            ttk.Label(metadata, text=value, wraplength=760, justify=tk.LEFT).grid(
                row=row, column=1, sticky="nw", pady=2
            )

    viewer = ScrolledText(
        root,
        wrap=tk.WORD,
        font=("TkFixedFont", 11),
        padx=10,
        pady=10,
    )
    viewer.pack(fill=tk.BOTH, expand=True, padx=16, pady=8)
    viewer.insert("1.0", body)
    viewer.configure(state=tk.DISABLED)

    buttons = ttk.Frame(root)
    buttons.pack(fill=tk.X, padx=16, pady=(8, 16))

    def deny():
        result["allowed"] = False
        root.destroy()

    def allow():
        result["allowed"] = True
        root.destroy()

    ttk.Button(buttons, text="Deny", command=deny).pack(side=tk.RIGHT)
    ttk.Button(buttons, text="Allow once", command=allow).pack(side=tk.RIGHT, padx=(0, 8))

    root.protocol("WM_DELETE_WINDOW", deny)
    root.bind("<Escape>", lambda _event: deny())
    root.bind("<Control-Return>", lambda _event: allow())

    root.eval("tk:PlaceWindow . center")
    root.mainloop()
    return result["allowed"]


def emit_decision(behavior: str) -> None:
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PermissionRequest",
                    "decision": {"behavior": behavior},
                }
            }
        )
    )


def main() -> None:
    event = json.load(sys.stdin)

    # Fail open into Claude Code's normal permission handling for other tools.
    if event.get("tool_name") != TARGET:
        print("{}")
        return

    tool_input = event.get("tool_input") or {}
    ctx = {
        "server": tool_input.get("server", ""),
        "tool": tool_input.get("tool", ""),
        "arguments": tool_input.get("arguments") or {},
        "session_id": event.get("session_id", ""),
    }

    plugins = discover_plugins()
    fields, body = run_plugins(ctx, plugins)
    title = f"Claude wants to call {ctx['server']} / {ctx['tool']}"

    try:
        allowed = ask_permission(title, fields, body)
    except Exception as exc:
        # Do not auto-approve if the custom UI fails — fall back to Claude Code's own prompt.
        print(f"mcp-gateway-pretty-print: approval UI failed: {exc}", file=sys.stderr)
        print("{}")
        return

    emit_decision("allow" if allowed else "deny")


if __name__ == "__main__":
    main()
