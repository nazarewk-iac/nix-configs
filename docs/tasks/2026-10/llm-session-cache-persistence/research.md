---
type: Research
description: Findings on llama-server disk-backed slot save/restore — the pinned-build mechanism and API, file format and size, router-mode caveats, the open session-keyed upstream PR, and how to drive it from OpenCode.
task: definition.md
authored_by: agent
timestamp: 2026-10-09T21:15:00+02:00
---

# Research: disk-backed llama-server session caches

> **Scope.** Research only, nothing implemented. All source references are to
> the pinned build, llama.cpp v0.6.0, commit
> `d81235049384534c167caea52b85a694f6103d14` (2026-10-05), the build that
> `packages/llama-cpp/default.nix` names `llama-cpp-v0_6_0`.

## 1. Summary

- The pinned build already has a **manual** disk primitive: `--slot-save-path`
  plus `POST /slots/{id_slot}?action=save|restore`. It writes one file per
  slot. A client must call it.
- The file holds the prompt tokens and the sequence KV state. It is tied to the
  model and to the context parameters. It survives a restart.
- The save is **not** automatic. `--cache-idle-slots` saves to the in-RAM
  prompt cache, not to disk. The context checkpoints are in RAM.
- The pinned build **lacks** two upstream changes that matter: checkpoint
  persistence across save/restore (#26004, merged 2026-10-08) and automatic
  session-keyed save/restore (#29738, open).
- Upstream #29738 is exactly the wanted feature: a session id in a request
  header or body field makes the server save on eviction and restore on return,
  flush on shutdown, and cap the number of files. It is **not merged** yet.
- The size of one file is proportional to the tokens used. For
  `qwen3.8-flash-next` the KV is about 24 KiB per token at F16, so a long
  ~240K-token session is about 5.7 GiB. 10-20 long sessions are 57-114 GiB.
- OpenCode can send custom headers (`options.headers`), and a plugin can inject
  a per-conversation header. That is the likely way to key the sessions.

## 2. Mechanism in the pinned build

### 2.1 Flags and endpoints

From `llama-server --help` and `tools/server/README.md`:

| Flag | Meaning |
|---|---|
| `--slot-save-path PATH` | Directory for slot KV save files. Default: disabled. |
| `-ctxcp, --ctx-checkpoints N` | Max context checkpoints per slot. Default: 32. |
| `-cms, --checkpoint-min-step N` | Minimum token spacing between checkpoints. Default: 8192. |
| `-cram, --cache-ram N` | RAM prompt-cache size in MiB. Default: 8192. |
| `--cache-idle-slots` | Save idle slots to the **RAM** prompt cache on a new task. Default: on, needs `cache-ram`. |

Endpoints (`server-context.cpp`):

- `GET /slots` — list slots. With `--slot-save-path` the save action is on.
- `POST /slots/{id_slot}?action=save` — body `{"filename": "..."}`.
- `POST /slots/{id_slot}?action=restore` — body `{"filename": "..."}`.
- `POST /slots/{id_slot}?action=erase`.

The filename is joined to the save path by plain string concatenation
(`handle_slots_save`, `server-context.cpp:5740`). The parser appends a directory
separator to `--slot-save-path` if it is missing
(`common/arg.cpp:3632`).

### 2.2 Path and filename validation

- `--slot-save-path` must be an existing directory at argument-parse time
  (`fs_is_directory`, `common/arg.cpp:3628`). In router mode the child parses
  its own arguments, so the directory must exist when the child spawns.
- `fs_validate_filename(filename)` runs with `allow_subdirs = false`
  (`common/common.h:919`). It rejects `/`, `\`, control characters, `..`
  (through the slash rule), a length over 255 bytes, and several Unicode
  look-alikes. All files therefore sit directly in the save path.

### 2.3 What a save does

`SERVER_TASK_TYPE_SLOT_SAVE` (`server-context.cpp:2750`) runs only when the
slot is idle; otherwise the task is deferred. It serializes
`slot->prompt.tokens` and calls `llama_state_seq_save_file`
(`server-context.cpp:2779`). The restore path (`server-context.cpp:2800`) loads
the file, checks that the restored token count fits the slot context
(`restored.size() > slot->n_ctx` is an error), and validates the tokens against
the model vocabulary (`restored.validate(ctx_tgt)`).

### 2.4 File format

`llama_context::state_seq_save_file` (`src/llama-context.cpp:3380`):

```
u32  LLAMA_STATE_SEQ_MAGIC    ("GGSQ")
u32  LLAMA_STATE_SEQ_VERSION  (4)
u32  n_token_count
u32  tokens[n_token_count]
...  serialized sequence state (state_seq_write_data)
```

The serialized state is written by `llama_memory_hybrid::state_write`
(`src/llama-memory-hybrid.cpp:190`), which calls the attention KV writer and
the recurrent writer:

- `llama_kv_cache::state_write` (`src/llama-kv-cache.cpp:2071`) writes only the
  cells that belong to the sequence (`cells.seq_has(i, seq_id)`), not the full
  context pool. The file size therefore tracks the **used** tokens, not
  `--ctx-size`.
- `llama_memory_recurrent::state_write` (`src/llama-memory-recurrent.cpp:784`)
  writes the recurrent state. This matters because `qwen3.8-flash-next` is a
  hybrid GDN model.

The format is model- and config-specific. The server does not store a model
fingerprint. A restore into a different architecture, quant, RoPE setup, or KV
type is not checked in the pinned build. Upstream PR #24004 describes an exact
model fingerprint as a correctness requirement for an automatic cache; the
manual endpoint relies on the operator.

## 3. Router-mode caveats (the brys deployment)

brys runs `llama-server` in **router mode** (`--models-dir`,
`--models-preset`). The router spawns one child process per model. From
`server.cpp` and `server-models.cpp`:

- `routes.get_slots = models_routes->proxy_get` and
  `routes.post_slots = models_routes->proxy_post` (`server.cpp:252`). The
  router proxies both to a child.
- `proxy_post` selects the child from the **JSON body field `model`**
  (`server-models.cpp:2036`). The documented save body `{"filename": "..."}`
  has no `model`, so a router-mode save must add `"model": "<name>"`.
- `proxy_get` selects the child from the **query parameter `model`**
  (`server-models.cpp:2021`), so `GET /slots?model=qwen3.8-flash-next`.
- The router overlays its own CLI arguments on every model preset
  (`server-models.cpp:745`), so `--slot-save-path` on the router propagates to
  every child. A per-model preset key `slot-save-path = ...` also works.
- All models share one save path. Two models that serve the same session id
  would share one file. This is a data-corruption risk in router mode
  (upstream #29678 states this).

## 4. Size and disk budget

### 4.1 Model geometry

From `docs/local-llms.md` and the model card: `Qwen3.8-Flash-Next` has 48
layers; only every 4th layer is full attention (12 of 48); the rest use GDN
linear attention. It has 2 KV heads and `head_dim` 256.

KV per token at F16 (K and V, 12 full-attention layers):

```
2 (K,V) x 12 layers x 2 kv_heads x 256 head_dim x 2 bytes = 24576 bytes
                                                          ~ 24 KiB / token
```

At the full 1M context this is about 24 GiB. This matches the `llm-qwen.nix`
comment "F16 KV (~24 GiB)".

### 4.2 Observed entry size

The `--cache-ram` task recorded one prompt-cache entry at **5758 MiB**
([../llm-prompt-cache-ram/done.md](../llm-prompt-cache-ram/done.md)). The RAM
prompt-cache entry size is the final sequence state size
(`server_prompt::prompt_save`, `server-context.cpp:308`), so the disk file is
the same order of magnitude. 5758 MiB / 24 KiB per token is about 240K tokens
of context.

### 4.3 Estimate for 10-20 sessions

| Session size | Per file (state only) | 10 sessions | 20 sessions |
|---|---|---|---|
| ~40K tokens | ~0.9 GiB | ~9 GiB | ~19 GiB |
| ~120K tokens | ~2.8 GiB | ~28 GiB | ~57 GiB |
| ~240K tokens | ~5.7 GiB | ~57 GiB | ~114 GiB |

These are state-only numbers. The checkpoint appendix (section 5.2) can add
much more.

### 4.4 Disk location

The model GGUFs live on the ZFS `usr/data` dataset
(`hosts/brys/llm.nix:406`, `kdn.disks.persist."usr/data"`). The box has a 2 TB
NVMe mirror. The save directory should live on the same dataset. **Verify the
free space on `usr/data` before deployment.** 114 GiB is safe on a 2 TB mirror
only if the dataset is not near full; measure it.

## 5. Upstream status

### 5.1 The wanted feature is an open PR

- [ggml-org/llama.cpp#29678](https://github.com/ggml-org/llama.cpp/issues/29678)
  — "Feature Request: automatic slot save/restore by client session id".
  Open. It contains the full design and the security model.
- [ggml-org/llama.cpp#29738](https://github.com/ggml-org/llama.cpp/pull/29738)
  — "feat(server): session-keyed automatic slot save/restore". Open,
  created 2026-09-30, one commit, 8 files, +914/-55.

PR #29738 adds:

- `--slot-save-sessions HEADERS` — enable session save/restore. Comma-separated
  header names in priority order. The body field `session_id` always wins. An
  empty value means "body field only".
- `--slot-save-sessions-max N` — cap on the number of saved sessions.
  Default 128.
- A session id from a header or the body field. If both are present and
  disagree, the request gets a 400.
- Automatic save when a slot that holds session A is handed to session B.
- Automatic restore when a request for session A arrives and A is on disk.
- A flush of the in-slot sessions on shutdown, sleep, and model reload.
- A startup index of the save directory, with oldest-first deletion past the
  cap.
- File names `llama-session-<id>.bin`, plus `llama-session-<id>.dft` for the
  draft context.
- `session_id` reported per slot in `GET /slots` and in
  `generation_settings`.

The PR reuses `--slot-save-path`. Without that flag the session id only pins
the slot in memory.

The PR's own non-goals: no draft-context persistence beyond the `.dft` file, no
hybrid/recurrent checkpoint persistence, no metadata in the file, no
embeddings/rerank handling.

### 5.2 Checkpoint persistence (merged after the pin)

[ggml-org/llama.cpp#26004](https://github.com/ggml-org/llama.cpp/pull/26004)
— "server : preserve context checkpoints across slot save/restore". Merged
2026-10-08, merge commit `033df86`. It closes issue #25913, "hybrid/recurrent
models lose all prompt reuse".

The pinned v0.6.0 (`d812350`, 2026-10-05) does **not** contain it. The repo's
`master` pin in `packages/llama-cpp/default.nix` (`9c2e0e4`, 2026-10-08) is 16
commits behind the merge and also does not contain it (verified: no
`SLOT_CKPT_MAGIC` in that source).

The change appends a `"SCKP"` appendix after the llama state payload. The
appendix holds up to `n_ctx_checkpoints` (default 32) state blobs. The comment
in the PR explains why: a recurrent state cannot be rewound, so the final state
alone cannot serve a request that diverges from the saved prompt earlier than
the end. For a straight continuation (the new prompt extends the saved prompt)
the final state is enough. For an edited or branched history the checkpoints are
needed.

The appendix can be large: each checkpoint is a state blob, and a long prompt
can carry up to 32 of them. This is the main unknown for the disk budget. If
the workload only ever continues the same prompt, `--ctx-checkpoints 0` keeps
the file at the state-only size.

### 5.3 Related upstream work

| Item | State | Note |
|---|---|---|
| [#29201](https://github.com/ggml-org/llama.cpp/issues/29201) export/import slot state over HTTP | open | `GET/PUT /slots/{id}/state`; lets a proxy move state between backends. |
| [#20697](https://github.com/ggml-org/llama.cpp/issues/20697) disk-based checkpoint cache `--cache-disk` | open | Moves the content-based checkpoint cache to disk. Identity-based #29738 is complementary. |
| [#24004](https://github.com/ggml-org/llama.cpp/pull/24004) `--slot-save-auto` | closed, not merged | A transparent block-hash disk cache with a model fingerprint. |
| [#20822](https://github.com/ggml-org/llama.cpp/issues/20822) auto save/restore in router mode | open | The router-mode counterpart. |

### 5.4 Known open bugs in the manual endpoints

| Issue | State | Impact |
|---|---|---|
| [#28194](https://github.com/ggml-org/llama.cpp/issues/28194) no KV reuse on hybrid/recurrent and SWA without checkpoints | open | Fixed by #26004 for hybrid/recurrent. |
| [#28276](https://github.com/ggml-org/llama.cpp/issues/28276) a restored slot state blocks the prompt-cache lookup | open | A restored state can hide a longer cached state. |
| [#28619](https://github.com/ggml-org/llama.cpp/issues/28619) save/restore never persists the draft context | open | The draft state is not saved by the manual endpoints. #29738 adds a `.dft` file. |
| [#26676](https://github.com/ggml-org/llama.cpp/issues/26676) restore reads the file but the slot stays empty | open | Reported on an older build; verify on ours. |
| [#30129](https://github.com/ggml-org/llama.cpp/issues/30129) RAM cache restores KV under a different LoRA config | open | Not relevant here (no LoRA), but a fingerprint gap. |

## 6. Integration options for OpenCode

### 6.1 Manual CLI wrapper (works on the pinned build)

A small script that calls the endpoints through the router:

```
POST /slots/<id>?action=save    {"model": "<name>", "filename": "<id>.bin"}
POST /slots/<id>?action=restore {"model": "<name>", "filename": "<id>.bin"}
GET  /slots?model=<name>
```

Pros: no new build. Cons: the caller must know the slot id, the save is racy
against slot assignment, and the hybrid/recurrent checkpoint bug means a
branched continuation re-prefills.

### 6.2 Session-keyed server (PR #29738) plus an OpenCode session header

The upstream design needs only a session id per request. OpenCode can supply
one:

- OpenCode supports `provider.<name>.options.headers` for static headers
  (documented for Helicone).
- The `opencode-helicone-session` plugin injects a per-conversation header
  (`Helicone-Session-Id`). A small analogous plugin can inject `x-session-id`
  on every request.

Then the server runs with `--slot-save-path <dir> --slot-save-sessions
x-session-id --slot-save-sessions-max 32`. The router forwards request headers
to the child, so router mode works.

The build needs PR #29738. Two ways:

- Apply #29738 as a patch to a `master`-based derivation. The repo already
  carries open-PR patches (`29250-no-mmap-prefetch.patch`,
  `25294-moe-stream.patch`, `26414-pin-hot-experts.patch`).
- Wait for #29738 to merge, then bump the pin.

The pin must also move past #26004 for the hybrid Qwen model to reuse prefixes
after an edit or a branch.

### 6.3 A proxy shim

The compat-proxy sits between OpenCode and the router
(`modules/slots/llm/proxy/default.nix`). It could add the session id, but it
needs the OpenCode session id first. A plugin is the cleaner source of that id.
The compat-proxy is an external flake input, so a change there is out of this
repo.

## 7. Security notes

- The session id is effectively a capability for that session's KV state. A
  caller who guesses an id can continue the conversation and observe responses
  conditioned on the hidden context. Use high-entropy ids (a UUID), keep the
  existing `--api-key`, and keep the LAN endpoint behind Caddy.
- The save files hold the raw prompt tokens and KV in plaintext and persist
  across restarts. The directory must be treated as sensitive and not
  world-readable. The current models directory is `0755`; the session store
  should be tighter.
- The id passes `fs_validate_filename`, so no path traversal is possible.
- A hostile client can flood unique ids and fill the cap. The cap and the
  `--api-key` bound this.
- In router mode all models share one save path. Two models with the same
  session id collide. Use a per-model prefix or one boot entry per model.

## 8. Open questions to resolve

1. **Real file sizes.** Measure one save on `llm-qwen` with
   `--ctx-checkpoints 0` and with the default 32, for a real session. This sets
   the retention budget.
2. **Checkpoint behaviour on the hybrid model.** Confirm whether a
   continuation and an edited-history request each re-prefill on the pinned
   build, and whether a post-#26004 build removes the re-prefill.
3. **#29738 rebase.** The PR predates #26004. Confirm whether its factored save
   path carries the checkpoint appendix after a rebase.
4. **OpenCode session id.** Confirm the OpenCode plugin API can read the
   current session id at request time and inject a header. The helicone plugin
   is the reference.
5. **Router model collisions.** Decide the file-naming scheme for a multi-model
   router, or restrict the feature to the single-model `llm-qwen` boot.
6. **Free space.** Check `zfs list` / `df` for `usr/data` on brys.

## 9. Recommendation

1. Measure the file size and the re-prefill behaviour on the pinned build first.
2. Prefer the upstream session-keyed route (#29738) over a hand-rolled wrapper,
   because it solves the races and the restart case and it is the design
   upstream will carry.
3. Build it as a `master`-based derivation with #29738 applied as a patch, and
   pin `master` past #26004. Keep the pinned v0.6.0 for the MTP graph until the
   patch is proven.
4. Add the OpenCode plugin that sends the session header.
5. Keep the feature on the single-model `llm-qwen` boot first, where the shared
   save path cannot collide.

## References

- Pinned source: `packages/llama-cpp/default.nix` (v0.6.0, `d812350`).
- `tools/server/server-context.cpp` — save/restore tasks and handlers.
- `src/llama-context.cpp`, `src/llama-kv-cache.cpp`,
  `src/llama-memory-recurrent.cpp`, `src/llama-memory-hybrid.cpp` — the state
  format.
- `common/arg.cpp`, `common/common.cpp` — `--slot-save-path` and
  `fs_validate_filename`.
- `tools/server/server-models.cpp` — router-mode proxying.
- [../llm-prompt-cache-ram/done.md](../llm-prompt-cache-ram/done.md) — the
  5.7 GiB entry and the `--cache-ram` lever.
- [docs/local-llms.md](../../../local-llms.md) — model geometry and RAM levers.
- Upstream: #29678, #29738, #26004, #29201, #20697, #24004, #20822, #28194,
  #28276, #28619, #26676, #30129.
