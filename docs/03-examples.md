# Examples

How to connect to inference-hub from different languages, tools, and frameworks.

For all examples below, replace:
- `SERVER_IP` with the machine's IP address (or `localhost` if on the same machine)
- `YOUR_API_KEY` with your actual API key (from `./hub add-key`)

## Python

### Quick test

```bash
pip install openai
export INFERENCE_HUB_URL="http://SERVER_IP:4200/v1"
export INFERENCE_HUB_KEY="YOUR_API_KEY"
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
    api_key="YOUR_API_KEY",
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
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d '{
    "model": "small",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### List models

```bash
curl http://SERVER_IP:4200/v1/models \
  -H "Authorization: Bearer YOUR_API_KEY"
```

### Streaming

```bash
curl http://SERVER_IP:4200/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
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
  apiKey: "YOUR_API_KEY",
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
  -e OPENAI_API_KEY=YOUR_API_KEY \
  --add-host=host.docker.internal:host-gateway \
  --name open-webui \
  ghcr.io/open-webui/open-webui:main
```

Replace `HOST_IP` with the server's LAN IP (not `localhost` — the container needs to reach the host network). Then open `http://localhost:3000` in your browser and select the `small` or `large` model.

## Agent Frameworks

Inference-hub works as a private backend for AI agent frameworks. Both OpenAI and Anthropic API patterns are supported.

### OpenAI-compatible agents

Any framework using the OpenAI SDK:

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://SERVER_IP:4200/v1",
    api_key="YOUR_API_KEY",
)

response = client.chat.completions.create(
    model="small",
    messages=[{"role": "user", "content": "Hello"}],
)
```

### Anthropic-compatible agents

Any framework using the Anthropic SDK:

```python
import anthropic

client = anthropic.Anthropic(
    base_url="http://SERVER_IP:4200/anthropic",
    api_key="YOUR_API_KEY",
)

message = client.messages.create(
    model="small",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Hello"}],
)
print(message.content[0].text)
```

### Environment variable pattern

Most frameworks accept endpoint configuration via environment variables:

```bash
# For OpenAI-compatible frameworks
export OPENAI_BASE_URL="http://SERVER_IP:4200/v1"
export OPENAI_API_KEY="YOUR_API_KEY"

# For Anthropic-compatible frameworks
export ANTHROPIC_BASE_URL="http://SERVER_IP:4200/anthropic"
export ANTHROPIC_API_KEY="YOUR_API_KEY"
```

Both endpoints serve the same models. Use whichever matches your framework's SDK.

## Any OpenAI- or Anthropic-compatible tool

The pattern is always the same:

| Setting | OpenAI SDK | Anthropic SDK |
|---|---|---|
| Base URL / API Base | `http://SERVER_IP:4200/v1` | `http://SERVER_IP:4200/anthropic/v1` |
| API Key | `YOUR_API_KEY` | `YOUR_API_KEY` |
| Model name | `small` or `large` | `small` or `large` |

This includes LangChain, LlamaIndex, AutoGen, CrewAI, Semantic Kernel, Continue.dev, Cursor, Aider, and anything else with an OpenAI- or Anthropic-compatible mode.
