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

This does everything automatically:

- Installs NVIDIA GPU drivers (if missing)
- Installs Docker from the official apt repo (not snap)
- Installs NVIDIA Container Toolkit so Docker can see your GPUs
- Installs HuggingFace CLI (`hf`) for downloading models
- Detects your GPU hardware (count, VRAM, CUDA version)
- Picks the right vLLM image for your driver
- Chooses appropriate models for your VRAM
- Generates a master API key and team API keys (default: 5)
- Creates your `.env` config file with everything pre-filled

Requires `sudo` for system packages. Safe to run multiple times (idempotent).

### 3. Set your HuggingFace token

The only thing setup can't generate is your HuggingFace token. Get one from https://huggingface.co/settings/tokens, then:

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

### 6. Verify it's working

```bash
./hub status
```

Wait until all services show healthy, then test:

```bash
curl http://localhost:4200/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_MASTER_KEY" \
  -d '{
    "model": "small",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

Your master key was printed during setup and is stored in `.env` as `LITELLM_MASTER_KEY`.

## Connecting clients

The API is OpenAI-compatible. Any tool, library, or framework that can talk to the OpenAI API can use inference-hub.

### Connection details

```
Base URL:  http://<machine-ip>:4200/v1
API Key:   a team key from setup (mind-team-xxx) or the master key
```

Available model names:
- `small` — the fast model (gpt-oss-20b by default)
- `large` — the big model (gpt-oss-120b by default, if configured)

When connecting from the same machine, use `localhost`. From other machines on the LAN or Tailscale, use the machine's IP address.

### Python (OpenAI SDK)

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://192.168.1.100:4200/v1",
    api_key="mind-team-abc123...",
)

response = client.chat.completions.create(
    model="small",
    messages=[{"role": "user", "content": "Explain transformers in one paragraph."}],
)
print(response.choices[0].message.content)
```

### curl

```bash
curl http://192.168.1.100:4200/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer mind-team-abc123..." \
  -d '{"model": "small", "messages": [{"role": "user", "content": "Hello"}]}'
```

### Urika

Inference-hub works as a private endpoint for [Urika](https://github.com/YOUR_ORG/urika) projects. This lets you run agents on your own hardware — nothing leaves your network.

In your project's `urika.toml`:

```toml
# Use inference-hub for all agents
[privacy]
mode = "private"

[privacy.endpoints.private]
base_url = "http://192.168.1.100:4200"
api_key_env = "INFERENCE_HUB_KEY"

[runtime]
model = "small"
```

Set the API key in your environment:

```bash
export INFERENCE_HUB_KEY="mind-team-abc123..."
```

You can also use inference-hub for specific agents while keeping others on cloud models (hybrid mode):

```toml
# Hybrid: data agent runs locally, everything else on cloud
[privacy]
mode = "hybrid"

[privacy.endpoints.private]
base_url = "http://192.168.1.100:4200"
api_key_env = "INFERENCE_HUB_KEY"

[runtime]
model = "claude-sonnet-4-5"

[runtime.models.data_agent]
endpoint = "private"
model = "small"

[runtime.models.tool_builder]
endpoint = "private"
model = "small"
```

On a dual-GPU machine (RTX Pro 6000 x2) with both models running, you can assign different agents to different models:

```toml
[privacy]
mode = "private"

[privacy.endpoints.private]
base_url = "http://192.168.1.100:4200"
api_key_env = "INFERENCE_HUB_KEY"

[runtime]
model = "small"

[runtime.models.task_agent]
endpoint = "private"
model = "large"

[runtime.models.planning_agent]
endpoint = "private"
model = "large"
```

Replace `192.168.1.100` with the actual IP of the machine running inference-hub (LAN IP or Tailscale IP).

### Remote access via Tailscale

If the machine is on Tailscale, team members can use the Tailscale IP instead of the LAN IP. No port forwarding needed. The Tailscale IP works from anywhere on your Tailnet.

### Distributing API keys

Setup generates team API keys and prints them. Give one key to each team member. They set it as an environment variable or use it directly in their client config. Keys are stored comma-separated in `.env` as `LITELLM_API_KEYS`.

To regenerate keys, delete the `LITELLM_API_KEYS` line from `.env` and re-run `./hub setup`.

## Hub commands

| Command | What it does |
|---|---|
| `./hub setup` | Install prerequisites, detect hardware, generate keys, create `.env` |
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

## Setting up a new workstation

The full process for bringing a fresh Ubuntu machine online:

```bash
# 1. Clone
git clone git@github.com:YOUR_ORG/inference-hub.git
cd inference-hub

# 2. Setup (installs everything, detects hardware, generates keys)
./hub setup
# May need to log out/in if Docker was just installed, then re-run:
# ./hub setup

# 3. Set HuggingFace token
sed -i 's/^HF_TOKEN=.*/HF_TOKEN=hf_your_token/' .env

# 4. Pull models and start
./hub pull-models
./hub start

# 5. Verify
./hub status

# 6. Test
curl http://localhost:4200/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_MASTER_KEY" \
  -d '{"model": "small", "messages": [{"role": "user", "content": "Hello"}]}'
```

That's it. Share the team API keys with your colleagues.

## Troubleshooting

**`./hub status` shows "not responding" for litellm:**
LiteLLM takes a few seconds to start. Wait 10-15 seconds after `./hub start` and check again.

**`./hub status` shows "not responding" for vllm-small:**
Model loading takes 1-2 minutes after start. Wait and check again. If it persists:
```bash
./hub logs vllm-small
```

**CUDA version error on start:**
Your NVIDIA driver is too old for the vLLM image. Run `./hub setup` — it auto-detects CUDA and pins the right image. If you need the latest vLLM, update your driver:
```bash
sudo apt-get update && sudo ubuntu-drivers autoinstall && sudo reboot
```

**Container exits immediately:**
Usually a GPU memory issue. Check `GPU_MEMORY_UTILIZATION` in `.env` — try lowering to `0.85`. Or the model is too large for your GPU.

**"NVIDIA runtime not found":**
Run `./hub setup` again — it configures the Docker NVIDIA runtime.

**Permission denied on Docker:**
After setup installs Docker, you need to log out and back in for the `docker` group membership to take effect. Or run `newgrp docker` in your current shell.

**Port 4200 already in use:**
Change `LITELLM_PORT` in `.env` to another port and restart.

## Hardware reference

| Hardware | VRAM | Recommended config |
|---|---|---|
| RTX 4090 | 24GB | Small model only (gpt-oss-20b) |
| RTX 5090 | 32GB | Small model only, or quantized 32B models |
| RTX Pro 6000 x2 | 192GB | Small + large (gpt-oss-20b + gpt-oss-120b) |

Setup auto-detects your hardware and configures `.env` accordingly. You can always override by editing `.env` or using `./hub set-model`.
