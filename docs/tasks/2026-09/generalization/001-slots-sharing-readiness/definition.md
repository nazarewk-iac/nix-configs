---
type: Task
description: Make modules/slots consumable by an external adopter today; the pre-push remote guard is already repaired, so a fork audit stays the real content gate.
status: open
authored_by: agent
timestamp: 2026-09-08T17:30:00+02:00
---

# 001 — readiness to share slots

Hub: [../generalization-plan.md](../definition.md). This is checkpoint 001, the head of
the first commit chain. Do not push.

Goal: an external adopter consumes `modules/slots` today. The leak bug is already fixed; item 1
records the state and the limit that remains.

## 1. P0 — the remote guard is repaired; the hook stays one net, not the gate

**Status: fixed in the tree.** Commit `e710bc92` ("fix(slots/jj): guard the public remote and
check diff content, not only paths", 2026-09-09) rewrote `modules/slots/jj/pre-push.sh` and
`modules/slots/jj/fork/check-fork-contamination.sh`. Every line number below is measured against
the current tree on 2026-09-10.

The guard direction is now correct. `pre-push.sh:92-95` returns early **only** for the private
fork remote, so every other remote runs the content checks:

```bash
  # The private fork remote may receive private content. Every other remote may not.
  if [ -n "$push_remote" ] && [ "$push_remote" = "$PRIVATE_REMOTE" ]; then
    return 0
  fi
```

That matches the option text, which is unchanged: `modules/slots/jj/default.nix:55` and `:66` both
read "blocked from pushing to non-fork remotes".

### What the fix covers

| Old defect | Where it is fixed now |
|---|---|
| Inverted remote comparison | `pre-push.sh:92-95` — the private remote is the only exemption |
| `push_remote` resolved to the literal `refs` | `:23` reads `$1`, then `PRE_COMMIT_REMOTE_NAME`; `:24-32` match the remote URL as a last resort; `:21-22` record the trap |
| Empty pattern list passed in silence | `:49-58` fail loudly, with a `KDN_JJ_PRE_PUSH_ALLOW_EMPTY=1` escape hatch |
| Empty stdin skipped the whole loop | `:136-152` fail closed for a public remote, pass for the private one, and accept a named `KDN_JJ_PRE_PUSH_RANGE` |
| The file check ignored the computed range | `check_range` at `:77-116` takes revision arguments; `:126-133` build them per ref |
| A new ref used `main..$local_sha`, empty when the branch **is** `main` | `:132` uses `--not --remotes=` instead |
| A path check could not see a private string in a public file | `:107-114` grep the diff content too |
| `grep -q` plus `pipefail` read a match as "no match" | `:60-68` never pass `-q` |

The two known limits are written into the script header at `:11-17`.

### The limit that still holds

**`jj git push` fires no git hook.** The hook runs only on a real `git push`. In this repo the one
alias that uses raw git for the public push is `jj sync-upstream`
(`modules/slots/jj/fork/default.nix:225`). Every other push goes through `jj git push` and reaches
no hook. So `jj fork-audit` is the content gate, and `hack/flake-update-complete.sh` is the
structural gate. `modules/slots/jj/default.nix:57-59` and `:68-70` state this in the option docs.

The same limit keeps `modules/slots/jj/fork/check-fork-contamination.sh` inert as a hook: it
installs at the `pre-commit` stage (`modules/slots/jj/fork/default.nix:247-252`), and jj fires no
`pre-commit` hook either. It is useful only when it runs by hand or through `jj fork-audit`.

### Tests — landed

`checks/jj-experiments/test_prepush.py` holds 15 cases (lines 109-294). They cover the public
block on a path, on a message and on a diff line, the private-remote pass, the always-blocked
message on both remotes, the loud failure and the escape hatch for an empty pattern list, an
unknown remote treated as public, the no-stdin fail-closed and private-pass paths, the named
range, and the new-ref and delete-only pushes.

### Remaining work for this checkpoint

A wrapper that checks before it pushes, so a `jj git push` cannot bypass the content check. jj
offers no hook mechanism, so the check must live in a jj alias. Until then, run `jj fork-audit`
before any push.

Cross-reference: [fork-contribution-access-tiers.research.md](../../fork-contribution-access-tiers/research.md)
§ A5 and [flake-update-procedure-gaps.research.md](../../flake-update-procedure-gaps/research.md) § O18.

## 2. Document the overlay requirement

An adopter must add `overlays = [ inputs.nix-configs.overlays.packages ]`. Nothing says so today.
7 slots need it because they use `pkgs.kdn.*`: `kdn-ssh-access`, `opencode-compat-proxy`,
`mcpsnoop`, `basic-memory`, `zellij-llm`, `kdn-slug`, `jj-mcp`.

## 3. Adopter entry point

Create a template at `templates/adopter/` with `devenv.yaml` and `devenv.nix`.

Requirements:

- It states the overlay requirement from item 2.
- It does **not** pin the adopter's nixpkgs to the creator's nixpkgs fork. Today `devenv.yaml`
  uses `follows: nix-configs/nixpkgs`, and this repo's nixpkgs is the creator's own fork.
- It enables one small slot as a worked example.
- It calls `mkSlots` directly. That is the supported adopter API — see the note below.

`checks/jj-experiments/devenv.nix` is the precedent for standalone slots consumption from a
subdirectory. Reuse its shape:

```nix
mkSlots = inputs.nix-configs.lib.kdn.mkSlots;
slotsPath = inputs.nix-configs + "/modules/slots";
```

> **A call to `mkSlots` is fine.** The adopter API is not "plain modules". The requirement is that
> a slot does not depend on the other module types. Do not extract slots into plain modules for
> the sake of it.

## 4. Adopter-facing doc

Create `docs/slots-for-adopters.md`, `type: How-To`. Cover:

- what a slot is, and the 5 targets (`nixos`, `darwin`, `home`, `devenv`, `users`);
- how to call `mkSlots` and enable a slot;
- the overlay requirement;
- **what each slot writes into the adopter repo.** State plainly that `kdn.jj` installs the
  creator's jj-only mandate as an agent rule. Also state that 5 slots read repo content through
  `${inputs.nix-configs}/.agents/…` (`jj`, `jj/fork`, `nix`, `zellij`, `mcp/basic-memory`).

Link to `modules/slots/README.md` and `.agents/rules/slots-standalone.md`. Do not duplicate them.
Do not duplicate [slots-modules-architecture.md](../../../2026-08/slots-modules-architecture/definition.md), which is in
progress and covers which architecture rules apply to slots.

## 5. Enforce the standalone rule in CI — **done**

`checks/standalone.nix` holds the gate. `checks/default.nix:49` imports it and `:63` merges its
outputs, so `nix flake check` runs it. It exports two checks: `standalone-slots` and
`standalone-aspects`.

`standalone-slots` asserts two things:

| Assertion | Mechanism |
|---|---|
| No slot names a universal option, a meta option, or `kdnConfig` | a source scan of every `.nix` file under `modules/slots/`, over 31 needles |
| The whole slots tree resolves with `pkgs` and `inputs` alone | one `mkSlots` render; the target key set must equal the six known targets |

Measured on 2026-09-11:

* `nix eval --no-eval-cache '.#checks.aarch64-darwin' --apply builtins.attrNames` lists both
  checks.
* The `standalone-slots` build script reads
  `standalone slots: 2 of 2 assertions pass`.
* A shell replica of the scan finds **zero** violations across the 19 slot files.

So the check needs **no allowlist for a slot**. `checks/standalone.nix:232` allowlists exactly
one aspect `enable` option, and that entry is a debt of the aspect tree, not of the slots tree.

Two known limits stay: the scan cannot see a computed option path, and it flags a rule name in a
trailing comment as a false positive. `checks/standalone.nix:8-24` records both.

## 6. One-line input hygiene

`flake.nix:25-26` on the public branch pins
`git+ssh://git@github.com/browsers-software/homebrew-tap`. Change it to
`github:Browsers-software/homebrew-tap`.

Verified without authentication: the repo reports `"private": false` and `"visibility": "public"`,
and `git ls-remote https://github.com/browsers-software/homebrew-tap HEAD` succeeds with no SSH
key.

This is **hygiene, not a blocker** — see correction 1 in the hub. An adopter never references this
input, so Lix never fetches it. It is the only `ssh://` input on the public branch. The others
belong to the private chain. Do not name them in any deliverable.

## Exit criteria

- The new `checks/jj-experiments` cases pass.
- `nix flake check` passes.
- The standalone check from item 5 passes for all 20 slots.
- Pattern V3: a scratch flake under `/tmp`, outside this repo, consumes the template and
  evaluates.
- Pattern V2: the same evaluation succeeds with no SSH agent.

## Out of scope

Do not rename `kdn.*`. Do not move `kdn-graph.nix` (that is 009). Do not change the distribution
shape (that is 010). Do not lift personal defaults out of slot options (that is 007).
