#!/usr/bin/env python3
"""
Interactive chat session with inference-hub.

Usage:
    pip install openai
    python chat_session.py

Set these environment variables before running:
    export INFERENCE_HUB_URL="http://192.168.1.100:4200/v1"
    export INFERENCE_HUB_KEY="your-api-key"

Type 'quit' or 'exit' to end the session.
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
messages = []

print(f"Chat session with '{MODEL}' at {BASE_URL}")
print("Type 'quit' to exit.\n")

while True:
    try:
        user_input = input("You: ").strip()
    except (EOFError, KeyboardInterrupt):
        print("\nBye!")
        break

    if user_input.lower() in ("quit", "exit", "q"):
        break
    if not user_input:
        continue

    messages.append({"role": "user", "content": user_input})

    response = client.chat.completions.create(
        model=MODEL,
        messages=messages,
    )

    reply = response.choices[0].message.content
    messages.append({"role": "assistant", "content": reply})
    print(f"\nAssistant: {reply}\n")
