# inference-hub

A reproducible LLM inference stack built on vLLM + LiteLLM, designed for multi-GPU Ubuntu workstations. Serves multiple models simultaneously over a single OpenAI-compatible API.

## What you get

- **Multiple models running at once** (e.g. a fast 20B and a large 120B)
- **Parallel request handling** via vLLM's continuous batching
- **One unified API endpoint** for the whole team (`http://<machine>:4200/v1`)
- **OpenAI-compatible** — works with any tool that speaks the OpenAI API
- **One command to start** on any workstation

## Quick start

```bash
git clone git@github.com:YOUR_ORG/inference-hub.git
cd inference-hub
./hub setup                    # installs everything, detects GPUs, generates API keys
# edit .env to add your HF_TOKEN
./hub pull-models              # download models
./hub start                    # start the stack
./hub status                   # verify everything is healthy
```

Setup auto-detects your hardware and configures everything. The only manual step is adding your [HuggingFace token](https://huggingface.co/settings/tokens).

## Connect to the API

```
Base URL:  http://<machine-ip>:4200/v1
API Key:   your mind-team-xxx key (printed during setup)
Model:     "small" or "large"
```

Works with any OpenAI-compatible client — Python, JavaScript, curl, Open WebUI, LangChain, Cursor, Urika, etc.

## Documentation

| Doc | Description |
|---|---|
| [Server Setup](docs/01-server-setup.md) | Full walkthrough for setting up a new workstation |
| [Client Connection](docs/02-client-connection.md) | How to connect from any machine or tool |
| [Examples](docs/03-examples.md) | Python scripts, curl, JavaScript, Open WebUI, Urika |
| [Managing Models](docs/04-managing-models.md) | Swapping models, adding/removing the large model |
| [Troubleshooting](docs/05-troubleshooting.md) | Common issues and fixes |

## Hub commands

| Command | What it does |
|---|---|
| `./hub setup` | Install prerequisites, detect hardware, generate keys |
| `./hub start` | Start all services |
| `./hub stop` | Stop all services |
| `./hub restart` | Stop + start |
| `./hub status` | Container state, GPU usage, health checks |
| `./hub pull-models` | Download models to local cache |
| `./hub set-model small <model>` | Switch the small model |
| `./hub set-model large <model>` | Switch the large model |
| `./hub set-model large --clear` | Disable the large model |
| `./hub logs [service]` | Tail logs (`vllm-small`, `vllm-large`, `litellm`) |

## Hardware reference

| Hardware | VRAM | Config |
|---|---|---|
| RTX 4090 | 24GB | Small model only |
| RTX 5090 | 32GB | Small model only |
| RTX Pro 6000 x2 | 192GB | Small + large |

Setup auto-detects your hardware and configures `.env` accordingly.
