---
type: Task
description: Make modules/slots consumable by an external adopter today, and fix the inverted pre-push guard that permits private content to the public remote.
status: open
authored_by: agent
timestamp: 2026-09-08T17:30:00+02:00
---

# 001 — slots sharing readiness

Hub: [../generalization-plan.md](../definition.md). This is checkpoint 001, the head of
the first commit chain. Do not push.

Goal: an external adopter consumes `modules/slots` today, and the one bug that leaks private
content is fixed.

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
**non-fork** remotes". So private content is blocked from the private fork and permitted to the
public remote.

**Verified.** In a throwaway repo with `PRIVATE_REMOTE=<fork>` and a commit that adds a path
matching a denied pattern: current code pushes to the public remote with exit **0** (allowed).
With the comparison inverted: public exits **1** (blocked), fork exits **0** (allowed).

Fix the comparison, and correct the comment to match the option docs.

### Two more defects in the same script — fix both

1. **Line 69 ignores the computed range.** It passes `"$remote_sha" "$local_sha"` to `git diff`
   instead of the `$range` built at lines 47-52. A new branch has a zero remote sha, which
   `git diff` rejects. The message check at line 81 uses `$range` correctly; the file check does
   not. Use `git diff --name-only "$range"`.
2. **An empty pattern list disables the check silently.** Lines 27-40 build
   `file_grep_args=(-q -i)` with no `-e` argument when the pattern list is empty. `grep` then
   exits 2, and the `if` at line 69 reads that as "no match", so the check **passes**. Patterns
   come from the git-ignored `devenv.slots.local.nix`, so a missing local file turns protection
   off with no warning. Guard on array length and fail loudly instead.

### Record, do not fix

For a new branch the range is `main..$local_sha` (line 49), which is empty when the pushed branch
**is** `main`. Note it in the script as a known limitation.

### Tests

Add cases to `checks/jj-experiments`:

| Case | Expected |
|---|---|
| public remote + file matching a denied pattern | blocked |
| fork remote + file matching a denied pattern | permitted |
| commit message matching an always-blocked pattern | blocked on both remotes |
| empty pattern list | loud failure, not a silent pass |
| new branch with a zero remote sha | no `git diff` error |

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

`checks/jj-experiments/devenv.nix` is the working precedent for standalone slots consumption from
a subdirectory. Reuse its shape:

```nix
mkSlots = inputs.nix-configs.lib.kdn.mkSlots;
slotsPath = inputs.nix-configs + "/modules/slots";
```

> **Calling `mkSlots` is fine.** The adopter API is not "plain modules". The requirement is that a
> slot does not depend on the other module types. Do not extract slots into plain modules for the
> sake of it.

## 4. Adopter-facing doc

Create `docs/slots-for-adopters.md`, `type: How-To`. Cover:

- what a slot is, and the 5 targets (`nixos`, `darwin`, `home`, `devenv`, `users`);
- how to call `mkSlots` and enable a slot;
- the overlay requirement;
- **what each slot writes into the adopter repo.** State plainly that `kdn.jj` installs the
  creator's jj-only mandate as an agent rule, and that 5 slots read repo content through
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
input, so Lix never fetches it. It is the only `ssh://` input on the public branch; the others
belong to the private chain and must not be named in any deliverable.

## Exit criteria

- The new `checks/jj-experiments` cases pass.
- `nix flake check` passes.
- The standalone check from item 5 passes for all 20 slots.
- Pattern V3: a scratch flake under `/tmp`, outside this repo, consumes the template and
  evaluates.
- Pattern V2: the same evaluation succeeds with no SSH agent.

## Out of scope

Renaming `kdn.*`. Moving `kdn-graph.nix` (that is 009). Changing the distribution shape (that is
010). Lifting personal defaults out of slot options (that is 007).
