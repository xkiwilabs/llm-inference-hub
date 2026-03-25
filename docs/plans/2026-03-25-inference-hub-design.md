# Inference Hub — Design Document

**Date:** 2026-03-25
**Status:** Approved

## Goal

A reproducible LLM inference stack that any Ubuntu workstation with NVIDIA GPUs can run via `git clone` + `./hub setup` + `./hub start`. Serves multiple models simultaneously over an OpenAI-compatible API for the team.

## Target Hardware (Phase 1)

x86 Ubuntu workstations with discrete NVIDIA GPUs: RTX 4090, RTX 5090, RTX Pro 6000 (single or dual). DGX Sparks (ARM) deferred to Phase 2.

## Stack

| Component | Role |
|---|---|
| vLLM | Inference engine — continuous batching, tensor parallelism |
| LiteLLM | Unified gateway — OpenAI-compatible API, model routing, API key auth |
| Docker Compose | Orchestration — single `docker-compose.yml`, `.env`-driven |
| Tailscale | Remote access (pre-existing, not managed by this repo) |

## Architecture Decisions

### Services (`docker-compose.yml`)

Three services:

- **vllm-small** — always runs. Serves the fast/small model on a single GPU. Port 8001 (internal only).
- **vllm-large** — conditional via `deploy.replicas: ${LARGE_MODEL_REPLICAS:-0}`. When `LARGE_MODEL` is blank, replicas=0 and no container starts. Port 8002 (internal only). The `hub` script auto-sets `LARGE_MODEL_REPLICAS=1` when `LARGE_MODEL` is non-empty.
- **litellm** — gateway. Always runs. Exposes port 4000 to host. Routes to vLLM backends.

### Model Cache

Shared HuggingFace cache at `~/.cache/huggingface` on the host. Both vLLM containers mount this read-only. `hub pull-models` and `hub set-model` download here via `huggingface-cli`. vLLM containers also have `HF_TOKEN` so they can pull at runtime if needed.

### Configuration

- **`.env`** — all hardware-specific and secret values: model names, GPU indices, tensor parallel size, memory utilization, HF token, LiteLLM master key, team API keys.
- **`litellm/config.yaml`** — model routing config. Uses LiteLLM's environment variable substitution (`os.environ/SMALL_MODEL`) to reference `.env` values at runtime. No templating step needed.
- **`docker-compose.yml`** — service definitions. Reads `.env`. Identical across all machines.

### Default Models

- Small: `openai/gpt-oss-20b` (21B MoE, MXFP4, fits in 16GB)
- Large: `openai/gpt-oss-120b` (117B MoE, MXFP4, fits in 80GB)

### API Key Management

Static keys defined in `litellm/config.yaml` via environment variables from `.env`. No database dependency.

## `hub` CLI

Single bash script at repo root. Commands:

| Command | Description |
|---|---|
| `hub setup` | Install all prerequisites, scaffold `.env` |
| `hub start` | Set replicas from `.env`, `docker compose up -d` |
| `hub stop` | `docker compose down` |
| `hub restart` | Stop + start |
| `hub status` | Container state + `nvidia-smi` GPU util + endpoint health checks |
| `hub pull-models` | Download all models in `.env` to host cache |
| `hub set-model small <model>` | Update `.env`, pull model, restart vllm-small |
| `hub set-model large <model>` | Update `.env`, pull model, restart vllm-large |
| `hub set-model large --clear` | Remove large model, set replicas to 0 |
| `hub logs [service]` | `docker compose logs -f [service]` |
| `hub help` | List commands |

### `hub setup` — Full Installer

Installs all missing prerequisites (requires `sudo`). Idempotent.

1. NVIDIA drivers — `ubuntu-drivers autoinstall` if `nvidia-smi` fails
2. Docker — official apt repo (not snap)
3. NVIDIA Container Toolkit — adds NVIDIA apt repo, installs `nvidia-ctk`
4. Docker runtime config — `nvidia-ctk runtime configure --runtime=docker`, restart Docker
5. `huggingface-cli` — `pip install huggingface-cli` (or `pipx`)
6. Copies `.env.example` to `.env` if missing
7. Prints instructions for editing `.env`

### `hub status` — Rich Status

- Container up/down state
- GPU utilization and VRAM usage via `nvidia-smi`
- HTTP health check against each model endpoint to confirm models are loaded and serving

## `.env.example`

```bash
# === HuggingFace ===
HF_TOKEN=

# === Models ===
SMALL_MODEL=openai/gpt-oss-20b
LARGE_MODEL=openai/gpt-oss-120b

# === GPU Configuration ===
SMALL_MODEL_GPU=0
LARGE_MODEL_GPUS=0,1
TENSOR_PARALLEL_SIZE=2
GPU_MEMORY_UTILIZATION=0.90

# === LiteLLM ===
LITELLM_MASTER_KEY=
LITELLM_API_KEYS=sk-team-key-1,sk-team-key-2

# === Ports ===
LITELLM_PORT=4000
```

## Repo Structure

```
inference-hub/
├── hub                         # CLI entry point (bash)
├── docker-compose.yml
├── .env.example
├── .env                        # gitignored
├── litellm/
│   └── config.yaml
├── scripts/                    # internal helpers sourced by hub
│   ├── setup.sh
│   ├── status.sh
│   └── pull-models.sh
├── docs/
│   ├── plans/
│   ├── onboarding.md
│   ├── adding-models.md
│   └── team-access.md
└── CLAUDE.md
```

## Out of Scope (Phase 1)

- ARM / DGX Spark support
- SGLang as secondary inference engine
- LiteLLM virtual key system with database
- Ansible/Terraform fleet management
