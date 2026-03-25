# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A reproducible LLM inference stack (vLLM + LiteLLM) for multi-GPU Ubuntu workstations, serving multiple simultaneous models via a unified OpenAI-compatible API. Designed for a small research/engineering team with heterogeneous hardware (24GB RTX 4090 through 192GB dual RTX Pro 6000, plus ARM-based DGX Sparks with unified memory).

## Stack

- **vLLM** — inference engine (continuous batching, tensor parallelism)
- **LiteLLM** — unified OpenAI-compatible gateway (routing, API key auth, usage logging)
- **Docker Compose** — orchestration (single `docker-compose.yml` for the full stack)
- **Tailscale** — remote access (network-layer auth, no port forwarding)

## Commands

```bash
# Start the full stack
docker compose up -d

# Check prerequisites (NVIDIA drivers, Docker, CUDA, nvidia-ctk)
./scripts/check-prerequisites.sh

# Pre-pull models from HuggingFace
./scripts/pull-models.sh

# Full onboarding for a fresh machine
./scripts/new-workstation.sh

# View logs
docker compose logs -f            # all services
docker compose logs -f vllm-small # specific service
docker compose logs -f litellm
```

## Architecture

All hardware-specific config lives in `.env` (gitignored). `docker-compose.yml` reads `.env` and is identical across all machines. Model routing and API keys are configured in `litellm/config.yaml`.

Key `.env` variables: `SMALL_MODEL`, `LARGE_MODEL` (blank to skip), `TENSOR_PARALLEL_SIZE`, `SMALL_MODEL_GPU`, `LARGE_MODEL_GPUS`, `GPU_MEMORY_UTILIZATION` (0.90 discrete, 0.85 unified/Spark).

The large model service starts conditionally — only when `LARGE_MODEL` is set.

## Design Principles

- **Simplicity and reproducibility first.** Prefer stable, well-supported patterns over clever abstractions.
- **`.env` drives all hardware-specific config.** The compose file never changes per-machine.
- **Secrets in `.env`, model config in `litellm/config.yaml`, service wiring in `docker-compose.yml`.** These three files are the source of truth.
- **SGLang (Phase 2) is additive.** When adding SGLang, do not refactor the existing vLLM setup to accommodate it. Add a new service and update the relevant route in LiteLLM config.

## ARM / DGX Spark Notes

DGX Sparks are ARM-based (Grace CPU + Blackwell GPU). The vLLM Docker image tag may differ from x86 machines — do not assume the same image works on both architectures. May need a separate compose override file.
