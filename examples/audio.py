#!/usr/bin/env python3
"""
Send an audio clip to the model and print its response.

Usage:
    pip install openai
    python audio.py --file clip.wav
    python audio.py --file speech.mp3 --prompt "Translate this to French."

Set these environment variables before running:
    export INFERENCE_HUB_URL="http://192.168.1.100:4200/v1"
    export INFERENCE_HUB_KEY="your-api-key"

Audio support (Gemma 4):
    - E2B / E4B: text + image + audio  (use these)
    - 26B MoE / 31B dense: text + image only (will return 400 on audio)

The default 'small' model (Gemma 4 E4B) supports audio. 'large' (26B MoE) does not.
"""

import argparse
import base64
import os
import sys
from pathlib import Path

try:
    from openai import BadRequestError, OpenAI
except ImportError:
    print("Install the OpenAI SDK first:  pip install openai")
    sys.exit(1)

AUDIO_EXTS = {".wav", ".mp3", ".flac", ".ogg", ".m4a"}


def build_audio_block(file_path: str) -> dict:
    ext = Path(file_path).suffix.lower()
    if ext not in AUDIO_EXTS:
        sys.exit(f"Unsupported audio extension '{ext}'. Supported: {sorted(AUDIO_EXTS)}")
    data = base64.b64encode(Path(file_path).read_bytes()).decode()
    return {"type": "input_audio", "input_audio": {"data": data, "format": ext.lstrip(".")}}


def main() -> None:
    parser = argparse.ArgumentParser(description="Send an audio clip to the inference hub.")
    parser.add_argument("--file", required=True, help="Path to a local audio file (wav, mp3, flac, ogg, m4a).")
    parser.add_argument("--prompt", default="Transcribe this audio.", help="Prompt to send alongside the audio.")
    parser.add_argument("--model", default=os.environ.get("INFERENCE_HUB_MODEL", "small"),
                        help="Model to call (default: 'small' = Gemma 4 E4B, which supports audio).")
    args = parser.parse_args()

    audio_block = build_audio_block(args.file)

    messages = [{"role": "user", "content": [
        {"type": "text", "text": args.prompt},
        audio_block,
    ]}]

    base_url = os.environ.get("INFERENCE_HUB_URL", "http://localhost:4200/v1")
    api_key = os.environ.get("INFERENCE_HUB_KEY", "YOUR_KEY_HERE")
    client = OpenAI(base_url=base_url, api_key=api_key)

    print(f"Sending audio to '{args.model}' at {base_url}\n")
    try:
        response = client.chat.completions.create(model=args.model, messages=messages)
    except BadRequestError as err:
        print(f"Server rejected the request (400): {err.message}")
        print("Audio requires Gemma 4 E2B or E4B. The 'large' model (26B MoE) is text+image only —")
        print("retry with --model small, which routes to Gemma 4 E4B by default.")
        sys.exit(1)

    print(response.choices[0].message.content)


if __name__ == "__main__":
    main()
