#!/usr/bin/env bash
# Called by hub status
# Shows: container states, GPU utilization, endpoint health checks.

echo "=== Models ==="
echo "  small: ${SMALL_MODEL:-<not set>}"
if [[ -n "${LARGE_MODEL:-}" ]]; then
    echo "  large: ${LARGE_MODEL}"
else
    echo "  large: (disabled)"
fi

echo ""
echo "=== Container Status ==="
docker compose -f "$HUB_DIR/docker-compose.yml" --env-file "$HUB_DIR/.env" ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

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

# LiteLLM gateway — requires API key for health check
if curl -sf --max-time 5 -H "Authorization: Bearer ${LITELLM_MASTER_KEY:-}" \
    "http://localhost:${LITELLM_PORT:-4200}/health" > /dev/null 2>&1; then
    echo "  litellm: healthy"
else
    echo "  litellm: not responding"
fi

# Postgres database
if docker compose -f "$HUB_DIR/docker-compose.yml" --env-file "$HUB_DIR/.env" \
    exec -T postgres pg_isready -U litellm > /dev/null 2>&1; then
    echo "  postgres: healthy"
else
    echo "  postgres: not responding"
fi

echo ""
echo "=== Connect ==="
PORT="${LITELLM_PORT:-4200}"
LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
[[ -n "$LAN_IP" ]] && echo "  LAN:       http://${LAN_IP}:${PORT}"
TS_IP=$(tailscale ip -4 2>/dev/null)
[[ -n "$TS_IP" ]] && echo "  Tailscale: http://${TS_IP}:${PORT}"
echo "  Local:     http://localhost:${PORT}"
