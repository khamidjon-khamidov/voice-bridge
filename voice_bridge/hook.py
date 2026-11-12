"""voice-bridge hook script, one for every hook event.

Claude Code pipes the hook input as JSON on stdin. We forward it to the hub
and turn the hub's reply into hook output:

  PostToolUse / UserPromptSubmit -> additionalContext (status request, phone messages)
  Stop                           -> {"decision": "block"} when a phone message arrives

Fails open: if the hub is down, the hook prints nothing and exits 0.
Stdlib + psutil only, to stay fast on every tool call.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.request

from voice_bridge.common import HUB_URL, PHONE_MODE_WAIT, git_branch, session_key


def main() -> None:
    try:
        inp = json.load(sys.stdin)
    except Exception:
        return
    event = inp.get("hook_event_name") or ""
    key, pid = session_key()
    if not key:
        return
    cwd = inp.get("cwd") or os.getcwd()
    payload = {
        "key": key, "pid": pid, "cwd": cwd, "event": event,
        "claude_session_id": inp.get("session_id"),
        "input": {k: inp.get(k) for k in ("message", "notification_type", "stop_hook_active", "source")},
    }
    if event in ("SessionStart", "UserPromptSubmit"):
        payload["branch"] = git_branch(cwd)

    timeout = PHONE_MODE_WAIT + 60 if event == "Stop" else 3
    try:
        req = urllib.request.Request(
            HUB_URL + "/api/hook", data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            res = json.load(resp)
    except Exception:
        return

    if event == "Stop" and res.get("block"):
        print(json.dumps({"decision": "block", "reason": res["block"]}))
    elif event in ("PostToolUse", "UserPromptSubmit") and res.get("context"):
        print(json.dumps({"hookSpecificOutput": {"hookEventName": event, "additionalContext": res["context"]}}))


if __name__ == "__main__":
    main()
