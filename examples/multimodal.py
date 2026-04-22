#!/usr/bin/env python3
"""
Send an image or audio file to the model and print its response.

Usage:
    pip install openai
    python multimodal.py --file path/to/photo.jpg
    python multimodal.py --file https://example.com/photo.jpg --prompt "What breed is this dog?"
    python multimodal.py --file clip.wav --model small

Set these environment variables before running:
    export INFERENCE_HUB_URL="http://192.168.1.100:4200/v1"
    export INFERENCE_HUB_KEY="your-api-key"

Model support notes (Gemma 4):
    - 26B MoE and 31B dense: text + image only
    - E2B and E4B: text + image + audio
    Sending audio to a text+image-only model will return a 400 error.
"""

import argparse
import base64
import mimetypes
import os
import sys
from pathlib import Path

try:
    from openai import BadRequestError, OpenAI
except ImportError:
    print("Install the OpenAI SDK first:  pip install openai")
    sys.exit(1)

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp"}
AUDIO_EXTS = {".wav", ".mp3", ".flac", ".ogg", ".m4a"}


def build_content_block(file_arg: str) -> dict:
    """Return an OpenAI-format content block for image or audio input."""
    is_url = file_arg.startswith(("http://", "https://"))
    ext = Path(file_arg).suffix.lower()

    if ext in IMAGE_EXTS:
        if is_url:
            url = file_arg
        else:
            mime, _ = mimetypes.guess_type(file_arg)
            mime = mime or "image/jpeg"
            data = base64.b64encode(Path(file_arg).read_bytes()).decode()
            url = f"data:{mime};base64,{data}"
        return {"type": "image_url", "image_url": {"url": url}}

    if ext in AUDIO_EXTS:
        if is_url:
            sys.exit("Audio via URL isn't supported — download the file and pass a local path.")
        data = base64.b64encode(Path(file_arg).read_bytes()).decode()
        return {"type": "input_audio", "input_audio": {"data": data, "format": ext.lstrip(".")}}

    sys.exit(f"Unrecognized file extension '{ext}'. Supported: {IMAGE_EXTS | AUDIO_EXTS}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Send an image or audio file to the inference hub.")
    parser.add_argument("--file", required=True, help="Path or URL to an image/audio file.")
    parser.add_argument("--prompt", default=None, help="Optional text prompt to accompany the file.")
    parser.add_argument("--model", default=os.environ.get("INFERENCE_HUB_MODEL", "small"))
    args = parser.parse_args()

    content_block = build_content_block(args.file)
    modality = content_block["type"].replace("_url", "").replace("input_", "")
    default_prompt = "Describe what you see." if modality == "image" else "Transcribe this audio."

    messages = [{"role": "user", "content": [
        {"type": "text", "text": args.prompt or default_prompt},
        content_block,
    ]}]

    base_url = os.environ.get("INFERENCE_HUB_URL", "http://localhost:4200/v1")
    api_key = os.environ.get("INFERENCE_HUB_KEY", "YOUR_KEY_HERE")
    client = OpenAI(base_url=base_url, api_key=api_key)

    print(f"Sending {modality} to '{args.model}' at {base_url}\n")
    try:
        response = client.chat.completions.create(model=args.model, messages=messages)
    except BadRequestError as err:
        print(f"Server rejected the request (400): {err.message}")
        if modality == "audio":
            print("Audio requires a Gemma 4 E2B or E4B model. 26B/31B are text+image only.")
        sys.exit(1)

    print(response.choices[0].message.content)


if __name__ == "__main__":
    main()
