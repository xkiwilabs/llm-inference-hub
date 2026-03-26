# Server Setup

How to set up inference-hub on a fresh Ubuntu workstation with NVIDIA GPUs.

## Prerequisites

- Ubuntu (22.04 or later)
- One or more NVIDIA GPUs
- Internet access (for downloading packages and models)
- A [HuggingFace account](https://huggingface.co/settings/tokens) with an access token

Everything else is installed automatically by `./hub setup`.

## Step-by-step

### 1. Clone the repo

```bash
git clone git@github.com:YOUR_ORG/inference-hub.git
cd inference-hub
```

Or with HTTPS:

```bash
git clone https://github.com/YOUR_ORG/inference-hub.git
cd inference-hub
```

### 2. Run setup

```bash
./hub setup
```

This does everything automatically (requires `sudo`):

- Installs NVIDIA GPU drivers (if missing)
- Installs Docker from the official apt repo (not snap)
- Installs NVIDIA Container Toolkit so Docker can see your GPUs
- Installs HuggingFace CLI (`hf`) for downloading models
- Detects your GPU hardware (count, VRAM, CUDA version)
- Picks the right vLLM Docker image for your NVIDIA driver
- Chooses appropriate models for your VRAM
- Generates a master API key and team API keys (default: 5)
- Creates your `.env` config file with everything pre-filled

If something is already installed, it skips it. Safe to run multiple times.

**Important:** If Docker was just installed, you may need to log out and back in (or run `newgrp docker`) before continuing.

### 3. Set your HuggingFace token

The only thing setup can't generate. Get a token from https://huggingface.co/settings/tokens, then:

```bash
sed -i 's/^HF_TOKEN=.*/HF_TOKEN=hf_your_token_here/' .env
```

### 4. Download models

```bash
./hub pull-models
```

Downloads the models to `~/.cache/huggingface`. This way containers start fast instead of downloading on first boot.

### 5. Start the stack

```bash
./hub start
```

Starts the vLLM inference engine(s) and the LiteLLM gateway. Model loading takes 1-2 minutes.

### 6. Verify

```bash
./hub status
```

Wait until all services show healthy. You should see:

```
=== Container Status ===
NAME                             STATUS                   PORTS
llm-inference-hub-litellm-1      Up 30 seconds            0.0.0.0:4200->4000/tcp
llm-inference-hub-vllm-small-1   Up 2 minutes (healthy)   127.0.0.1:8001->8001/tcp

=== GPU Utilization ===
  GPU 0 (NVIDIA GeForce RTX 4090): 4% util, 22118/24564 MiB

=== Model Health Checks ===
  vllm-small: healthy
  litellm: healthy
```

### 7. Share API keys

During setup, team API keys were printed to the screen. They are also stored in `.env` as `LITELLM_API_KEYS`. Give one key to each team member.

To regenerate keys, delete the `LITELLM_API_KEYS` line from `.env` and re-run `./hub setup`.

## What setup auto-detects

| GPUs | VRAM | Models configured | Tensor parallel |
|---|---|---|---|
| 1 GPU, < 30GB | e.g. RTX 4090 | Small only | 1 |
| 1 GPU, 30-79GB | e.g. RTX 5090 | Small only | 1 |
| Any, 80-159GB | e.g. 2x 48GB | Small + large (conservative memory) | GPU count |
| Any, 160GB+ | e.g. 2x RTX Pro 6000 | Small + large | GPU count |

## Overriding defaults

Edit `.env` directly, or use `./hub set-model`:

```bash
# Change a model
./hub set-model small Qwen/Qwen2.5-14B-Instruct

# Change the port
sed -i 's/^LITELLM_PORT=.*/LITELLM_PORT=8080/' .env
./hub restart
```

See [Managing Models](04-managing-models.md) for more.
