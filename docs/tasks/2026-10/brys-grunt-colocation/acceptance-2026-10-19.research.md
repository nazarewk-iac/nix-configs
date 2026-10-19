---
type: Research
description: Live acceptance test of the brys llama-swap matrix routing, deployed to the llms-frontier specialisation on 2026-10-19. Proves the never-evict guarantee for the frontier and the DS4-alone set; records the one defect (with_grunt points at a missing qwen3.5-4b file).
task: definition.md
authored_by: agent
timestamp: 2026-10-19T08:30:00+02:00
---

# brys llama-swap live acceptance test (2026-10-19)

## Deployment

The swap config was built from the current tree and activated on brys, into the
swapping specialisation `llms-frontier` (a `switch --specialisation`, so it
activates in place; no reboot).

- Running system: `nixos-system-brys-llms-frontier-26.11.20261011.7fd4004`
  (previously generation 716, built 2026-10-14, router mode).
- `llama-swap` active, `llama-cpp` inactive (router replaced), compat-proxy and
  Caddy active.
- Rendered config: 31 models, `use: matrix`, sets `main`, `with_grunt`,
  `with_surveyed`; `evict_costs` 1000 for the frontier pair, 1 for the rest.

## Results

The acceptance criterion (definition.md) is **"the grunt routes through the
compat-proxy without evicting Qwen"**. Proven, with one caveat.

| Test | Command | Outcome |
|---|---|---|
| Baseline `/v1/models` | `curl :39700/v1/models` | PASS — 31 ids + the `frontier`/`grunt`/`qwen` aliases |
| Frontier load | `POST {"model":"qwen3.8-flash-next"}` | PASS — child PID 1044764, RSS ~64.8 GiB, port 10027 |
| Surveyed grunt co-residence | while Qwen resident, `POST {"model":"tmax-2b"}` | **PASS** — Qwen PID 1044764 stays resident, `tmax-2b` starts beside it (PID 1045452) |
| DS4-alone | `POST {"model":"deepseek-v4-flash"}` | **PASS** — Qwen evicted, DS4 loads; journal: `model=deepseek-v4-flash set=with_surveyed evict=[qwen3.8-flash-next] cost=1000` |
| `with_grunt` path | `POST {"model":"qwen3.5-4b"}` | **BLOCKED** — see defect below |

The never-evict guarantee holds in both directions that were reachable: a
frontier request keeps its slot while a surveyed grunt runs beside it, and a
request for DS4 evicts the *other heavy model* only, at cost 1000. A cost-1
grunt is never the reason a frontier is evicted.

## Defect found: `with_grunt` references a missing file

`qwen3.5-4b` (the GPU grunt) is configured with
`hfRepo = "unsloth/Qwen3.5-4B-GGUF"`, so its `cmd` points at
`/var/lib/kdn/llms/models/unsloth/Qwen3.5-4B-GGUF/Qwen3.5-4B-Q4_K_M.gguf`, which
does **not** exist. llama-swap logs
`matrix: starting qwen3.5-4b failed: upstream command exited prematurely` and the
request fails. A usable copy exists at
`/var/lib/kdn/llms/models/surveyed/qwen3.5-4b.gguf` (2.7 GB), but no config entry
references it.

So the literal `with_grunt` never-evict path could not be exercised; the
`with_surveyed` path was, and it passes. The fix is to point the grunt at the
existing file (either `hfRepo = "surveyed"`, or download the unsloth path). Not
done in this test (test scope was read-only).

## Clean-up

`llama-swap` left active. The two children resident at the end were DS4 and
`tmax-2b`, which `unloadTimeout = 30` clears when idle.
