#!/usr/bin/env python3
"""
Streaming example — see tokens arrive in real time.

Usage:
    pip install openai
    python streaming.py

Set these environment variables before running:
    export INFERENCE_HUB_URL="http://192.168.1.100:4200/v1"
    export INFERENCE_HUB_KEY="mind-team-your-key-here"
"""

import os
import sys

try:
    from openai import OpenAI
except ImportError:
    print("Install the OpenAI SDK first:  pip install openai")
    sys.exit(1)

BASE_URL = os.environ.get("INFERENCE_HUB_URL", "http://localhost:4200/v1")
API_KEY = os.environ.get("INFERENCE_HUB_KEY", "YOUR_KEY_HERE")
MODEL = os.environ.get("INFERENCE_HUB_MODEL", "small")

client = OpenAI(base_url=BASE_URL, api_key=API_KEY)

print(f"Streaming from '{MODEL}'...\n")

stream = client.chat.completions.create(
    model=MODEL,
    messages=[{"role": "user", "content": "Write a short poem about GPUs."}],
    stream=True,
)

for chunk in stream:
    if chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="", flush=True)

print("\n")
