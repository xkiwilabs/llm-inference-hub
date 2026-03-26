# Managing Models

How to swap, add, and remove models.

## Changing models

```bash
# Switch the small model
./hub set-model small Qwen/Qwen2.5-14B-Instruct

# Switch the large model
./hub set-model large openai/gpt-oss-120b

# Remove the large model (free up VRAM)
./hub set-model large --clear
```

Each command updates `.env`, downloads the new model if needed, and restarts the affected service. LiteLLM is also restarted so it picks up the new model name.

## Adding a large model

If your machine was set up with only a small model (single GPU), you can add a large model later:

```bash
./hub set-model large openai/gpt-oss-120b
```

This sets `LARGE_MODEL` in `.env`, downloads the model, and starts the `vllm-large` container.

## Removing the large model

```bash
./hub set-model large --clear
```

Blanks `LARGE_MODEL` in `.env` and scales the `vllm-large` container to 0 replicas. VRAM is freed immediately.

## Pre-downloading models

To download models without starting them (useful for slow connections):

```bash
./hub pull-models
```

This downloads whatever is in `SMALL_MODEL` and `LARGE_MODEL` in `.env` to `~/.cache/huggingface`.

## Which models work?

Any model on HuggingFace that vLLM supports. Some options:

| Model | Size | VRAM needed | Notes |
|---|---|---|---|
| `openai/gpt-oss-20b` | 21B (MoE) | ~16GB | Default small. Needs CUDA 12.8+ / driver 570+ |
| `openai/gpt-oss-120b` | 117B (MoE) | ~80GB | Default large. Needs CUDA 12.8+ / driver 570+ |
| `Qwen/Qwen2.5-0.5B-Instruct` | 0.5B | ~1GB | Tiny, good for testing |
| `Qwen/Qwen2.5-7B-Instruct` | 7B | ~14GB | Good small model |
| `Qwen/Qwen2.5-14B-Instruct` | 14B | ~28GB | Fits on RTX 4090 with quantization |
| `Qwen/Qwen2.5-72B-Instruct` | 72B | ~140GB | Needs multi-GPU |

## Model names in the API

Regardless of what model is running, clients always use `"model": "small"` or `"model": "large"`. LiteLLM handles the routing. This means you can swap the underlying model without changing any client code.
