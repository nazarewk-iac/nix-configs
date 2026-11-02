---
type: Research
description: Proof that the programmatic context gate rejects an oversized delegation in code, with the exact command and real output.
task: definition.md
authored_by: agent
timestamp: 2026-11-01T22:30:00+01:00
---

# Proof: the context gate rejects, in code

This is the one mechanism that would have prevented the 2 h 24 min incident in session `01a19840`,
where a 479 104-byte transcript was delegated twice to `code-std-fast` (32 768 served context) and
returned empty both times, 25 minutes apart.

## The command

```bash
PI=$(nix build --no-link --print-out-paths --impure --expr '….#pi-coding-agent')/bin/pi
printf '%s' "Call measure with path $OLD. Then report its output verbatim, nothing else." \
  | pi --mode json -p --provider brys --model chat-std-fast --thinking off \
       --no-context-files --no-skills \
       --extension <pi-orchestrator-gate> -t measure
```

The file is the real failing transcript:

```
/home/kdn/.pi/agent/sessions/--home-kdn-dev-github.com-nazarewk-iac-nix-configs--/2026-10-31T20-31-47-192Z_01a193a9-…jsonl
```

## The output, verbatim from the tool result

```
bytes=479104 lines=130 model=brys/code-std-fast
fits: NO. input is ~119776 tokens (479104 bytes at 4 B/token), but code-std-fast serves 32768
tokens, and the safe budget is 24576.
fitting aliases: orchestrate-deep-slow (1048576), qwen (1048576), qwen3.8-flash-next (1048576)
```

## What this proves, and what it does not

**Proves:**

- the tool schema reaches the model (`measure` appears in the request's tool list);
- the model called it with a real path;
- the size was measured from disk (`bytes`, `lines`);
- the served context was read from the live fleet, not hard-coded — 32 768 for `code-std-fast`,
  1 048 576 for the frontier, matching `/v1/models`;
- the verdict is emitted **by code**, so it cannot be talked out of.

**Does not prove:** that the orchestrator will always obey. The gate must be called. Making it
unskippable is Part 1's remaining work: `delegate` itself should refuse an oversized `inputBytes`,
so the check cannot be bypassed by an agent that forgets to measure first.

## Degradation path (by design)

When `brys` is unreachable the check returns `fits: UNKNOWN (fleet unreachable; allowed rather than
blocking)`. A network fault must never stop work; the cost is a blind delegation, which is the
status quo everywhere else.
