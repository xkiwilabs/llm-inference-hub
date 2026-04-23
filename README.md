# inference-hub

A reproducible LLM inference stack built on vLLM + LiteLLM, designed for multi-GPU Ubuntu workstations. Serves multiple models simultaneously over a single OpenAI-compatible API.

Ships with **Google Gemma 4** by default: a small multimodal model (text + image + audio) and a large MoE model for heavier reasoning.

## What you get

- **Multiple models running at once** — default: Gemma 4 E4B (small, ~6.3GB 4-bit) + Gemma 4 26B-A4B MoE (large)
- **Multimodal by default** — text + image on both models, plus audio on the small model
- **Tool calling** pre-wired with Gemma 4's native tool-call format
- **Parallel request handling** via vLLM's continuous batching
- **One unified API endpoint** for the whole team (`http://<machine>:4200/v1`)
- **OpenAI-compatible** — works with any tool that speaks the OpenAI API
- **Anthropic-compatible** — also works with tools that speak the Anthropic Messages API
- **One command to start** on any workstation

## Quick start

```bash
git clone <repo-url>
cd inference-hub
./hub setup                    # installs everything, detects GPUs
# edit .env to add your HF_TOKEN
./hub pull-models              # download models
./hub start                    # start the stack
./hub status                   # verify everything is healthy
```

Setup auto-detects your hardware and configures everything. The only manual step is adding your [HuggingFace token](https://huggingface.co/settings/tokens).

## Connect to the API

```
OpenAI endpoint:    http://<machine-ip>:4200/v1
Anthropic endpoint: http://<machine-ip>:4200/anthropic/v1
API Key:            your API key (create with `./hub add-key`)
Model:              "small" or "large"
```

Works with any OpenAI- or Anthropic-compatible client — Python, JavaScript, curl, Open WebUI, LangChain, Cursor, etc.

## Documentation

| Doc | Description |
|---|---|
| [Server Setup](docs/01-server-setup.md) | Full walkthrough for setting up a new workstation |
| [Client Connection](docs/02-client-connection.md) | How to connect from any machine or tool |
| [Examples](docs/03-examples.md) | Python scripts, curl, JavaScript, Open WebUI, Agent Frameworks |
| [Managing Models](docs/04-managing-models.md) | Swapping models, adding/removing the large model |
| [Troubleshooting](docs/05-troubleshooting.md) | Common issues and fixes |

## Hub commands

| Command | What it does |
|---|---|
| `./hub setup` | Install prerequisites, detect hardware |
| `./hub start` | Start all services |
| `./hub stop` | Stop all services |
| `./hub restart` | Stop + start |
| `./hub status` | Container state, GPU usage, health checks |
| `./hub pull-models` | Download models to local cache |
| `./hub set-model small <model>` | Switch the small model |
| `./hub set-model large <model>` | Switch the large model |
| `./hub set-model large --clear` | Disable the large model |
| `./hub add-key <name>` | Create a named API key |
| `./hub list-keys` | List all API keys and usage |
| `./hub delete-key <name>` | Revoke an API key |
| `./hub usage [name]` | Show spend/token usage summary |
| `./hub metrics` | Show live model and request metrics |
| `./hub logs [service]` | Tail logs (`vllm-small`, `vllm-large`, `litellm`, `postgres`) |

## Default models

| Alias | Model | Size | Modalities |
|---|---|---|---|
| `small` | `google/gemma-4-E4B-it` | ~8B params (6.3GB 4-bit) | text + image + **audio** |
| `large` | `google/gemma-4-26B-A4B-it` | 26B MoE, 4B active | text + image |

Both support tool calling via Gemma 4's native parser. Swap either with `./hub set-model small|large <hf-model-id>` — see [Managing Models](docs/04-managing-models.md).

## Hardware reference

| Hardware | VRAM | Config |
|---|---|---|
| RTX 4090 | 24GB | Small model only (E4B fits comfortably) |
| RTX 5090 | 32GB | Small model only |
| RTX Pro 6000 x2 | 192GB | Small + large (default) |

Setup auto-detects your hardware and configures `.env` accordingly.
