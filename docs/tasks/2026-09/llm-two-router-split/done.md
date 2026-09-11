---
type: Solution
description: Two llama-server routers behind one proxy endpoint — the frontier model stays resident while the small set swaps, and brys runs the split with a measured co-residency cost.
task: definition.md
authored_by: agent
timestamp: 2026-09-11T12:00:00Z
---

# The two-router LLM split, landed

Parent: [definition.md](definition.md). Design: [design.md](design.md).

## Root cause analysis

One `llama-server` router cannot meet two needs at once. `--models-max 1` keeps exactly one model
resident, so the router evicts the frontier weights whenever a second model loads. The frontier
model is the largest, so a re-read from disk costs the most.

Raising `--models-max` on the single router does not fix it either. The frontier model then shares
its residency slot with a small model, and the eviction order is the router's choice, not the
operator's.

So the fix needs two separate residency policies in one deployment: one router pinned to the
frontier model alone, and a second router that holds a **set** of small models and swaps inside
that set. A client must still see one endpoint, because a caller cannot pick a port per model.

## Solution

Three parts: the slot grows a router set, the proxy routes on the `model` field, and one host
enables it.

### 1. The slot — `modules/slots/llm/default.nix`

| Line | Content |
|---|---|
| `:121-146` | the per-router preset and filter helpers |
| `:171-176` | one systemd unit per router, `lib.nameValuePair "llama-cpp-router-${name}"` |
| `:184` | the `ExecStart` that runs `llama-server` |
| `:385-441` | the `kdn.llm.local.routers` option |
| `:559-569` | `models.<name>.mainRouter` — each model picks its router |
| `:788` | an assertion that a router name is lowercase alphanumeric |
| `:820-823` | the unit merge, so the extra routers join the default one |

A host that names no extra router keeps the old single-router behaviour.

### 2. The proxy — `packages/opencode-compat-proxy/patches/router.patch`

| Line | Content |
|---|---|
| `:20` | `UPSTREAMS = {"frontier": UPSTREAM}` — the upstream table |
| `:23` | `ROUTE` — the model-to-upstream map |
| `:71-72` | `_build_route` builds the map from the environment |
| `:76-78` | the per-model upstream resolution |
| `:125-146` | `GET /v1/models` merges the model list across every entry of `UPSTREAMS` |

A model the map does not name falls back to the frontier upstream, so an unknown model still
answers.

### 3. The host — `hosts/brys/llm-minimal.nix`

`:49-56` enables `kdn.llm.local.routers.small`. Six models set `mainRouter = "small"`, at
`:85,93,100,108,116,124`. `docs/local-llms.md:136-157` documents the result: the `main` router on
its own port with `--models-max 1` for the frontier model, and the `small` router on its own port
with `--models-max 2` for the set.

The main `brys` host enables no extra router, so it gets no `ROUTER_*` environment and keeps the
original single-router behaviour (`docs/local-llms.md:155-157`).

### The exit test, item by item

| Item | State | Evidence |
|---|---|---|
| 1. the host enables a second router, and both answer on their own ports | met | `hosts/brys/llm-minimal.nix:49-56`; the port map at `docs/local-llms.md:136-157` |
| 2. a frontier request and a small request both succeed through one endpoint | met | the proxy resolves per model at `router.patch:76-78`; the measured run at `docs/local-llms.md:159-169` drove both sides |
| 3. the frontier weights stay hot across a small-model swap | met, measured | `docs/local-llms.md:159-169` — the frontier model never cold-reloads across a swap on the small router |
| 4. `/v1/models` lists the models of both routers | met by code and documentation, **not** by a recorded response | `router.patch:125-146` merges the lists; `docs/local-llms.md:27` and `:40` state the contract |

## Verification steps

```bash
# the slot declares the router set and the per-model selector
grep -n "routers" modules/slots/llm/default.nix | sed -n '1,20p'
grep -n "mainRouter" modules/slots/llm/default.nix

# the proxy routes per model and merges the model list
grep -n "UPSTREAMS\|^ROUTE\|_build_route" packages/opencode-compat-proxy/patches/router.patch

# the host enables the second router, and six models pick it
grep -n "routers\|mainRouter" hosts/brys/llm-minimal.nix

# the recorded measurement
sed -n '136,170p' docs/local-llms.md
```

The deployment is a boot specialisation, so a live check needs a boot into `llm-minimal` on
`brys`. Do not activate it in place.

## Follow-up notes

- **Record one `/v1/models` response.** Exit item 4 rests on the patch and on the documented
  contract. One captured response body that lists both sets would close it fully.
- **`definition.md:29` is now stale.** It reads "No host enables an extra router yet, so the
  split is unused in production". `hosts/brys/llm-minimal.nix:49-56` enables one.
- **Co-residency is expensive on this box, and that is a hardware limit, not a defect.** A
  resident small model contends for the same memory bandwidth. `docs/local-llms.md:159-169`
  records the cost per co-tenant and names the cheapest one. Treat the largest models as
  exclusive.
- **`--sleep-idle-seconds -1` pins a router's last resident model.** So the frontier router is
  never truly alone once the small set has been touched (`docs/local-llms.md:167-169`).
- Per-model tuning stays out of scope, by `definition.md:40-43`.
