---
type: Research
description: Two independent reviews of the fleet LLM data-model design, round 1, with the findings that forced a v2 design.
task: definition.md
authored_by: agent
timestamp: 2026-11-02T14:10:00+01:00
---

# Design reviews — round 1

Two independent reviewers examined [design.md](design.md) (v1) and the current
code. Both verdicts: **right general shape, not implementable as written.** The
findings below merge their reports. Line references are to the files at
2026-11-02.

## Consensus blockers

### B1 — `contextSize` means two different things

`data/llm.nix` holds the **native** context (DS4 128K, qwen3-30b-a3b 40K,
qwen3.8-27b 128K). The **served** context is forced by the `lib.mapAttrs`
override in `hosts/brys/llm.nix:478-482`, which is why the router file's own
`ctx` values are dead: `qwen3.8-27b` has `ctx = 32768` in
`llm-routers.nix:375-377` but serves 131072; `qwen3.5-35b-a3b` has `ctx =
8192` but serves 262144. v1's `resolve` fallback to `m.contextSize` diverges
from this. **Fix:** three named values — `contextSize` (native, on the model),
`servedContext` (per host), and a per-profile override — with one documented
precedence chain. The served value, not the router `ctx`, is authoritative.

### B2 — the entire perf literals must move, not "two values"

`deepseekPerf` (`llm.nix:238-284`) and `qwenPerf` (`llm.nix:297-363`) are large
literal blocks moved today by function arguments. v1 called them "profile
deltas". They are mostly **static per-model serving data**. Every key must move:
`reasoning, reasoningEffort, batchSize, ubatchSize, parallel, kvUnified, mmap,
ropeScaling, ropeScale, ropeFreqBase, yarnOrigCtx, cacheTypeK, cacheTypeV,
cacheRam, sessionHeaders, sessionMaxSessions, ctxCheckpoints, checkpointMinStep,
specType, specDraftNMax, specDraftPMin, specDraftPrio, nGpuLayers, cpuMoe,
noKvOffload, draftNGpuLayers, device`.

### B3 — cross-model conditionals baked into perf

`deepseekPerf.mmap = if qwenGpu then null else true` (`llm.nix:260`): DS4's
`mmap` depends on the **Qwen** flag. Both profiles have `qwenGpu = true`, so the
value is `null` today. A static rewrite that emits `mmap = on` changes the served
preset. The data must hold the resolved `mmap = null`. Same class: `cpuRange` /
`cpuStrict` are absent because `cpuPinned = false`; the data leaves them unset.

### B4 — the `frontier` alias is `withFrontier`-parameterized

`qwenAliases = [ "qwen" "orchestrate-deep-slow" ] ++ lib.optional (!withFrontier)
"frontier"` (`llm.nix:171-175`). With `withFrontier = true`, Qwen does not own
`frontier`; DS4 does. v1 hardcodes the current resolved aliases, which is
correct only while `withFrontier = true`. **Fix:** either model the alias as a
profile/flag delta, or delete the `!withFrontier` branch as dead for the shipping
hosts and say so.

### B5 — five models live only in the router file

`phi-4`, `qwen3-coder-next`, `qwen3-235b` (small set), `gpt-oss-120b` (small),
`qwen3.5-9b` (grunt) have **no** `data/llm.nix` entry. v1's migration would drop
them. They must move into `data/llm.nix` even though `withSmall = false` serves
none today, so a future `withSmall = true` still works.

### B6 — host-wide (non-model) config must move too

`hosts/brys/llm.nix:428-458`: `package`, `defaultThreads`, `modelsDir`,
`download.tokenFile/mode/xetConcurrency`, `domain`, `certs.*`, `apiKeyDir`. v1
omitted these. They belong in the cross-model host block.

### B7 — shallow `//` corrupts `download`, `mmproj`, `draft`

The resolver used `//` for the whole model. `download.enable = false` in a
`common` layer plus a profile `download.glob` yields a contradictory pair the
aspect treats as "no download" (the glob is ignored). `perf`, `download`,
`mmproj`, `draft` all need **deep** merge.

## Consensus major/minor

### M1 — double `hosts` key is confusing

`data.hosts.<host>` (cross-model) and `models.<id>.hosts.<host>` (per model) are
both `hosts`. **Fix:** rename the cross-model one `servers.<host>`.

### M2 — `sets` and `mainRouter` duplicate one fact

A single-set model writes both `sets = ["surveyed"]` and `common.mainRouter =
"surveyed"`. **Fix:** one `set` scalar plus an optional `extraSets` list; derive
`mainRouter` from `set`.

### M3 — member view is under-specified and broken today

Members (`oams`) import `brys/llm-agents.nix`, and `oams` hardcodes the base URL
literal (`hosts/oams/devenv.nix:163`). v1 says "read data/llm.nix" but gives no
function and would leak host plumbing. **Fix:** `mkMemberView data <host>`
returns `{ endpoint; aliasToModel; modelIdentity; }` with serving keys
physically removed. `endpoints.<host>` is the one URL source; oams reads it.

### M4 — profiles split across two keys; Qwen perf is not a profile delta

v1 put profile set-enablement under `data.hosts.<host>.profiles` and
per-model deltas under `models.<id>.hosts.<host>.profiles`. Both brys profiles
are byte-identical for Qwen; the **only** true profile delta is DS4
`contextSize` (128K vs 320K). **Fix:** `servers.<host>.profiles.<profile>` holds
"what is served" (enabled sets/models). A per-model profile override exists only
for DS4's context.

### M5 — member/client context with two hosts

Q2 (which context a client sees when profiles differ) becomes fatal once
`enji` exists. The member and client must read **per-host** served context, not
one top-level value.

### M6 — brys-specific set vocabulary

`small|grunt|surveyed|main` is brys's. A second host declares its own router
names under `servers.<host>.routers`; `set` values are free-form per host.

### M7 — missing review.md and dead links

v1 referenced `review.md` (this file) three times before it existed. Fixed here.

## Decisions taken for v2

| #   | Question              | Decision                                                                                                                                  |
| --- | --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Q1  | single vs multi set   | one `set` scalar; `extraSets` optional list for the rare multi-role case                                                                  |
| Q2  | client/member context | client reads native `contextSize` (safe: clamps output below all served); member reads per-host `servedContext`                           |
| Q3  | identity per host?    | identity (`aliases`, `capabilities`, `vision`, native `contextSize`) is host-agnostic; `vision`'s projector is per-host (`common.mmproj`) |
| Q4  | member abstraction    | `mkMemberView` in `lib/llm.nix`; drop the host-file import from members                                                                   |

v2 must be re-reviewed before implementation.

---

# Design reviews — round 2

Two independent reviewers checked design v2 against the round-1 findings and for
new defects. **Verdict both: shape sound, projection pseudocode and a few data
details still wrong.** All round-1 blockers are correctly placed; round 2 found
concrete defects to fix before implementation.

## Round-1 status

| Finding                             | Status                                                     |
| ----------------------------------- | ---------------------------------------------------------- |
| B1 three contexts                   | resolved                                                   |
| B2 perf literals move               | resolved                                                   |
| B3 mmap=`null` baked                | resolved                                                   |
| B4 frontier alias dead branch       | resolved (both hosts `withFrontier=true`)                  |
| B5 five router-only models          | **partial** — `gpt-oss-120b` must be deleted, not migrated |
| B6 host-wide slot fields move       | resolved                                                   |
| B7 deep-merge download/mmproj/draft | resolved                                                   |
| M1 double hosts key                 | resolved (`servers.<host>`)                                |
| M2 set/mainRouter dup               | resolved structurally, derivation buggy (R5)               |
| M3 member view                      | **partial** — new bugs R2, R3                              |
| M4 profiles unified                 | resolved                                                   |
| M5 client/member context            | resolved                                                   |
| M6 set vocabulary free-form         | resolved                                                   |
| M7 review.md                        | resolved                                                   |

## New findings (round 2)

- **R1 [BLOCKER] `profiles.sets` names routers that do not exist.** The profiles
  enable `[ "frontier" "qwen" "grunt" "surveyed" ]`, but `servers.brys.routers`
  declares only `small|grunt|surveyed`. Resolve by declaring `frontier` and
  `qwen` routers in `servers.brys.routers` (they are real routers on brys's
  llama-swap today — DS4 on the primary `main` router, Qwen likewise). Alternatively
  rename the tokens so `sets` matches router keys. `frontier`/`qwen` are the two
  aliases `oams` depends on, so this cannot be left dangling.
- **R2 [BLOCKER] `mkMemberView` `inherit (m) aliases` throws on alias-less models.**
  Many models have no `aliases` (e.g. `tmax-2b`, `ministral-3-3b-instruct`,
  `gemma-4-e2b`). Use one binding `aliases = m.aliases or [];`, not `inherit`.
- **R3 [BLOCKER] `modelsOnHost` is undefined.** Define it explicitly as
  **host-presence**, not profile/set filtering:
  `filterAttrs (id: m: m.hosts ? ${host}) data.models`. Filtering by enabled
  sets would drop aliases when a profile disables a set — a regression against
  today, where members see the flag-selected set regardless of profile.
- **R4 [MAJOR] `serverEntry` hardcodes `mainRouter = h.set` and cannot serve
  `extraSets`.** Pass the set name into `serverEntry`; set `mainRouter = <that
set>`. `genAttrs` + `head (attrValues …)` also silently keeps one entry when a
  model is in two enabled sets. Either implement `extraSets` correctly (entries
  keyed per set) or drop `extraSets` entirely (no model needs it today) and keep
  a single `set`.
- **R5 [MAJOR] `package = <build ref>` cannot live in `data/llm.nix`.** The file
  is imported by the client (`lib/llm.nix`, `devenv.nix`) with no `pkgs`. Use a
  **named-key string** (`package = "llama-cpp-sessions"`) that the server
  (`hosts/brys/llm.nix`) maps to `pkgs.kdn.…`. `data/llm.nix` stays pure data.
- **R6 [MAJOR] `download.minBytes` dropped.** Qwen sets `download.minBytes =
10000000` (`llm.nix:401`). Carry it in `common.download`.
- **R7 [MAJOR] `qwen3.5-9b enable=false` dropped.** Migrate it as
  `common.enable = false`; the default `enable = true` would flip it on.
- **R8 [MAJOR] `qwen3-30b-a3b` file path.** The `small` set uses flat
  `hfFile = "Qwen3-30B-A3B-Q4_K_M.gguf"` + `hfRepo = "Qwen/Qwen3-30B-A3B-GGUF"`;
  the **served** (`surveyed`) copy uses nested
  `hfFile = "Qwen/Qwen3-30B-A3B-GGUF/Qwen3-30B-A3B-Q4_K_M.gguf"` + `hfRepo =
"surveyed"`. Migrate the surveyed nested form. Same care for `qwen3-next-80b`.
- **R9 [SCOPE] `gpt-oss-120b` is deleted, not migrated.** Remove it from the
  migrate list; delete `llm-routers.nix:76-82` and its files.
- **R10 [MAJOR] `oams` `apiKeyFile` literal.** oams hardcodes
  `apiKeyFile = "/run/configs/llms/llama-server/api-keys/default"`
  (`hosts/oams/devenv.nix:166`). Add `endpoints.<host>.apiKeyFile` so the member
  view covers it, or state it stays a member-local literal.
- **R11 [MINOR] naming invariants.** State: `set` must be a key of
  `servers.<host>.routers`; profiles are per-host; the member view is
  single-host (a multi-host member needs a later host-list/index).
- **R12 [MINOR] STE/jargon.** Gloss `coResidentTiers`, `vulkanDeviceSelect`;
  rephrase "computed value, stored as resolved data".

Decisions carried forward: Q1 one `set` (drop `extraSets` unless implemented
R4), Q2 client native / member per-host, Q3 identity host-agnostic, Q4
`mkMemberView`. v3 fixes R1–R12; a short round-3 check follows.

---

# Design reviews — round 3

One reviewer verified v3 against R1-R12. **Verdict: nearly ready; one real
inconsistency remains that invalidates R1's fix.**

## R-findings status

| Finding                       | Status                    |
| ----------------------------- | ------------------------- |
| R1 frontier/qwen routers      | **WRONG FIX** — see below |
| R2 mkMemberView alias binding | resolved                  |
| R3 modelsOnHost defined       | resolved (host-presence)  |
| R4 drop extraSets, one set    | resolved                  |
| R5 package named key          | resolved                  |
| R6 download.minBytes          | resolved                  |
| R7 qwen3.5-9b enable=false    | resolved                  |
| R8 surveyed nested path       | resolved                  |
| R9 delete gpt-oss-120b        | resolved                  |
| R10 endpoints.apiKeyFile      | resolved                  |
| R11 naming invariants         | resolved                  |
| R12 STE                       | resolved                  |

## The one remaining defect

**R13 [BLOCKER] `frontier` and `qwen` are NOT routers.** Verified in the code:
`hosts/brys/llm-routers.nix` declares only three routers (`small`, `grunt`,
`surveyed`) and every model's `mainRouter` is one of `small|grunt|surveyed` or
absent. The frontier models (`deepseek-v4-flash`, `qwen3.8-flash-next`) set **no
`mainRouter`**, so llama-swap places them on the implicit **primary** router. So:

- The real router vocabulary is **`main | small | grunt | surveyed`**.
- `frontier` and `qwen` are model _groups on the `main` router_, not routers.
- v3's `servers.brys.routers = { frontier; qwen; grunt; surveyed; small; }` and
  `profiles.desktop.sets = [ "frontier" "qwen" ... ]` name two routers that do
  not exist, and they use `mainRouter = h.set` with `h.set = "frontier"` — a
  router llama-swap has never run.

**Correct model:** `set` = the router name (`main|small|grunt|surveyed`). Both
frontier models have `set = "main"`. Profiles enable router names. The old
`withFrontier`/`withQwen` flags both default true on both brys profiles, and
both models share `main`, so enabling `main` serves both — the independent
gating is not needed for shipping brys. The `frontier` **alias** stays on DS4
(already handled, B4).

**Minimal v4 change:** `servers.brys.routers` = `{ main; small; grunt; surveyed; }`
(no `frontier`/`qwen`); `profiles.*.sets` = `[ "main" "grunt" "surveyed" ]`;
`models.deepseek-v4-flash.hosts.brys.set = "main"`;
`models.qwen3.8-flash-next.hosts.brys.set = "main"`. Everything else in v3
holds.

## Non-blocking notes

- `lib.recursiveUpdate` concatenates lists. `extraFlags` sits only in a model's
  `common.perf` and only DS4 has a profile layer (with no `perf`), so no
  duplication occurs today. Keep `extraFlags` out of any profile layer; note it.
- Small-only models (`phi-4`, `qwen3-coder-next`, `qwen3-235b`) migrate with
  `set = "small"`; the profile does not enable `small`, so they are not served.
  They carry no aliases, so the member view is unaffected. Correct.

v4 = v3 with R13 applied. A one-line diff; no new review round needed beyond
confirming the router vocabulary.
