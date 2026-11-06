# vLLM behind llama-swap on the GX10

The configuration behind the post
[*How I set up an inference server on the GX10*](https://josehenrique.dev/posts/gx10-inference-server/).
These are the files running on the machine, copied as they are.

- `llama-swap.yaml`: goes in `/etc/llama-swap/config.yaml`. One entry per model.
  One model is loaded at a time, and it unloads after 15 idle minutes.
- `llama-swap.service`: the systemd unit.

## Adapting it

- The images and flags target the GB10 (arm64, 121 GiB of unified memory).
  `--gpu-memory-utilization` is a share of that pool, so check it on other
  hardware.
- Weights are expected in `/srv/models/hf`, and `HF_HUB_OFFLINE=1` keeps vLLM
  from downloading them at startup. Download them first or drop that flag.
- The unit requires `llm-firewall.service`, which is not included: it is an
  nftables rule that drops port 8000 on every interface except loopback, the
  pod network and Tailscale. llama-swap listens on `0.0.0.0:8000` with no
  authentication, so put an equivalent rule in place before removing that
  dependency.
