#!/usr/bin/env bash
# Called by hub pull-models
# Downloads models defined in .env using the huggingface CLI.

# Find the CLI command (hf is the new name, huggingface-cli is legacy)
if command -v hf &>/dev/null; then
    HF_CMD="hf"
elif command -v huggingface-cli &>/dev/null; then
    HF_CMD="huggingface-cli"
else
    echo "Error: huggingface CLI not found. Run './hub setup' first."
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
    $HF_CMD download "$model"
    echo "  Done: $model"
}

pull_model "${SMALL_MODEL:-}"
pull_model "${LARGE_MODEL:-}"

echo ""
echo "All models downloaded to $($HF_CMD env 2>/dev/null | grep -i cache || echo '~/.cache/huggingface')"
