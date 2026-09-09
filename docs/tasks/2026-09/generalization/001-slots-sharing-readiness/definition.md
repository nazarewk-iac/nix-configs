---
type: Task
description: Make modules/slots consumable by an external adopter today, and fix the inverted pre-push guard that permits private content to the public remote.
status: open
authored_by: agent
timestamp: 2026-09-08T17:30:00+02:00
---

# 001 — readiness to share slots

Hub: [../generalization-plan.md](../definition.md). This is checkpoint 001, the head of
the first commit chain. Do not push.

Goal: an external adopter consumes `modules/slots` today. Fix the one bug that leaks private
content.

## 1. P0 — fix the inverted remote guard

**File:** `modules/slots/jj/pre-push.sh`

The guard at lines 64-67 skips the denied-file and denied-message checks for every remote
**except** the private fork:

```bash
  # Remote protection: only applies when pushing to the private fork remote
  if test "$push_remote" != "$PRIVATE_REMOTE"; then
    continue
  fi
```

`PRIVATE_REMOTE` is `cfg.fork.remote` (`modules/slots/jj/fork/default.nix:23`). The option docs
say the opposite — `modules/slots/jj/default.nix:54` and `:59` both read "blocked from pushing to
**non-fork** remotes". So the hook blocks private content to the private fork, and permits it to
the public remote.

**Verified.** Take a throwaway repo with `PRIVATE_REMOTE=<fork>`, and a commit that adds a path
that matches a denied pattern. Current code pushes to the public remote with exit **0** (allowed).
With an inverted comparison: public exits **1** (blocked), fork exits **0** (allowed).

Fix the comparison. Correct the comment to match the option docs.

### Two more defects in the same script — fix both

1. **Line 69 ignores the computed range.** It passes `"$remote_sha" "$local_sha"` to `git diff`
   instead of the `$range` from lines 47-52. A new branch has a zero remote sha, which `git diff`
   rejects. The message check at line 81 uses `$range` correctly. The file check does not. Use
   `git diff --name-only "$range"`.
2. **An empty pattern list disables the check silently.** Lines 27-40 build
   `file_grep_args=(-q -i)` with no `-e` argument when the pattern list is empty. `grep` then
   exits 2. The `if` at line 69 reads that as "no match", so the check **passes**. Patterns come
   from the git-ignored `devenv.slots.local.nix`, so an absent local file turns protection off
   with no warning. Guard on the array length instead, and fail loudly.

### Read this before you fix the comparison — the guard is inert three ways over

Measured on 2026-09-09 in throwaway repos under `/tmp`, with an isolated `HOME`, `JJ_CONFIG`, and
`GIT_CONFIG_GLOBAL=/dev/null`. jj 0.44.0, prek 0.5.2. Each finding is **verified**, and each one
alone is enough to make the hook pass everything. So the inverted comparison at lines 64-67 is
**not** the reason private content reaches the public remote. It is the third reason.

**Defect A — `jj` fires no git hook.** A colocated repo held an executable `.git/hooks/pre-push`
that printed a marker and exited 1.

| Command | Hook ran | Exit | Result |
|---|---|---|---|
| `jj git push --remote=origin --bookmark=main` | **no** | 0 | the remote gained the ref |
| `git push origin main` (control) | **yes** | 1 | git refused the push |
| `jj commit -m …` | **no** | 0 | jj created the commit |

This repo pushes with `jj git push` everywhere except one line
(`modules/slots/jj/fork/default.nix:193`, the public push, which uses raw `git push`). So the only
push that reaches the hook is the public one — the exact push that lines 64-67 then skip.

It also makes `modules/slots/jj/fork/check-fork-contamination.sh` **dead code**: it is the only
content-aware check in the repo, and `fork/default.nix:217` installs it at the `pre-commit` stage,
which jj never fires.

**Defect B — prek hands the hook no stdin, so the loop body never runs.** Both hooks install
through devenv `git-hooks`, which is **prek**, not python pre-commit (`.git/hooks/pre-push` names
`prek-0.5.2`). A probe hook at the `pre-push` stage with `pass_filenames = false` received:

```
argc=0  argv=[]
PRE_COMMIT_REMOTE_NAME=origin
PRE_COMMIT_REMOTE_BRANCH=refs/heads/main
--- stdin ---            (empty)
```

Control, a **native** `.git/hooks/pre-push` on the same push:

```
argc=2  argv=[origin <url>]
--- stdin ---
refs/heads/main <local_sha> refs/heads/main 0000000000000000000000000000000000000000
```

prek parses the ref lines itself (it sets `PRE_COMMIT_TO_REF`) and forwards none of them.
`pre-push.sh:42` reads its ref lines from stdin:

```bash
while read -r _local_ref local_sha remote_ref remote_sha; do
```

With no stdin the loop iterates **zero** times. So every check inside it never runs, including the
always-on blocked-message check at lines 54-62. The hook always exits 0.

**Defect C — `push_remote` never holds a remote name.** `argc=0` means `$1` is empty, so line 10
falls back to `${PRE_COMMIT_REMOTE_BRANCH%%/*}`. Measured, that expands `refs/heads/main` to
**`refs`**. The variable that does hold the remote name is `PRE_COMMIT_REMOTE_NAME`, and the script
never reads it. So `push_remote` is `refs` on every push, and the comparison at line 65 is never
equal — even for the private fork.

**What this means for the fix.** Correct all four, in this order:

1. Read the remote name from `PRE_COMMIT_REMOTE_NAME`, with `$1` as the fallback (defect C).
2. Take the ref range from `PRE_COMMIT_FROM_REF`/`PRE_COMMIT_TO_REF` when stdin is empty, or fail
   loudly on an empty stdin. Never treat empty stdin as "nothing to check" (defect B).
3. Invert the comparison at lines 64-67, and correct the comment (the original P0).
4. Move the guard out of `.git/hooks/` for jj-driven pushes (defect A). jj offers no hook
   mechanism, so the check must run inside a wrapper — a jj alias that checks, then pushes.
   Without this, every `jj git push` stays unchecked whatever else you fix.

Cross-reference: [fork-contribution-access-tiers.research.md](../../fork-contribution-access-tiers/research.md)
§ A5 and [flake-update-procedure-gaps.research.md](../../flake-update-procedure-gaps/research.md) § O18.

### Record, do not fix

For a new branch the range is `main..$local_sha` (line 49), which is empty when that branch **is**
`main`. Note it in the script as a known limitation.

### Tests

Add cases to `checks/jj-experiments`:

| Case | Expected |
|---|---|
| public remote + file that matches a denied pattern | blocked |
| fork remote + file that matches a denied pattern | permitted |
| commit message that matches an always-blocked pattern | blocked on both remotes |
| empty pattern list | loud failure, not a silent pass |
| new branch with a zero remote sha | no `git diff` error |
| hook invoked through prek, with no stdin | loud failure, not a silent pass (defect B) |
| `push_remote` resolved from a prek environment | the real remote name, never `refs` (defect C) |
| push through `jj git push` | the wrapper runs the check (defect A) |

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
Do not duplicate [slots-modules-architecture.md](../../../slots-modules-architecture.md), which is in
progress and covers which architecture rules apply to slots.

## 5. Enforce the standalone rule in CI

`.agents/rules/slots-standalone.md` states that a slot must not reference or assign any
`modules/universal` or `modules/meta` option. Nothing enforces it. `checks/` holds only a jj
pytest suite.

Add a check that each slot evaluates on its own and references no universal or meta option.

## 6. One-line input hygiene

`flake.nix:14` on the public branch pins
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
