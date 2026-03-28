#!/usr/bin/env python3
"""
Test your connection to inference-hub.

Usage:
    pip install openai
    python test_connection.py

Set these environment variables before running:
    export INFERENCE_HUB_URL="http://192.168.1.100:4200/v1"
    export INFERENCE_HUB_KEY="your-api-key"

Or edit the defaults below.
"""

import os
import sys

try:
    from openai import OpenAI
except ImportError:
    print("Install the OpenAI SDK first:  pip install openai")
    sys.exit(1)

# -- Configuration --
BASE_URL = os.environ.get("INFERENCE_HUB_URL", "http://localhost:4200/v1")
API_KEY = os.environ.get("INFERENCE_HUB_KEY", "YOUR_KEY_HERE")
MODEL = os.environ.get("INFERENCE_HUB_MODEL", "small")

client = OpenAI(base_url=BASE_URL, api_key=API_KEY)

# 1. List available models
print(f"Connecting to {BASE_URL}...")
try:
    models = client.models.list()
    print(f"Available models: {[m.id for m in models.data]}")
except Exception as e:
    print(f"Connection failed: {e}")
    sys.exit(1)

# 2. Send a test message
print(f"\nSending test message to model '{MODEL}'...")
response = client.chat.completions.create(
    model=MODEL,
    messages=[{"role": "user", "content": "What is 2+2? Reply in one sentence."}],
    max_tokens=50,
)

print(f"Response: {response.choices[0].message.content}")
print(f"\nTokens used: {response.usage.total_tokens}")
print("Connection successful!")
