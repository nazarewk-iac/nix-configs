---
type: Solution
description: Add a fork llama.cpp build with #26004 + the rebased #29738, a slot-level disk session store with a 200 GB prune, and an opencode plugin that sends x-session-id; deployed and verified on brys.
task: definition.md
authored_by: agent
timestamp: 2026-10-09T23:00:00+02:00
---

# Disk-backed, session-keyed llama-server KV caches

## Root cause analysis

The pinned `llama-cpp-v0_6_0` (commit `d812350`) has the manual disk primitive
`--slot-save-path` plus `POST /slots/{id}?action=save|restore`, but:

1. No automatic save/restore. A client must call the endpoints itself.
2. No checkpoint persistence: upstream PR #26004 (merged 2026-10-08, commit
   `033df86`) appends the context checkpoints to the save file. The pin is
   older than that merge, so a restored hybrid/recurrent slot loses its rewind
   points. `qwen3.8-flash-next` is hybrid (GDN + QSA), so this matters.
3. Upstream PR #29738 ("session-keyed automatic slot save/restore") adds the
   automatic path, but it is still open and was authored before #26004, so it
   does not compile against current master (it uses the removed `fs_list` /
   `common_file_info` helpers).

## Solution

### 1. A fork build (`packages/llama-cpp/default.nix`)

`nazarewk-iac/llama.cpp`, branch `main`, commit
`6beadd4d6b73a87c61208cf76067eb7fd64ffea0`. It is upstream master `79e2e74`
(tag `b11538`, which already carries #26004) plus one cherry-picked commit:
PR #29738, rebased so its factored save path also appends the #26004
checkpoint appendix. The rebase resolved three conflicts in
`server-context.cpp` and rebuilt `test_slot_save.py`, and rewrote the removed
`fs_list` call with `std::filesystem::directory_iterator`.

New attributes: `llama-cpp-sessions` (CPU) and `llama-cpp-sessions-vulkan`.
The Qwen specialisations select `llama-cpp-sessions`.

### 2. Slot options (`modules/slots/llm/default.nix`)

- `sessionStore = { path; group; maxBytes; maxAgeMinutes; pruneInterval; }`
  (`null` by default). When set, the slot creates the `group`, adds it to the
  llama-cpp DynamicUser as a supplementary group, adds `path` to
  `ReadWritePaths`, and runs a `kdn-llm-session-prune` service+timer that
  enforces `maxBytes` (LRU by mtime) and `maxAgeMinutes`.
- Per-model `perf.ctxCheckpoints`, `perf.checkpointMinStep`,
  `perf.sessionHeaders`, `perf.sessionMaxSessions`, emitted into the preset INI
  as `ctx-checkpoints`, `checkpoint-min-step`, `slot-save-sessions`,
  `slot-save-sessions-max`. `perf.sessionHeaders` also emits
  `slot-save-path = sessionStore.path`.

### 3. brys wiring (`hosts/brys/llm.nix`, `llm-qwen.nix`, `llms-frontier.nix`)

- `sessionStore.path = "/var/lib/kdn/llms/sessions"`, group
  `llama-cpp-sessions`, `maxBytes = 200 GiB`, `maxAgeMinutes = 1440`.
- The directory is persisted under `usr/cache` with mode `0770` and that group.
- Qwen `perf`: `sessionHeaders = "x-session-id"`, `sessionMaxSessions = 64`,
  `ctxCheckpoints = 32`, `checkpointMinStep = 10500`.
- `qwenCacheRam` lowered from 36864 to 16384 MiB to fund the checkpoints.
- Both Qwen specialisations set `llamaPackage = pkgs.kdn.llama-cpp-sessions`.

### 4. Client (`modules/den/aspects/llm-client.nix`, `modules/slots/llm/client/default.nix`)

A generated opencode plugin `.opencode/plugins/kdn-llm-session-id.ts` uses the
`chat.headers` hook to send `x-session-id: <session id>` for the LAN provider
ids only. `devenv.files` writes it into the project, so opencode auto-loads it.

## Verification steps

Manual mechanism on the pinned build (tiny model, `--slot-save-path`):
cold `prompt_n 2001 / cache_n 0`; save; restart; restore; the same prompt then
`prompt_n 1 / cache_n 2000`, and a continuation `prompt_n 7 / cache_n 2001`.

Fork build:
`nix build .#...llama-cpp-sessions` succeeds; `--help` lists
`--slot-save-sessions` and `--slot-save-sessions-max`; `nm` finds the
`qwen4exp::graph_mtp` symbol; version `0.6.0 (build 11539, commit 6beadd4d6)`.

Deployed on brys (`llms-frontier`, `nixos-rebuild switch`):
- Child args contain `--slot-save-path /var/lib/kdn/llms/sessions
  --slot-save-sessions x-session-id --slot-save-sessions-max 64
  --ctx-checkpoints 32 --checkpoint-min-step 10500`.
- A request with `session_id: "test-1"` lands in slot 3
  (`GET /slots?model=qwen3.8-flash-next` reports it).
- A second session pinned to slot 3 evicts `test-1` to disk:
  `llama-session-test-1.bin` + `.dft`, journal
  `appended 2 context checkpoint(s) (225.142 MiB)`.
- `systemctl restart llama-cpp`, then a `test-1` request:
  `prompt_n 4 / cache_n 42`, journal
  `restored 2 context checkpoint(s)` and `restored session test-1`.
- The prune timer runs every 15 min and exits 0.

## Follow-up notes

- **Sizes.** The GDN recurrent state is ~112 MiB, and a checkpoint is the
  recurrent state only, so each checkpoint is ~112 MiB. A 65-token session file
  is 356 MB: ~114 MB base + 2 x ~112 MiB checkpoints. `ctx-checkpoints 32`
  bounds the checkpoint RAM at ~14 GiB over four slots. Re-measure after a real
  long session.
- **RAM.** The Qwen child sits at ~116.5 GB VmRSS with `cache-ram 16384`. The
  disk session store makes a large RAM prompt cache less necessary; lower it
  further only if a real long session shows pressure.
- **`maxAgeMinutes` is a second bound.** The prune deletes by age (24 h) and by
  bytes (200 GB). The upstream `--slot-save-sessions-max` deletes by count at
  startup.
- **Client coverage.** The plugin ships only in this repository's devenv shell.
  A user who runs opencode outside this project needs the same plugin in
  `~/.config/opencode/plugins/`.
- **Hard-kill gap.** #29738 flushes on eviction, shutdown, sleep and reload. A
  `kill -9`, OOM, or power loss loses everything since the last flush. Add a
  periodic save if that matters.
- **den `llm` aspect parity.** The new options live in the slot and the client
  aspect. The server-side den `llm` aspect (`modules/den/aspects/llm.nix`) is
  not yet mirrored; brys uses the slot route.
- **Upstream.** When #29738 merges, drop the fork and pin upstream. #26004 is
  already in master.
