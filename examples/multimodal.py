#!/usr/bin/env python3
"""
Send an image to the model and print its response.

Usage:
    pip install openai
    python multimodal.py --file path/to/photo.jpg
    python multimodal.py --file https://example.com/photo.jpg --prompt "What breed is this dog?"
    python multimodal.py --file diagram.png --model large

Set these environment variables before running:
    export INFERENCE_HUB_URL="http://192.168.1.100:4200/v1"
    export INFERENCE_HUB_KEY="your-api-key"

Image support (Gemma 4):
    All Gemma 4 variants (E2B, E4B, 26B MoE, 31B dense) accept image input.
    For audio, use examples/audio.py — audio only works with E2B / E4B.
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


def build_image_block(file_arg: str) -> dict:
    is_url = file_arg.startswith(("http://", "https://"))
    ext = Path(file_arg).suffix.lower()

    if ext not in IMAGE_EXTS:
        sys.exit(f"Unsupported image extension '{ext}'. Supported: {sorted(IMAGE_EXTS)}")

    if is_url:
        url = file_arg
    else:
        mime, _ = mimetypes.guess_type(file_arg)
        mime = mime or "image/jpeg"
        data = base64.b64encode(Path(file_arg).read_bytes()).decode()
        url = f"data:{mime};base64,{data}"
    return {"type": "image_url", "image_url": {"url": url}}


def main() -> None:
    parser = argparse.ArgumentParser(description="Send an image to the inference hub.")
    parser.add_argument("--file", required=True, help="Path or URL to an image file.")
    parser.add_argument("--prompt", default="Describe what you see.", help="Prompt to send alongside the image.")
    parser.add_argument("--model", default=os.environ.get("INFERENCE_HUB_MODEL", "small"))
    args = parser.parse_args()

    image_block = build_image_block(args.file)

    messages = [{"role": "user", "content": [
        {"type": "text", "text": args.prompt},
        image_block,
    ]}]

    base_url = os.environ.get("INFERENCE_HUB_URL", "http://localhost:4200/v1")
    api_key = os.environ.get("INFERENCE_HUB_KEY", "YOUR_KEY_HERE")
    client = OpenAI(base_url=base_url, api_key=api_key)

    print(f"Sending image to '{args.model}' at {base_url}\n")
    try:
        response = client.chat.completions.create(model=args.model, messages=messages)
    except BadRequestError as err:
        print(f"Server rejected the request (400): {err.message}")
        sys.exit(1)

    print(response.choices[0].message.content)


if __name__ == "__main__":
    main()
