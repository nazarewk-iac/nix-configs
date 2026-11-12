---
type: Research
description: Measured evidence for every traffic path into the brys and oams llama-swap servers on 2026-11-12, with the health-check volume and the model-swap storm it causes.
authored_by: agent
timestamp: 2026-11-12T13:20:00+01:00
---

# Traffic into the brys and oams local model servers

## Method

- `ss -tnp` on each host, filtered on ports `39700`, `39704` and `443`.
- `journalctl -u llama-swap` on each host, grouped by request path and `User-Agent`.
- The generated gateway config on etra
  (`/nix/store/zrjip57hngzdl5rdx561ypciq7vqyis4-litellm-config.json`).
- The Caddy access log on etra for `litellm.etra.priv.nb.net.int.kdn.im`.
- `netbird status -d` on etra to map every client address to a peer.

## Who reaches the relays

On brys and on oams, every established connection to `:39704` has peer `100.79.187.16`, which is
etra (`etra.priv.nb.net.int.kdn.im`). Nothing else reaches the NetBird relay. On brys, the
Prometheus container reaches `:39700` through the `10.233.90.1` relay; on oams, only loopback
traffic exists.

## Request mix, last 10 minutes

brys:

```
592 POST /v1/chat/completions | AsyncOpenAI/Python 3.14.1
323 GET  /v1/models          | curl/8.23.0
323 GET  /api/metrics/activity| curl/8.23.0
 12 GET  /v1/models          | litellm/1.108.0
```

oams:

```
304 GET  /v1/models           | curl/8.23.0
304 GET  /api/metrics/activity | curl/8.23.0
 80 POST /v1/chat/completions | AsyncOpenAI/Python 3.14.1
 10 GET  /v1/models           | python-httpx/0.28.1
  5 GET  /v1/models           | litellm/1.108.0
```

The `AsyncOpenAI` requests are the LiteLLM background health checks. The `curl/8.23.0` pairs are
`llm-stats.service` (`packages/llm/llm-stats/llm-stats.sh`), which polls `/api/metrics/activity`
and `/v1/models` every 2 s. The `litellm/1.108.0` and `python-httpx` requests are the gateway's
model discovery.

## Gateway shape

The active config has 37 deployments on brys, 5 on oams and 3 on Requesty. It sets:

```json
"background_health_checks": true,
"health_check_interval": 30,
"health_check_staleness_threshold": 120,
"enable_health_check_routing": true
```

and every deployment carries `health_check_max_tokens = 1` and `health_check_timeout = 5`. The
probe is a real completion. 37 deployments / 30 s is 1.23 probes/s, which matches the measured
592 per 10 minutes on brys. 5 / 30 s is 0.17/s, which matches 80 per 10 minutes on oams.

## The probe causes a model swap storm

brys, `journalctl -u llama-swap`, 2026-11-12T13:13:17:

```
[DEBUG] matrix: starting swap for model qwen3-omni-30b-a3b, evicting [qwen3.5-35b-a3b qwen3.5-4b]
[DEBUG] [qwen3.5-4b] sending stop signal with timeout 15m0s
[DEBUG] matrix: queuing request for model qwen3.5-4b (collides with in-flight swap)
[DEBUG] matrix: queuing request for model qwen3-vl-30b-a3b (collides with in-flight swap)
[DEBUG] matrix: queuing request for model ornith-1.5-35b-a3b (collides with in-flight swap)
[DEBUG] matrix: queuing request for model granite-4.2-3b (collides with in-flight swap)
[DEBUG] matrix: queuing request for model nemotron-3-nano-30b-a3b (collides with in-flight swap)
... 15 more models queued in the same second ...
[DEBUG] <qwen3-omni-30b-a3b> Executing start command: ...llama-server --port 10010 ...
```

All probes of one health-check round arrive together, so the matrix engine tries to serve every
model at once, evicts what is resident, and starts a child process. On oams the same pattern shows
as a `granite-4.2-3b` child starting while `gemma-4-e4b` had been resident for 1763 s.

## Why the probes are not worth their cost

`docs/tasks/2026-11/litellm-gateway/routing-and-timeouts.design.md` measured two things:

1. Health-check routing does not protect against a blackholed host here, because the etra-side
   socat relay accepts the connect and hangs on its upstream.
2. The mechanism that does work is the host-side probe: `litellm-host-probe.timer` runs every
   15 s, connects to `100.79.164.36:39704` and `100.79.80.79:39704` directly, and writes
   `/var/lib/litellm/host-health.json` (`{"brys": true, "oams": true}` at measurement time).
   `probe.host_probe` drops a deployment whose host is down before any connect.

So the per-deployment completion probes add no protection that the host probe does not already
provide, and they force a swap every 30 s.

## Real client traffic

The etra Caddy access log for the gateway aggregates to:

```
1259  oams  GET  /v1/models           opencode/latest/2.2.5/cli
  52  oams  POST /v1/chat/completions curl/8.22.0
   4  oams  POST /v1/chat/completions pi/1.4.0 (linux; node/v24.21.0; x64)
   3  oams  POST /v1/chat/completions pi/1.5.0 (linux; node/v24.22.2; x64)
   2  oams  POST /v1/chat/completions opencode/latest/2.2.5/cli
```

All of it comes from oams (`100.79.80.79` and its NetBird IPv6
`fdb8:f45:ae6e:89fe:a575:7007:3214:dc3d`). The `/v1/models` poll is the opencode discovery loop,
once per minute. No other peer used the gateway in the log window.

## The intended fix

`hosts/etra/litellm.nix`, `gatewayConfig.general_settings`:

```nix
background_health_checks = false;
enable_health_check_routing = false;
```

Keep `num_retries = 1`, `cooldown_time = 30`, `allowed_fails = 2` and the host probe. A real
failure then cools the deployment, and a dead host is still filtered before the connect.

The host probe itself changed from a bare TCP connect to `GET /health` on llama-swap, which answers
`OK` without loading a model. See [done.md](done.md).
