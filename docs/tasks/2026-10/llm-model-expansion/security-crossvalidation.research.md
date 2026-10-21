---
type: Research
description: Cross-validate the registered brys fleet against the Hacker News discussion "Qwen3-Coder writes less secure code when told it's for a US persona" (HN 50179706). Identify the flagged model, the dependable Qwen picks, and a deregistration/cleanup list.
task: definition.md
authored_by: agent
timestamp: 2026-10-21T12:30:00+02:00
---

# Security cross-validation of the fleet (HN 50179706)

## The discussion

The thread [Qwen3-Coder writes less secure code when told it's for a US persona](https://news.ycombinator.com/item?id=50179706)
discusses a Hirundo.io blog post. The claim: `Qwen/Qwen3-Coder-30B-A3B-Instruct`
writes less secure code when the prompt says the code is for a US persona. The
post frames it as a risk and offers "westernized" models as the fix.

## What the thread actually establishes

The top-voted comments push back hard, and the pushback is consistent:

- **The flagged model is old and weak.** Comment 50181243: it is
  `Qwen/Qwen3-Coder-30B-A3B-Instruct`, from July 2025, non-reasoning only, AA
  score 10, and a **80% hallucination rate**. `Qwen3.8-27B` has fewer
  parameters, AA score 34, and a 30% hallucination rate.
- **The study looks like a vendor ad.** Comment 50180600, 50181429: the company
  markets "westernized" safer models, so the result is an ad for its own product.
- **Weak statistics.** Comment 50180625: significance is p=0.03, with multiple
  prompts tested, which is weak for a claim this broad.
- **Independent replication found nothing systematic.** Comment 50180762: across
  6,237 generated programs, exactly 10 failed a security check, scattered with no
  pattern by country or customer.
- **It is not a "backdoor".** Comment 50180564: no evidence of intent, no
  attacker-controlled access; it is degraded quality, not a backdoor.

The credible general principle (comment 50182097, "emergent misalignment"):
narrow alignment training can degrade a model broadly when a trigger appears in
context. This is a real, documented LLM behaviour, not specific to one vendor.

## Cross-validation against the fleet

The study names exactly one model: **`Qwen3-Coder-30B-A3B-Instruct`**. The fleet
serves it as `qwen3-coder-30b-a3b` (alias `code-std-fast-alt`).

No other served model matches the study's profile (old Qwen3, non-reasoning,
code). The rest of the fleet is either newer Qwen reasoning models or
non-Qwen models.

Two facts, separate from the security claim, already argue for removal:

1. It is **superseded**: `north-mini-code-1.0` (CohereLabs, 2026-06) is the
   `code-std-fast` primary and is faster (18 vs 9.1 tok/s).
2. It is **weak by the thread's own numbers** (80% hallucination, non-reasoning).

## Recommendation 1 — deregister and clean up

| model | id / alias | size | reason |
|---|---|---|---|
| `qwen3-coder-30b-a3b` | `code-std-fast-alt` | 18.5 GB | the exact model in the study; old, non-reasoning, 80% hallucination; superseded by `north-mini-code-1.0` |
| `qwq-32b` | not registered | 19.8 GB | old (2025-03) dense reasoner, superseded, known language-mixing; already measured-not-registered, so this is file cleanup only |

Optional, in the `llm-small` boot entry only (not currently served by
`llms-frontier`): `qwen3-30b-a3b` (Qwen3, 2025) and `qwen3-coder-next` (2026-01)
are older-generation Qwen. They are not running, so no urgency; revisit if
`llm-small` is used for security-sensitive code.

**Cleanup commands (on brys):**

```
rm /var/lib/kdn/llms/models/surveyed/qwen3-coder-30b-a3b.gguf   # 18.5 GB
rm /var/lib/kdn/llms/models/surveyed/qwq-32b.gguf               # 19.8 GB
```

Remove the `qwen3-coder-30b-a3b` model entry and its `code-std-fast-alt` alias
from `hosts/brys/llm-routers.nix`, then redeploy.

## Recommendation 2 — dependable Qwen and specialized models

Ranked by generation and capability. The newest reasoning-capable models are the
most dependable; the thread's own numbers support this (`Qwen3.8-27B` AA 34,
30% hallucination, versus the flagged model's AA 10, 80%).

**Qwen general (dependable):**

| model | release | note |
|---|---|---|
| `qwen3.8-flash-next` | 2026-08 | newest; frontier orchestrator; vision; 1M ctx |
| `qwen3.8-27b` | 2026-08 | newest mid; vision; reasoning; the thread's recommended upgrade |
| `qwen3.6-35b-a3b` | 2026-04 | fast MoE generalist |
| `qwen3.6-27b` | 2026-04 | proven daily driver |
| `qwen3.5-35b-a3b` | 2026-02 | fast MoE generalist |
| `qwen3.5-4b` / `-2b` / `-0.8b` | 2026-02 | small grunts |

**Qwen specialized (dependable):**

| model | release | note |
|---|---|---|
| `qwen3-vl-30b-a3b` | 2025-10 | vision, MoE, fast; current VL line |
| `qwen3-vl-8b-instruct` | 2025-10 | small vision |
| `qwen3-omni-30b-a3b` | 2025-09 | audio + vision + text |
| `qwen3-embedding-4b` | 2025-05 | retrieval; no code generation |
| `qwen3-reranker-4b` | 2025-06 | reranking; no code generation |

The specialized models are not code generators, so the study's specific claim
does not apply to them. They are older than Qwen3.5/3.6 but are the current
members of their lines.

**For code specifically (sidestep the concern entirely):** prefer the non-Qwen
code models, which carry no CCP-alignment training:

| model | vendor | note |
|---|---|---|
| `north-mini-code-1.0` | CohereLabs (Canada) | `code-std-fast`; 18 tok/s |
| `mellum-2.1-12b-a2.5b-thinking` | JetBrains (Czech) | `reason-quick-fast`; code-tuned |
| `tiel-coder-35b-a3b` | community | measured, not registered |

## Confidence

The specific security claim is **weak**: one vendor study, p=0.03, a
cherry-picked old model, and an independent replication that found no pattern.
Do not treat it as proof that Qwen models are backdoored.

The practical conclusion is **strong** for a different reason: the flagged model
is outdated and weak on its own merits, and it is already superseded. Removing it
costs nothing and removes the only fleet member the study names.

## See also

- [popularity-sweep/measured.research.md](popularity-sweep/measured.research.md)
- [qwen-specialized-measured.research.md](qwen-specialized-measured.research.md)
- [model-selection-guide.md](model-selection-guide.md)
- [alias-scheme.design.md](alias-scheme.design.md)
