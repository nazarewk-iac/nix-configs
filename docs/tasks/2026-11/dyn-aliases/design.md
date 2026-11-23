---
type: Design
description: The final shape of the dyn-* intent names — gateway presets for text, one gateway ladder for modality that asks the placement tree per candidate, and no second scheduler anywhere.
timestamp: 2026-11-24T00:20:00+01:00
---

# `dyn-*` intent names — final

## The one rule

**One oracle, one executor.** The placement policy tree (`internal/policy`) is the only thing that
decides whether a model can be used; the LiteLLM gateway is the only thing that executes a `dyn-*`
request. No launcher, no second ladder, no second copy of the fit arithmetic.

## Text: `dyn-fast`, `dyn-avg`, `dyn-max`

Gateway deployments over `qfn`, one per effort level. `data/llm.nix` carries the level, `lib/llm.nix`
maps it through `data.models.qfn.reasoning.levels` (`high` → `xhigh`).

| name       | `chat_template_kwargs`                               | `max_tokens` |
| ---------- | ---------------------------------------------------- | -----------: |
| `dyn-fast` | `{enable_thinking: false}`                           |         2048 |
| `dyn-avg`  | `{enable_thinking: true, reasoning_effort: "low"}`   |         8192 |
| `dyn-max`  | `{enable_thinking: true, reasoning_effort: "xhigh"}` |        32768 |

Mechanics, verified: `extra_body` reaches the upstream on a streaming completion; `max_tokens` in it
wins over the client's value; a client's own `chat_template_kwargs` replaces the deployment's, so
thinking is advertised, not enforced. Say that in the docs and stop there.

## Modality: `dyn-audio`, `dyn-image`

A LiteLLM model group per class whose deployments are the candidates in preference order, and a
`filter_deployments` callback (`hosts/etra/litellm_resident.py`) that walks them in order:

1. **Resident** — ask brys llama-swap `/v1/models`; a loaded candidate wins.
2. **Beside** — ask the placement tree (`POST /decide {"model": candidate}`) for each remaining
   candidate in order; the first `admit` wins.
3. **Suggest** — nothing admits: return a 409 built from the _tree's own_ refusal
   (`alternatives`, `confirmField`, `current_profile`) plus the per-candidate verdicts.
4. **Never switch.** No `/select`, no `/admit`.

The callback must not re-derive fit from `vramMiB` rows: that is the second copy the review found.
`/decide` is advisory, unlocked and already returns the trace.

`dyn-video` and `dyn-image-gen` are **not** names. The three editors are A1111 servers
(`/sdapi/v1/options`, `unlisted`); they are documented as the route `/upstream/<model>/sdapi/…`.

## Reach

- The names live **only on the gateway**. They are not `data.models` entries and must not be: an
  entry there would emit a brys llama-swap `cmd` and a second gateway group with the same name.
- `mkPiModelsJson` and `nameToBaseFor` learn about `data.dyn` explicitly.
- The gateway's client key is the `all-models` entry of `hosts/etra/litellm-keys.sops.yaml`
  (`/run/configs/llms/litellm/client-key`): it carries **no** `models` list, so
  `litellm_enforce.py` allows every group and the five names need no allow-list change. The two
  scoped keys (`pi-fast`, `pi-all-local`) do not carry them; adding one there is a deliberate
  widening of that key.
- The direct `brys`/`oams` endpoints keep model ids; `dyn-*` there answers "no router", by design.

## Transport to the tree

The manager binds `127.0.0.1:8181`, so brys exposes it on the mesh with one narrow relay
(`llm-netbird-relay-decide`, port 8182, `nb-priv` only, like the llama-swap relay) and etra relays
it into the gateway container (`litellm-brys-decide`, `KDN_DECIDE_URL`). The relay carries `/decide`
and `/status` only; the ladder never calls `/select` or `/admit`, so it cannot switch the engine.

## Data

```nix
dyn = {
  fast  = { base = "qfn"; thinking = "off";  maxTokens = 2048;  };
  avg   = { base = "qfn"; thinking = "low";  maxTokens = 8192;  };
  max   = { base = "qfn"; thinking = "high"; maxTokens = 32768; };
  audio = { kind = "audio"; models = [ "qwen3-omni" ]; };
  image = { kind = "image"; models = [ "qwen3-vl-30b-a3b" "ornith-1.5-35b-a3b" "qwen2.5-vl-7b" ]; };
};
```

`models`, not `candidates`: that is the field name the existing readers already use.

## Acceptance

1. `dyn-fast` returns no `reasoning_content`; `dyn-max` does, on the same prompt and the same engine.
2. Both answer while the engine rests on a **text** profile, and neither moves `last_switch`.
3. On an **image** profile the text presets may fail: `auto` is refused when the current profile is
   not a text profile. The refusal must name that, not time out. The callback checks the text
   presets too, so the client gets a 409 naming the current profile and the text profiles, instead
   of the upstream's opaque failure.
4. `dyn-image` with `qwen3-vl-30b-a3b` resident returns it, with no switch and no load.
5. `dyn-image` on `max-multi` with nothing resident returns **409**, built from the tree's refusal,
   naming `qfn-fast-colo` / `qfn-max-colo`, every candidate, and the failing check per candidate.
6. `/v1/models` lists `dyn-fast`, `dyn-avg`, `dyn-max` with **`max_input_tokens`** 262144 and the
   preset's `max_output_tokens`, and `dyn-audio`/`dyn-image` with the window of their default
   route (32768) — the same number their Pi entry promises, never a 262144 a 32k model cannot
   serve. The gateway publishes `max_input_tokens`, not the OpenAI field name `context_length`;
   verified live 2026-11-24.
7. `pi --list-models` shows the text presets with the right context, cap and thinking flag.
8. `dyn-image-gen` and `dyn-video` are absent from `/v1/models` and documented as routes.

## What is explicitly not built

- A launcher that `exec`s a candidate: it cannot answer a 409, so it cannot deliver rungs 3–4.
- A gate with a candidate list: correct in principle, but it needs a per-candidate supervisor, a
  proxy rebuilt per choice, a residency source, and an answer to how the manager accounts for a
  child whose footprint is not one policy row. Only worth it if a `dyn-image` name is needed on brys
  itself.
- A second behaviour tree. The class is a loop over the existing tree, not a new one.
