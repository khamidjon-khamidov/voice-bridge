#!/usr/bin/env python3
"""Add (or remove with --remove) voice-bridge's hooks, env and rules in ~/.claude.

Idempotent: our hook entries are recognised by the vb-hook path, and the
CLAUDE.md rules live between two marker comments. A backup of
settings.json is written next to it before any change.
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOOK_CMD = str(ROOT / ".venv" / "bin" / "vb-hook")
CLAUDE_DIR = Path.home() / ".claude"
SETTINGS = CLAUDE_DIR / "settings.json"
CLAUDE_MD = CLAUDE_DIR / "CLAUDE.md"
RULES = ROOT / "CLAUDE_RULES.md"
BEGIN, END = "<!-- voice-bridge:begin -->", "<!-- voice-bridge:end -->"

# event -> (matcher or None, timeout seconds)
EVENTS = {
    "SessionStart": (None, 10),
    "UserPromptSubmit": (None, 10),
    "PostToolUse": ("*", 10),
    "Notification": (None, 10),
    "Stop": (None, 3600),  # phone mode waits here for your next instruction
    "SessionEnd": (None, 10),
}
TOOL_PERMS = ["mcp__voice-bridge__report", "mcp__voice-bridge__ask_user"]
ENV = {"MCP_TOOL_TIMEOUT": "1200000"}  # 20 min, longer than ask_user's 15


def is_ours(group: dict) -> bool:
    return any("vb-hook" in (h.get("command") or "") for h in group.get("hooks", []))


def configure_settings(remove: bool) -> None:
    settings = json.loads(SETTINGS.read_text()) if SETTINGS.exists() else {}
    if SETTINGS.exists():
        shutil.copy2(SETTINGS, SETTINGS.with_name("settings.json.bak-voice-bridge"))

    hooks = settings.setdefault("hooks", {})
    for event, (matcher, timeout) in EVENTS.items():
        groups = [g for g in hooks.get(event, []) if not is_ours(g)]
        if not remove:
            group = {"hooks": [{"type": "command", "command": HOOK_CMD, "timeout": timeout}]}
            if matcher:
                group = {"matcher": matcher, **group}
            groups.append(group)
        if groups:
            hooks[event] = groups
        else:
            hooks.pop(event, None)
    if not hooks:
        settings.pop("hooks")

    perms = settings.setdefault("permissions", {})
    allow = [p for p in perms.get("allow", []) if p not in TOOL_PERMS]
    if not remove:
        allow += TOOL_PERMS
    if allow:
        perms["allow"] = allow
    else:
        perms.pop("allow", None)
    if not perms:
        settings.pop("permissions")

    env = settings.setdefault("env", {})
    for k, v in ENV.items():
        if remove:
            env.pop(k, None)
        else:
            env[k] = v
    if not env:
        settings.pop("env")

    SETTINGS.parent.mkdir(parents=True, exist_ok=True)
    SETTINGS.write_text(json.dumps(settings, indent=2) + "\n")


def configure_rules(remove: bool) -> None:
    text = CLAUDE_MD.read_text() if CLAUDE_MD.exists() else ""
    if BEGIN in text and END in text:
        before, rest = text.split(BEGIN, 1)
        after = rest.split(END, 1)[1]
        text = before.rstrip("\n") + ("\n" if before.strip() else "") + after.lstrip("\n")
    if not remove:
        block = f"{BEGIN}\n{RULES.read_text().strip()}\n{END}\n"
        text = (text.rstrip("\n") + "\n\n" if text.strip() else "") + block
    if text.strip():
        CLAUDE_MD.write_text(text)
    elif CLAUDE_MD.exists():
        CLAUDE_MD.unlink()


if __name__ == "__main__":
    remove = "--remove" in sys.argv
    configure_settings(remove)
    configure_rules(remove)
    print(("Removed" if remove else "Configured") + f" hooks/env/permissions in {SETTINGS} and rules in {CLAUDE_MD}")
