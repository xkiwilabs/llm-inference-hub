#!/usr/bin/env bash
# Called by hub add-key / list-keys / delete-key / usage
# Manages virtual API keys via the LiteLLM admin API.

ACTION="${1:-}"
shift || true

LITELLM_URL="http://localhost:${LITELLM_PORT:-4200}"
MASTER_KEY="${LITELLM_MASTER_KEY:-}"

if [[ -z "$MASTER_KEY" ]]; then
    echo "Error: LITELLM_MASTER_KEY not set. Run './hub setup' first."
    exit 1
fi

check_litellm() {
    if ! curl -sf --max-time 3 -H "Authorization: Bearer $MASTER_KEY" \
        "$LITELLM_URL/health" > /dev/null 2>&1; then
        echo "Error: LiteLLM is not running. Run './hub start' first."
        exit 1
    fi
}

case "$ACTION" in
    add)
        NAME="${1:-}"
        if [[ -z "$NAME" ]]; then
            echo "Usage: ./hub add-key <name>"
            exit 1
        fi

        check_litellm

        RESPONSE=$(curl -sf --max-time 10 \
            -X POST "$LITELLM_URL/key/generate" \
            -H "Authorization: Bearer $MASTER_KEY" \
            -H "Content-Type: application/json" \
            -d "{\"key_alias\": \"$NAME\"}" 2>&1)

        if [[ $? -ne 0 || -z "$RESPONSE" ]]; then
            echo "Error: Failed to create key. Response: ${RESPONSE:-<empty>}"
            exit 1
        fi

        KEY=$(echo "$RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'key' in data:
    print(data['key'])
else:
    print('ERROR:' + json.dumps(data), file=sys.stderr)
    sys.exit(1)
" 2>&1)

        if [[ $? -ne 0 ]]; then
            echo "Error: Failed to parse response. $KEY"
            exit 1
        fi

        echo "Created key for $NAME: $KEY"
        ;;

    list)
        check_litellm

        RESPONSE=$(curl -sf --max-time 10 \
            -X GET "$LITELLM_URL/key/list" \
            -H "Authorization: Bearer $MASTER_KEY" 2>&1)

        if [[ $? -ne 0 || -z "$RESPONSE" ]]; then
            echo "Error: Failed to list keys. Response: ${RESPONSE:-<empty>}"
            exit 1
        fi

        echo "$RESPONSE" | python3 -c "
import sys, json

data = json.load(sys.stdin)

# The response may be a dict with a 'keys' field or a list directly
if isinstance(data, dict):
    keys = data.get('keys', [])
else:
    keys = data

# Filter out the master key (no alias) and collect virtual keys
virtual_keys = []
for k in keys:
    alias = k.get('key_alias') or k.get('key_name') or ''
    token = k.get('token', k.get('key', ''))
    spend = k.get('spend', 0.0)
    if alias:
        virtual_keys.append((alias, token, spend))

if not virtual_keys:
    print('No API keys found. Create one with: ./hub add-key <name>')
    sys.exit(0)

# Print table
print(f\"{'Name':<20} {'Key':<18} {'Spend':>10}\")
print(f\"{'-'*20} {'-'*18} {'-'*10}\")
for alias, token, spend in virtual_keys:
    truncated = token[:10] + '...' if len(token) > 10 else token
    spend_str = f'\${spend:.4f}' if spend else '\$0.0000'
    print(f'{alias:<20} {truncated:<18} {spend_str:>10}')
"
        ;;

    delete)
        NAME="${1:-}"
        if [[ -z "$NAME" ]]; then
            echo "Usage: ./hub delete-key <name>"
            exit 1
        fi

        check_litellm

        # First, find the key token by alias
        RESPONSE=$(curl -sf --max-time 10 \
            -X GET "$LITELLM_URL/key/list" \
            -H "Authorization: Bearer $MASTER_KEY" 2>&1)

        if [[ $? -ne 0 || -z "$RESPONSE" ]]; then
            echo "Error: Failed to list keys. Response: ${RESPONSE:-<empty>}"
            exit 1
        fi

        KEY_TOKEN=$(echo "$RESPONSE" | python3 -c "
import sys, json

name = '$NAME'
data = json.load(sys.stdin)

if isinstance(data, dict):
    keys = data.get('keys', [])
else:
    keys = data

for k in keys:
    alias = k.get('key_alias') or k.get('key_name') or ''
    if alias == name:
        print(k.get('token', k.get('key', '')))
        sys.exit(0)

print('', file=sys.stderr)
sys.exit(1)
" 2>&1)

        if [[ $? -ne 0 || -z "$KEY_TOKEN" ]]; then
            echo "Error: No key found with name '$NAME'."
            exit 1
        fi

        # Delete the key
        DEL_RESPONSE=$(curl -sf --max-time 10 \
            -X POST "$LITELLM_URL/key/delete" \
            -H "Authorization: Bearer $MASTER_KEY" \
            -H "Content-Type: application/json" \
            -d "{\"keys\": [\"$KEY_TOKEN\"]}" 2>&1)

        if [[ $? -ne 0 ]]; then
            echo "Error: Failed to delete key '$NAME'. Response: ${DEL_RESPONSE:-<empty>}"
            exit 1
        fi

        echo "Deleted key '$NAME'."
        ;;

    usage)
        NAME="${1:-}"

        check_litellm

        RESPONSE=$(curl -sf --max-time 10 \
            -X GET "$LITELLM_URL/key/list" \
            -H "Authorization: Bearer $MASTER_KEY" 2>&1)

        if [[ $? -ne 0 || -z "$RESPONSE" ]]; then
            echo "Error: Failed to fetch key usage. Response: ${RESPONSE:-<empty>}"
            exit 1
        fi

        echo "$RESPONSE" | python3 -c "
import sys, json

name = '$NAME' if '$NAME' else None
data = json.load(sys.stdin)

if isinstance(data, dict):
    keys = data.get('keys', [])
else:
    keys = data

virtual_keys = []
for k in keys:
    alias = k.get('key_alias') or k.get('key_name') or ''
    spend = k.get('spend', 0.0)
    if alias:
        virtual_keys.append((alias, spend))

if not virtual_keys:
    print('No API keys found. Create one with: ./hub add-key <name>')
    sys.exit(0)

if name:
    found = [vk for vk in virtual_keys if vk[0] == name]
    if not found:
        print(f\"Error: No key found with name '{name}'.\", file=sys.stderr)
        sys.exit(1)
    alias, spend = found[0]
    spend_str = f'\${spend:.4f}' if spend else '\$0.0000'
    print(f'Key: {alias}')
    print(f'Spend: {spend_str}')
else:
    total = 0.0
    print(f\"{'Name':<20} {'Spend':>10}\")
    print(f\"{'-'*20} {'-'*10}\")
    for alias, spend in virtual_keys:
        spend_str = f'\${spend:.4f}' if spend else '\$0.0000'
        print(f'{alias:<20} {spend_str:>10}')
        total += spend or 0.0
    print(f\"{'-'*20} {'-'*10}\")
    total_str = f'\${total:.4f}'
    print(f\"{'Total':<20} {total_str:>10}\")
"
        ;;

    *)
        cat <<'EOF'
Usage: ./hub <command> [args]

Key management commands:
  add-key <name>       Create a new API key
  list-keys            List all API keys
  delete-key <name>    Delete an API key by name
  usage [name]         Show spend for all keys or a specific key
EOF
        ;;
esac
