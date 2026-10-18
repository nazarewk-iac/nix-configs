---
type: Research
description: Measured warm-start, session-save, and restore timings for the llama-cpp-sessions build on brys — cold versus warm reuse, switch cost, and disk cost.
task: definition.md
authored_by: agent
timestamp: 2026-10-18T08:00:00+02:00
---

# Warm-start session measurements (2026-10-18)

Measured on brys, 2026-10-18, the `llama-cpp-sessions` build, model
`qwen3.8-flash-next`, session store `/var/lib/kdn/llms/sessions`.

## Timings

| measurement | value |
|---|---|
| cold: service start -> router listening | 274 ms |
| cold: model load (child, journal) | 67.5 s |
| cold: service start -> first response (wall) | 72.6 s |
| warm reuse, request 1 (cold prefix) | prompt_n=2030, cache_n=30, prompt_ms=76106 |
| warm reuse, request 2 (same prompt) | prompt_n=4, cache_n=2056, prompt_ms=437 (0.44 s) |
| warm reuse, request 3 | prompt_n=4, cache_n=2056, prompt_ms=358 (0.36 s) |
| warm-prefix speed-up | ~174x (76.1 s -> 0.44 s) |
| session create (2459-token prompt, cold) | prompt_ms=86953, cache_n=0 |
| save-on-shutdown file | llama-session-testrestore.bin = 394,426,740 B (376 MiB); appended 2 checkpoints (225.142 MiB) |
| restore after restart (journal) | "restored session testrestore ... (173.83 ms)", restored 2 checkpoints |
| resume request after restore | prompt_n=4, cache_n=2455, prompt_ms=394 (0.39 s) |
| model reload on that restart (warm page cache) | 23.3 s (vs 67.5 s cold) |
| switch Qwen -> DeepSeek (DS4 load) | wall 192.8 s; DS4 child load 179 s + 7.6 s prompt |
| switch DeepSeek -> Qwen (Qwen load) | wall 114.2 s; Qwen child load 104 s + 5.3 s prompt |
| session store total | 62 G across 16 files |
| largest session file | 8,181,312,424 B (7.6 GiB) |
| cold read of 7.6 GiB session file (dd iflag=direct after drop_caches) | 2.5 GB/s |
| restore effective read (394 MB / 0.1738 s) | ~2.3 GB/s |

## What is lost / recovered

(a) Session restore reads the file into the slot and reinstates the token sequence
+ KV (attention KV used cells, q8_0, and the GDN recurrent state) + saved
checkpoints. On resume cache_n=2455 of 2459, so only 4 new tokens prefill.
Recovered: the whole processed prefix. Not recovered: sampling RNG state, MTP
draft trajectories, any in-flight generation.

(b) In-RAM KV is lost on restart. The 62 G on disk is a snapshot. Restart destroys
RAM KV and the in-RAM `--cache-ram` entries; rebuilt by reloading the model
(23-67 s) and reading session files back.

(c) Early prompt divergence falls back to a full re-prefill: hybrid GDN
(non-rewindable), so reuse needs a context checkpoint at/before the first
mismatch. The OpenCode date changing in the system prompt forces n_past=0
(n_prompt_tokens_cache=0). The disk file does not help because the slot is reused
in place.

(d) Config bounds: `--ctx-checkpoints 32` (>=900 tokens apart), `--swa-checkpoints 32`,
`--cache-ram 8192` (8 GiB, RAM, lost on restart), `--slot-save-sessions-max 64`,
`--slot-save-sessions x-session-id`, `--ctx-size 1048576` across parallel 4. Save
triggers only on slot eviction to a different session or shutdown, so an
always-hot session's file can go stale.

(e) Disk cost: store 62 G / 16 files on 707 G free; largest 7.6 GiB; restore of the
used portion at 2.3-2.5 GB/s cold (ZFS direct), vs warm ~10 GB/s mirror, so a
7.6 GiB restore is ~3.3 s of pure I/O.

## Implication for llama-swap

llama-swap owns the child process; a session's disk file only helps if llama-swap
keeps the same slot/session warm or restores it; checkpoint placement (a checkpoint
at the end of the system prompt) is what makes daily prompt changes cheap.
