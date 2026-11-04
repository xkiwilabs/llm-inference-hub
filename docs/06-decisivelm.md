# DecisiveLM (optional)

[DecisiveLM](https://github.com/xkiwilabs/decisive-lm) answers typed questions about a *state* — text, JSON, an image or an audio clip — with calibrated probabilities, in a single forward pass. Ask "is this customer angry?" or "which of these categories is this photo?" and get back a probability (or a probability per option), not generated text.

It is a Gemma 4 model plus a small adapter, in two sizes (see [Choosing a model](#choosing-a-model)). It is **not** a chat model and cannot run inside vLLM, so it runs as its own server on the same machine and the hub only routes to it. Users call it through the hub with their usual hub API key:

```
POST http://<machine-ip>:4200/decisivelm/v1/systemone
GET  http://<machine-ip>:4200/decisivelm/v1/models
```

Nothing here is needed to run the rest of the hub. With `DECISIVELM_URL` blank (the default) there is no route and nothing changes.

## Choosing a model

Both models take the same requests and give the same kinds of answers; the server, install and API are identical. Pick one per hub.

| | E4B | 26B-A4B |
|---|---|---|
| HuggingFace | [`xkiwilabs/decisivelm-e4b-general`](https://huggingface.co/xkiwilabs/decisivelm-e4b-general) | [`xkiwilabs/decisivelm-26b-a4b-general`](https://huggingface.co/xkiwilabs/decisivelm-26b-a4b-general) |
| Backbone | Gemma 4 E4B (~15 GB download) | Gemma 4 26B-A4B (~49 GB download) |
| GPU memory | ~16–18 GB; `DECISIVELM_MEMORY_GB=20` | ~55–60 GB (provisional); `DECISIVELM_MEMORY_GB=64` |
| Where it fits | Beside `vllm-small` on a 96 GB card, or alone on a 24 GB card | Needs a GPU with ~64 GB free — in practice its own GPU |
| Typical latency | ~0.1 s | ~0.45 s |
| Inputs | Text, JSON, images; audio accepted but untested | Text, JSON, images; **no audio** |

Both bundles are Apache-2.0 and public, so no token is needed to download them. Start with E4B unless you have a spare large GPU and want the bigger backbone. The model cards on HuggingFace describe each one's strengths and weak spots.

## Requirements

- **GPU memory:** see the table above, on top of what vLLM uses. The `DECISIVELM_MEMORY_GB` cap stops DecisiveLM from ever squeezing vLLM.
- **Disk:** the pinned backbone (in the HuggingFace cache) plus the bundle (under 100 MB).
- **Software:** [uv](https://docs.astral.sh/uv/) to install the DecisiveLM server.

## 1. Download the model

The easiest way is to let the hub fetch it. Add to `.env` (or the 26B repo instead):

```
DECISIVELM_BUNDLE_REPO=xkiwilabs/decisivelm-e4b-general
```

then run:

```bash
./hub pull-models
```

This downloads, alongside the small and large models:

- the bundle (adapter + scorer head + calibration) into `~/.cache/decisivelm/bundles/decisivelm-e4b-general` (change the parent dir with `DECISIVELM_BUNDLE_DIR`). The directory name is the bundle's name — what callers put in `model`;
- the exact backbone revision the bundle was trained against, read from the bundle's `calibration.json`, into the HuggingFace cache. The bundle only works with that revision and the server checks it. If your `small` or `large` model is a different revision of the same Gemma model, this is an extra download.

The server reads the default HuggingFace cache. If you set `HF_HOME` or `HF_HUB_CACHE` for the hub, give the DecisiveLM server the same setting.

To download by hand instead:

```bash
# E4B
hf download xkiwilabs/decisivelm-e4b-general --local-dir ~/.cache/decisivelm/bundles/decisivelm-e4b-general
hf download google/gemma-4-E4B-it --revision ee0ef6023621cff504d758262d4e04895a5af4a2

# 26B-A4B
hf download xkiwilabs/decisivelm-26b-a4b-general --local-dir ~/.cache/decisivelm/bundles/decisivelm-26b-a4b-general
hf download google/gemma-4-26B-A4B-it --revision 4d7ae4984b7db7de8f8457170b3f1a419ee76d52
```

## 2. Install and run the DecisiveLM server

```bash
git clone https://github.com/xkiwilabs/decisive-lm && cd decisive-lm
uv sync --extra serve                 # add --extra audio to accept audio states

DECISIVELM_BUNDLES=~/.cache/decisivelm/bundles/decisivelm-e4b-general \
DECISIVELM_HOST=127.0.0.1,172.17.0.1 \
DECISIVELM_DEVICE=cuda:0 \
DECISIVELM_MEMORY_GB=20 \
DECISIVELM_AUTH=litellm \
DECISIVELM_LITELLM_URL=http://127.0.0.1:4200 \
uv run python -m decisivelm.serve
```

For 26B-A4B, point `DECISIVELM_BUNDLES` at `~/.cache/decisivelm/bundles/decisivelm-26b-a4b-general`, set `DECISIVELM_MEMORY_GB=64`, and pick a GPU with that much free in `DECISIVELM_DEVICE` (on a two-GPU hub, not the one `vllm-large` is using). The audio extra does nothing for it. One server holds bundles of one backbone only.

What those settings do:

| Variable | Meaning |
|---|---|
| `DECISIVELM_BUNDLES` | Bundle dir, a dir of bundle dirs, or several of either comma-joined. Each bundle's name is its directory name. |
| `DECISIVELM_DEFAULT` | Optional; the bundle used when a request has no `model`. |
| `DECISIVELM_HOST` | Addresses to listen on. `127.0.0.1` for local callers; `172.17.0.1` (the Docker bridge, check with `ip -4 addr show docker0`) so the LiteLLM container can reach it. **Never `0.0.0.0`.** |
| `DECISIVELM_PORT` | Default `8003`. |
| `DECISIVELM_DEVICE` | Optional; `cuda:N` picks a GPU. Default `cuda`, else `mps`, else `cpu`. |
| `DECISIVELM_MEMORY_GB` | Hard GPU memory cap, so DecisiveLM can never squeeze vLLM. |
| `DECISIVELM_AUTH=litellm` | Check each caller's hub key against the hub (see [How auth works](#how-auth-works)). |
| `DECISIVELM_MAX_TOKENS` | Longest whole request (state + every question and option), default 12,288. A state is cut at 8,192 tokens, leaving about 4,000 for questions and options. Raising it needs more GPU memory. |

The server is yours to run — as a terminal process or a `systemd --user` service. The hub never starts or stops it, so a DecisiveLM crash or restart never touches vLLM.

**Docker (untested on GPU).** The repo's `Dockerfile` builds a server image. It runs offline, so run `./hub pull-models` first to put the backbone in the cache. Inside the container the gateway is `host.docker.internal`, not `127.0.0.1`:

```bash
docker build -t decisivelm-serve .
docker run -d --name decisivelm --gpus '"device=0"' --add-host host.docker.internal:host-gateway \
  -p 127.0.0.1:8003:8003 -p 172.17.0.1:8003:8003 \
  -v ~/.cache/huggingface/hub:/models/hub:ro -v ~/.cache/decisivelm/bundles:/bundles:ro \
  -e DECISIVELM_BUNDLES=/bundles -e DECISIVELM_MEMORY_GB=20 \
  -e DECISIVELM_AUTH=litellm -e DECISIVELM_LITELLM_URL=http://host.docker.internal:4200 \
  decisivelm-serve
```

Startup takes about a minute. The uv route above is the tested one.

Check it is up:

```bash
curl http://localhost:8003/health
```

## 3. Connect it to the hub

Add to `.env`:

```
DECISIVELM_URL=http://host.docker.internal:8003      # where LiteLLM reaches it; blank = no route
DECISIVELM_HEALTH_URL=http://localhost:8003/health   # optional, for ./hub status
```

and run `./hub restart`. `./hub status` now shows a `decisivelm` health line, and `./hub start` prints the route.

> `./hub restart` also restarts vLLM, which takes a few minutes. To pick up the route without touching vLLM, recreate only the gateway (about 10–30 s of gateway downtime):
>
> ```bash
> set -a; source .env; set +a; export HUB_DIR=$PWD
> source scripts/render-config.sh; render_litellm_config
> docker compose --env-file .env up -d --force-recreate --no-deps litellm
> ```

## Calling it

### curl

```bash
curl http://SERVER_IP:4200/decisivelm/v1/systemone \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "state": "My card was declined twice today and nobody at the bank will call me back.",
    "questions": {
      "angry": {"type": "noul", "instructions": "The customer is angry"},
      "topic": {"type": "choice", "instructions": "What is the message about?",
                "criteria": {"card": "a card payment problem", "loan": "a loan",
                             "other": "something other than cards or loans"}}
    }
  }'
```

The `Content-Type: application/json` header is required — without it the gateway answers 422.

### Python

```bash
export INFERENCE_HUB_URL="http://SERVER_IP:4200/v1"
export INFERENCE_HUB_KEY="YOUR_API_KEY"
python examples/decisivelm.py --text "My card was declined twice today."
python examples/decisivelm.py --image path/to/photo.jpg
```

[`examples/decisivelm.py`](../examples/decisivelm.py) uses only the Python standard library. In your own code:

```python
import json, os, urllib.request

req = urllib.request.Request(
    "http://SERVER_IP:4200/decisivelm/v1/systemone",
    data=json.dumps({
        "state": "My card was declined twice today.",
        "questions": {"angry": {"type": "noul", "instructions": "The customer is angry"}},
    }).encode(),
    headers={"Authorization": "Bearer YOUR_API_KEY", "Content-Type": "application/json"},
)
answer = json.load(urllib.request.urlopen(req))
print(answer["answers"]["angry"]["noul"])   # probability the statement is true
```

## Request format

`POST /decisivelm/v1/systemone` takes a JSON body. Unknown fields are rejected.

| Field | Required | Meaning |
|---|---|---|
| `state` | yes | A string, or a JSON object (arrays must be wrapped in an object). |
| `questions` | yes | An object `{id: question}`. The model never sees the ids, so `instructions` must carry the whole question. |
| `media` | no | Up to 4 images and 4 audio clips: `[{"type": "image" \| "audio", "data": "<base64>"}]`. Plain base64 of the file bytes (a `data:` URL prefix is also accepted) — not a path or URL. PNG/JPEG images; WAV/FLAC/OGG/MP3 audio (E4B only, cut at 30 s; the server needs the `audio` extra). |
| `model` | no | Which bundle answers (see `GET /decisivelm/v1/models`); defaults to the server's default bundle. |

Question types:

| Type | Shape | Answer |
|---|---|---|
| `noul` | `{"type": "noul", "instructions": "<a statement>"}` | `{"noul": p}` — the probability the statement is true of the state |
| `choice` | `{"type": "choice", "instructions": "...", "criteria": {"option": "description", ...}}` (2–255 unordered options) | `{"choice", "confidence", "probabilities": {option: p}}` |
| `score` | `{"type": "score", "instructions": "...", "criteria": ["lowest level", ..., "highest"]}` (2–10 ordered levels, numbered 0..n−1) | `{"score" (expected level, a float), "confidence", "legend", "probabilities"}` |

Options never see each other, so a catch-all like `"other"` needs a self-contained description ("something other than cards or loans"), not just "other".

The response is `{"model": "<bundle that answered>", "answers": {id: answer}, "usage": {...}}`. Errors are `{"error": {"message", "type"}}`; warnings come back in the `X-DecisiveLM-Warnings` header as a JSON list.

The full reference is in DecisiveLM's guide, [Requests and responses](https://github.com/xkiwilabs/decisive-lm/blob/main/docs/guide/04-requests-and-responses.md).

## Images and audio

```json
{
  "state": "A photo.",
  "media": [{"type": "image", "data": "<base64 of a JPEG or PNG>"}],
  "questions": {
    "subject": {"type": "choice", "instructions": "What does the photo mainly show?",
                "criteria": {"animal": "an animal", "vehicle": "a car, truck, boat or plane",
                             "other": "anything other than an animal or a vehicle"}}
  }
}
```

Both general bundles were trained on one photo task (VizWiz-VQA: whether a blind user's photo can answer their question). Other kinds of image are zero-shot, so calibrate their probabilities on ~100 labelled images of your task before you rely on review thresholds.

Audio works only with E4B (the server needs `--extra audio`), and the general bundle was not trained on audio and has not been evaluated on it. Treat audio answers as untested. The 26B-A4B backbone has no audio input at all; audio sent to it is rejected with a 400.

## How auth works

LiteLLM can only check hub keys on routes like this one with an Enterprise licence, so the hub forwards the caller's `Authorization` header and the DecisiveLM server checks the key against the hub itself (`DECISIVELM_AUTH=litellm`). In practice:

- any valid hub key can call DecisiveLM;
- LiteLLM's spend tracking and rate limits do not apply to this route — the DecisiveLM server logs usage per key (as a hash prefix, never the key);
- a deleted or rotated key keeps working for up to 5 minutes, because the server caches key checks.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `./hub status` shows `decisivelm: not responding` | The DecisiveLM server isn't running (it does not start with the hub). Start it, then check `curl http://localhost:8003/health`. |
| 5xx from `/decisivelm/...` | Same as above, or the server isn't listening on the Docker bridge address (`DECISIVELM_HOST` must include it). |
| 404 from `/decisivelm/...` | `DECISIVELM_URL` isn't set, or the gateway wasn't restarted after setting it. |
| 401 | Missing or invalid hub key. |
| 422 | Missing `Content-Type: application/json` header. |
| 400 | Invalid body — an unknown field, a top-level array as `state`, media that isn't base64 or isn't a readable image/sound file, or audio sent to a server without the `audio` extra or to a 26B-A4B server. The `error.message` says which. |
| 404 with an `error` body naming a bundle | The `model` you asked for isn't loaded on the server. |
| 413 | The request is longer than `DECISIVELM_MAX_TOKENS` (default 12,288: a state is cut at 8,192 tokens, which leaves about 4,000 for questions and options). Send fewer or shorter questions, or raise the limit on the server (more GPU memory). |
| 503 | The GPU ran out of memory, or the server couldn't reach the hub to check the key. |
