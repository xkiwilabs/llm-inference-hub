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
# DECISIVELM_BUNDLES. Its calibration.json pins the exact backbone it was trained against (E4B or 26B-A4B),
# which is fetched into the HF cache.
if [[ -n "${DECISIVELM_BUNDLE_REPO:-}" ]]; then
    bundle_dir="${DECISIVELM_BUNDLE_DIR:-$HOME/.cache/decisivelm/bundles}/$(basename "$DECISIVELM_BUNDLE_REPO")"
    echo "Pulling DecisiveLM bundle $DECISIVELM_BUNDLE_REPO..."
    $HF_CMD download "$DECISIVELM_BUNDLE_REPO" --local-dir "$bundle_dir"

    read -r base_model base_revision < <(python3 -c "
import json, sys
b = json.load(open(sys.argv[1]))['backbone']
print(b['model_id'], b['revision'])
" "$bundle_dir/calibration.json" 2>/dev/null) || { echo "Error: no backbone pin in $bundle_dir/calibration.json"; exit 1; }
    echo "Pulling DecisiveLM backbone $base_model@$base_revision..."
    $HF_CMD download "$base_model" --revision "$base_revision"
    echo "  Done: $bundle_dir (point the DecisiveLM server's DECISIVELM_BUNDLES here)"
fi

echo ""
echo "All models downloaded to $($HF_CMD env 2>/dev/null | grep -i cache || echo '~/.cache/huggingface')"
