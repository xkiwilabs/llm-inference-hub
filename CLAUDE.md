# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A reproducible LLM inference stack (vLLM + LiteLLM) for multi-GPU Ubuntu workstations, serving multiple simultaneous models via a unified OpenAI-compatible API. Designed for a small research/engineering team with heterogeneous hardware (24GB RTX 4090 through 192GB dual RTX Pro 6000). ARM-based DGX Sparks deferred to Phase 2.

## Stack

- **vLLM** — inference engine (continuous batching, tensor parallelism, MXFP4 via Marlin on Ampere)
- **LiteLLM** — unified OpenAI-compatible gateway (routing, API key auth)
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
./hub logs [service]                 # tail docker compose logs
```

## Architecture

**Three Docker Compose services:**
- `vllm-small` — always runs, single GPU, port 8001 (localhost only)
- `vllm-large` — conditional via `deploy.replicas` (0 or 1), port 8002 (localhost only)
- `litellm` — gateway, port 4000 (exposed to network), depends on vllm-small healthy

**Configuration files:**
- `.env` — all hardware-specific and secret values (gitignored). Drives everything.
- `litellm/config.yaml` — model routing. Uses `os.environ/VAR` syntax for env var substitution at runtime.
- `docker-compose.yml` — service definitions. Identical across all machines.

**Key `.env` variables:** `SMALL_MODEL`, `LARGE_MODEL` (blank to skip), `TENSOR_PARALLEL_SIZE`, `SMALL_MODEL_GPU`, `LARGE_MODEL_GPUS`, `GPU_MEMORY_UTILIZATION` (0.90 for discrete GPUs).

**The large model service** uses `deploy.replicas: ${LARGE_MODEL_REPLICAS:-0}`. The `hub` script auto-sets this to 1 when `LARGE_MODEL` is non-empty.

**Model cache:** shared HuggingFace cache at `~/.cache/huggingface`, mounted into vLLM containers.

**Default models:** `openai/gpt-oss-20b` (small), `openai/gpt-oss-120b` (large). Both are MoE with native MXFP4 quantization. `VLLM_MXFP4_USE_MARLIN=1` is set in compose for Ampere GPU compatibility.

## Script Structure

`hub` sources scripts from `scripts/`:
- `scripts/setup.sh` — idempotent prerequisite installer (NVIDIA drivers, Docker, nvidia-ctk, huggingface-cli)
- `scripts/start.sh` — sets replicas, runs compose up
- `scripts/status.sh` — container state, nvidia-smi, endpoint health checks
- `scripts/pull-models.sh` — downloads models via huggingface-cli
- `scripts/set-model.sh` — updates .env, pulls model, restarts service

## Design Principles

- **Simplicity and reproducibility first.** Prefer stable, well-supported patterns over clever abstractions.
- **`.env` drives all hardware-specific config.** The compose file never changes per-machine.
- **Secrets in `.env`, model routing in `litellm/config.yaml`, service wiring in `docker-compose.yml`.**
- **SGLang (Phase 2) is additive.** Do not refactor the vLLM setup to accommodate it.
