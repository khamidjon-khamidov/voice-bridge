"""Natural speech with Kokoro, run locally on the Mac (ONNX, CPU).

The hub turns a message into a small MP3 and the phone plays it. If the model
files are missing, or the text isn't English, the phone falls back to the
browser's own (robotic) voice.
"""

from __future__ import annotations

import asyncio
import io
import os
import re
import threading
from collections import OrderedDict
from pathlib import Path

MODEL_DIR = Path(os.environ.get(
    "VB_TTS_DIR", Path.home() / "Library" / "Application Support" / "voice-bridge" / "models"))
MODEL = MODEL_DIR / "kokoro-v1.0.onnx"
VOICES_FILE = MODEL_DIR / "voices-v1.0.bin"
SPEED = float(os.environ.get("VB_TTS_SPEED", "1.05"))

VOICES = {
    "af_heart": "Heart · US woman",
    "af_bella": "Bella · US woman",
    "af_nicole": "Nicole · US woman, soft",
    "am_michael": "Michael · US man",
    "am_fenrir": "Fenrir · US man",
    "bf_emma": "Emma · UK woman",
    "bm_george": "George · UK man",
}
DEFAULT_VOICE = os.environ.get("VB_TTS_VOICE", "af_heart")
if DEFAULT_VOICE not in VOICES:
    DEFAULT_VOICE = "af_heart"

# Kokoro's English model reads Cyrillic and other scripts badly; leave those to the phone.
NON_LATIN = re.compile(r"[^\x00-ɏ -⁯₠-⃏]")


class TTS:
    def __init__(self) -> None:
        self._model = None
        self._lock = threading.Lock()
        self._cache: OrderedDict[tuple[str, str], bytes] = OrderedDict()

    @staticmethod
    def available() -> bool:
        return MODEL.exists() and VOICES_FILE.exists()

    @staticmethod
    def can_say(text: str) -> bool:
        return bool(text.strip()) and not NON_LATIN.search(text)

    def _load(self):
        if self._model is None:
            from kokoro_onnx import Kokoro
            self._model = Kokoro(str(MODEL), str(VOICES_FILE))
        return self._model

    def warm(self) -> None:
        if self.available():
            with self._lock:
                self._load().create("Ready.", voice=DEFAULT_VOICE, speed=SPEED, lang="en-us")

    def synth(self, text: str, voice: str) -> bytes:
        import soundfile as sf

        voice = voice if voice in VOICES else DEFAULT_VOICE
        key = (text, voice)
        if key in self._cache:
            self._cache.move_to_end(key)
            return self._cache[key]
        with self._lock:
            samples, rate = self._load().create(text, voice=voice, speed=SPEED, lang="en-us")
        buf = io.BytesIO()
        sf.write(buf, samples, rate, format="MP3", subtype="MPEG_LAYER_III")
        data = buf.getvalue()
        self._cache[key] = data
        while len(self._cache) > 200:
            self._cache.popitem(last=False)
        return data

    async def mp3(self, text: str, voice: str) -> bytes:
        return await asyncio.to_thread(self.synth, text, voice)


tts = TTS()
