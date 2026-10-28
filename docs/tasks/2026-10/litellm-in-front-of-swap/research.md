---
type: Research
description: What litellm 1.102.1 as packaged in this nixpkgs can do in front of llama-swap, what it cannot do, how the existing compat proxy already overlaps it, and the safety rules a retry must obey.
task: definition.md
authored_by: agent
timestamp: 2026-10-27T21:20:00+01:00
---

# Research: litellm in this stack

Checked 2026-10-27 against the pinned nixpkgs (the patched tree under
`.flake.patches/nixpkgs/`), the repository's own proxy aspect, and the earlier
scheduler survey.

## 1. Availability, exactly

```
$ nix eval --raw nixpkgs#litellm.version
1.102.1
```

A NixOS module exists: `.flake.patches/nixpkgs/repo/nixos/modules/services/misc/litellm.nix`.

Its option surface is a free-form YAML passthrough:

```nix
services.litellm = {
  enable = true;
  package = pkgs.litellm;
  stateDir = "/var/lib/litellm";
  host = "127.0.0.1";
  port = 8080;
  settings = {
    model_list = [ … ];
    router_settings = { … };
    litellm_settings = { … };
    general_settings = { … };
    environment_variables = { … };
  };
  environment = { SCARF_NO_ANALYTICS = "True"; DO_NOT_TRACK = "True"; … };
};
```

So the whole litellm config language is reachable from Nix, with no packaging
work. That is the main argument in its favour: the cheap part is genuinely cheap.

## 2. What it cannot do

It does not own a process lifecycle. No load, no evict, no RAM awareness, no
admission gate. Verbatim from
[../../brys-grunt-colocation/llama-router-scheduler.research.md](../../brys-grunt-colocation/llama-router-scheduler.research.md):

> LiteLLM proxy — Pin/prio ✓, active-request ✓, resource aware ✗ ("no
> process/mem lifecycle"), GGUF ✗ (proxies, does not spawn) → **No fit — routing
  only**.

That conclusion stands and is the reason this task is scoped to *around* the
request, never to concurrency.

## 3. What we already run, which overlaps

`modules/den/aspects/llm-proxy.nix` runs `opencode-compat-proxy`:

- a thin FastAPI layer between opencode and one backend;
- it translates a DeepSeek DSML or Qwen XML raw tool call into OpenAI
  `tool_calls` JSON on the stream;
- it passes every other path through;
- one instance per upstream, one `systemd` unit each;
- a fork adds `forwardClientAuth` on the streaming path.

So the repo already owns a proxy process, in Python, with tests. That changes the
cost calculus: retries and request logging inside **our** proxy is a small patch,
while litellm is a new service, a new config language, a new auth tier and a
possible extra dependency tree.

The one thing the current proxy does **not** do is retry or log.

## 3b. Layer order matters, and it is not free

The DSML rewrite exists because a local model emits a tool call as raw text and
OpenCode needs `tool_calls` JSON. Whichever proxy sits closest to the model sees
the raw text. So:

- **litellm closest to the model** would see DSML and would have to pass it
  through untouched; it would also see the rewritten `tool_calls` on the way back
  only if the compat proxy sits outside it. Both orders are workable, but only
  one preserves the current translation point: keep `opencode-compat-proxy`
  **nearest the model**.
- Retries must live **outside** the rewriting layer, so a retry re-sends the
  client's original request rather than a half-translated one.

## 4. Retry semantics that are actually safe

llama-swap's own behaviour matters here: it **queues** a request for a model that
is loading (measured: an unload *does* cut an in-flight stream, but a request for
a loading model waits), and a swap is 90–120 s on this box, longer under CPU pressure
(`docs/local-llms.md`, and the frontier comment in `hosts/brys/default.nix`). So:

| Situation | Retry safe? | Why |
|---|---|---|
| Connection refused (model failed to start) | yes, after backoff | no output was produced |
| HTTP 5xx before any stream byte | yes | nothing was sent to the user |
| Timeout with zero tokens received | yes | the client saw nothing |
| Stream ended after N tokens | **no** transparent retry | the client already rendered them; a retry duplicates or contradicts |
| Swap in progress (long TTFT, stream alive) | **no** | the request is healthy, just slow; a second one queues behind the same load |

So a naive `num_retries` is dangerous twice over: it can duplicate a partial
answer, and it can add queue depth to a box whose bottleneck is the queue.

## 5. What would be logged — and why this is now the weakest argument

**Update 2026-10-27:** llama-swap already records exactly this. Verified by
sending three requests and reading them back:

```
GET /api/metrics/activity → per request: model, tokens.{input,output},
                            tokens.prompt_per_second, tokens.tokens_per_second,
                            duration_ms, resp_status_code, has_capture
GET /api/captures/<id>    → the request and response bodies, Authorization: [REDACTED]
GET /api/metrics/stats    → totals plus p50/p95/p99 histograms of both rates
```

So a proxy is **not** needed to obtain the data; a poller is, because the
activity list is a ring buffer sized by `captureBuffer` (10/50). That poller is
one of the concurrency task's deliverables.

What remains genuinely absent is **retry, fallback, cooldown and timeout**, which
is a much narrower reason to add a service.

litellm can emit it through `litellm_settings.callbacks`. Options, cheapest
first:

1. a **custom callback** that appends one JSON line per request to a file;
- `jsonl` logging to a directory;
- a Langfuse/OTEL exporter (a dependency and a service we would then have to run).

The repo's habit is a git-ignored path plus plain text (`.worklog.md`,
`/tmp/opencode/`). A JSONL file fits that habit better than a database.

Privacy: a chat request body can hold a user's text, and a screenshot rule already
exists. Log metadata (ids, sizes, timing, model, outcome) by default; store bodies
only when a debug flag is on, and never commit them.

## 6. Cost check, to be measured

A pass-through proxy on the same host adds one local hop. For streaming this is
usually negligible, but the box is CPU-bound and the proxy is Python. The
measurement is TTFT and tok/s at the client, with and without the hop. If a
regression appears, that decides the task against litellm.

## 7. The smallest thing that could work instead

In the existing `opencode-compat-proxy`:

- wrap the upstream call in a try/except that retries on connection error and
  pre-stream 5xx, with a cap and a backoff;
- write one JSONL line per request;
- keep a per-model cooldown table so a model that failed twice is skipped for N
  seconds.

That is roughly what litellm's router does, in ~100 lines we already own, with no
new process. It is the baseline litellm must beat.

## 8. Not verified

- Whether litellm's `router_settings.retry_policy` distinguishes "no bytes yet" from
  "stream started". Its docs describe retries per exception type, which suggests
  yes for connection errors; must be confirmed before adopting.
- Whether litellm 1.102.1 can be pointed at llama-swap's model ids without a
  `model_list` entry per alias (the proxy would otherwise duplicate the whole
  alias map that `hosts/brys/llm-routers.nix` already owns).
- The TTFT cost of the extra hop on this CPU.
