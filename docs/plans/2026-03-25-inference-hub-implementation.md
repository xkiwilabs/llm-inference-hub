# Inference Hub Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a reproducible LLM inference stack (vLLM + LiteLLM + Docker Compose) that any x86 Ubuntu workstation with NVIDIA GPUs can run via `git clone` + `./hub setup` + `./hub start`.

**Architecture:** Single `docker-compose.yml` with three services (vllm-small, vllm-large, litellm). All hardware config in `.env`. A `hub` bash CLI wraps compose and adds model management, status, and setup. The large model service uses `deploy.replicas` set to 0 or 1 to conditionally start.

**Tech Stack:** Docker Compose, vLLM (vllm/vllm-openai), LiteLLM (ghcr.io/berriai/litellm), Bash, huggingface-cli

---

### Task 1: Initialize Git Repo and Scaffold

**Files:**
- Create: `.gitignore`
- Create: `.env.example`

**Step 1: Initialize git repo**

Run: `git init`

**Step 2: Create `.gitignore`**

```
.env
*.log
```

**Step 3: Create `.env.example`**

```bash
# === HuggingFace ===
HF_TOKEN=                          # your HuggingFace access token (https://huggingface.co/settings/tokens)

# === Models ===
SMALL_MODEL=openai/gpt-oss-20b    # model for the small/fast instance
LARGE_MODEL=openai/gpt-oss-120b   # leave blank for single-model setup

# === GPU Configuration ===
SMALL_MODEL_GPU=0                  # GPU device index for small model
LARGE_MODEL_GPUS=0,1              # GPU device indices for large model (comma-separated)
TENSOR_PARALLEL_SIZE=2             # number of GPUs for tensor parallelism on large model
GPU_MEMORY_UTILIZATION=0.90        # fraction of GPU memory vLLM may use (0.85 for unified memory)

# === LiteLLM ===
LITELLM_MASTER_KEY=                # admin key for LiteLLM management API
LITELLM_API_KEYS=sk-team-key-1,sk-team-key-2   # comma-separated team API keys

# === Ports ===
LITELLM_PORT=4000                  # port exposed to host for the unified API
```

**Step 4: Commit**

```bash
git add .gitignore .env.example
git commit -m "init: scaffold repo with .gitignore and .env.example"
```

---

### Task 2: Docker Compose Services

**Files:**
- Create: `docker-compose.yml`

**Step 1: Create `docker-compose.yml`**

Three services:
- `vllm-small`: always runs, single GPU, port 8001 internal
- `vllm-large`: replicas controlled by `LARGE_MODEL_REPLICAS` (default 0), port 8002 internal
- `litellm`: gateway, port 4000 exposed to host

```yaml
services:
  vllm-small:
    image: vllm/vllm-openai:latest
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=${SMALL_MODEL_GPU:-0}
      - HF_TOKEN=${HF_TOKEN}
      - VLLM_MXFP4_USE_MARLIN=1
    volumes:
      - ${HF_CACHE_DIR:-~/.cache/huggingface}:/root/.cache/huggingface
    command: >
      --model ${SMALL_MODEL}
      --gpu-memory-utilization ${GPU_MEMORY_UTILIZATION:-0.90}
      --port 8001
      --host 0.0.0.0
    ports:
      - "8001"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8001/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 120s
    restart: unless-stopped

  vllm-large:
    image: vllm/vllm-openai:latest
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=${LARGE_MODEL_GPUS:-0,1}
      - HF_TOKEN=${HF_TOKEN}
      - VLLM_MXFP4_USE_MARLIN=1
    volumes:
      - ${HF_CACHE_DIR:-~/.cache/huggingface}:/root/.cache/huggingface
    command: >
      --model ${LARGE_MODEL}
      --tensor-parallel-size ${TENSOR_PARALLEL_SIZE:-1}
      --gpu-memory-utilization ${GPU_MEMORY_UTILIZATION:-0.90}
      --port 8002
      --host 0.0.0.0
    ports:
      - "8002"
    deploy:
      replicas: ${LARGE_MODEL_REPLICAS:-0}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8002/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 180s
    restart: unless-stopped

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    environment:
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - SMALL_MODEL=${SMALL_MODEL}
      - LARGE_MODEL=${LARGE_MODEL}
    volumes:
      - ./litellm/config.yaml:/app/config.yaml
    command: --config /app/config.yaml --port 4000 --host 0.0.0.0
    ports:
      - "${LITELLM_PORT:-4000}:4000"
    depends_on:
      vllm-small:
        condition: service_healthy
    restart: unless-stopped
```

Notes for the implementor:
- `runtime: nvidia` requires NVIDIA Container Toolkit installed on host.
- `VLLM_MXFP4_USE_MARLIN=1` ensures gpt-oss MXFP4 models work on Ampere GPUs (RTX 4090) by using the Marlin kernel instead of Triton.
- `vllm-large` uses `deploy.replicas: ${LARGE_MODEL_REPLICAS:-0}`. The `hub` script sets this to 1 when `LARGE_MODEL` is non-empty.
- `litellm` depends on `vllm-small` being healthy. It does NOT depend on `vllm-large` because that service may have 0 replicas.
- `start_period` is generous (120s/180s) because model loading takes time, especially on first run.
- `HF_CACHE_DIR` allows override but defaults to `~/.cache/huggingface`.

**Step 2: Verify compose file parses**

Run: `docker compose config` (with a `.env` file present — copy from `.env.example` and fill in dummy values for validation)

**Step 3: Commit**

```bash
git add docker-compose.yml
git commit -m "feat: add docker-compose with vllm-small, vllm-large, litellm services"
```

---

### Task 3: LiteLLM Configuration

**Files:**
- Create: `litellm/config.yaml`

**Step 1: Create `litellm/config.yaml`**

```yaml
model_list:
  - model_name: small
    litellm_params:
      model: openai/os.environ/SMALL_MODEL
      api_base: http://vllm-small:8001/v1
      api_key: "no-key-needed"

  - model_name: large
    litellm_params:
      model: openai/os.environ/LARGE_MODEL
      api_base: http://vllm-large:8002/v1
      api_key: "no-key-needed"

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY

litellm_settings:
  drop_params: true
```

Notes for the implementor:
- `os.environ/SMALL_MODEL` is LiteLLM's env var substitution syntax — it calls `os.getenv("SMALL_MODEL")` at runtime.
- The `openai/` prefix tells LiteLLM to use the OpenAI-compatible provider (which vLLM implements).
- `api_key: "no-key-needed"` — vLLM doesn't require auth, but LiteLLM requires this field.
- `drop_params: true` — silently drops unsupported params rather than erroring. Useful because different clients send different params.
- Team API keys: LiteLLM in proxy mode uses `LITELLM_MASTER_KEY` for admin. For team keys with static config (no database), keys are passed as allowed keys. This may need adjustment — verify the exact LiteLLM static key config syntax during implementation. Check [LiteLLM docs on proxy config](https://docs.litellm.ai/docs/proxy/configs) for the `general_settings.allowed_keys` or equivalent field.

**Step 2: Commit**

```bash
git add litellm/config.yaml
git commit -m "feat: add litellm config with model routing and env var substitution"
```

---

### Task 4: `hub` CLI — Core Structure and Help

**Files:**
- Create: `hub`

**Step 1: Create the `hub` script skeleton**

```bash
#!/usr/bin/env bash
set -euo pipefail

HUB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source .env if it exists
if [[ -f "$HUB_DIR/.env" ]]; then
    set -a
    source "$HUB_DIR/.env"
    set +a
fi

usage() {
    cat <<'EOF'
Usage: ./hub <command>

Commands:
  setup                     Install prerequisites and scaffold .env
  start                     Start all services
  stop                      Stop all services
  restart                   Restart all services
  status                    Show service status, GPU utilization, and health
  pull-models               Download models defined in .env
  set-model <slot> <model>  Change a model (slot: small|large, or "large --clear")
  logs [service]            Tail service logs
  help                      Show this help message
EOF
}

cmd="${1:-help}"
shift || true

case "$cmd" in
    setup)      source "$HUB_DIR/scripts/setup.sh" ;;
    start)      source "$HUB_DIR/scripts/start.sh" ;;
    stop)       docker compose -f "$HUB_DIR/docker-compose.yml" down ;;
    restart)    source "$HUB_DIR/scripts/start.sh" --restart ;;
    status)     source "$HUB_DIR/scripts/status.sh" ;;
    pull-models) source "$HUB_DIR/scripts/pull-models.sh" ;;
    set-model)  source "$HUB_DIR/scripts/set-model.sh" "$@" ;;
    logs)       docker compose -f "$HUB_DIR/docker-compose.yml" logs -f "$@" ;;
    help|*)     usage ;;
esac
```

**Step 2: Make executable**

Run: `chmod +x hub`

**Step 3: Create empty script placeholders**

Run:
```bash
mkdir -p scripts
touch scripts/setup.sh scripts/start.sh scripts/status.sh scripts/pull-models.sh scripts/set-model.sh
```

**Step 4: Commit**

```bash
git add hub scripts/
git commit -m "feat: add hub CLI skeleton with command routing"
```

---

### Task 5: `hub start` and `hub stop`

**Files:**
- Create: `scripts/start.sh`

**Step 1: Implement `scripts/start.sh`**

```bash
# Called by hub start / hub restart
# Sets LARGE_MODEL_REPLICAS based on whether LARGE_MODEL is set, then runs compose up.

RESTART=false
if [[ "${1:-}" == "--restart" ]]; then
    RESTART=true
    docker compose -f "$HUB_DIR/docker-compose.yml" down
fi

# Auto-set replicas: 1 if LARGE_MODEL is set, 0 otherwise
if [[ -n "${LARGE_MODEL:-}" ]]; then
    export LARGE_MODEL_REPLICAS=1
else
    export LARGE_MODEL_REPLICAS=0
fi

echo "Starting inference hub..."
echo "  Small model: ${SMALL_MODEL:-<not set>}"
if [[ "${LARGE_MODEL_REPLICAS}" == "1" ]]; then
    echo "  Large model: ${LARGE_MODEL}"
else
    echo "  Large model: (none)"
fi

docker compose -f "$HUB_DIR/docker-compose.yml" up -d

echo ""
echo "Services starting. Run './hub status' to check health."
```

**Step 2: Test start with a dummy `.env`**

Create a temporary `.env` with `SMALL_MODEL=openai/gpt-oss-20b`, `LARGE_MODEL=`, and run `./hub start`. Verify only vllm-small and litellm containers start (vllm-large has 0 replicas). Then `./hub stop`.

**Step 3: Commit**

```bash
git add scripts/start.sh
git commit -m "feat: implement hub start with conditional large model replicas"
```

---

### Task 6: `hub status`

**Files:**
- Create: `scripts/status.sh`

**Step 1: Implement `scripts/status.sh`**

```bash
# Called by hub status
# Shows: container states, GPU utilization, endpoint health checks.

echo "=== Container Status ==="
docker compose -f "$HUB_DIR/docker-compose.yml" ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "=== GPU Utilization ==="
if command -v nvidia-smi &>/dev/null; then
    nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total \
        --format=csv,noheader,nounits | while IFS=',' read -r idx name util mem_used mem_total; do
        printf "  GPU %s (%s): %s%% util, %s/%s MiB\n" \
            "$(echo "$idx" | xargs)" \
            "$(echo "$name" | xargs)" \
            "$(echo "$util" | xargs)" \
            "$(echo "$mem_used" | xargs)" \
            "$(echo "$mem_total" | xargs)"
    done
else
    echo "  nvidia-smi not found"
fi

echo ""
echo "=== Model Health Checks ==="

check_endpoint() {
    local name="$1" url="$2"
    if curl -sf --max-time 5 "$url" > /dev/null 2>&1; then
        echo "  $name: healthy"
    else
        echo "  $name: not responding"
    fi
}

# Small model — always check
check_endpoint "vllm-small" "http://localhost:8001/health"

# Large model — only check if replicas > 0
if [[ -n "${LARGE_MODEL:-}" ]]; then
    check_endpoint "vllm-large" "http://localhost:8002/health"
fi

# LiteLLM gateway
check_endpoint "litellm" "http://localhost:${LITELLM_PORT:-4000}/health"
```

Notes for the implementor:
- The health check URLs use localhost because the ports are exposed to the host via compose. However, vllm-small and vllm-large expose their ports internally only (no host mapping in the compose file as written). Either: (a) add host port mappings for 8001/8002 in compose for debugging, or (b) use `docker compose exec` to curl from inside the network. Option (a) is simpler — add `"127.0.0.1:8001:8001"` and `"127.0.0.1:8002:8002"` to the compose ports so they're reachable from the host but not from the network. Update the compose file in Task 2 accordingly.

**Step 2: Test with running containers**

Run `./hub start` then `./hub status`. Verify all three sections display correctly.

**Step 3: Commit**

```bash
git add scripts/status.sh
git commit -m "feat: implement hub status with container, GPU, and health info"
```

---

### Task 7: `hub pull-models`

**Files:**
- Create: `scripts/pull-models.sh`

**Step 1: Implement `scripts/pull-models.sh`**

```bash
# Called by hub pull-models
# Downloads models defined in .env using huggingface-cli.

if ! command -v huggingface-cli &>/dev/null; then
    echo "Error: huggingface-cli not found. Run './hub setup' first."
    exit 1
fi

if [[ -z "${HF_TOKEN:-}" ]]; then
    echo "Error: HF_TOKEN not set in .env"
    exit 1
fi

export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"

pull_model() {
    local model="$1"
    if [[ -z "$model" ]]; then return; fi
    echo "Pulling $model..."
    huggingface-cli download "$model"
    echo "  Done: $model"
}

pull_model "${SMALL_MODEL:-}"
pull_model "${LARGE_MODEL:-}"

echo ""
echo "All models downloaded to $(huggingface-cli env | grep -i cache || echo '~/.cache/huggingface')"
```

**Step 2: Test**

Set `HF_TOKEN` and `SMALL_MODEL` in `.env`. Run `./hub pull-models`. Verify the model downloads to `~/.cache/huggingface`.

**Step 3: Commit**

```bash
git add scripts/pull-models.sh
git commit -m "feat: implement hub pull-models using huggingface-cli"
```

---

### Task 8: `hub set-model`

**Files:**
- Create: `scripts/set-model.sh`

**Step 1: Implement `scripts/set-model.sh`**

```bash
# Called by hub set-model <slot> <model|--clear>
# Updates .env, pulls the model, restarts the affected service.

SLOT="${1:-}"
MODEL="${2:-}"

if [[ -z "$SLOT" ]]; then
    echo "Usage: ./hub set-model <small|large> <model-name>"
    echo "       ./hub set-model large --clear"
    exit 1
fi

ENV_FILE="$HUB_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: .env not found. Run './hub setup' first."
    exit 1
fi

update_env_var() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "$ENV_FILE"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    else
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

case "$SLOT" in
    small)
        if [[ -z "$MODEL" ]]; then
            echo "Error: specify a model name"
            exit 1
        fi
        echo "Setting small model to: $MODEL"
        update_env_var "SMALL_MODEL" "$MODEL"

        # Re-source .env
        set -a; source "$ENV_FILE"; set +a

        # Pull model
        source "$HUB_DIR/scripts/pull-models.sh"

        # Restart small service
        docker compose -f "$HUB_DIR/docker-compose.yml" up -d --force-recreate vllm-small
        echo "Done. vllm-small restarting with $MODEL"
        ;;

    large)
        if [[ "$MODEL" == "--clear" ]]; then
            echo "Clearing large model..."
            update_env_var "LARGE_MODEL" ""
            export LARGE_MODEL_REPLICAS=0
            docker compose -f "$HUB_DIR/docker-compose.yml" up -d --scale vllm-large=0
            echo "Done. Large model disabled."
        else
            if [[ -z "$MODEL" ]]; then
                echo "Error: specify a model name or --clear"
                exit 1
            fi
            echo "Setting large model to: $MODEL"
            update_env_var "LARGE_MODEL" "$MODEL"

            # Re-source .env
            set -a; source "$ENV_FILE"; set +a

            # Pull model
            source "$HUB_DIR/scripts/pull-models.sh"

            # Start/restart large service with replicas=1
            export LARGE_MODEL_REPLICAS=1
            docker compose -f "$HUB_DIR/docker-compose.yml" up -d --force-recreate vllm-large
            echo "Done. vllm-large restarting with $MODEL"
        fi
        ;;

    *)
        echo "Error: slot must be 'small' or 'large'"
        exit 1
        ;;
esac
```

**Step 2: Test**

```bash
# Set a different small model
./hub set-model small Qwen/Qwen2.5-14B-Instruct
# Verify .env updated and service restarted

# Enable large model
./hub set-model large openai/gpt-oss-120b
# Verify .env updated, model pulled, service started with replicas=1

# Disable large model
./hub set-model large --clear
# Verify LARGE_MODEL is blank and vllm-large has 0 replicas
```

**Step 3: Commit**

```bash
git add scripts/set-model.sh
git commit -m "feat: implement hub set-model for swapping and clearing models"
```

---

### Task 9: `hub setup` — Full Installer

**Files:**
- Create: `scripts/setup.sh`

This is the largest script. It installs all prerequisites idempotently.

**Step 1: Implement `scripts/setup.sh`**

```bash
# Called by hub setup
# Installs NVIDIA drivers, Docker, NVIDIA Container Toolkit, huggingface-cli.
# Idempotent — safe to run multiple times.

echo "=== Inference Hub Setup ==="
echo ""

need_sudo=false

# --- NVIDIA Drivers ---
echo "[1/5] Checking NVIDIA drivers..."
if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
    echo "  OK: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"
else
    echo "  Installing NVIDIA drivers..."
    need_sudo=true
    sudo apt-get update
    sudo apt-get install -y ubuntu-drivers-common
    sudo ubuntu-drivers autoinstall
    echo "  Installed. A REBOOT may be required."
fi

# --- Docker ---
echo "[2/5] Checking Docker..."
if command -v docker &>/dev/null; then
    echo "  OK: $(docker --version)"
else
    echo "  Installing Docker..."
    need_sudo=true
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker "$USER"
    echo "  Installed. You may need to log out and back in for group membership."
fi

# --- NVIDIA Container Toolkit ---
echo "[3/5] Checking NVIDIA Container Toolkit..."
if command -v nvidia-ctk &>/dev/null; then
    echo "  OK: $(nvidia-ctk --version 2>/dev/null || echo 'installed')"
else
    echo "  Installing NVIDIA Container Toolkit..."
    need_sudo=true
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit
fi

# --- Configure Docker runtime ---
echo "[4/5] Configuring Docker NVIDIA runtime..."
if docker info 2>/dev/null | grep -q "nvidia"; then
    echo "  OK: NVIDIA runtime configured"
else
    need_sudo=true
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker
    echo "  Configured and Docker restarted"
fi

# --- huggingface-cli ---
echo "[5/5] Checking huggingface-cli..."
if command -v huggingface-cli &>/dev/null; then
    echo "  OK: $(huggingface-cli version 2>/dev/null || echo 'installed')"
else
    echo "  Installing huggingface-cli..."
    if command -v pipx &>/dev/null; then
        pipx install huggingface_hub[cli]
    else
        pip install --user huggingface_hub[cli]
    fi
    echo "  Installed"
fi

# --- .env ---
echo ""
if [[ ! -f "$HUB_DIR/.env" ]]; then
    cp "$HUB_DIR/.env.example" "$HUB_DIR/.env"
    echo "Created .env from .env.example"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Edit .env — set HF_TOKEN and LITELLM_MASTER_KEY at minimum"
echo "  2. Run: ./hub pull-models"
echo "  3. Run: ./hub start"
```

**Step 2: Test on current machine**

Run `./hub setup`. Verify each check passes (or installs if missing). Run again — verify it's idempotent (all "OK").

**Step 3: Commit**

```bash
git add scripts/setup.sh
git commit -m "feat: implement hub setup with full prerequisite installer"
```

---

### Task 10: Update CLAUDE.md and Final Polish

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docker-compose.yml` (bind vllm ports to 127.0.0.1 for status health checks)

**Step 1: Update `docker-compose.yml` vllm port mappings**

Change `vllm-small` ports from `"8001"` to `"127.0.0.1:8001:8001"` and `vllm-large` ports from `"8002"` to `"127.0.0.1:8002:8002"`. This allows `hub status` to health-check from the host while keeping ports off the network.

**Step 2: Update `CLAUDE.md`**

Reflect actual commands, actual file structure, and any nuances discovered during implementation.

**Step 3: Commit**

```bash
git add CLAUDE.md docker-compose.yml
git commit -m "docs: update CLAUDE.md and expose vllm ports to localhost for health checks"
```

---

### Task 11: End-to-End Test on RTX 4090

**Step 1: Clean test**

```bash
# Start fresh
./hub stop 2>/dev/null || true

# Setup (should be all OK if already installed)
./hub setup

# Configure for 4090 (single GPU, small model only)
# Edit .env:
#   SMALL_MODEL=openai/gpt-oss-20b
#   LARGE_MODEL=
#   SMALL_MODEL_GPU=0
#   TENSOR_PARALLEL_SIZE=1
#   GPU_MEMORY_UTILIZATION=0.90
```

**Step 2: Pull and start**

```bash
./hub pull-models
./hub start
```

**Step 3: Verify status**

```bash
./hub status
# Expected:
#   vllm-small: healthy
#   litellm: healthy
#   GPU 0: shows utilization and VRAM usage
```

**Step 4: Test inference through LiteLLM**

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-team-key-1" \
  -d '{
    "model": "small",
    "messages": [{"role": "user", "content": "Hello, what model are you?"}]
  }'
```

**Step 5: Test set-model**

```bash
./hub set-model large openai/gpt-oss-120b
# Should fail gracefully on 4090 (not enough VRAM) — verify error message in logs
./hub set-model large --clear
```

**Step 6: Test stop**

```bash
./hub stop
./hub status
# Expected: all services down
```
