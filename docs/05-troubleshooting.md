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

Your NVIDIA driver is too old for the vLLM image. Run `./hub setup` — it auto-detects CUDA and pins a compatible image. If you need the latest vLLM and gpt-oss models, update your driver:

```bash
sudo apt-get update && sudo ubuntu-drivers autoinstall && sudo reboot
```

## Container exits immediately

Usually a GPU memory issue. Try:

1. Lower `GPU_MEMORY_UTILIZATION` in `.env` to `0.85`
2. Use a smaller model
3. Check logs: `./hub logs vllm-small`

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
