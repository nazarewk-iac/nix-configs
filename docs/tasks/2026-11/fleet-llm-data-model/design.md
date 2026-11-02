---
type: Design
description: The central fleet LLM data model (v4) — one data/llm.nix with a servers root key, per-model host/set data, and three projections (server, client, member). Revised after three review rounds.
task: definition.md
authored_by: agent
timestamp: 2026-11-02T15:00:00+01:00
---

# Central fleet LLM data model — design v4

> Status: **ready to implement.** Round-1, round-2 and round-3 findings are in
> [review.md](review.md); v4 resolves them all. v4 is v3 with the round-3
> router-vocabulary correction (R13) applied.

## Change log

- v1 → v2: renamed cross-model host key to `servers.<host>`; split `contextSize`
  into three named values; moved the full perf literals; resolved the `frontier`
  alias; added the five router-only models and host-wide slot fields; deep-merge
  `perf`/`download`/`mmproj`/`draft`; `set`/`extraSets`; `mkMemberView`;
  unified `profiles`. (M1–M7, B1–B7.)
- v2 → v3: fix `mkMemberView` alias binding (R2); define `modelsOnHost` (R3);
  drop `extraSets`, one `set` per model (R4); `package` as a named-key string
  (R5); carry `download.minBytes` (R6); keep `qwen3.5-9b enable=false` (R7);
  migrate the surveyed file path for `qwen3-30b-a3b`/`qwen3-next-80b` (R8);
  **delete** `gpt-oss-120b`, do not migrate (R9); `endpoints.<host>.apiKeyFile`
  (R10); naming invariants (R11); STE fixes (R12).
- v3 → v4: correct the router vocabulary to `main | small | grunt | surveyed`
  (R13). `frontier` and `qwen` are model _groups on `main`_, not routers; both
  frontier models use `set = "main"`, and every profile's `sets` is
  `[ "main" "grunt" "surveyed" ]`.

## Principles

1. **One file, one truth.** `data/llm.nix` holds every fact about every model
   and every serving host. No consumer derives a model fact from a second file.
2. **Identity is host-agnostic; serving is per-host.** What a model _is_ is the
   same on every host. How it is _loaded_ is a host fact.
3. **Config is central, consumption is selective.** Each consumer projects one
   view. A projection removes what the consumer must not see, so host plumbing
   cannot leak into a member.
4. **Profiles are per-host deltas.** A boot profile overrides only what differs.
   On brys, exactly one value differs: DeepSeek's served context.

## Vocabulary

- **model** — one GGUF the fleet can serve, by base id.
- **host** — a machine that serves models (`brys`; later `enji`).
- **server** — the cross-model config for a host: routers, swap policy, session
  store, boot profiles, generated files.
- **profile** — a boot choice on a host that changes _what is served_
  (`desktop`, `appliance`). Profiles are per host; brys has two.
- **set** — the router a model lands on. **A host declares its own router
  names.** On brys they are `main`, `grunt`, `surveyed`, `small`. **Invariant:**
  a model's `set` must be a key of `servers.<host>.routers`. Both frontier models
  are on `main`; `frontier` and `qwen` are model groups, not routers.
- **serving data** — what llama-server needs to load a model: file, download,
  mmproj, draft, perf.
- **native context** — the model's trained window. **served context** — the
  window a host actually serves (smaller, or larger via rope).
- **swap policy** — the rule that states which models may be resident together.
  `coResidentTiers` is the resolved list of co-residence groups; the host
  computes it from each model's `perf.device`.

## The shape

`data/llm.nix` returns:

```nix
{
  # ---- fleet-wide, host-agnostic ----------------------------------------
  endpoints = {
    <host> = { baseUrl; api; apiKey; apiKeyFile; };
  };
  pi = { defaults = { contextWindow; maxTokens; }; aliases = { ... }; };

  # ---- cross-model per-host config --------------------------------------
  servers = {
    brys = {
      # host-wide slot facts (moved from hosts/brys/llm.nix:428-458)
      package = "llama-cpp-sessions";    # a named key; the host maps it to a pkg
      defaultThreads = 16;
      modelsDir = "/var/lib/kdn/llms/models";
      download = { tokenFile; mode; xetConcurrency; };
      domain; certs; apiKeyDir;
      sessionStore = { path; group; maxBytes; };

      # routers on this host; a model's `set` names one of these keys.
      # `main` is llama-swap's primary router; it holds the frontier models.
      routers = {
        main     = { enable; port; threads; modelsMax; apiKeyDir; };
        grunt    = { enable; port; threads; modelsMax; apiKeyDir; };
        surveyed = { enable; port; threads; modelsMax; apiKeyDir; };
        small    = { enable; port; threads; modelsMax; apiKeyDir; };
      };

      # cross-model serving policy (the resolved value, computed by the host)
      swap = { enable; coResidentTiers; persistentModels; vulkanDeviceSelect; };

      # boot profiles: WHICH ROUTERS ARE SERVED
      profiles = {
        desktop   = { sets = [ "main" "grunt" "surveyed" ]; };
        appliance = { sets = [ "main" "grunt" "surveyed" ]; };
      };
    };
  };

  # ---- the models -------------------------------------------------------
  models = {
    "<model-id>" = {
      # identity: same on every host
      aliases = [ "<purpose-id>" ... ];      # may be absent
      capabilities = { operation; loadSeconds; };
      pi = { contextWindow; maxTokens; };
      vision = true;
      contextSize = <int>;                   # NATIVE window

      hosts = {
        brys = {
          set = "surveyed";                  # one set; must be a routers key
          servedContext = <int>;             # served window on this host

          common = {
            enable = true;
            hfRepo; hfFile;
            download = { enable; minBytes; glob; };  # deep-merged
            mmproj = { enable; hfRepo; hfFile; };    # absent => none
            draft  = { enable; hfRepo; hfFile; };    # absent => none
            perf = { device; nGpuLayers; threads; parallel; kvUnified;
                     cacheTypeK; cacheTypeV; cacheRam; ropeScaling; ropeScale;
                     ropeFreqBase; yarnOrigCtx; batchSize; ubatchSize; mmap;
                     reasoning; reasoningEffort; extraFlags; sessionHeaders;
                     sessionMaxSessions; ctxCheckpoints; checkpointMinStep;
                     specType; specDraftNMax; specDraftPMin; specDraftPrio;
                     cpuMoe; noKvOffload; draftNGpuLayers; }; };
          };

          # profile override: only a model that truly differs by profile.
          # On brys today this is only DS4's served context.
          profiles = {
            desktop   = { servedContext = 131072; };
            appliance = { servedContext = 327680; };
          };
        };
        # enji = { ... };
      };
    };
  };
}
```

### The three contexts

| Name                                      | Where                  | Means                                 |
| ----------------------------------------- | ---------------------- | ------------------------------------- |
| `contextSize`                             | `models.<id>`          | native trained window (host-agnostic) |
| `hosts.<host>.servedContext`              | model × host           | the window this host serves           |
| `hosts.<host>.profiles.<p>.servedContext` | model × host × profile | profile-specific served window        |

**Precedence:** `profiles.<p>.servedContext ?? hosts.<host>.servedContext ??
contextSize`. One chain, three names. `qwen3.8-27b` writes `servedContext =
131072`; the old router `ctx = 32768` is discarded.

### One set per model

A model belongs to one router: `set = "surveyed"`. There is **no** `extraSets`.
No model needs a second router today. If one ever does, add a second model id
(e.g. `x-cpu`) rather than a list — this keeps the projection one-entry-per-id.
(R4.)

## Resolution — the projections

All three live in `lib/llm.nix`. Each takes the data and a host; none imports a
host file.

### Server projection

```nix
mkServerModels = data: host: profile:
  let
    srv = data.servers.${host};
    enabled = srv.profiles.${profile}.sets;
  in
  lib.mapAttrs (id: m: serverEntry data host profile id)
    (lib.filterAttrs
      (id: m: let h = m.hosts.${host} or null; in
               h != null && builtins.elem h.set enabled)
      data.models);

serverEntry = data: host: profile: id:
  let
    m = data.models.${id};
    h = m.hosts.${host};
    p = h.profiles.${profile} or { };
    perf = lib.foldl' lib.recursiveUpdate { } [
      (h.common.perf or { })
      (p.perf or { })
      { contextSize = p.servedContext or h.servedContext or m.contextSize; }
    ];
  in
  {
    aliases = m.aliases or [ ];
    enable = h.common.enable or true;         # qwen3.5-9b keeps false (R7)
    mainRouter = h.set;                       # one set per model (R4)
    inherit (h.common) hfRepo hfFile;
    download = lib.recursiveUpdate (h.common.download or { }) (p.download or { });  # R6 keeps minBytes
    mmproj   = lib.recursiveUpdate (h.common.mmproj   or { }) (p.mmproj   or { });
    draft    = lib.recursiveUpdate (h.common.draft    or { }) (p.draft    or { });
    perf = perf;
  };
```

Client-only identity (`capabilities`, `pi`, `vision`, `gpu`, `source`, `stats`)
is not copied into a server entry; the server submodule has no such options.
`download`, `mmproj`, `draft` deep-merge so `download.enable = false` in `common`
and a `download.minBytes`/`glob` combine correctly (B7, R6).

### Client projection (unchanged in behavior)

`mkPiModelsJson` and `mkCatalog` read `data.models`, using **native**
`contextSize` (safe: a client output cap clamped to the native value is at or
below every served window), plus `pi`, `vision`, `aliases`, `capabilities`. No
host serving data is touched. Q2 decision.

### Member projection — `mkMemberView`

```nix
# Host-presence only: every model this host has a serving block for,
# regardless of which profile is booted (R3). Not filtered by enabled sets.
modelsOnHost = data: host:
  lib.filterAttrs (_id: m: m.hosts ? ${host}) data.models;

mkMemberView = data: host:
  let
    onHost = modelsOnHost data host;
  in
  {
    endpoint = data.endpoints.${host};        # baseUrl, api, apiKey, apiKeyFile (R10)
    # alias -> base id, over every model this host serves
    aliasToModel =
      lib.foldl' (acc: id:
        lib.foldl' (a: alias: a // { ${alias} = id; })
          acc (data.models.${id}.aliases or [ ]))
        { } (builtins.attrNames onHost);
    # identity only; serving keys physically absent
    models = lib.mapAttrs (_id: m: {
      aliases = m.aliases or [ ];             # R2: no `inherit`, guards absent
      inherit (m) contextSize vision capabilities;
    }) onHost;
  };
```

A member (oams, future) calls `mkMemberView data "brys"`. It cannot see
`hfRepo`, `perf`, ports, or device pins — those keys do not exist in its view.
`hosts/oams/devenv.nix` reads `view.endpoint.baseUrl` and `view.endpoint.apiKeyFile`
instead of its hardcoded literals. `llm-agents.nix` becomes a pure function of
`view.aliasToModel`.

## Migration

1. Add `servers.brys` with all four routers (`main`, `grunt`, `surveyed`,
   `small`), swap (store the resolved `coResidentTiers`), sessionStore,
   host-wide slot fields, `package = "llama-cpp-sessions"` (a key), and the two
   profiles (`sets = [ "main" "grunt" "surveyed" ]`) (R13, R5, B6).
2. Populate `models` with every served model. From the router file: all
   `surveyed` models, `qwen3.5-4b` and `qwen3.5-9b` (`enable = false`) from
   `grunt`, and `phi-4`, `qwen3-coder-next`, `qwen3-235b`, `small`-only models.
   The two frontier models (`deepseek-v4-flash`, `qwen3.8-flash-next`) take
   `set = "main"` (R13). **Do NOT migrate `gpt-oss-120b`; delete it** (R9). Take
   the **served** context (the old override value) as `servedContext`; discard
   the dead router `ctx` (B1, R8). Use the **surveyed nested** `hfRepo`/`hfFile`
   for `qwen3-30b-a3b` and `qwen3-next-80b`, not the small-set flat path (R8).
3. Move the full `deepseekPerf`/`qwenPerf` literals into the two models'
   `common.perf`, with the resolved values (`mmap = null` for DS4) (B2, B3).
4. Add the per-model `hosts.brys` blocks; `qwen3.5-9b` keeps `common.enable =
false` (R7). Carry `download.minBytes` on Qwen (R6).
5. Add `endpoints.brys.apiKeyFile` (R10).
6. Write the three projections in `lib/llm.nix`; add a `deepMerge` alias to
   `lib.recursiveUpdate`.
7. Rewrite `hosts/brys/llm.nix` to call `mkServerModels`; remove the flag
   plumbing (`withFrontier/withQwen/withSmall/withGrunt/withSurveyed/qwenMtp/
qwenVision/cpuPinned/contextSize`) that becomes data.
8. Point `llm-agents.nix` and `oams` at `mkMemberView data "brys"`.
9. Delete `hosts/brys/llm-routers.nix`.

## Verification (must gate the merge)

- Capture today's `kdn.llm.local.models` for both brys profiles (desktop
  `contextSize=131072`, appliance `contextSize=327680`) as JSON.
- After migration, eval both and diff: **must be byte-identical**.
- Diff `mkPiModelsJson` and `mkCatalog` output: identical.
- Diff `mkMemberView data "brys"` alias→model map against today's
  `llm-agents.nix` derivation for `oams`.

## Risks

- **Flag removal scope.** Removing seven flags is the largest behavior surface.
  Remove them only after the eval-diff is green.
- **`coResidentTiers` is derived, not literal.** Store the resolved value for
  both profiles (identical today) and note it is derived from `perf.device`.
- **A second host.** `servers.enji` and `models.<id>.hosts.enji` are allowed.
  The member view is single-host by construction; a multi-host member needs a
  later host-list or fleet alias index (R11).

## Out of scope

- Serving on a second host. The shape allows it; this task does not build it.
