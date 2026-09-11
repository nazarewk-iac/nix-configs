---
type: Task
status: done
solution: done.md
description: Assertion 7 of the fork update completion check called every new public lock node private, so it failed on any public input addition.
timestamp: 2026-09-12T01:00:00Z
authored_by: agent
---

# `flake-update-complete.sh` assertion 7 uses the wrong baseline

## Symptom

`hack/flake-update-complete.sh` exits 1 with two failures, and no leak is present:

```
FAIL  flake.lock on the upstream tip holds no fork-only node (2 found)
FAIL  devenv.lock on the upstream tip holds no fork-only node (2 found)
```

The two nodes are `den` and `nix-effects`. The public `flake.nix` declares both. They are public.

## Cause

Assertion 7 computed:

```
flagged = keys(upstream-tip lock) ∩ ( keys(fork-tip lock) − keys(already-pushed public lock) )
```

The right-hand set is **"new since the last public push"**, not **"private"**. The two coincide
only while nobody adds a public input. So the assertion fails on every public input addition.

The den port added two public inputs, so the assertion started to fail.

## Requirement

Assertion 7 must take its baseline from what the public flake **declares**, not from the last
public push. A new public input must pass. A private input must still fail.
