#!/usr/bin/env bash
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
