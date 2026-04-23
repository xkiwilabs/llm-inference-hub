# Managing Models

How to swap, add, and remove models.

## Default models

Out of the box, inference-hub runs Google's **Gemma 4** family:

| Alias | HF model ID | Params | Modalities | Notes |
|---|---|---|---|---|
| `small` | `google/gemma-4-E4B-it` | ~8B (4.5B active) | text + image + **audio** | Balanced on-device model, ~6.3GB at 4-bit |
| `large` | `google/gemma-4-26B-A4B-it` | 26B MoE, 4B active | text + image | Mixture-of-experts, runs near dense-7B speed |

Both support tool calling with the `gemma4` parser (already wired up in `docker-compose.yml`).

### Other Gemma 4 variants

| Model | Size | Modalities | When to use |
|---|---|---|---|
| `google/gemma-4-E2B-it` | ~2B | text + image + audio | Very low VRAM / edge |
| `google/gemma-4-E4B-it` | ~8B | text + image + audio | **Default small** |
| `google/gemma-4-26B-A4B-it` | 26B MoE | text + image | **Default large** |
| `google/gemma-4-31B-it` | 31B dense | text + image | Max quality, needs ~80GB bf16 |
| `nvidia/Gemma-4-31B-IT-NVFP4` | 31B @ NVFP4 | text + image | 31B dense in ~18GB (Blackwell only) |

The E2B / E4B variants are the only ones that accept audio input. 26B MoE and 31B dense are text + image only — sending audio to them returns a 400.

## Changing models

```bash
# Switch the small model
./hub set-model small google/gemma-4-E2B-it

# Switch the large model
./hub set-model large nvidia/Gemma-4-31B-IT-NVFP4

# Remove the large model (free up VRAM)
./hub set-model large --clear
```

Each command updates `.env`, downloads the new model if needed, and restarts the affected service. LiteLLM is also restarted so it picks up the new model name.

## Adding a large model

If your machine was set up with only a small model (single GPU), you can add a large model later:

```bash
./hub set-model large google/gemma-4-26B-A4B-it
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

## Using non-Gemma models

Any model on HuggingFace that vLLM supports works. A few alternatives:

| Model | Size | VRAM needed | Notes |
|---|---|---|---|
| `Qwen/Qwen2.5-0.5B-Instruct` | 0.5B | ~1GB | Tiny, good for testing |
| `Qwen/Qwen2.5-7B-Instruct` | 7B | ~14GB | Text-only |
| `Qwen/Qwen2.5-14B-Instruct` | 14B | ~28GB | Fits on RTX 4090 with quantization |
| `Qwen/Qwen2.5-72B-Instruct` | 72B | ~140GB | Needs multi-GPU |
| `openai/gpt-oss-20b` | 21B (MoE) | ~16GB | Needs CUDA 12.8+ / driver 570+ |
| `openai/gpt-oss-120b` | 117B (MoE) | ~80GB | Needs CUDA 12.8+ / driver 570+ |

> **Heads up:** the default vLLM command in `docker-compose.yml` passes `--tool-call-parser gemma4`, `--reasoning-parser gemma4`, and a Gemma-specific chat template. If you swap to a non-Gemma model, change `TOOL_CALL_PARSER` in `.env` (e.g. `hermes`, `qwen25`) and update the chat-template flag accordingly, or remove those flags entirely.

## Model names in the API

Regardless of what model is running, clients always use `"model": "small"` or `"model": "large"`. LiteLLM handles the routing. This means you can swap the underlying model without changing any client code.

## VRAM tuning

Memory utilization is set per-service in `.env`:

```
SMALL_GPU_MEM_UTIL=0.25   # E4B is small; leaves ~70GB free on GPU 0 for other work
LARGE_GPU_MEM_UTIL=0.65   # 26B MoE needs weights + KV + CUDA graphs
MAX_MODEL_LEN=32768       # per-request context window
```

Lower these if you need to share the GPU with other workloads (e.g. computer-vision training). Raise `MAX_MODEL_LEN` only after verifying the KV cache still fits.
