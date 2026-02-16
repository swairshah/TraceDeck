#!/usr/bin/env python3
"""
Realtime mic transcription with ElevenLabs Speech-to-Text.

Usage:
  python stt.py
  python stt.py --language en --commit-strategy vad
  python stt.py --list-devices

Requirements:
  pip install websockets sounddevice

This script reads ELEVENLABS_API_KEY from:
1) process environment, then
2) ~/.env
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import json
import os
import sys
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

MISSING_DEPS: list[str] = []

try:
    import sounddevice as sd
except ModuleNotFoundError:
    sd = None  # type: ignore[assignment]
    MISSING_DEPS.append("sounddevice")

try:
    import websockets
except ModuleNotFoundError:
    websockets = None  # type: ignore[assignment]
    MISSING_DEPS.append("websockets")


def load_api_key() -> str:
    key = os.getenv("ELEVENLABS_API_KEY")
    if key:
        return key

    home_env = Path.home() / ".env"
    if home_env.exists():
        for raw_line in home_env.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            var_name, var_value = line.split("=", 1)
            if var_name.strip() != "ELEVENLABS_API_KEY":
                continue
            cleaned = var_value.strip().strip("'").strip('"')
            if cleaned:
                return cleaned

    raise RuntimeError(
        "ELEVENLABS_API_KEY not found. Set it in env or in ~/.env."
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Live mic transcription via ElevenLabs WebSocket STT."
    )
    parser.add_argument(
        "--model",
        default="scribe_v2_realtime",
        help="ElevenLabs realtime STT model id",
    )
    parser.add_argument(
        "--language",
        default=None,
        help="Language code (e.g. en). Omit for auto-detect.",
    )
    parser.add_argument(
        "--commit-strategy",
        choices=("manual", "vad"),
        default="vad",
        help="Transcript commit strategy.",
    )
    parser.add_argument(
        "--manual-commit-secs",
        type=float,
        default=2.5,
        help="When using manual commit, force a commit every N seconds.",
    )
    parser.add_argument(
        "--sample-rate",
        type=int,
        default=16000,
        help="Microphone capture sample rate (PCM 16-bit).",
    )
    parser.add_argument(
        "--chunk-ms",
        type=int,
        default=100,
        help="Audio chunk size in milliseconds.",
    )
    parser.add_argument(
        "--device",
        default=None,
        help="Input device index or name (optional).",
    )
    parser.add_argument(
        "--timestamps",
        action="store_true",
        help="Request committed transcript with word timestamps.",
    )
    parser.add_argument(
        "--previous-text",
        default=None,
        help="Optional short context sent with first chunk only.",
    )
    parser.add_argument(
        "--list-devices",
        action="store_true",
        help="List audio devices and exit.",
    )
    return parser.parse_args()


def make_ws_url(args: argparse.Namespace) -> str:
    params = {
        "model_id": args.model,
        "audio_format": f"pcm_{args.sample_rate}",
        "commit_strategy": args.commit_strategy,
        "include_timestamps": "true" if args.timestamps else "false",
    }
    if args.language:
        params["language_code"] = args.language
    return (
        "wss://api.elevenlabs.io/v1/speech-to-text/realtime?"
        + urlencode(params)
    )


async def send_audio(
    websocket: Any,
    audio_queue: asyncio.Queue[bytes],
    sample_rate: int,
    commit_strategy: str,
    manual_commit_secs: float,
    previous_text: str | None,
) -> None:
    first_chunk = True
    last_commit_at = asyncio.get_running_loop().time()
    while True:
        chunk = await audio_queue.get()
        payload: dict[str, object] = {
            "message_type": "input_audio_chunk",
            "audio_base_64": base64.b64encode(chunk).decode("ascii"),
            "sample_rate": sample_rate,
        }
        if commit_strategy == "manual":
            now = asyncio.get_running_loop().time()
            should_commit = (now - last_commit_at) >= manual_commit_secs
            payload["commit"] = should_commit
            if should_commit:
                last_commit_at = now
        if first_chunk and previous_text:
            payload["previous_text"] = previous_text
        await websocket.send(json.dumps(payload))
        first_chunk = False


async def receive_events(
    websocket: Any,
) -> None:
    partial_line_active = False
    async for message in websocket:
        event = json.loads(message)
        msg_type = event.get("message_type", "")

        if msg_type == "session_started":
            session_id = event.get("session_id")
            print(f"Session started: {session_id}")
            continue

        if msg_type == "partial_transcript":
            text = (event.get("text") or "").strip()
            if text:
                sys.stdout.write(f"\r[partial] {text}   ")
                sys.stdout.flush()
                partial_line_active = True
            continue

        if msg_type in (
            "committed_transcript",
            "committed_transcript_with_timestamps",
        ):
            text = (event.get("text") or "").strip()
            if text:
                if partial_line_active:
                    sys.stdout.write("\n")
                    partial_line_active = False
                print(f"[final]   {text}")
            continue

        if "error" in msg_type:
            if partial_line_active:
                sys.stdout.write("\n")
                partial_line_active = False
            print(f"[{msg_type}] {event}")
            continue

        # Keep unknown events visible for debugging.
        print(f"[{msg_type}] {event}")


async def run(args: argparse.Namespace) -> None:
    api_key = load_api_key()
    ws_url = make_ws_url(args)
    chunk_frames = int(args.sample_rate * args.chunk_ms / 1000)
    loop = asyncio.get_running_loop()
    audio_queue: asyncio.Queue[bytes] = asyncio.Queue(maxsize=32)

    def on_audio(indata, frames, time_info, status) -> None:
        del frames, time_info
        if status:
            print(f"\n[audio-status] {status}", file=sys.stderr)
        chunk = indata.tobytes()

        def enqueue() -> None:
            if audio_queue.full():
                try:
                    audio_queue.get_nowait()
                except asyncio.QueueEmpty:
                    pass
            audio_queue.put_nowait(chunk)

        loop.call_soon_threadsafe(enqueue)

    headers = {"xi-api-key": api_key}
    connect_kwargs = {
        "max_size": None,
        "ping_interval": 20,
        "ping_timeout": 20,
    }

    # websockets versions differ between `additional_headers` and `extra_headers`.
    try:
        websocket = await websockets.connect(
            ws_url, additional_headers=headers, **connect_kwargs
        )
    except TypeError:
        websocket = await websockets.connect(
            ws_url, extra_headers=headers, **connect_kwargs
        )

    try:
        print("Connected. Speak into your mic. Press Ctrl+C to stop.")
        print(f"URL: {ws_url}")

        stream = sd.InputStream(
            samplerate=args.sample_rate,
            channels=1,
            dtype="int16",
            blocksize=chunk_frames,
            device=args.device,
            callback=on_audio,
        )

        with stream:
            await asyncio.gather(
                send_audio(
                    websocket,
                    audio_queue,
                    args.sample_rate,
                    args.commit_strategy,
                    args.manual_commit_secs,
                    args.previous_text,
                ),
                receive_events(websocket),
            )
    finally:
        await websocket.close()


def main() -> int:
    args = parse_args()

    if MISSING_DEPS:
        print(
            "Missing Python packages: "
            + ", ".join(sorted(set(MISSING_DEPS))),
            file=sys.stderr,
        )
        print(
            "Install with: pip install websockets sounddevice",
            file=sys.stderr,
        )
        return 1

    if args.list_devices:
        print(sd.query_devices())
        return 0

    try:
        asyncio.run(run(args))
        return 0
    except KeyboardInterrupt:
        print("\nStopped.")
        return 0
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
