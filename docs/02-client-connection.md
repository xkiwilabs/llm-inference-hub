# Client Connection

How to connect to inference-hub from any machine on your network.

## Connection details

| Setting | OpenAI SDK | Anthropic SDK |
|---|---|---|
| Base URL | `http://<server-ip>:4200/v1` | `http://<server-ip>:4200/anthropic/v1` |
| API Key | Your key from `./hub add-key` | Same key |
| Model | `small` or `large` | `small` or `large` |

- **Same machine:** use `localhost` instead of the IP
- **LAN:** use the server's local IP (e.g. `192.168.1.100`)
- **Remote via Tailscale:** use the server's Tailscale IP (e.g. `100.x.x.x`)

## Testing your connection

The simplest test from any machine:

```bash
curl http://SERVER_IP:4200/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d '{"model": "small", "messages": [{"role": "user", "content": "Hello"}]}'
```

If you get a JSON response with a `choices` array, you're connected.

## What models are available?

Ask the API:

```bash
curl http://SERVER_IP:4200/v1/models \
  -H "Authorization: Bearer YOUR_API_KEY"
```

This returns the list of loaded models. Typically `small` and (if configured) `large`.

## Compatibility

Inference-hub speaks the OpenAI API. Any tool with a "custom OpenAI endpoint" or "OpenAI-compatible" option works. This includes:

- Python (OpenAI SDK, LangChain, LlamaIndex, AutoGen, CrewAI)
- JavaScript/TypeScript (OpenAI SDK)
- Rust, Go, Java (any OpenAI client library)
- Open WebUI, LibreChat (browser-based chat UIs)
- Cursor, Continue.dev, Aider (AI coding tools)
- AI agent frameworks (any Anthropic or OpenAI-compatible framework)
- Anything else that can hit an OpenAI- or Anthropic-compatible REST API

See [Examples](03-examples.md) for specific setup instructions for each.
