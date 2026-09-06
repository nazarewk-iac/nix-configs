---
type: Design
description: Split the brys LLM slot into two llama-server routers (DS4 frontier + freely-swapping small set) behind one front-facing endpoint, routed on the JSON model field in the compat-proxy.
authored_by: agent
timestamp: 2026-09-06T00:00:00+02:00
---

# Design — two-router LLM split (DS4 frontier + small-set)

Operator goal (locked): **one frontier model (DeepSeek V4 Flash "DS4") stays hot as the sole
frontier; all smaller models live in a separate set that swaps freely among itself.** Real
benches prove a single router with `models-max 1` thrashes DS4 (~77 G mmap weight cache
evicted by the kernel) whenever any non-trivial second model loads. So we need TWO
llama-server routers: one that never evicts DS4, one whose job is only to swap among the
small set.

This is design/research only. No files modified except this doc. Everything below is the
minimum viable design that works and stays nix-idiomatic.

## Current wiring (facts, verified)

- `modules/slots/llm/default.nix` — `services.llama-cpp` (singleton, `:39703`, `--models-preset
  <global INI>`, `--models-max 1`, `--sleep-idle-seconds -1`, `--api-key-file`); one
  `kdn-llm-proxy-lan` compat-proxy (`127.0.0.1:9530`, `UPSTREAM_URL=http://127.0.0.1:39703`,
  `PROXY_HOST/PROXY_PORT`); one Caddy vhost keyed on `cfg.domain` with `extraConfig
  "reverse_proxy 127.0.0.1:9530"`, no matcher.
- The model preset INI is generated **once from ALL enabled models** (`modelPresetIni`,
  `presetSection`, lines 102-104). Router/INI/proxy are singletons.
- A separate, proven parametrized proxy slot exists: `modules/slots/llm/proxy/default.nix`
  (`kdn.llm.proxy.instances` = `attrsOf submodule` → one `kdn-llm-proxy-<name>` unit each with
  `upstreamUrl/host/port/forwardClientAuth`). Used for requesty/local.
- The compat-proxy (`packages/opencode-compat-proxy`, FastAPI `proxy.py`) **already reads the
  JSON body** in `proxy()` (it logs `model=`, does DSML/XML translation) and it **already holds
  `model` in hand** via `j.get("model")`. This is the natural routing point.
- Model list already lives entirely under `kdn.llm.local.models` on the host
  (`hosts/brys/default.nix:45-116`), each with `perf.*` (threads, cpuRange, contextSize…).

## 1. Option structure — `kdn.llm.local.routers.<name>`

Pick: **`routers` as an `attrsOf submodule`, each naming its model set by reference; plus a
flat `router` = "which router owns this model (default "main")" on each model.** Rationale:
it reuses the existing per-model `perf.*`/`aliases`/contextSize options unchanged (no new
per-router model duplication), and keeps the primary router (services.llama-cpp) exactly as-is
so the frontier path is untouched. The existing `models.*` option stays the single source of
truth; a router just selects a subset.

```nix
# modules/slots/llm/default.nix — options to add
options.kdn.llm.local.routers = lib.mkOption {
  type = lib.types.attrsOf (lib.types.submodule ({lib, ...}: {
    options.enable = lib.mkEnableOption "this llama-server router";
    options.port = lib.mkOption { type = lib.types.port; default = 39704; };   # auto-increment below
    options.threads = lib.mkOption { type = lib.types.int;  default = 8; };    # fewer threads: see §4
    options.apiKeyDir = lib.mkOption { type = lib.types.nullOr lib.types.path; default = null; };
  }));
  default = {};
};
# + one per-model selector (defaults to the singleton "main" router):
#   models.<name>.mainRouter = mkOption { type = str; default = "main"; };
```

The second router-B unit is a raw `systemd.services."llama-cpp-router-<name>"` (we keep
`services.llama-cpp` for the frontier — it is a mismatch to fight the singleton). Its INI is
the per-router **filtered view** of the same `modelPresetIni` generator — factor `presetSection`
already takes `name`; change `modelPresetIni` to be a function of a filter:

```nix
# modules/slots/llm/default.nix — factored INI
presetIni = routerName: lib.concatStringsSep "\n" (
  lib.mapAttrsToList (name: _: presetSection name) (
    lib.filterAttrs (name: m: m.enable && m.mainRouter == routerName) cfg.models
  ));
mainIni  = presetIni "main";
# router-B INIs from cfg.routers.*, keyed by router name, written per-unit:
#   ${pkgs.writeText "models-${name}.ini" (presetIni name)}

# second unit (router B), near the services.llama-cpp block:
systemd.services = lib.mapAttrs' (name: r: lib.nameValuePair "llama-cpp-router-${name}" {
  wantedBy = ["multi-user.target"];
  environment.PATH = [ "${cfg.package}/bin" ];          # llama-server
  serviceConfig = {
    ExecStart = lib.concatStringsSep " " [
      "${cfg.package}/bin/llama-server"
      "--host 127.0.0.1" "--port ${toString r.port}"
      "--models-preset ${presetIni name}" "--models-max 1"
      "--sleep-idle-seconds -1"
      "--threads ${toString r.threads}"
      # + --cpu-range/--cpu-strict from a router-level cpuRange option
    ] + lib.optionalString (r.apiKeyDir != null) " --api-key-file /var/lib/llama-cpp-${name}/api-keys";
    LimitMEMLOCK = "infinity";
  };
}) (lib.filterAttrs (_: r: r.enable) cfg.routers);
```

`mainRouter = "main"` on every model means the existing host file needs a one-line addition per
small model (or a default of `"main"` means only router-B members get touched). **All seven
models keep their existing `perf.*`/ctx definitions** — router B's INI for a member reuses its
`contextSize`/`threads` from `models.*`, so no per-router perf duplication.

## 2. Small-set membership + ctx defaults

Recommend the **full swap-set** as default: `phi-4`, `qwen3-30b-a3b`, `qwen3-coder-next`,
`qwen3-next-80b`, `gpt-oss-120b-Q4_K_M`, and **`qwen3-235b` boxed alone**. Rationale: router
B's job is free swapping among itself (it never needs DS4 resident too), so it can hold ANY
non-frontier model — its only constraint is RAM for exactly one at a time, same as the current
single router. Frontier `deepseek-v4-flash` stays `mainRouter = "main"` and never enters B.

| Router B member | ctx | t/s | peak resident | note |
|---|---|---|---|---|
| phi-4 | 16384 (arch ceiling) | 2.86 | 17.7 G | lightweight, coexists anyway |
| qwen3-30b-a3b | 131072 | 11.4 | 44.4 G | coexists w/ DS4 already |
| qwen3-coder-next | 131072 | 5.34 | 65.6 G | — |
| qwen3-next-80b | 131072 | 3.29 | 80 G | — |
| gpt-oss-120b Q4_K_M | 131072 | 12.7 | 72 G | fast, worth having |
| qwen3-235b (IQ2_M) | 65536 | ~slow | ~100 G | box-alone; near RAM ceiling |

These are already the exact `perf.contextSize` values on `hosts/brys/default.nix`; the design
simply keeps them. Load-time cost per switch on `:39704` is the real UX tax — this is why the
frontier stays on its own never-evicted router. Accept the switch cost inside router B; it is
contained and does not touch DS4.

## 3. Routing — compat-proxy body routing (option c)

Pick: **(c) route on the JSON `model` field in the (already body-reading) compat-proxy.** Not
(a) path-prefix or (b) two vhosts — those shatter the "one front-facing endpoint + transparent
`model=` field" ergonomics a client already enjoys, forcing a different base URL or path per
set. Caddy cannot read the body, so this is a tiny, well-scoped change to the one layer that
already parses JSON.

Change location: in `proxy()` in `packages/opencode-compat-proxy/proxy.py`, right after the
body is parsed and `j` is available (`model = j.get("model")`), and the request/response block
that currently targets a single `UPSTREAM`. **Small change**: split `UPSTREAM` into a dict by
model, e.g.

```python
UPSTREAMS = {  # overridable via env, keyed by upstream name
    "frontier": os.environ.get("UPSTREAM_URL", "http://127.0.0.1:39703"),
    "small":    os.environ.get("SMALL_UPSTREAM_URL", "http://127.0.0.1:39704"),
}
# {model: router} table, derived from the model lists:
ROUTE = {
    "deepseek-v4-flash": "frontier", "frontier": "frontier",       # + draft alias
    "phi-4": "small", "qwen3-30b-a3b": "small", "fast": "small",
    "qwen3-coder-next": "small", "qwen3-next-80b": "small",
    "gpt-oss-120b": "small", "qwen3-235b": "small", ...,
}
UPSTREAM = lambda m: UPSTREAMS[ROUTE.get(m, "frontier")]  # unknown → frontier? or small
```

Replace the handful of `UPSTREAM + ...` call sites in `proxy()` / `stream_with_sections` /
`models_list` / `catch_all` with `UPSTREAM(model_from_request)`. The catch-all `/v1/models`
route must **merge** the two routers' listings rather than pick one. This is a moderate edit to
one file plus the existing `forward-auth.patch` style — recompute the package hash, add
roughly 20 lines, ship as a new patch. Client impact: **none** — same endpoint, same `model=`
field, proxy re-writes nothing; it only picks the upstream.

If the proxy change is later deemed too invasive, fallback is (a): separate the small-set behind
a second compat-proxy on its own port and Caddy route on a `/small` path prefix — but this
FAILS the "one endpoint + transparent model" goal and is rejected as the primary.

## 4. Concurrency / scheduling verdict

**Accept a hot DS4 + an active small model running simultaneously, but pin router B to fewer
threads.** On a 16-core/128 G box, the real shared ceiling is **memory bandwidth (~40 GB/s)**,
not CPU cores — two simultaneous decodes simply split it, so aggregate t/s drops but neither
stalls trivially. Give router B `threads = 8` (and an optional `cpuRange` of the upper/odd
cores, `--cpu-strict 1`) so DS4 keeps its 16 physical threads; a 30B-A3B at 8 threads is still
bandwidth-happy and leaves headroom. Total resident for "DS4 + gpt-oss-120b" ≈ 77 + 14 KV + 72
≈ within 128 G; DS4's mmap stays hot because A never both loads on the same router and B never
evicts it. Do NOT mlock the small set; leave them evictable by design.

## 5. Implementation plan (Phase 2a/b/c)

Smallest first step that PROVES the two-router + split works before committing the full proxy:

- **Phase 2a — raw second router only.** Add `kdn.llm.local.routers` + the `llama-cpp-router-small`
  unit + the filtered INI, pointing at `:39704` with `phi-4` + `qwen3-30b` only. No proxy, no
  Caddy. Verify via curl to `:39704` directly: switch among the two small models, confirm DS4
  stays hot on `:39703` (no re-read from disk) and that both coexist in RSS. **This proves the
  core premise.**
- **Phase 2b — compat-proxy body routing.** Add the `ROUTE`/`UPSTREAMS` split + merged
  `/v1/models` in a new patch. Point the existing `kdn-llm-proxy-lan` at its upstreams via env
  (`UPSTREAM_URL`, `SMALL_UPSTREAM_URL`). Test from OpenCode: pick DS4 and a small model via
  `model=`, confirm transparent routing and that DSML/XML translation still works through both.
  Use the existing parametrized `kdn.llm.proxy.instances` if a second NAT port is wanted during
  bring-up.
- **Phase 2c — full small-set + ergonomics.** Add coder-next/next-80b/gpt-oss-120b/qwen3-235b
  to router B by flipping `mainRouter`, tune `threads`/`cpuRange`, and finalize `/v1/models`
  merge. Then run the **Phase 3 co-residency tests**: concurrent DS4 + each small model,
  measure t/s and DS4 re-read-vs-hot, iterate `threads`.
