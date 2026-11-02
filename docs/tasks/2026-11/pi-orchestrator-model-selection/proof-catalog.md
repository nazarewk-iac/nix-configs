---
type: Research
description: Proof that the model catalog renders from data/llm.nix, parses, and carries the capability and cost hints the orchestrator needs — with the exact command and real output.
task: definition.md
authored_by: agent
timestamp: 2026-11-02T11:30:00+01:00
---

# Proof: the model catalog renders and carries capability + cost hints

Part 2 of the task. The catalog is what lets the orchestrator pick a model from intent and cost
instead of a fixed tier. It is rendered by `lib/llm.nix` (`mkCatalog`) from the single source of
truth, `data/llm.nix`, and reaches the orchestrator through the `rules` channel (the system prompt).

## The command

```bash
nix eval --impure --raw --expr '
  let f = builtins.getFlake (toString ./.);
      lib = f.inputs.nixpkgs.lib;
  in (import ./lib/llm.nix { inherit lib; }).mkCatalog'
```

## The output, verbatim (first rows)

```
alias	ctx	op	load~s	vision	model
audio-std-mid	32768	cpu	20	yes	qwen3-omni-30b-a3b
balanced	131072	cpu	120	-	qwen3-next-80b
chat-deep-slow	131072	cpu	40	yes	qwen3.8-27b
chat-dumb-fast	16384	gpu	2	-	qwen3.5-4b
chat-std-fast	32768	cpu	15	-	lfm2.5-24b-a2b
code-std-fast	32768	cpu	15	-	north-mini-code-1.0
orchestrate-deep-slow	524288	cpu	90	-	qwen3.8-flash-next
vision-quick-fast	32768	gpu	3	yes	qwen3-vl-8b-instruct
```

One row per **purpose alias** (the key the orchestrator names in a delegation), not per model. The
columns are what the alias name cannot already say:

| Column   | Meaning                                              |
| -------- | ---------------------------------------------------- |
| `alias`  | the intent the orchestrator passes to `delegate`     |
| `ctx`    | served context in tokens — the hard filter           |
| `op`     | `cpu` or `gpu` — where the model runs                |
| `load~s` | estimated cold-load seconds — is a switch affordable |
| `vision` | `yes` when the model accepts images                  |
| `model`  | the served base id, for a human reading a trace      |

## Coverage: every purpose-alias model has capabilities

```bash
nix eval --impure --json --expr '
  let f = builtins.getFlake (toString ./.);
      lib = f.inputs.nixpkgs.lib;
      d = import ./data/llm.nix;
      aliased = builtins.filter (n: d.models.${n} ? aliases) (builtins.attrNames d.models);
  in { count = builtins.length aliased;
       missing = builtins.filter (n: !(d.models.${n} ? capabilities)) aliased; }'
```

```
{"count":22,"missing":[]}
```

All 22 models that carry a purpose alias have a `capabilities` block; none are missing.

## Delivery to the orchestrator (the review's A1 finding)

The review's first accepted finding was that the catalog must reach the **decider**, not a
sub-agent. Verified: the catalog text is present in the session's system prompt. `devenv.nix`
concatenates `data/pi/AGENTS.md` and `mkCatalog` into the single `pi.coding-agent.rules` value, so
a freshly started session's `<addendum>` section contains the whole table. The `orchestrator.md`
agent then applies the ordered decision rule over it.

## What this proves, and what it does not

**Proves:** the catalog is reproducible by `nix eval`; it carries context, operation mode, an
estimated load time, and a vision flag per alias; and every aliased model supplies the hints.

**Does not prove:** that the estimates are accurate. `loadSeconds` and `operation` are hints with an
order-of-magnitude purpose (1 s vs 90 s), not predictions — review caveat C2. They are marked as
estimates in the catalog header (`load~s`) and in `data/llm.nix`.
