#!/usr/bin/env python3
"""
Ask DecisiveLM typed questions about a text, image or audio state, through the hub.

DecisiveLM is optional — the hub must have a DecisiveLM server connected
(see docs/06-decisivelm.md). Uses only the Python standard library.

Usage:
    python decisivelm.py --text "My card was declined twice today."
    python decisivelm.py --image path/to/photo.jpg
    python decisivelm.py --audio clip.wav
    python decisivelm.py --list-bundles

Set these environment variables before running:
    export INFERENCE_HUB_URL="http://192.168.1.100:4200/v1"
    export INFERENCE_HUB_KEY="your-api-key"
"""

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

# Example questions. Ids ("angry", "topic", ...) are never shown to the model,
# so each question's instructions must stand on their own.
TEXT_QUESTIONS = {
    "angry": {"type": "noul", "instructions": "The customer is angry"},
    "topic": {
        "type": "choice",
        "instructions": "What is the message about?",
        "criteria": {
            "card": "a card payment problem",
            "loan": "a loan",
            "other": "something other than cards or loans",
        },
    },
    "urgency": {
        "type": "score",
        "instructions": "How urgent is this message?",
        "criteria": ["not urgent", "somewhat urgent", "very urgent"],
    },
}

IMAGE_QUESTIONS = {
    "subject": {
        "type": "choice",
        "instructions": "What does the photo mainly show?",
        "criteria": {
            "animal": "an animal",
            "vehicle": "a car, truck, boat or plane",
            "other": "anything other than an animal or a vehicle",
        },
    },
    "outdoors": {"type": "noul", "instructions": "The photo was taken outdoors"},
}

AUDIO_QUESTIONS = {
    "speech": {"type": "noul", "instructions": "Someone is speaking in the recording"},
}


def hub_root() -> str:
    # INFERENCE_HUB_URL is the OpenAI base (…/v1) shared with the other examples.
    url = os.environ.get("INFERENCE_HUB_URL", "http://localhost:4200/v1").rstrip("/")
    return url[: -len("/v1")] if url.endswith("/v1") else url


def call(method: str, path: str, body: dict | None = None) -> dict:
    api_key = os.environ.get("INFERENCE_HUB_KEY", "YOUR_KEY_HERE")
    req = urllib.request.Request(
        f"{hub_root()}/decisivelm/v1{path}",
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            warnings = resp.headers.get("X-DecisiveLM-Warnings")
            if warnings:
                print(f"Warnings: {warnings}\n")
            return json.load(resp)
    except urllib.error.HTTPError as err:
        detail = err.read().decode(errors="replace")
        sys.exit(f"DecisiveLM returned {err.code}: {detail}")
    except urllib.error.URLError as err:
        sys.exit(f"Could not reach {hub_root()}: {err.reason}")


def media_item(kind: str, path: str) -> dict:
    # Plain base64 of the file bytes — not a data: URL.
    return {"type": kind, "data": base64.b64encode(Path(path).read_bytes()).decode()}


def print_answers(result: dict) -> None:
    print(f"Bundle: {result['model']}  ({result['usage']['latency_ms']:.0f} ms)\n")
    for qid, ans in result["answers"].items():
        if ans["type"] == "noul":
            print(f"{qid:10} p(true) = {ans['noul']:.3f}")
        elif ans["type"] == "choice":
            probs = ", ".join(f"{k} {v:.3f}" for k, v in ans["probabilities"].items())
            print(f"{qid:10} {ans['choice']}  (confidence {ans['confidence']:.3f}; {probs})")
        elif ans["type"] == "score":
            levels = ", ".join(f"{ans['legend'][k]} {v:.3f}" for k, v in ans["probabilities"].items())
            print(f"{qid:10} score {ans['score']:.2f}  (confidence {ans['confidence']:.3f}; {levels})")


def main() -> None:
    parser = argparse.ArgumentParser(description="Ask DecisiveLM questions through the inference hub.")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--text", help="A text state to ask about.")
    group.add_argument("--image", help="Path to a PNG or JPEG image.")
    group.add_argument("--audio", help="Path to a WAV/FLAC/OGG/MP3 clip (cut at 30 s).")
    group.add_argument("--list-bundles", action="store_true", help="List the bundles the server has loaded.")
    parser.add_argument("--bundle", help="Bundle to use (default: the server's default bundle).")
    args = parser.parse_args()

    if args.list_bundles:
        models = call("GET", "/models")
        for m in models["data"]:
            print(m["id"] + ("  (default)" if m["id"] == models.get("default") else ""))
        return

    if args.text:
        body = {"state": args.text, "questions": TEXT_QUESTIONS}
    elif args.image:
        body = {"state": "A photo.", "media": [media_item("image", args.image)], "questions": IMAGE_QUESTIONS}
    else:
        body = {"state": "An audio recording.", "media": [media_item("audio", args.audio)], "questions": AUDIO_QUESTIONS}
    if args.bundle:
        body["model"] = args.bundle

    print_answers(call("POST", "/systemone", body))


if __name__ == "__main__":
    main()
