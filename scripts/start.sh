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
