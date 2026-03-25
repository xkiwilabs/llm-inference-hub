# Called by hub setup
# Installs NVIDIA drivers, Docker, NVIDIA Container Toolkit, huggingface CLI.
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
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
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
        sudo gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
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

# --- huggingface CLI (hf) ---
echo "[5/5] Checking huggingface CLI..."
if command -v hf &>/dev/null; then
    echo "  OK: $(hf version 2>/dev/null || echo 'installed')"
elif command -v huggingface-cli &>/dev/null; then
    echo "  OK: $(huggingface-cli version 2>/dev/null || echo 'installed (legacy command)')"
else
    echo "  Installing huggingface CLI..."
    if command -v pipx &>/dev/null; then
        pipx install huggingface_hub[cli]
    else
        sudo apt-get install -y pipx
        pipx install huggingface_hub[cli]
    fi
    echo "  Installed"
fi

# --- .env ---
echo ""
if [[ ! -f "$HUB_DIR/.env" ]]; then
    cp "$HUB_DIR/.env.example" "$HUB_DIR/.env"
    echo "Created .env from .env.example"
fi

# --- GPU auto-detection ---
ENV_FILE="$HUB_DIR/.env"

update_env() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "$ENV_FILE"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    else
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
    echo "=== Detecting GPU hardware ==="

    GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -1 | xargs)
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1 | xargs)
    GPU_VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1 | xargs)
    TOTAL_VRAM_MB=0
    while IFS= read -r line; do
        TOTAL_VRAM_MB=$((TOTAL_VRAM_MB + $(echo "$line" | xargs)))
    done < <(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits)
    TOTAL_VRAM_GB=$((TOTAL_VRAM_MB / 1024))

    echo "  GPUs:       $GPU_COUNT x $GPU_NAME"
    echo "  VRAM/GPU:   $((GPU_VRAM_MB / 1024)) GB"
    echo "  Total VRAM: ${TOTAL_VRAM_GB} GB"
    echo ""

    # Configure GPU indices
    if [[ "$GPU_COUNT" -eq 1 ]]; then
        update_env "SMALL_MODEL_GPU" "0"
        update_env "LARGE_MODEL_GPUS" "0"
        update_env "TENSOR_PARALLEL_SIZE" "1"
    elif [[ "$GPU_COUNT" -eq 2 ]]; then
        update_env "SMALL_MODEL_GPU" "0"
        update_env "LARGE_MODEL_GPUS" "0,1"
        update_env "TENSOR_PARALLEL_SIZE" "2"
    elif [[ "$GPU_COUNT" -ge 3 ]]; then
        update_env "SMALL_MODEL_GPU" "0"
        # Use all GPUs for the large model
        GPUS=$(seq -s, 0 $((GPU_COUNT - 1)))
        update_env "LARGE_MODEL_GPUS" "$GPUS"
        update_env "TENSOR_PARALLEL_SIZE" "$GPU_COUNT"
    fi

    update_env "GPU_MEMORY_UTILIZATION" "0.90"

    # Choose models based on total VRAM
    if [[ "$TOTAL_VRAM_GB" -ge 160 ]]; then
        # 160GB+ (e.g. 2x RTX Pro 6000): both models
        update_env "SMALL_MODEL" "openai/gpt-oss-20b"
        update_env "LARGE_MODEL" "openai/gpt-oss-120b"
        echo "  Config: small (gpt-oss-20b) + large (gpt-oss-120b)"
    elif [[ "$TOTAL_VRAM_GB" -ge 80 ]]; then
        # 80-159GB (e.g. single 96GB, or 2x48GB): small + large fits tight
        update_env "SMALL_MODEL" "openai/gpt-oss-20b"
        update_env "LARGE_MODEL" "openai/gpt-oss-120b"
        update_env "GPU_MEMORY_UTILIZATION" "0.85"
        echo "  Config: small (gpt-oss-20b) + large (gpt-oss-120b), conservative memory (0.85)"
    elif [[ "$TOTAL_VRAM_GB" -ge 30 ]]; then
        # 30-79GB (e.g. RTX 5090 32GB, or 2x24GB): small model only
        update_env "SMALL_MODEL" "openai/gpt-oss-20b"
        update_env "LARGE_MODEL" ""
        echo "  Config: small only (gpt-oss-20b) — not enough VRAM for large model"
    else
        # <30GB (e.g. RTX 4090 24GB): small model only
        update_env "SMALL_MODEL" "openai/gpt-oss-20b"
        update_env "LARGE_MODEL" ""
        echo "  Config: small only (gpt-oss-20b) — not enough VRAM for large model"
    fi

    echo "  GPU settings written to .env"
fi

# --- API keys ---
echo ""
echo "=== API Key Generation ==="
echo ""

# Generate master key if not already set
CURRENT_MASTER=$(grep "^LITELLM_MASTER_KEY=" "$ENV_FILE" 2>/dev/null | cut -d= -f2-)
if [[ -z "$CURRENT_MASTER" ]]; then
    MASTER_KEY="sk-master-$(openssl rand -hex 16)"
    update_env "LITELLM_MASTER_KEY" "$MASTER_KEY"
    echo "Generated master key: $MASTER_KEY"
else
    MASTER_KEY="$CURRENT_MASTER"
    echo "Master key already set (keeping existing)"
fi

# Ask how many team keys to generate
echo ""
read -rp "How many team API keys to generate? [5]: " KEY_COUNT
KEY_COUNT="${KEY_COUNT:-5}"

KEYS=()
for i in $(seq 1 "$KEY_COUNT"); do
    key="sk-team-$(openssl rand -hex 12)"
    KEYS+=("$key")
done

# Write comma-separated keys to .env
KEY_LIST=$(IFS=,; echo "${KEYS[*]}")
update_env "LITELLM_API_KEYS" "$KEY_LIST"

echo ""
echo "Generated $KEY_COUNT team API keys:"
echo ""
echo "  ┌──────────────────────────────────────┐"
echo "  │  Team API Keys — copy and share      │"
echo "  ├──────────────────────────────────────┤"
for i in "${!KEYS[@]}"; do
    printf "  │  %d. %-33s│\n" "$((i + 1))" "${KEYS[$i]}"
done
echo "  └──────────────────────────────────────┘"
echo ""
echo "  Master key (admin only, do not share):"
echo "  $MASTER_KEY"

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Edit .env — set HF_TOKEN (get from https://huggingface.co/settings/tokens)"
echo "  2. Run: ./hub pull-models"
echo "  3. Run: ./hub start"
