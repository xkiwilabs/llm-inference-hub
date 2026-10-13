# Troubleshooting

## `./hub status` shows "not responding" for litellm

LiteLLM takes a few seconds to start. Wait 10-15 seconds after `./hub start` and check again.

## `./hub status` shows "not responding" for vllm-small

Model loading takes 1-2 minutes after start. Wait and check again. If it persists:

```bash
./hub logs vllm-small
```

## CUDA version error on start

```
nvidia-container-cli: requirement error: unsatisfied condition: cuda>=12.9
```

Your NVIDIA driver is too old for the vLLM image. Install driver 570 specifically (do **not** use `ubuntu-drivers autoinstall` — it may install a driver that's too new):

```bash
sudo apt-get update && sudo apt-get install nvidia-driver-570 && sudo reboot
```

Then re-run `./hub setup` to auto-detect the new CUDA version.

## CUDA "unsupported display driver" error (Error 803)

```
RuntimeError: Error 803: system has unsupported display driver / cuda driver combination
```

Your NVIDIA driver is **too new** for the vLLM Docker image. This typically happens with driver 580+ (CUDA 13.0). Downgrade to driver 570:

```bash
sudo apt-get install nvidia-driver-570 && sudo reboot
```

## Container exits immediately

Usually a GPU memory issue. Try:

1. Lower `SMALL_GPU_MEM_UTIL` / `LARGE_GPU_MEM_UTIL` in `.env`
2. Use a smaller model (e.g. `google/gemma-4-E2B-it` for the small slot)
3. Check logs: `./hub logs vllm-small`

## "No available memory for the cache blocks"

vLLM couldn't fit the KV cache after loading weights. Either bump the corresponding `*_GPU_MEM_UTIL` in `.env`, or lower `MAX_MODEL_LEN` (default 32768). Context length scales KV cache linearly.

## 400 error when sending audio

There are two different causes, so read the error message.

**"Invalid or unsupported audio file"** — the server can't decode audio at all, whatever the format. The upstream `vllm/vllm-openai` image ships without vLLM's audio extras, so `vllm-small` is built from `vllm/Dockerfile`, which adds them. If you see this error, the container is probably still running the stock image (for example, it was started from an older checkout). Rebuild and recreate it:

```bash
docker compose build --pull vllm-small
docker compose up -d --force-recreate vllm-small
```

`./hub logs vllm-small` will show `Please install vllm[audio] for audio support` if this is the cause.

**Model doesn't support audio** — audio input only works on Gemma 4 **E2B** or **E4B**. The default `small` model is E4B (audio-capable); the default `large` model is 26B MoE and is text + image only. Retry with `--model small`, or swap your small model to an E-variant. See [Managing Models](04-managing-models.md).

## "NVIDIA runtime not found"

Run `./hub setup` again — it configures the Docker NVIDIA runtime.

## Permission denied on Docker

After setup installs Docker, you need to log out and back in for the `docker` group membership to take effect. Quick fix without logging out:

```bash
newgrp docker
```

## Port 4200 already in use

Change `LITELLM_PORT` in `.env` to another port:

```bash
sed -i 's/^LITELLM_PORT=.*/LITELLM_PORT=4201/' .env
./hub restart
```

## Model not found (404) from LiteLLM

The model name in the LiteLLM config doesn't match what vLLM loaded. This happens if you changed models without restarting:

```bash
./hub restart
```

## Client gets "No api key passed in"

You need to pass an API key with every request. Use the `Authorization: Bearer` header with the API key you received from `./hub add-key`.

## Asked for `large` but a smaller model answered

This is expected behaviour, not a bug. When `large` is unavailable, LiteLLM falls back to `small` so the request succeeds instead of hanging or returning `429`.

Confirm it by checking the response headers — `x-litellm-attempted-fallbacks: 1` means a fallback happened, and `x-litellm-model-group` names the model that actually answered. See [Client Connection](02-client-connection.md#automatic-fallback-from-large-to-small).

To find out why `large` was unavailable:

```bash
./hub logs vllm-large
```

Look for the model still loading (normal for a few minutes after start), or `Running: 0 reqs, Waiting: N reqs` with near-zero throughput, which means the scheduler has stalled and the service needs a restart:

```bash
docker restart llm-inference-hub-vllm-large-1
```

## Requests hang for a long time before failing

Requests time out after `request_timeout` (600s, set in `litellm/config.template.yaml`), retried once — so a fully wedged backend can take up to ~20 minutes to return an error.

If that is too long for your use, lower `request_timeout` in `litellm/config.template.yaml` and run `./hub restart`. Set it above the time your longest legitimate generation needs, or you will kill valid requests.

## Can't connect from another machine

1. Check the server is running: `./hub status` on the server
2. Check the port is open: `curl http://SERVER_IP:4200/health` from the client
3. If using Tailscale, make sure both machines are on the same Tailnet
4. The vLLM ports (8001, 8002) are localhost-only by design — clients connect through LiteLLM on port 4200

## Database issues

If `./hub add-key` or `./hub list-keys` fails:

1. Check postgres is running: `./hub status`
2. Check logs: `./hub logs postgres`
3. Reset the database (destroys all keys): `docker volume rm llm-inference-hub_pgdata && ./hub restart`
