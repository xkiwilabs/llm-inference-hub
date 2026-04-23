# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A reproducible LLM inference stack (vLLM + LiteLLM + PostgreSQL) for multi-GPU Ubuntu workstations, serving multiple simultaneous models via unified OpenAI-compatible and Anthropic-compatible APIs. Designed for heterogeneous hardware (24GB RTX 4090 through 192GB dual RTX Pro 6000).

## Stack

- **vLLM** — inference engine (continuous batching, tensor parallelism, MXFP4 via Marlin on Ampere)
- **LiteLLM** — unified API gateway (routing, API key auth, usage tracking). Serves both OpenAI (`/v1`) and Anthropic (`/anthropic/v1`) endpoints.
- **PostgreSQL** — stores virtual API keys and per-user usage data
- **Docker Compose** — orchestration (single `docker-compose.yml` for the full stack)
- **Tailscale** — remote access (network-layer auth, not managed by this repo)

## Commands

Everything goes through the `hub` CLI at the repo root:

```bash
./hub setup                          # install prerequisites, scaffold .env
./hub start                          # start all services
./hub stop                           # stop all services
./hub restart                        # stop + start
./hub status                         # containers + GPU util + health checks
./hub pull-models                    # download models in .env to host cache
./hub set-model small <model>        # change small model (updates .env, pulls, restarts)
./hub set-model large <model>        # change large model
./hub set-model large --clear        # disable large model
./hub add-key <name>                 # create an API key for a user
./hub list-keys                      # list all API keys and usage
./hub delete-key <name>              # delete a user's API key
./hub usage [name]                   # show usage summary (or per-user detail)
./hub metrics                        # show throughput, latency, and tokens/sec
./hub logs [service]                 # tail docker compose logs
```

## Architecture

**Four Docker Compose services:**
- `vllm-small` — always runs, single GPU, port 8001 (localhost only)
- `vllm-large` — conditional via `deploy.replicas` (0 or 1), port 8002 (localhost only)
- `postgres` — stores API keys and usage data, port 5432 (localhost only)
- `litellm` — gateway, port 4000 (exposed to network), depends on vllm-small and postgres healthy

**Configuration files:**
- `.env` — all hardware-specific and secret values (gitignored). Drives everything.
- `litellm/config.template.yaml` — model routing template. Uses `os.environ/VAR` syntax and `${VAR}` for envsubst.
- `litellm/config.yaml` — generated from template by `scripts/start.sh` (gitignored).
- `docker-compose.yml` — service definitions. Identical across all machines.

**Key `.env` variables:** `SMALL_MODEL`, `LARGE_MODEL` (blank to skip), `TENSOR_PARALLEL_SIZE`, `SMALL_MODEL_GPU`, `LARGE_MODEL_GPUS`, `SMALL_GPU_MEM_UTIL`, `LARGE_GPU_MEM_UTIL`, `MAX_MODEL_LEN`, `TOOL_CALL_PARSER`, `LITELLM_MASTER_KEY`, `POSTGRES_PASSWORD`.

**The large model service** uses `deploy.replicas: ${LARGE_MODEL_REPLICAS:-0}`. The `hub` script auto-sets this to 1 when `LARGE_MODEL` is non-empty.

**Model cache:** shared HuggingFace cache at `~/.cache/huggingface`, mounted into vLLM containers.

**Default models:** `google/gemma-4-E4B-it` (small) and `google/gemma-4-26B-A4B-it` (large).
- Small (E4B): ~8B params, text + image + **audio**. Runs on GPU 0.
- Large (26B MoE, 4B active): text + image only. Runs on GPU 1.
- Tool calling: `--tool-call-parser gemma4 --reasoning-parser gemma4` with `examples/tool_chat_template_gemma4.jinja`. `TOOL_CALL_PARSER` in `.env` controls both.
- Large service enables `--kv-cache-dtype fp8` for Blackwell KV-cache compression.
- Only E2B / E4B accept audio input — 26B MoE and 31B dense are text + image only.

**API key management:** Keys are stored in PostgreSQL via LiteLLM's virtual key system. Admin creates keys with `./hub add-key <name>`. Per-user usage is tracked automatically.

## Script Structure

`hub` sources scripts from `scripts/`:
- `scripts/setup.sh` — idempotent prerequisite installer (NVIDIA drivers, Docker, nvidia-ctk, HuggingFace CLI)
- `scripts/start.sh` — sets replicas, generates config from template, runs compose up
- `scripts/status.sh` — container state, nvidia-smi, endpoint health checks
- `scripts/pull-models.sh` — downloads models via HuggingFace CLI (`hf`)
- `scripts/set-model.sh` — updates .env, pulls model, restarts service
- `scripts/keys.sh` — manages API keys via LiteLLM admin API (add, list, delete, usage)
- `scripts/metrics.sh` — fetches Prometheus metrics from vLLM endpoints

## Design Principles

- **Simplicity and reproducibility first.** Prefer stable, well-supported patterns over clever abstractions.
- **`.env` drives all hardware-specific config.** The compose file never changes per-machine.
- **Secrets in `.env`, model routing in `litellm/config.yaml`, service wiring in `docker-compose.yml`.**
- **SGLang (Phase 2) is additive.** Do not refactor the vLLM setup to accommodate it.
