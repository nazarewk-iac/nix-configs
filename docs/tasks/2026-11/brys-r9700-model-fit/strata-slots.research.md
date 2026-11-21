---
type: Research
description: How the Strata 0.1.62 engine allocates K/V across request slots on one card — per slot at --max-context, no shared pool, no per-slot context — with code and string evidence, and the closest supported shape to one 1M orchestrator plus a swarm of 256k agents.
task: ../definition.md
authored_by: agent
timestamp: 2026-11-21T17:51:00+01:00
---

# Strata: K/V across slots, and the 1M-plus-swarm question

**Short answer: no.** One engine has one `--max-context`; every request slot is a full
session of that size, and the K/V is per slot, never pooled. Closest fit: **512k, `--batch 4`**.

Evidence: engine binary strings, engine `--help`, terminal Python, two `--plan` runs; no model loaded.

## 1. K/V is per slot, at `--max-context`, never shared

- Slot count is the only thing `--batch` changes. Engine help: "up to N requests decode
  together in batch slots (2..8 normally) ... each slot with its own session (VRAM like
  the main one)".
- Each slot is carved like the main session: engine string `verify: a slot's session is
  not carved like the stage's own (layer range, context)`.
- Two refusals multiply slots by context: `strata-q36: not enough VRAM for %d slots at a
  context of %d (%.2f GiB each, %.2f GiB free)` and `; this start keeps %d request slots
  (--batch %d), each a session of its own, so the card is too small for them at this
  context: use a smaller --max-context or fewer --batch slots`.
- With `--kv-resident` the slot K/V moves to pinned RAM and is still per slot: `WARNING:
  --batch %d: a slot's K/V takes %.2f GiB of pinned RAM, %.1f GiB are available ...` and
  `All %d are carved as asked; a smaller --max-context makes a slot smaller`.
- Code path: the engine allocates one session per slot (`q36_engine.cu::alloc_session`,
  named in `strata_control/own_path_fit.py:10`). The terminal prices it at
  `strata_control/vram_fit.py:161` — `extra = min(int(slots), SLOTS_MAX) * main`, where
  `main = session_mib(ctx, kv, kv_resident)`; `vram_fit.py:26` says "every slot holds a
  session of its own, the size of the main one, on every backend". Arithmetic, k8v4 =
  816 B/cell over 12 QSA layers: 1M = 9.56 GiB, 256k = 2.39 GiB (x8 = 19.1 GiB), 512k =
  4.78 GiB — both given measurements match this exactly.

## 2. Heterogeneous slot sizing: not supported

- The full flag list (every `^  --` line of the engine `--help`) has one context flag
  (`--max-context N`, "KV/state capacity") and one slot-count flag (`--batch N / --slots N`).
  Nothing else matches slot/context/parallel: no `--slot-context`, no `--kv-per-slot`.
- A request cannot lower it: the only request-time check is `ERR prompt (%zu tokens) +
  max_new (%lld) exceeds the context (%d)`.
- The per-request control channel `strata_tune` carries `pcie_frac`, `spec_min_p`,
  `aux_cpus` only (`strata_control/tune_knobs.py:130-137`).
- The engine may run **fewer** slots than asked, never different sizes: `WARNING:
  --batch: %d slot sessions fit, and a batch window holds at most %d rows, so %d slots`.
- Terminal `--parallel N` becomes engine `--batch N` (`engines.py:802`); the ceiling is 8 (`PARALLEL_MAX = 8`, `engines.py:762`).

## 3. `--kv-grow`, and the full predicate

- Help: "the K/V takes VRAM only for the cells the requests reach and the expert cache
  holds the rest, giving slots back as the context grows (one GPU, with --expert-profile;
  STRATA_KV_GROW=1/0 also). Default: the whole --max-context allocated at start".
- The refusal is one string, so the engine prints no per-condition reason:
  `strata generate: --kv-grow is off (one GPU, a profile, the whole K/V in VRAM, every
  expert in RAM, no --batch, --vram-elastic or --peer-device)`.
  It requires: one GPU, `--expert-profile`, the whole K/V in VRAM (that is, **no
  `--kv-resident`**), every expert in RAM, and the absence of `--batch`, `--vram-elastic`
  and `--peer-device`.
- Growth is reported as `elastic K/V: %lld of %lld cells in VRAM ... the expert cache
  (%lld slots) gives the K/V room below slot %lld as the context grows`.
- It cannot help here: all three profiles set `--kv-resident`, and the goal needs
  `--batch`. It also grows one K/V for the slots that exist; it never sizes them apart.

## 4. Real semantics (the docs disagree with the measurements)

| flag | real meaning | evidence |
| --- | --- | --- |
| `--max-context N` | capacity of **one** session, and the size every slot is carved at (default 4096) | help; carve string |
| `--kv-resident N` | stream: N cells of each QSA layer stay in VRAM, the **whole** session K/V sits in pinned RAM; 0 = all in VRAM; floor is 4096 | help; `KV_RESIDENT_MIN = 4096  # qsa_kv_resident_min()` at `vram_fit.py:94` |
| `--batch N` / `--slots N` | N concurrent request slots (2..8), each a full session of `--max-context` | help; `PARALLEL_MAX = 8` |
| `--parallel N` | terminal/server flag only, becomes `--batch N`; never an engine flag | `engines.py:802`; both appear in `--plan` |

Two doc gaps: the help says the `--kv-resident` minimum is 20480 while the engine raises a
smaller window to 4096; and "VRAM like the main one" hides that under streaming a slot's
cost lands in **pinned RAM** — the wall is RAM (the 65.6 GiB check), not the card.

## 5. Closest supported shape to 1 orchestrator at 1M plus N agents at 256k

1. **512k with `--batch 4`** (new, untested). 4 x 4.78 = 19.1 GiB pinned K/V, the same
   budget as the measured-fitting 8 x 256k. One 512k orchestrator plus three agents of up
   to 256k each, all live. Cost: `--rope-scale 2` (trained context is 262144, the
   `--yarn-orig-ctx` default) and the whole engine drops to 512k.
2. **Two profiles, one role each** (the current answer): `max` / `omni-max` at 1M with 1
   slot, `omni-fast` at 1M with 2 slots. Sequential switching, not concurrent.
3. **1M with `--batch 2`** on the IQ2_XS pack — measured to load and serve with 7.8 GiB
   `MemAvailable`; UD-IQ4_XS at 2 slots is OOM-killed.
4. **Two engines on one card**, each with its own `--max-context`, sharing RAM through
   `--shared-expert-arena` on /dev/shm (the mechanism `serve/replicas.py` uses). The flag
   exists, but this needs the dense weights twice in VRAM and is unmeasured.

`--plan` refuses none of these: it lowers `--kv-resident` to 4096 and warns. Measured:
`omni-fast --parallel 8` plans `--batch 8` with the note "short of GPU memory: more is read
from RAM and the SSD". The wall appears at start as the pinned-RAM warning, then as OOM.

**Recommendation:** one engine, one `--max-context`, chosen so that
`slots x max_context x 816 B x 12 <= pinned-RAM budget` — 512k x 4 slots today, or the
current 1M x 1 slot plus a 512k x 4 profile selected by role.
