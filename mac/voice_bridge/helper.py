"""voice-bridge MCP helper.

Claude Code starts one of these per session (stdio). It opens no port: it
just forwards report / ask_user to the hub, tagged with its session key.
"""

from __future__ import annotations

import os

import httpx
from fastmcp import FastMCP

from voice_bridge.common import HUB_URL, git_branch, session_key

KEY, PID = session_key()
if KEY is None:
    KEY = f"pid-{os.getppid()}"
CWD = os.getcwd()

mcp = FastMCP(
    "voice-bridge",
    instructions=(
        "These tools reach the user's phone, where messages are read aloud. "
        "Keep every message under two sentences of plain speech: no code, paths or markdown."
    ),
)


async def post(path: str, payload: dict, timeout: float = 10) -> dict:
    data = {"key": KEY, "pid": PID, "cwd": CWD, "branch": git_branch(CWD), **payload}
    async with httpx.AsyncClient(base_url=HUB_URL, timeout=timeout) as client:
        r = await client.post(path, json=data)
        r.raise_for_status()
        return r.json()


@mcp.tool()
async def report(message: str) -> str:
    """Send a short status update to the user's phone, read aloud. Does not wait.

    Use only for milestones: a refactor step done, tests passing or failing,
    a PR opened, being blocked. Under two sentences, plain speech.
    """
    try:
        r = await post("/api/report", {"text": message})
    except Exception:
        return "The voice-bridge hub isn't running, so the update wasn't delivered."
    return "Delivered." if r.get("phone") else "Saved; the phone isn't connected right now."


@mcp.tool()
async def ask_user(question: str) -> str:
    """Ask the user a short question on their phone and wait for the answer.

    Use only for real decisions, unclear requirements, or risky actions
    (deleting files, changing dependencies, large rewrites, deploys).
    Under two sentences; make it answerable by voice.
    """
    try:
        r = await post("/api/ask", {"text": question}, timeout=3600)
    except Exception:
        return "The voice-bridge hub isn't reachable. Ask the user in the terminal instead."
    status = r.get("status")
    if status == "answered":
        return f"The user answered: {r.get('answer', '')}"
    if status == "no_phone":
        return "The user's phone isn't connected. Ask in the terminal instead."
    return (
        f"No answer from the phone within {r.get('minutes', '?')} minutes. If the action is safe "
        "and reversible, use your best judgment and report what you chose; otherwise ask in the terminal."
    )


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
