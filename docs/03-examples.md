# Examples

How to connect to inference-hub from different languages, tools, and frameworks.

For all examples below, replace:
- `SERVER_IP` with the machine's IP address (or `localhost` if on the same machine)
- `mind-team-YOUR_KEY` with your actual API key

## Python

### Quick test

```bash
pip install openai
export INFERENCE_HUB_URL="http://SERVER_IP:4200/v1"
export INFERENCE_HUB_KEY="mind-team-YOUR_KEY"
python examples/test_connection.py
```

This lists available models, sends a test message, and confirms the connection works.

### Interactive chat

```bash
python examples/chat_session.py
```

A multi-turn chat in your terminal. Maintains conversation history.

### Streaming

```bash
python examples/streaming.py
```

Watch tokens arrive in real time.

### In your own code

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://SERVER_IP:4200/v1",
    api_key="mind-team-YOUR_KEY",
)

response = client.chat.completions.create(
    model="small",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Explain transformers in one paragraph."},
    ],
)
print(response.choices[0].message.content)
```

## curl

### Simple request

```bash
curl http://SERVER_IP:4200/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer mind-team-YOUR_KEY" \
  -d '{
    "model": "small",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### List models

```bash
curl http://SERVER_IP:4200/v1/models \
  -H "Authorization: Bearer mind-team-YOUR_KEY"
```

### Streaming

```bash
curl http://SERVER_IP:4200/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer mind-team-YOUR_KEY" \
  -d '{
    "model": "small",
    "stream": true,
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## JavaScript / TypeScript

```bash
npm install openai
```

```typescript
import OpenAI from "openai";

const client = new OpenAI({
  baseURL: "http://SERVER_IP:4200/v1",
  apiKey: "mind-team-YOUR_KEY",
});

const response = await client.chat.completions.create({
  model: "small",
  messages: [{ role: "user", content: "Hello!" }],
});
console.log(response.choices[0].message.content);
```

## Open WebUI

[Open WebUI](https://github.com/open-webui/open-webui) gives you a ChatGPT-like browser interface for your models.

```bash
docker run -d -p 3000:8080 \
  -e OPENAI_API_BASE_URL=http://HOST_IP:4200/v1 \
  -e OPENAI_API_KEY=mind-team-YOUR_KEY \
  --add-host=host.docker.internal:host-gateway \
  --name open-webui \
  ghcr.io/open-webui/open-webui:main
```

Replace `HOST_IP` with the server's LAN IP (not `localhost` — the container needs to reach the host network). Then open `http://localhost:3000` in your browser and select the `small` or `large` model.

## Urika

Inference-hub works as a private endpoint for [Urika](https://github.com/YOUR_ORG/urika) projects. Run agents on your own hardware — nothing leaves your network.

### Fully private

All agents use inference-hub:

```toml
# urika.toml
[privacy]
mode = "private"

[privacy.endpoints.private]
base_url = "http://SERVER_IP:4200"
api_key_env = "INFERENCE_HUB_KEY"

[runtime]
model = "small"
```

```bash
export INFERENCE_HUB_KEY="mind-team-YOUR_KEY"
urika run my-project
```

### Hybrid (sensitive data stays local)

Data agent runs on inference-hub, everything else on cloud:

```toml
# urika.toml
[privacy]
mode = "hybrid"

[privacy.endpoints.private]
base_url = "http://SERVER_IP:4200"
api_key_env = "INFERENCE_HUB_KEY"

[runtime]
model = "claude-sonnet-4-5"

[runtime.models.data_agent]
endpoint = "private"
model = "small"

[runtime.models.tool_builder]
endpoint = "private"
model = "small"
```

### Per-agent model assignment (dual GPU)

On a machine with both models running, assign heavy-reasoning agents to the large model:

```toml
# urika.toml
[privacy]
mode = "private"

[privacy.endpoints.private]
base_url = "http://SERVER_IP:4200"
api_key_env = "INFERENCE_HUB_KEY"

[runtime]
model = "small"

[runtime.models.task_agent]
endpoint = "private"
model = "large"

[runtime.models.planning_agent]
endpoint = "private"
model = "large"
```

## Any OpenAI-compatible tool

The pattern is always the same:

| Setting | Value |
|---|---|
| Base URL / API Base | `http://SERVER_IP:4200/v1` |
| API Key | `mind-team-YOUR_KEY` |
| Model name | `small` or `large` |

This includes LangChain, LlamaIndex, AutoGen, CrewAI, Semantic Kernel, Continue.dev, Cursor, Aider, and anything else with an OpenAI-compatible mode.
