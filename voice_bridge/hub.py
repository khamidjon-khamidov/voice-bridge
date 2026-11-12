"""voice-bridge hub.

One long-running process. It serves the phone page, keeps a card for every
Claude Code session on this Mac, and is the meeting point between:

  * the MCP helper in each session   (report / ask_user)
  * the hook script in each session  (status requests, idle, phone mode)
  * the phone page                   (answers, status, instructions)

State lives in memory; restarting the hub forgets history.
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import os
import time
import uuid
from pathlib import Path

import psutil
import uvicorn
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import FileResponse, JSONResponse, Response, StreamingResponse
from starlette.routing import Route

from voice_bridge.tts import DEFAULT_VOICE, VOICES, tts

HOST = os.environ.get("VB_HOST", "127.0.0.1")
PORT = int(os.environ.get("VB_PORT", "8765"))
ASK_TIMEOUT = float(os.environ.get("VB_ASK_TIMEOUT", "900"))
PHONE_MODE_WAIT = float(os.environ.get("VB_PHONE_MODE_WAIT", "1800"))
PHONE_GRACE = 600  # a phone seen this recently still counts as "connected"
ENDED_TTL = 3600  # ended sessions stay on the page this long
MAX_MESSAGES = 500
STATIC = Path(__file__).parent / "static"
# Phone mode and custom names per session survive hub restarts here.
STATE_FILE = Path(os.environ.get(
    "VB_STATE_FILE", Path.home() / "Library" / "Application Support" / "voice-bridge" / "state.json"))

STATUS_PROMPT = (
    "The user pressed Status on their phone. Call the voice-bridge `report` tool "
    "now with a one-sentence progress summary, then carry on with your work."
)


def now() -> float:
    return time.time()


class Hub:
    def __init__(self) -> None:
        self.sessions: dict[str, dict] = {}
        self.saved: dict[str, dict] = self._load()
        self.messages: list[dict] = []
        self.questions: dict[str, dict] = {}
        self.subscribers: set[asyncio.Queue] = set()
        self.phone_seen = 0.0
        # Millisecond-based ids keep growing across hub restarts, so a phone
        # reconnecting with an old Last-Event-ID never skips new messages.
        self.seq = int(now() * 1000)

    # ---------- phone ----------
    def phone_present(self) -> bool:
        return bool(self.subscribers) or now() - self.phone_seen < PHONE_GRACE

    def push(self, payload: dict, eid: int | None = None) -> None:
        chunk = (f"id: {eid}\n" if eid is not None else "") + "data: " + json.dumps(payload) + "\n\n"
        for q in list(self.subscribers):
            q.put_nowait(chunk)

    def changed(self) -> None:
        self.push(self.snapshot())

    def snapshot(self) -> dict:
        order = {"waiting": 0, "needs_terminal": 1, "working": 2, "idle": 3, "ended": 4}
        sessions = sorted(self.sessions.values(), key=lambda s: (order.get(s["state"], 9), -s["started"]))
        return {
            "type": "state",
            "sessions": [self.public(s) for s in sessions],
            "questions": [
                {"qid": qid, "sid": q["sid"], "text": q["text"], "ts": q["ts"]}
                for qid, q in sorted(self.questions.items(), key=lambda kv: kv[1]["ts"])
            ],
        }

    @staticmethod
    def public(s: dict) -> dict:
        out = {k: v for k, v in s.items() if not k.startswith("_") and k != "inbox"}
        out["queued"] = len(s["inbox"])
        return out

    # ---------- messages ----------
    def add(self, s: dict | None, kind: str, text: str, speak: bool = True, **extra) -> dict:
        self.seq += 1
        m = {
            "type": "message", "id": self.seq, "sid": s["id"] if s else None,
            "label": s["label"] if s else "", "kind": kind, "text": text,
            "speak": speak, "ts": now(), **extra,
        }
        if speak:
            # Say which session is talking only when more than one is running.
            several = sum(1 for x in self.sessions.values() if x["state"] != "ended") > 1
            who = (s["label"] if s and several else "").replace("_", " ").replace(" · ", ", ").strip()
            m["say"] = (f"{who} asks: {text}" if kind == "question" else f"{who}: {text}") if who else text
            m["natural"] = tts.can_say(m["say"])
        self.messages.append(m)
        del self.messages[:-MAX_MESSAGES]
        if s and kind == "report":
            s["last"] = text
        self.push(m, m["id"])
        return m

    def after(self, last: int | None) -> list[dict]:
        if last is None:
            return self.messages[-100:]
        return [m for m in self.messages if m["id"] > last]

    # ---------- sessions ----------
    def upsert(self, d: dict) -> dict:
        key = d.get("key") or "unknown"
        s = self.sessions.get(key)
        if s is None:
            cwd = d.get("cwd") or ""
            name = Path(cwd).name or "session"
            branch = d.get("branch")
            saved = self.saved.get(key, {})
            s = {
                "id": key, "label": self._unique_label(saved.get("label") or (f"{name} · {branch}" if branch else name)),
                "auto_label": not saved.get("label"), "cwd": cwd, "branch": branch, "pid": d.get("pid"),
                "claude_session_id": d.get("claude_session_id"), "state": "working", "last": "",
                "phone_mode": bool(saved.get("phone_mode")), "phone_waiting_until": None, "status_requested": False,
                "inbox": [], "started": now(), "updated": now(), "_wake": asyncio.Event(),
            }
            self.sessions[key] = s
            self.add(s, "system", f"New session: {s['label']}", speak=False)
        else:
            if d.get("pid") and not s["pid"]:
                s["pid"] = d["pid"]
            if d.get("claude_session_id"):
                s["claude_session_id"] = d["claude_session_id"]
            if d.get("branch") and d["branch"] != s["branch"]:
                s["branch"] = d["branch"]
                if s["auto_label"]:
                    s["label"] = self._unique_label(f"{Path(s['cwd']).name} · {d['branch']}", s["id"])
            if s["state"] == "ended":
                s["state"] = "working"
        s["updated"] = now()
        return s

    # ---------- saved state ----------
    @staticmethod
    def _load() -> dict:
        try:
            data = json.loads(STATE_FILE.read_text())
            return data if isinstance(data, dict) else {}
        except Exception:
            return {}

    def save(self) -> None:
        for s in self.sessions.values():
            entry = {"phone_mode": s["phone_mode"], "label": None if s["auto_label"] else s["label"]}
            if s["state"] == "ended" or not (entry["phone_mode"] or entry["label"]):
                self.saved.pop(s["id"], None)
            else:
                self.saved[s["id"]] = entry
        try:
            STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
            STATE_FILE.write_text(json.dumps(self.saved))
        except Exception:
            pass

    def set_phone_mode(self, s: dict, on: bool, why: str) -> None:
        if s["phone_mode"] == on:
            return
        s["phone_mode"] = on
        if not on:
            s["_wake"].set()  # release a waiting Stop hook
        self.add(s, "system", why, speak=False)
        self.save()

    def _unique_label(self, label: str, own: str | None = None) -> str:
        taken = {x["label"] for x in self.sessions.values() if x["state"] != "ended" and x["id"] != own}
        base, n = label, 2
        while label in taken:
            label, n = f"{base} #{n}", n + 1
        return label

    def deliver(self, s: dict) -> str | None:
        """Text to slip into Claude's context: status request and phone messages."""
        parts = []
        if s["status_requested"]:
            s["status_requested"] = False
            parts.append(STATUS_PROMPT)
        if s["inbox"]:
            parts += [f"Message from the user, sent from their phone: {t}" for t in s["inbox"]]
            parts.append("The user is listening on their phone: answer them with the voice-bridge "
                         "`report` tool (under two sentences), as well as in the terminal.")
            s["inbox"].clear()
            self.add(s, "system", "Delivered to Claude.", speak=False)
        return "\n".join(parts) or None


hub = Hub()


async def body(req: Request) -> dict:
    try:
        data = await req.json()
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


async def wait_event(req: Request, event: asyncio.Event, timeout: float) -> str:
    """Wait for event; give up on timeout or if the caller hangs up."""
    end = now() + timeout
    while True:
        if event.is_set():
            return "set"
        if await req.is_disconnected():
            return "gone"
        left = end - now()
        if left <= 0:
            return "timeout"
        with contextlib.suppress(asyncio.TimeoutError):
            await asyncio.wait_for(event.wait(), min(1.0, left))


def session_or_404(sid: str | None):
    s = hub.sessions.get(sid or "")
    return s, (None if s else JSONResponse({"error": "No such session."}, status_code=404))


# ---------- helper API (MCP tools) ----------
async def api_report(req: Request):
    d = await body(req)
    s = hub.upsert(d)
    hub.add(s, "report", (d.get("text") or "").strip())
    hub.changed()
    return JSONResponse({"ok": True, "phone": hub.phone_present()})


async def api_ask(req: Request):
    d = await body(req)
    s = hub.upsert(d)
    text = (d.get("text") or "").strip()
    if not hub.phone_present():
        hub.add(s, "system", f"Asked while your phone was away: {text}", speak=False)
        hub.changed()
        return JSONResponse({"status": "no_phone"})

    qid = uuid.uuid4().hex[:10]
    q = {"sid": s["id"], "text": text, "ts": now(), "event": asyncio.Event(), "answer": None}
    hub.questions[qid] = q
    s["state"] = "waiting"
    hub.add(s, "question", text, qid=qid)
    hub.changed()

    result = await wait_event(req, q["event"], ASK_TIMEOUT)
    if hub.questions.pop(qid, None) is not None:  # not answered
        if s["state"] == "waiting" and not any(x["sid"] == s["id"] for x in hub.questions.values()):
            s["state"] = "working"
        hub.add(s, "system", "Question expired without an answer." if result == "timeout"
                else "Question withdrawn.", speak=False)
        hub.changed()
    if result == "set":
        return JSONResponse({"status": "answered", "answer": q["answer"]})
    return JSONResponse({"status": "timeout", "minutes": max(1, round(ASK_TIMEOUT / 60))})


# ---------- hook API ----------
async def api_hook(req: Request):
    d = await body(req)
    ev = d.get("event") or ""
    inp = d.get("input") or {}
    s = hub.upsert(d)
    context = block = None

    if ev == "SessionStart":
        s["state"] = "idle"
    elif ev == "UserPromptSubmit":
        s["state"] = "working"
        # Typing in the terminal means you're back at the desk, unless this
        # prompt is just carrying phone messages that were waiting.
        if not s["inbox"]:
            hub.set_phone_mode(s, False, "Phone mode off: you typed in the terminal.")
        context = hub.deliver(s)
    elif ev == "PostToolUse":
        if s["state"] in ("idle", "needs_terminal"):
            s["state"] = "working"
        context = hub.deliver(s)
    elif ev == "Notification":
        msg = inp.get("message") or ""
        if inp.get("notification_type") == "permission_prompt" or "permission" in msg.lower():
            s["state"] = "needs_terminal"
            hub.add(s, "system", "Needs you at the terminal: " + (msg or "permission prompt"))
    elif ev == "SessionEnd":
        s["state"] = "ended"
    elif ev == "Stop":
        block = hub.deliver(s)
        if not block:
            s["state"] = "idle"
            hub.add(s, "system", "Finished.", speak=False)
            if s["phone_mode"]:
                s["_wake"].clear()
                s["phone_waiting_until"] = now() + PHONE_MODE_WAIT
                hub.changed()
                result = await wait_event(req, s["_wake"], PHONE_MODE_WAIT)
                s["phone_waiting_until"] = None
                if result == "set" and s["inbox"]:
                    block = hub.deliver(s)
        if block:
            s["state"] = "working"

    hub.changed()
    return JSONResponse({"context": context, "block": block})


# ---------- phone API ----------
async def api_answer(req: Request):
    d = await body(req)
    q = hub.questions.pop(d.get("qid") or "", None)
    if q is None:
        return JSONResponse({"error": "That question is no longer open."}, status_code=404)
    q["answer"] = (d.get("text") or "").strip()
    s = hub.sessions.get(q["sid"])
    if s and s["state"] == "waiting" and not any(x["sid"] == s["id"] for x in hub.questions.values()):
        s["state"] = "working"
    hub.add(s, "answer", q["answer"], speak=False, qid=d.get("qid"))
    q["event"].set()
    if s:
        hub.set_phone_mode(s, True, "Phone mode on: you answered from the phone.")
    hub.changed()
    return JSONResponse({"ok": True})


async def api_status(req: Request):
    d = await body(req)
    target = d.get("id")
    targets = [s for s in hub.sessions.values()
               if s["state"] != "ended" and (target in (None, "all") or s["id"] == target)]
    if not targets:
        hub.add(None, "status", "No active sessions.")
    for s in targets:
        st = s["state"]
        if st == "working":
            s["status_requested"] = True
            hub.add(s, "system", "Asked Claude for a status…", speak=False)
        elif st == "waiting":
            q = next((x for x in hub.questions.values() if x["sid"] == s["id"]), None)
            hub.add(s, "status", "Waiting for your answer" + (f": {q['text']}" if q else "."))
        elif st == "needs_terminal":
            hub.add(s, "status", "Needs you at the terminal.")
        else:
            hub.add(s, "status", "Idle. Last update: " + (s["last"] or "none yet."))
    hub.changed()
    return JSONResponse({"ok": True})


async def api_instruct(req: Request):
    d = await body(req)
    s, err = session_or_404(d.get("id"))
    if err:
        return err
    text = (d.get("text") or "").strip()
    if not text:
        return JSONResponse({"error": "Empty message."}, status_code=400)
    s["inbox"].append(text)
    hub.add(s, "instruction", text, speak=False)
    hub.set_phone_mode(s, True, "Phone mode on: you're messaging from the phone.")
    delivery = "next_step"
    if s["phone_waiting_until"]:
        s["_wake"].set()
        delivery = "now"
    elif s["state"] == "idle":
        delivery = "queued_idle"
        hub.add(s, "system", "Claude had already stopped, so this one waits for your next terminal "
                "prompt. After that, phone mode keeps it listening to the phone.")
    hub.changed()
    return JSONResponse({"ok": True, "delivery": delivery})


async def api_phone_mode(req: Request):
    d = await body(req)
    s, err = session_or_404(d.get("id"))
    if err:
        return err
    on = bool(d.get("on"))
    hub.set_phone_mode(s, on, "Phone mode on." if on else "Phone mode off.")
    hub.changed()
    return JSONResponse({"ok": True})


async def api_label(req: Request):
    d = await body(req)
    s, err = session_or_404(d.get("id"))
    if err:
        return err
    label = (d.get("label") or "").strip()[:40]
    if label:
        s["label"], s["auto_label"] = hub._unique_label(label, s["id"]), False
        hub.save()
    hub.changed()
    return JSONResponse({"ok": True})


async def api_forget(req: Request):
    d = await body(req)
    s = hub.sessions.get(d.get("id") or "")
    if s and s["state"] == "ended":
        del hub.sessions[s["id"]]
        hub.changed()
    return JSONResponse({"ok": True})


async def events(req: Request):
    raw = req.headers.get("last-event-id")
    last = int(raw) if raw and raw.isdigit() else None
    q: asyncio.Queue = asyncio.Queue()
    hub.subscribers.add(q)
    hub.phone_seen = now()

    async def stream():
        try:
            yield "retry: 2000\n\n"
            yield "data: " + json.dumps(hub.snapshot()) + "\n\n"
            for m in hub.after(last):
                yield f"id: {m['id']}\ndata: " + json.dumps({**m, "replay": True}) + "\n\n"
            while True:
                try:
                    chunk = await asyncio.wait_for(q.get(), 15)
                except asyncio.TimeoutError:
                    chunk = ": ping\n\n"
                hub.phone_seen = now()
                yield chunk
        finally:
            hub.subscribers.discard(q)
            hub.phone_seen = now()

    return StreamingResponse(stream(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


async def index(_: Request):
    return FileResponse(STATIC / "index.html", headers={"Cache-Control": "no-store"})


async def voices(_: Request):
    return JSONResponse({
        "available": tts.available(), "default": DEFAULT_VOICE,
        "voices": [{"id": k, "name": v} for k, v in VOICES.items()],
    })


async def audio(req: Request):
    """MP3 of one message in a natural voice, made on demand and cached."""
    mid = req.path_params["mid"]
    if mid == 0:  # voice preview from the picker
        m = {"say": "Hi, this is how I sound.", "natural": True}
    else:
        m = next((x for x in reversed(hub.messages) if x["id"] == mid), None)
    if m is None or not m.get("say"):
        return JSONResponse({"error": "No such message."}, status_code=404)
    if not (tts.available() and m.get("natural")):
        return JSONResponse({"error": "Natural voice unavailable for this message."}, status_code=503)
    try:
        data = await tts.mp3(m["say"], req.query_params.get("voice") or DEFAULT_VOICE)
    except Exception as e:  # fall back to the phone's own voice
        print(f"audio {mid}: failed: {e}", flush=True)
        return JSONResponse({"error": f"Speech failed: {e}"}, status_code=500)
    print(f"audio {mid}: {len(data) // 1024} KB sent", flush=True)
    return Response(data, media_type="audio/mpeg", headers={"Cache-Control": "private, max-age=3600"})


async def health(_: Request):
    return JSONResponse({"ok": True, "sessions": len(hub.sessions), "phone": hub.phone_present()})


async def reaper() -> None:
    """Mark sessions ended when their Claude process is gone; drop old ones."""
    while True:
        await asyncio.sleep(10)
        dirty = False
        for key, s in list(hub.sessions.items()):
            if s["state"] != "ended" and s["pid"] and not psutil.pid_exists(s["pid"]):
                s["state"], s["updated"], dirty = "ended", now(), True
                s["_wake"].set()
            if s["state"] == "ended" and now() - s["updated"] > ENDED_TTL:
                del hub.sessions[key]
                dirty = True
        if dirty:
            hub.save()
            hub.changed()


@contextlib.asynccontextmanager
async def lifespan(_app):
    task = asyncio.create_task(reaper())
    asyncio.get_running_loop().run_in_executor(None, tts.warm)  # first message plays without a cold start
    yield
    task.cancel()


app = Starlette(
    routes=[
        Route("/", index),
        Route("/health", health),
        Route("/api/voices", voices),
        Route("/audio/{mid:int}", audio),
        Route("/events", events),
        Route("/api/report", api_report, methods=["POST"]),
        Route("/api/ask", api_ask, methods=["POST"]),
        Route("/api/hook", api_hook, methods=["POST"]),
        Route("/api/answer", api_answer, methods=["POST"]),
        Route("/api/status", api_status, methods=["POST"]),
        Route("/api/instruct", api_instruct, methods=["POST"]),
        Route("/api/phone_mode", api_phone_mode, methods=["POST"]),
        Route("/api/label", api_label, methods=["POST"]),
        Route("/api/forget", api_forget, methods=["POST"]),
    ],
    lifespan=lifespan,
)


def main() -> None:
    uvicorn.run(app, host=HOST, port=PORT, log_level="warning")


if __name__ == "__main__":
    main()
