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

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Edit .env — set HF_TOKEN and LITELLM_MASTER_KEY at minimum"
echo "  2. Run: ./hub pull-models"
echo "  3. Run: ./hub start"
