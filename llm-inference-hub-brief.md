# inference-hub

> A reproducible, team-facing LLM inference stack built on vLLM + LiteLLM, designed for multi-GPU Ubuntu workstations. Supports multiple simultaneous models, parallel request processing, and OpenAI-compatible API access over a local network or Tailscale VPN.

---

## Context & Goals

This repo packages a production-grade LLM serving stack as infrastructure-as-code so that any new workstation can be brought online with a `git clone` and a single command. It is designed for a small research/engineering team who need:

- Multiple models running simultaneously (e.g. a fast 20–32B model and a large 70–120B model)
- Parallel request handling (continuous batching — not one-at-a-time like Ollama)
- A single unified OpenAI-compatible endpoint for all team members and internal platforms
- Per-user API key management and usage tracking
- Local network access + remote access via Tailscale

The stack is intentionally simple to start, with a clear path to adding SGLang as a second inference engine later (particularly for multi-agent workloads where shared-prefix KV cache reuse matters).

---

## Target Hardware

This stack is designed to run identically across all Ubuntu workstations in the fleet. The Docker Compose + `.env` pattern means the codebase is the same everywhere — only a handful of `.env` values change per machine.

| Hardware | VRAM | Memory Architecture | Practical Model Range |
|---|---|---|---|
| RTX 4090 | 24GB | Discrete | Up to ~14B comfortably, 32B with quantisation |
| RTX 5090 | 32GB | Discrete | Up to 32B comfortably |
| DGX Spark 96 | 96GB | Unified (CPU+GPU shared) | Up to 70B |
| DGX Spark 128 | 128GB | Unified (CPU+GPU shared) | 70B–120B range |
| RTX Pro 6000 ×2 | 192GB total | Discrete, tensor parallel | 120B+ across both GPUs |

**Remote access:** Tailscale (team members connect via Tailnet, authenticated at network layer)

### ARM Architecture Note (DGX Sparks)
The DGX Sparks are ARM-based (Grace CPU + Blackwell GPU). vLLM does support ARM but requires the correct image variant — do not assume the same Docker image tag works across x86 and ARM machines. The Sparks should be tested separately and may need a different `image:` line in `docker-compose.yml` or a separate compose override file.

---

## Stack

| Component | Role |
|---|---|
| **vLLM** | Inference engine — continuous batching, tensor parallelism across GPUs |
| **LiteLLM** | Unified gateway — OpenAI-compatible API, model routing, API key auth, usage logging |
| **Docker Compose** | Orchestration — reproducible, portable, one-command startup |
| **Tailscale** | Remote access — team hits Tailscale IP:port, no port forwarding needed |

### Planned addition (Phase 2)
| Component | Role |
|---|---|
| **SGLang** | Secondary inference engine for agentic/multi-agent workloads — RadixAttention gives meaningful throughput gains when many requests share large common prefixes (system prompts, agent state, tool definitions) |

---

## Intended Model Layout

Model layout is driven entirely by `.env` — `docker-compose.yml` reads these values so the same file works across all machines.

```
# .env example — RTX Pro 6000 x2 (192GB discrete)
SMALL_MODEL=Qwen/Qwen2.5-32B-Instruct
LARGE_MODEL=Qwen/Qwen2.5-72B-Instruct
TENSOR_PARALLEL_SIZE=2
SMALL_MODEL_GPU=0
LARGE_MODEL_GPUS=0,1
GPU_MEMORY_UTILIZATION=0.90

# .env example — DGX Spark 128 (128GB unified)
SMALL_MODEL=Qwen/Qwen2.5-32B-Instruct
LARGE_MODEL=Qwen/Qwen2.5-72B-Instruct
TENSOR_PARALLEL_SIZE=1          # fits in single unified pool, no split needed
SMALL_MODEL_GPU=0
LARGE_MODEL_GPUS=0
GPU_MEMORY_UTILIZATION=0.85     # slightly conservative for unified memory

# .env example — RTX 4090 (24GB discrete)
SMALL_MODEL=Qwen/Qwen2.5-14B-Instruct
LARGE_MODEL=                    # leave blank, no large model instance started
TENSOR_PARALLEL_SIZE=1
SMALL_MODEL_GPU=0
GPU_MEMORY_UTILIZATION=0.90
```

`docker-compose.yml` conditionally starts the large model service only if `LARGE_MODEL` is set, so low-VRAM machines cleanly run single-model without errors.

### Unified vs Discrete Memory
Docker and the NVIDIA Container Toolkit expose the GPU as a device regardless of memory architecture — no special handling required at the container level. The only difference is:
- **Discrete GPUs:** tensor parallel across physical GPUs to span large models
- **Unified memory (Sparks):** large VRAM pool in a single device, tensor parallel size = 1

---

## Repo Structure

```
inference-hub/
├── docker-compose.yml          # Full stack definition
├── .env.example                # Template for environment secrets
├── .env                        # Local secrets (gitignored)
├── litellm/
│   └── config.yaml             # Model routing, virtual keys, rate limits
├── vllm/
│   └── start.sh                # vLLM launch helpers (optional, compose handles this)
├── scripts/
│   ├── check-prerequisites.sh  # Verify NVIDIA drivers, Docker, CUDA
│   ├── pull-models.sh          # Helper to pre-pull models from HuggingFace
│   └── new-workstation.sh      # Full onboarding script for a fresh machine
├── docs/
│   ├── onboarding.md           # Step-by-step for new workstations
│   ├── adding-models.md        # How to add/swap models
│   ├── team-access.md          # How team members connect (Tailscale, API keys)
│   └── phase2-sglang.md        # Notes on adding SGLang when ready
└── AI_BRIEF.md                 # This file
```

---

## Key Design Decisions

**Why vLLM over Ollama/LM Studio?**
Ollama and LM Studio are single-model, limited-batching tools — fine for personal use, not for a team hitting multiple models in parallel. vLLM uses PagedAttention and continuous batching to handle concurrent requests efficiently and supports tensor parallelism to split large models across multiple GPUs.

**Why LiteLLM as a gateway?**
Without a gateway, each model is a separate endpoint on a different port. LiteLLM gives the team one URL and one API key format. It also handles per-key rate limiting and usage logging, and makes it trivial to swap the backend inference engine (vLLM → SGLang) without changing any downstream tooling.

**Why Docker Compose?**
Reproducibility. Every workstation gets the same environment. No "works on my machine" issues with CUDA versions, Python dependencies, etc. Note: Docker GPU access requires the **NVIDIA Container Toolkit** (`nvidia-ctk`) to be installed on the host — this is the one host-level prerequisite that cannot be containerised. The `check-prerequisites.sh` script verifies drivers, toolkit, and Docker runtime config before anything else runs.

**Why `.env` drives all hardware-specific config?**
The fleet spans very different hardware (24GB discrete up to 192GB across two GPUs, plus unified memory Sparks). Making model names, tensor parallel size, GPU indices, and memory utilisation all `.env` variables means `docker-compose.yml` is identical on every machine — only the `.env` file differs. `GPU_MEMORY_UTILIZATION` should be set slightly lower (0.85) on unified memory machines (Sparks) vs discrete GPU machines (0.90) to account for the shared CPU/GPU memory pool.

**Why Tailscale for remote access?**
Already in use across the team. Authenticated at the network layer, so LiteLLM's API key auth is a clean second layer on top. No port forwarding or VPN server to manage.

**Why not TensorRT-LLM / Triton?**
Maximum raw performance, but extremely heavyweight to set up and maintain. Not worth the ops burden for a research team. vLLM is within ~10–15% of TRT-LLM performance at a fraction of the complexity.

---

## Phase 2: Adding SGLang

When multi-agent workloads (e.g. Urika, xPrism orchestration patterns) are a primary use case, SGLang's RadixAttention can deliver significant throughput improvements over vLLM for those specific workloads due to KV cache reuse across requests with shared prefixes.

The migration is low-risk because LiteLLM abstracts the backend:
1. Add a SGLang service to `docker-compose.yml`
2. Update one route in `litellm/config.yaml` to point the relevant model at SGLang's port
3. Benchmark and compare — keep whichever performs better for that model/workload

Nothing downstream (team tooling, agent platforms, API clients) changes.

---

## Immediate Next Steps

- [ ] Create `.env` from `.env.example` with HuggingFace token and LiteLLM master key
- [ ] Write `docker-compose.yml` with vLLM (two instances) and LiteLLM services
- [ ] Write `litellm/config.yaml` with model routing and virtual API keys
- [ ] Write `scripts/check-prerequisites.sh`
- [ ] Test stack on primary workstation
- [ ] Write `docs/onboarding.md` for next workstation deployment
- [ ] Push to private GitHub repo
- [ ] Issue API keys to team members

---

## Notes for Claude Code

When working in this repo, the goal is always **simplicity and reproducibility first**. Prefer well-supported, stable configuration patterns over clever abstractions. All secrets go in `.env` (gitignored). All model config goes in `litellm/config.yaml`. Docker Compose is the single source of truth for how services are wired together. If adding SGLang, it should be additive — do not refactor the vLLM setup to accommodate it.
