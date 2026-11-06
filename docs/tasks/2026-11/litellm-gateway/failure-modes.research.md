# LiteLLM gateway — backend failure modes, measured (2026-11-06)

The gateway registers **brys** (all 32 aliases) and, for the 4 aliases oams serves
(`tiny-dumb-fast`, `tiny-dumb-fast-alt`, `tools-dumb-fast`, `chat-dumb-fast-alt`),
a **second deployment on oams**. LiteLLM load-balances across the two and fails
over on error. These are the measured behaviours for `tiny-dumb-fast` (2
deployments) unless stated. Route config: `timeout=120`, `num_retries=1`,
`allowed_fails=2`, `cooldown_time=30`, `routing_strategy=simple-shuffle`,
`enable_weighted_failover=true`.

The serving deployment is visible per response in `x-litellm-model-id` and
`x-litellm-model-api-base` — the way to see which host answered.

## Normal (both serving)
10 calls → **brys 4 / oams 6** (load-balanced). First call that landed on oams
took **2.4 s** (cold model load), the rest ~50-70 ms. Both hosts are live.

## A. oams reachable but not serving (llama-swap stopped)
Setup: `oams-llm off` (llama-swap stopped; the NetBird relay + socat stay up, so
the TCP connect succeeds then the backend is **refused**).

- 10 calls → **all served by brys, HTTP 200, 0 failed**, ~50-80 ms.
- The picks that hit oams first pay a small retry penalty (~80 ms vs ~50 ms
  baseline): oams returns connection-refused, LiteLLM retries brys.
- **Client-invisible.** Refused = failover in tens of milliseconds.

## B. oams unreachable (blackholed — SYN dropped, no RST)
Setup: temporary nftables DROP on oams for `nb-priv` → tcp 39704 (SYN blackholed,
exactly like NetBird being off / a dead route). This is the dangerous case.

- Fresh router state, request that picks oams: **hangs the full 120 s timeout**
  before failing over. Measured: one call `200` at **120.07 s** (oams timed out,
  retried brys); a call that picked oams twice (`num_retries=1` → 2 attempts)
  **exceeded 200 s** (curl never got a response).
- Once oams cools down (`allowed_fails=2`, `cooldown_time=30`) subsequent calls
  are fast (~0.1 s, served by brys).
- **Worst case latency ≈ `timeout × (num_retries+1)` = 120 × 2 = 240 s.**
- A blackholed backend is ~1000× worse than a stopped one (240 s vs ~30 ms).

## C. A model whose ONLY backend is down (brys-only alias, brys refused)
Setup: stop the etra→brys egress relay; request `chat-dumb-fast` (brys-only).

- Attempts 1-3 → **HTTP 500** (1.9-3.4 s then 0.06 s; refused + retry).
- Attempts 4-5 → **HTTP 429** (~0.03 s) once the deployment is cooled: "no
  healthy deployment" is a fast `RouterRateLimitError` → 429.
- So: transient errors first, then a fast 429 while cooling, then retries after
  `cooldown_time`.

## What this means operationally

- **oams going away never causes a client error for its 4 shared aliases** —
  brys serves the same models, so oams is pure redundancy there. A client only
  fails when a **brys-only** alias's backend is down (scenario C).
- **Refused (host stopped, port closed) is cheap.** **Blackholed (NetBird off /
  dead route) is expensive** — up to 240 s per affected request because the
  connect hangs instead of failing fast.
- **Recommendation for blackhole safety:** enable background health checks +
  `enable_health_check_routing` so a dead-but-blackholed oams is detected and
  skipped *before* a client request pays the 120 s connect timeout. Until then,
  the 120 s `timeout` bounds the damage but a client can still wait it out once
  per cooldown window.
- **Cold start**: a freshly started oams model pays its load time on the first
  request (2.4 s for qwen3.5-0.8b); account for `capabilities.loadSeconds`.

## Reproducing (safe, contained)

```sh
# which host served
curl -sD - -o /dev/null http://etra:4000/v1/chat/completions -H "Authorization: Bearer $KEY" \
  -H 'Content-Type: application/json' -d '{"model":"tiny-dumb-fast","messages":[{"role":"user","content":"hi"}],"max_tokens":3}' \
  | grep -i x-litellm-model-id

# A: refused  -> stop llama-swap, keep relay up
sudo oams-llm off
# B: blackholed -> drop SYN, then restore
sudo nft insert rule inet nixos-fw input iifname "nb-priv" tcp dport 39704 drop
#   ... probe ... then:
sudo nft -a list chain inet nixos-fw input | grep 39704   # find handle
sudo nft delete rule inet nixos-fw input handle <H>
```
