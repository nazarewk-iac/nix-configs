---
type: Research
description: Root cause of the full-context re-prefill of a resumed session — a hybrid GDN model cannot reuse a prefix unless a context checkpoint covers the divergence point, so an early divergence (the OpenCode date) forces a full re-process.
task: definition.md
authored_by: agent
timestamp: 2026-10-12T06:56:54+02:00
---

# Why a resumed session re-prefills the whole context

Measured on brys, `llama-cpp-sessions-0.6.0-unstable-2026-10-09` (the fork), the
`llm-qwen` boot, session `ses_ee324b411ffe1JJtR5p4wl7I6Z`.

## Symptom

A request that resumes a long session re-processes the **whole** prompt, not the
new tail:

```
task 39195 | prompt processing, n_tokens = 41851, progress = 0.16, t = 1551 s / 26.98 t/s
/slots -> n_prompt_tokens 20686, n_prompt_tokens_processed 16590, n_prompt_tokens_cache 0
```

`n_prompt_tokens_cache = 0` is the key number: the server reuses no prefix. The
prompt is ~258K tokens, so the request spends about 2.6 hours before the first
generated token.

## The prompt prefix did not change

The compat proxy logs every request shape. The last request before the gap and
the resuming request agree on the parts that matter:

```
Oct 11 22:18  msgs=490 tools=11  msg[0] role=system content_len=20137  msg[1] content_len=22
Oct 12 06:29  msgs=492 tools=11  msg[0] role=system content_len=20137  msg[1] content_len=22
```

The slot also still held the session, so the fork reused the slot **in place**
and did not restore from disk:

```
slot get_availabl: id 3 | task -1 | selected slot by session id (ses_ee324...)
```

`content_len` is a character count. A date change keeps the length: `Sun Oct 11
2026` and `Mon Oct 12 2026` are both 15 characters. The OpenCode system prompt
embeds the current date, so the text changed while the length did not.

## Root cause: hybrid reuse needs a checkpoint

Qwen3.8-Flash-Next is a hybrid GDN+QSA model. Most layers are recurrent (GDN);
a recurrent state cannot be rewound. llama.cpp therefore cannot reuse a partial
prefix unless a **context checkpoint** exists at or before the divergence point.

The fork code (`tools/server/server-context.cpp`, commit `6beadd4d6`):

```cpp
n_past = slot.prompt.tokens.get_common_prefix(input_tokens);   // LCP        (3934)

const auto pos_min_thold = std::max(0, pos_next - n_swa - ...);             // (4017)
if (pos_min >= pos_min_thold) {                                             // (4069)
    // find a context checkpoint that covers the reuse point
    bool do_reset = it == slot.prompt.checkpoints.rend();
    if (do_reset) {
        pos_next = 0;
        n_past   = 0;   // full re-process                                  // (4113)
    }
}
```

Two cases follow:

- **Normal turn (prompt grows at the end).** The common prefix is the whole
  previous prompt (~261K tokens). Then `pos_next` is large, `pos_min` (0) is
  below `pos_min_thold`, the checkpoint search is **skipped**, and the prefix is
  reused. This is why a normal turn evaluates only 100-800 tokens.
- **Early divergence (the date changed).** The common prefix ends inside the
  system prompt, so `pos_next` is small. Then `pos_min (0) >= pos_min_thold`,
  the checkpoint search runs, finds no checkpoint before the first user message,
  sets `do_reset`, and forces `n_past = 0` — a full re-process.

The forcing line is `SLT_TRC`, so the default log level does not show it:

```
forcing full prompt re-processing due to lack of cache data
(likely due to SWA or hybrid/recurrent memory, ...)
```

## Why the disk session file did not help

- The slot was reused in place, so the fork never read the file.
- The file is stale anyway. `llama-session-ses_ee324...bin` is dated
  `2026-10-11 06:27`, written under MTP-on. Under MTP-off it fails:

  ```
  E state_read_data: incompatible key rotation (0 instead of 256)
  E llama_state_seq_load_file: error loading sequence state file: failed to restore kv cache
  W slot get_availabl: failed to restore session ses_ee324..., starting fresh
  ```

- The fork writes a session file only when a slot is evicted to a **different**
  session, or on shutdown. One always-hot session is never evicted, so the file
  was never re-saved under MTP-off.

## Consequences for the warm-start design

- A warm base prefix is not enough on its own. If the first difference between
  the request and the warm prefix is **before the first checkpoint**, the model
  re-processes the whole prompt. The warm prefix must match up to the first
  user message, or a checkpoint must exist at the divergence point.
- Any daily-changing content in the system prompt (the date) breaks the reuse
  once per day, at the cost of a full re-prefill. A stable system prompt, or a
  checkpoint placed at the end of the system prompt, avoids this.
- The same applies to any early prompt change: a new tool set, a new agent
  prompt, or a re-rendered message list.

## How to confirm

- Run the server with `slots_debug` (or TRC logging) to print the token mismatch
  around `n_past` and the `forcing full prompt re-processing` line.
- Compare the exact `msg[0]` text of two requests on different days. The proxy
  logs only the length.

## References

- Fork source: `nazarewk-iac/llama.cpp` `6beadd4d6`, `tools/server/server-context.cpp`.
- [../llm-session-cache-persistence/research.md](../llm-session-cache-persistence/research.md)
  — the disk session store and the hybrid checkpoint limit.
- [../w6600-amdgpu-hang/research.md](../w6600-amdgpu-hang/research.md) — the MTP build.
- `hosts/brys/llm.nix` — `qwenPerf` (checkpoints, `swa-checkpoints`).
