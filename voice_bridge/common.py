"""Bits shared by the MCP helper and the hook script.

Both run as descendants of one Claude Code process, so that process
(its PID plus start time) is the key that ties a helper and its hooks to
the same session card on the phone.
"""

from __future__ import annotations

import os
import subprocess

import psutil

HUB_URL = os.environ.get("VB_HUB_URL", "http://127.0.0.1:8765")
PHONE_MODE_WAIT = float(os.environ.get("VB_PHONE_MODE_WAIT", "1800"))


def _is_claude(p: psutil.Process) -> bool:
    # The native install runs as ~/.local/share/claude/versions/<version>,
    # so the process name is the version number; argv[0] is still "claude".
    try:
        cmd = p.cmdline()
        if cmd and os.path.basename(cmd[0]).lower() == "claude":
            return True
        if "/claude/versions/" in (p.exe() or ""):
            return True
        if (p.name() or "").lower() in ("node", "bun"):
            return any("claude" in part.lower() for part in cmd[:3])
    except psutil.Error:
        pass
    return False


def session_key() -> tuple[str | None, int | None]:
    """Return (key, pid) of the nearest Claude Code ancestor process."""
    try:
        p = psutil.Process(os.getpid()).parent()
        while p is not None:
            if _is_claude(p):
                return f"{p.pid}-{int(p.create_time())}", p.pid
            p = p.parent()
    except psutil.Error:
        pass
    return None, None


def git_branch(cwd: str) -> str | None:
    try:
        out = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True, text=True, timeout=2,
        )
    except Exception:
        return None
    branch = out.stdout.strip()
    return branch if out.returncode == 0 and branch and branch != "HEAD" else None
