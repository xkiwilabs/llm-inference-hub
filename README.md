# inference-hub

A reproducible LLM inference stack built on vLLM + LiteLLM, designed for multi-GPU Ubuntu workstations. Serves multiple models simultaneously over a single OpenAI-compatible API.

## What you get

- **Multiple models running at once** (e.g. a fast 20B and a large 120B)
- **Parallel request handling** via vLLM's continuous batching
- **One unified API endpoint** for the whole team (`http://<machine>:4200/v1`)
- **OpenAI-compatible** — works with any tool that speaks the OpenAI API
- **One command to start** on any workstation

## Quick start

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

This installs everything you need (requires `sudo`):
- NVIDIA GPU drivers
- Docker (official apt repo)
- NVIDIA Container Toolkit (lets Docker see your GPUs)
- HuggingFace CLI (`hf`) for downloading models
- Creates your `.env` config file from the template

If something is already installed, it skips it. Safe to run multiple times.

### 3. Edit your `.env`

```bash
nano .env
```

You **must** set these two values:

| Variable | What it is | Where to get it |
|---|---|---|
| `HF_TOKEN` | HuggingFace access token | https://huggingface.co/settings/tokens |
| `LITELLM_MASTER_KEY` | Admin API key (you choose this) | Pick any string, e.g. `sk-master-myteam-2026` |

Then configure for your hardware:

**Single GPU (RTX 4090 / 5090):**
```bash
SMALL_MODEL=openai/gpt-oss-20b
LARGE_MODEL=
SMALL_MODEL_GPU=0
TENSOR_PARALLEL_SIZE=1
GPU_MEMORY_UTILIZATION=0.90
```

**Dual GPU (RTX Pro 6000 x2):**
```bash
SMALL_MODEL=openai/gpt-oss-20b
LARGE_MODEL=openai/gpt-oss-120b
SMALL_MODEL_GPU=0
LARGE_MODEL_GPUS=0,1
TENSOR_PARALLEL_SIZE=2
GPU_MEMORY_UTILIZATION=0.90
```

Leave `LARGE_MODEL=` blank if you only have one GPU or don't need a second model.

### 4. Download models

```bash
./hub pull-models
```

Downloads the models you configured to `~/.cache/huggingface`. The 20B model is ~10-12GB. This way containers start fast instead of downloading on first boot.

### 5. Start the stack

```bash
./hub start
```

This starts the vLLM inference engine(s) and the LiteLLM gateway. Model loading takes 1-2 minutes.

### 6. Verify it's working

```bash
./hub status
```

Wait until you see all services as healthy. Then test with a request:

```bash
curl http://localhost:4200/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_MASTER_KEY" \
  -d '{
    "model": "small",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

Replace `YOUR_MASTER_KEY` with the `LITELLM_MASTER_KEY` you set in `.env`.

## Using the API

The API is OpenAI-compatible. Point any tool or library at:

```
Base URL: http://<machine-ip>:4200/v1
API Key:  your LITELLM_MASTER_KEY
```

Available model names:
- `small` — the fast model (gpt-oss-20b by default)
- `large` — the big model (gpt-oss-120b by default, if configured)

### Python example

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://192.168.1.100:4200/v1",
    api_key="sk-master-myteam-2026",
)

response = client.chat.completions.create(
    model="small",
    messages=[{"role": "user", "content": "Explain transformers in one paragraph."}],
)
print(response.choices[0].message.content)
```

### Remote access via Tailscale

If the machine is on Tailscale, team members can use the Tailscale IP instead of the LAN IP. No port forwarding needed.

## Hub commands

| Command | What it does |
|---|---|
| `./hub setup` | Install prerequisites, create `.env` |
| `./hub start` | Start all services |
| `./hub stop` | Stop all services |
| `./hub restart` | Stop + start |
| `./hub status` | Container state, GPU usage, health checks |
| `./hub pull-models` | Download models in `.env` to local cache |
| `./hub set-model small <model>` | Switch the small model |
| `./hub set-model large <model>` | Switch the large model |
| `./hub set-model large --clear` | Disable the large model |
| `./hub logs [service]` | Tail logs (services: `vllm-small`, `vllm-large`, `litellm`) |

### Changing models

```bash
# Switch to a different small model
./hub set-model small Qwen/Qwen2.5-14B-Instruct

# Add a large model on a machine that wasn't running one
./hub set-model large openai/gpt-oss-120b

# Remove the large model (free up VRAM)
./hub set-model large --clear
```

This updates `.env`, downloads the model, and restarts the affected service in one step.

## Troubleshooting

**`./hub status` shows "not responding":**
Model loading takes 1-2 minutes after start. Wait and check again. If it persists, check logs:
```bash
./hub logs vllm-small
```

**Container exits immediately:**
Usually a GPU memory issue. Check `GPU_MEMORY_UTILIZATION` in `.env` — try lowering to `0.85`. Or the model is too large for your GPU.

**"NVIDIA runtime not found":**
Run `./hub setup` again — it configures the Docker NVIDIA runtime.

**Permission denied on Docker:**
After setup installs Docker, you need to log out and back in for the `docker` group membership to take effect. Or run `newgrp docker` in your current shell.

## Hardware reference

| Hardware | VRAM | Recommended config |
|---|---|---|
| RTX 4090 | 24GB | Small model only (gpt-oss-20b) |
| RTX 5090 | 32GB | Small model only, or quantized 32B models |
| RTX Pro 6000 x2 | 192GB | Small + large (gpt-oss-20b + gpt-oss-120b) |
