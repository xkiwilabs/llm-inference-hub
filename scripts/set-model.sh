#!/usr/bin/env bash
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

        # Pull the new model
        export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"
        HF_CMD=$(command -v hf || command -v huggingface-cli)
        echo "Pulling $MODEL..."
        $HF_CMD download "$MODEL"

        # Regenerate litellm config and restart services
        envsubst < "$HUB_DIR/litellm/config.template.yaml" > "$HUB_DIR/litellm/config.yaml"
        docker compose -f "$HUB_DIR/docker-compose.yml" --env-file "$HUB_DIR/.env" up -d --force-recreate vllm-small litellm
        echo "Done. vllm-small restarting with $MODEL"
        ;;

    large)
        if [[ "$MODEL" == "--clear" ]]; then
            echo "Clearing large model..."
            update_env_var "LARGE_MODEL" ""
            export LARGE_MODEL_REPLICAS=0
            docker compose -f "$HUB_DIR/docker-compose.yml" --env-file "$HUB_DIR/.env" up -d --scale vllm-large=0
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

            # Pull the new model
            export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"
            HF_CMD=$(command -v hf || command -v huggingface-cli)
            echo "Pulling $MODEL..."
            $HF_CMD download "$MODEL"

            # Regenerate litellm config and restart services
            export LARGE_MODEL_REPLICAS=1
            envsubst < "$HUB_DIR/litellm/config.template.yaml" > "$HUB_DIR/litellm/config.yaml"
            docker compose -f "$HUB_DIR/docker-compose.yml" --env-file "$HUB_DIR/.env" up -d --force-recreate vllm-large litellm
            echo "Done. vllm-large restarting with $MODEL"
        fi
        ;;

    *)
        echo "Error: slot must be 'small' or 'large'"
        exit 1
        ;;
esac
