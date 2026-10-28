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

# Optional DecisiveLM bundle (blank = skip). The bundle is a plain directory the DecisiveLM server loads via
# DECISIVELM_BUNDLES; its backbone must be the exact revision it was trained against, fetched into the HF cache.
if [[ -n "${DECISIVELM_BUNDLE_REPO:-}" ]]; then
    bundle_dir="${DECISIVELM_BUNDLE_DIR:-$HOME/.cache/decisivelm/bundles}/$(basename "$DECISIVELM_BUNDLE_REPO")"
    base_model="${DECISIVELM_BASE_MODEL:-google/gemma-4-E4B-it}"
    base_revision="${DECISIVELM_BASE_REVISION:-ee0ef6023621cff504d758262d4e04895a5af4a2}"
    echo "Pulling DecisiveLM backbone $base_model@$base_revision..."
    $HF_CMD download "$base_model" --revision "$base_revision"
    echo "Pulling DecisiveLM bundle $DECISIVELM_BUNDLE_REPO..."
    $HF_CMD download "$DECISIVELM_BUNDLE_REPO" --local-dir "$bundle_dir"
    echo "  Done: $bundle_dir (point the DecisiveLM server's DECISIVELM_BUNDLES here)"
fi

echo ""
echo "All models downloaded to $($HF_CMD env 2>/dev/null | grep -i cache || echo '~/.cache/huggingface')"
