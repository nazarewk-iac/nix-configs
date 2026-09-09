---
type: Research
description: Lix-verified answers to Q1-Q4 on flake input overhead, with a ranked list of techniques for this repo's cost and an adopter's cost.
authored_by: agent
timestamp: 2026-09-09T12:00:00+02:00
---

# 010 — flake input overhead: research

Task: [generalization-010-flake-input-overhead.md](definition.md).
Hub: [../generalization-plan.md](../definition.md).

## Verdict

**Very little helps.** The adopter cost is already near the floor. A fresh adopter pays one
4.1 MB tree fetch and 54 841 bytes of lock text. The first lock run takes 1.2 s. A read of
`lib.kdn` plus the package overlay takes 0.14 s. Lix fetches zero of the other 100 lock nodes.

Exactly one measurable defect exists, and one line causes it. `flake.nix:7`
(`inputs.nixpkgs-lib.follows = "nixpkgs";`) puts a `follows` entry on the `nix-configs` node of
every adopter lock. That entry sets `mustRefetch` on every later lock run. So Lix fetches the whole
4.1 MB tree again each time. A four-line edit removes the defect. Measured: the extra tree fetch
disappears.

The `?dir=` subflake works on Lix today. It cuts an adopter lock from 101 nodes to about 4. It is a
real option, not a blocked one. It is also a rare pattern, and it needs a second lock file. The
root `nix flake check` and `nix flake update` do not cover it. Do the four-line edit first. Hold
the subflake until an adopter complains about lock text.

## Environment

| Item | Value |
|---|---|
| Evaluator | Lix 2.95.2, aarch64-darwin, `experimental-features = flakes nix-command` |
| Lix source | `/nix/store/nyiq27r0br3xrgsa2pdq0vali48b7xpp-source` (the `src` of the `lix-2.95.2` derivation in use) |
| devenv | 2.2.3+ffb790f |
| Public root lock | 101 nodes, 55 root inputs, 54 841 bytes |
| Scratch flakes | all under `/tmp/gen010/`, never inside this repo |

Every measurement below comes from plain Lix. The one exception is the devenv paragraph in Q2,
which names devenv explicitly.

Adopter tests run under Pattern V2 (no SSH agent, no usable key):

```bash
SSH_AUTH_SOCK= GIT_SSH_COMMAND='ssh -o BatchMode=yes -o IdentitiesOnly=yes -o IdentityFile=/dev/null' \
  nix flake lock --debug
```

The debug line `got tree '%s' from '%s'` marks each call to `fetchOrSubstituteTree`. It is the
reliable counter for a tree fetch. The counter `keeping existing input` marks a lock node that Lix
copies with no tree fetch.

## Q1 — do `follows` stanzas prevent lazy resolution? — **confirmed**

### The code path

`computeLocks` starts at `flake.cc:799-806` with `trustLock = false`:

```cpp
computeLocks(
    flake.inputs,
    newLockFile.root,
    {},
    lockFlags.recreateLockFile ? nullptr : oldLockFile.root.get_ptr(),
    {},
    parentPath,
    false);
```

For each input, `flake.cc:656-658` selects the lazy branch:

```cpp
if (oldLock
    && oldLock->originalRef == *input.ref
    && !hasOverride)
{
    debug("keeping existing input '%s'", inputPathS);
```

The lazy branch builds `fakeInputs` from the old lock instead of a tree fetch
(`flake.cc:681-691`). One check can break it. `flake.cc:692-707`:

```cpp
} else if (auto follows = std::get_if<1>(&i.second)) {
    if (!trustLock) {
        // It is possible that the flake has changed,
        // so we must confirm all the follows that are in the lock file are also in the flake.
        auto overridePath(inputPath);
        overridePath.push_back(i.first);
        auto o = overrides.find(overridePath);
        // If the override disappeared, we have to refetch the flake,
        // since some of the inputs may not be present in the lock file.
        if (o == overrides.end()) {
            mustRefetch = true;
```

So a `follows` entry **in the lock node of a direct input** forces a tree fetch. The one escape:
the parent `flake.nix` still declares the same override. `flake.cc:717-721` then passes
`trustLock = !mustRefetch` down. One clean level switches the check off for every level below it.
That is why the effect stops at depth 1 and never cascades.

`updateOverrides` (`flake.cc:502-505`) records an override only when the stanza carries a `ref` or
a `follows`. A nested stanza that carries neither adds no override, and needs none.

### Case (a) — a `follows` in this repo's own `flake.nix`

**No fetch of the followed input. One extra fetch of this repo's own tree, on every lock run after
the first.**

`flake.nix:7` is the only root-level `follows` in the public tree:

```nix
inputs.nixpkgs-lib.follows = "nixpkgs";
```

An adopter lock stores it on the `nix-configs` node as
`"nixpkgs-lib": ["nix-configs","nixpkgs"]`. Measured, with
`inputs.nix-configs.url = "github:nazarewk-iac/nix-configs"`:

| Run | `got tree` calls | `keeping existing input` | `creating new input` | Wall time |
|---|---|---|---|---|
| First lock | 3 (own path input twice, `nix-configs` once) | 100 | 1 | 1.2 s |
| Re-lock, no edit | 2 (own path input, `nix-configs`) | 101 | 0 | 0.15 s |

The re-lock fetch of `github:nazarewk-iac/nix-configs/918fd52…` is `mustRefetch` at work. Proof
that the one `follows` entry causes it: delete only that entry from the lock, then re-lock. The
`got tree` count drops from 2 to 1, and the lock stays at 102 nodes.

```bash
jq 'del(.nodes["nix-configs"].inputs["nixpkgs-lib"])' flake.lock > new && mv new flake.lock
nix flake lock --debug 2>&1 | grep 'got tree'   # only the adopter's own path input
```

A controlled pair confirms the mechanism in isolation. `libA` declares a root-level `follows`.
`libB` is identical, with no such stanza. An adopter of `libA` fetches the `libA` tree on every
re-lock. An adopter of `libB` fetches nothing:

```
adA RE-lock:  keeping existing input 'lib'
              got tree '…' from 'git+file:///…/libA?…rev=5b2382e…'
adB RE-lock:  keeping existing input 'lib'
              (no got tree)
```

Cost size: the fetch hits Lix's fetcher cache when the rev is present, so a warm machine pays
milliseconds. A cold machine pays a real network fetch of the whole 4.1 MB tree, once per lock
run.

### Case (b) — a `follows` or `--override-input` from the adopter

**A `follows` override fetches nothing. A URL override fetches its own target, on every lock
run.**

`flake.cc:633-641` returns early for any `follows`, before the `assert(input.ref)` and before any
fetch:

```cpp
if (input.follows) {
    InputPath target;
    target.insert(target.end(), input.follows->begin(), input.follows->end());
    debug("input '%s' follows '%s'", inputPathS, printInputPath(target));
    node->inputs.insert_or_assign(id, target);
    continue;
}
```

Measured with `inputs.lib.inputs.dnp.follows = "mynp";`:

```
creating new input 'lib'            -> got tree (the library itself, needed anyway)
keeping existing input 'lib/d1'
keeping existing input 'lib/d2'
creating new input 'mynp'           -> got tree (the adopter's own input)
```

The overridden `dnp` node never appears and never fetches. The lock holds `d1 d2 lib mynp root`.
The re-lock fetches nothing at all. The reason: the adopter's own `flake.nix` supplies the
override that the `!trustLock` check needs.

A URL override behaves differently. `hasOverride` blocks the lazy branch permanently
(`flake.cc:658`). So `creating new input 'lib/dnp'` and its tree fetch repeat on the first lock
run **and on every re-lock**. Measured with `inputs.lib.inputs.dnp.url = "git+file://…/d2";`.

### Lock drift — the one path to an SSH error

**Confirmed.** Remove a `follows` from `flake.nix` and keep the lock. The override disappears, the
`!trustLock` check fails, and Lix fetches the input tree again:

```
keeping existing input 'd1'
got tree '…' from 'git+file:///…/d1?…rev=d33bd5c…'    <- mustRefetch
creating new input 'd1/dnp'
got tree '…' from 'git+file:///…/dnp?…rev=20f724c…'
```

The public lock holds one node with an `ssh://` git URL
(`brew-tap--browsers-software--homebrew-tap`). A drift that touches such a node hands the adopter
an SSH failure. With the lock and `flake.nix` in agreement, no adopter run needs SSH. The Pattern
V2 first lock above exits 0 and never contacts an SSH host.

### Is the node a lazy thunk at eval time?

**Yes.** `call-flake.nix:7-15` wraps `fetchTree` in `builtins.mapAttrs`, so each node is a lazy
attribute:

```nix
allNodes = builtins.mapAttrs (
  key: node:
  let
    sourceInfo =
      if key == lockFile.root then
        rootSrc
      else
        fetchTree (node.info or { } // removeAttrs node.locked [ "dir" ]);
```

Measured on the real repo. An adopter reads `nix-configs.lib.kdn`, applies
`nix-configs.overlays.packages`, and counts the 46 `pkgs.kdn.*` packages. That makes exactly **2**
`got tree` calls — its own path input and the `nix-configs` tree. Time: 0.14 s. Lix fetches none of
the other 100 nodes.

### Correction to the task's known partial answer

010 states that case (b) forces a fetch, because an override takes the "creating new input"
branch. That holds only for a **URL** override or `--override-input`. A `follows` override returns
early at `flake.cc:633-641` and fetches nothing. Case (a), not case (b), is the one that costs an
extra tree fetch.

## Q2 — relative paths and `git+file:` purity — **confirmed**

| Input URL in a plain `flake.nix` | Result on Lix 2.95.2 |
|---|---|
| `git+file:.` (inside its own git repo) | fails — `error: found circular import of flake 'git+file:.'` |
| `git+file:.` (plain directory, no git) | fails — `error: program 'git' failed with exit code 128` |
| `git+file:../target` | **locks and evaluates**, but points at the process cwd |
| `git+file://<absolute>/target` | works (the control) |
| `path:./inner` (inside the flake's own tree) | works |
| `path:../target` (plain directory parent) | fails — `relative path '../target' points outside of its parent's store path '/nix/store/…-source'` |
| `path:../target` (git repo parent) | fails — same error |
| `path:../../../target` | fails — same error |

Two findings need care.

**`git+file:` with a relative path is not a solution, even though it locks.** The lock records
`"url": "file:../target"`. Lix interprets that string against the **process cwd**, not the flake
root. A lock run from `/tmp` fails with `program 'git' failed with exit code 128`. The same run
from the flake's own directory succeeds. A downstream consumer breaks as soon as its store lacks
the tree. Proof, against a fresh chroot store:

```
… while fetching the input 'git+file://file:../tgt2?ref=refs/heads/master&rev=732d72c…'
error: program 'git' failed with exit code 128
```

The mangled `git+file://file:../tgt2` shows that the relative URL does not round-trip through the
lock. A warm store hides the fault, because `fetchOrSubstituteTree` accepts a store path that
already matches the recorded narHash (`flake.cc:74`).

**`path:` with a relative path can never leave the flake's own tree.** The guard is
`path.cc:126-129` inside `PathInputScheme::fetch`:

```cpp
// for security, ensure that if the parent is a store path, it's inside it
if (store->isInStore(parent)) {
    auto storePath = store->printStorePath(store->toStorePath(parent).first);
    if (!isDirOrInDir(absPath, storePath))
        throw BadStorePath("relative path '%s' points outside of its parent's store path '%s'", path, storePath);
```

Lix copies every flake source into the store first. So the parent is always a store path, and
`../` always leaves it. `path:./inner` stays inside and works.

### Why this repo's devenv inputs work

devenv 2.2.3 does not use Lix's `call-flake.nix`. Its generated bootstrap file calls
`bootstrap/resolve-lock.nix` from the devenv source, and passes the project root in as `src`. That
resolver rewrites relative inputs against `src`:

```nix
isRelativePath = p: p != null && (builtins.substring 0 2 p == "./" || builtins.substring 0 3 p == "../");
# Resolve relative paths against src
resolvedLocked = locked
  // (if locked.type or null == "path" && isRelativePath (locked.path or null)
then { path = toString src + "/${locked.path}"; }
```

It also maps a local path input to the live filesystem path, not to a store copy
(`outPath = /. + resolvedLocked.path;`). It maps `path = "."` straight to `rootSrc`. So
`path.cc:129` never runs. The root `devenv.yaml` records `nix-configs: url: git+file:.`.
`devenv.lock` stores it as `{"type":"git","url":"file:."}`, with no rev and no narHash — a shape
plain Lix rejects. A devenv subdirectory shell in this repo uses `path:../..` for the same reason.
That file is not on the public branch, so this document omits the path.

**So the creator's position is right in substance, and one detail needs an update.** Plain Lix
accepts a relative `git+file:` URL. But the URL is cwd-relative and it breaks a cold consumer, so
it is unusable. Plain Lix rejects a relative `path:` above the flake root. Neither `$PWD` nor
impurity is the reason.

## Q3 — does `?dir=<subdir>` work for a plain flake consumer? — **confirmed**

### Item 1 — lock scope

**The consumer's lock holds only the subflake's inputs.** Tested with `github:` on this repo's own
public subflake, `templates/terraform/flake.nix`:

```bash
nix flake metadata 'github:nazarewk-iac/nix-configs?dir=templates/terraform' --json --no-write-lock-file
```

19 nodes, 5 root inputs (`devenv`, `flake-parts`, `mk-shell-bin`, `nix2container`, `nixpkgs`). The
root flake's 55 root inputs and 101 nodes do not appear. A consumer flake with that input locks to
20 nodes and 11 009 bytes. The root flake locks to 101 nodes and 54 841 bytes.

A controlled `git+file:` pair gives the same answer at a smaller scale. A root flake with 3 inputs
plus a subflake with 1 input yields a 3-node, 1 103-byte consumer lock.

### Item 2 — a read above the subflake root

**It works, for both fetch types.** `call-flake.nix:17-21` sets the source root to the whole tree
and points `outPath` at the subdirectory:

```nix
subdir = if key == lockFile.root then rootSubdir else node.locked.dir or "";
outPath = sourceInfo + ((if subdir == "" then "" else "/") + subdir);
flake = import (outPath + "/flake.nix");
```

So a relative read above the subflake root stays inside the same store path. Measured against the
real `github:` subflake, in pure eval:

```
s.sourceInfo.outPath = /nix/store/k1i7g6iqm4m6vvz92wqhiiq5j90ldb9w-source
s.outPath            = /nix/store/k1i7g6iqm4m6vvz92wqhiiq5j90ldb9w-source/templates/terraform
readFile (s.outPath + "/../../lib/default.nix")   -> "{ lib, ... }:\nlet\n  callLibs = path: …"
readDir  (s.outPath + "/../../modules/slots")     -> 14 entries
```

The store path is the whole 4.0 MB tree. A `git+file:` test proves the same through the
subflake's own `outputs`: `answer = (import ../lib/helper.nix).answer;` evaluates to `42`.

**Partial finding 2 in the task needs a correction.** `path.cc:129` sits inside
`PathInputScheme::fetch`. Only a `path:` **input** reaches it. A plain file read such as
`import ../../lib` never reaches it, because that is an evaluator file read, not an input fetch.

A related surprise: a `path:` input **does** work upward from inside a `?dir=` subflake. The
reason: `../` stays inside the same fetched tree. It is a trap, not a feature. A subflake with
`inputs.up.url = "path:../"` pulls the root flake's whole input set back into the consumer's lock.
Measured: 6 nodes instead of 3 in the controlled test.

### Item 3 — the subflake's own lock, and root coverage

Three separate answers, all confirmed.

- **A consumer does not need the subflake to hold a lock.** The consumer locks the subflake's
  inputs itself: `creating new input 's/d2'`. The cost: that fetch has no pin, so it takes the
  input's latest ref at lock time.
- **A direct `nix flake metadata` on the subflake ref fails without a lock.** The subflake tree is
  read-only, so Lix cannot write one:
  `error: cannot write modified lock file of flake 'github:…?dir=templates/terraform' (use '--no-write-lock-file' to ignore)`.
  That call also spent 117 s and fetched `github:NixOS/nixpkgs/nixos-unstable`.
- **The root flake covers neither.** `nix flake lock` and `nix flake update` at the root create no
  `sub/flake.lock` and never touch one. `nix flake check` at the root evaluates only the root
  flake's outputs. A subflake needs its own lock, its own update step, and its own check.

### Item 4 — how common is a `?dir=` library entry point?

**Rare.** A survey of every `flake.lock` in this machine's store found 223 lock files. It found
only two distinct real upstream `?dir=` inputs:

| Input | Nature |
|---|---|
| `github:wez/wezterm?dir=nix` | a flake that packages an application, inside the application repo |
| `github:cachix/devenv?dir=src/modules` | devenv's own module tree |

Neither is a public library entry point in the sense 010 asks about. The rarity is a caution about
tool support and about adopter knowledge. It is not a technical blocker. The technique works.

## Q4 — does any candidate depend on `lazy-trees`? — **confirmed**

`lazy-trees` does not exist on Lix. A source-wide search of the Lix 2.95.2 tree returns **0** hits
for `lazy-trees` or `lazyTrees`. The CLI agrees:
`nix --extra-experimental-features lazy-trees eval --expr 1` warns
`unknown experimental feature 'lazy-trees'`.

No candidate depends on it. Every candidate below works on Lix 2.95.2 today.

| Candidate | Works today on Lix | Feature flags needed | Note |
|---|---|---|---|
| `?dir=<subdir>` subflake | yes | `flakes nix-command` | Proven in Q3, both `github:` and `git+file:`. |
| `follows` dedup | yes | `flakes nix-command` | Proven in Q1. A root-level `follows` costs one tree fetch per adopter lock run. |
| `flake = false` | yes | `flakes nix-command` | It removes lock nodes, not fetches. 33 public nodes already use it. |
| Lix's internal `call-flake.nix` | yes | `flakes nix-command` | Not an adopter API. Its lazy `mapAttrs` is what makes the 101-node lock cheap. |
| A `call-flake`-style pure-Nix resolver | yes | none beyond what the caller already needs | It re-implements lock resolution in Nix, as devenv's `resolve-lock.nix` does. It changes which code resolves the lock, not the fetch volume. |
| `npins` | yes | none | `pkgs.npins` is 0.5.0. It drops flakes, so it drops the lock-node problem and the flake API with it. |
| `flake-compat` | yes | none | Plain Nix reads `flake.nix` and `flake.lock`. Same fetch volume. |

One term needs care: `flakes` and `nix-command` are themselves experimental features. This repo
already enables both (`experimental-features = flakes nix-command`). Nothing in the table needs a
third one.

## Ranked techniques

Value against effort. Rank 1 is the best trade.

### (a) this repo's own lock and eval cost

The lock size costs this repo almost nothing. A 101-node lock computation takes 0.15 s when no
input changes. The plan already measures 93 s for one warm Darwin host eval. So the lock text is
below the noise floor.

1. **Keep `flake.nix` and `flake.lock` in agreement.** Value: high, cost: zero. Drift is the only
   mechanism that turns a lazy node into a real fetch. It is also the only one that can demand
   SSH. This is already the practice; the new fact is that it matters.
2. **Widen `flake = false`.** Value: low, cost: low. It removes lock nodes and lock text. It
   removes no fetch. 33 of 101 public nodes already use it.
3. **Cut root inputs.** Value: real, but out of scope here. 55 root inputs drive the node count
   more than any technique in this document.

Nothing else in the candidate set improves this repo's own cost.

### (b) an adopter's cost

Baseline, measured under Pattern V2: one 4.1 MB tree fetch and 54 841 bytes of lock text. The
first lock takes 1.2 s, a re-lock takes 0.15 s. A read of `lib.kdn` plus the package overlay takes
0.14 s. Total: 2 tree fetches, no SSH.

1. **Drop the root-level `follows` at `flake.nix:7`.** Value: high against a four-line cost.
   Point `flake.nix:90`, `flake.nix:91`, and `flake.nix:124` at `"nixpkgs"` instead of
   `"nixpkgs-lib"`. Then delete line 7. That removes the only `follows` array on the
   `nix-configs` node. After the edit, no adopter lock run fetches the whole tree again. Measured
   effect: `got tree` per re-lock drops from 2 to 1. Verify with the drvPath gate (Pattern V1).
   `haumea`, `flake-parts`, and `nixos-generators` all end up on the same `nixpkgs` tree, so the
   result must be a no-op.
2. **A `?dir=` subflake that exports `lib.kdn` and the slot modules.** Value: high on lock text,
   medium overall. Cost: medium, and it repeats. It takes an adopter lock from 101 nodes and
   54 841 bytes to about 4 nodes and about 1 KB. The input set is already known: `modules/slots`
   and `lib` reference only three flake inputs — `mcp-servers-nix`, `nix-rosetta-builder`, and
   `nix-configs` itself. A read above the subflake root works, so the subflake needs no file
   copies. See the cost list below.
3. **Widen `flake = false`.** Value: low, cost: low. Less lock text for the adopter too.
4. **`npins` or `flake-compat`.** Value: none for this problem. An adopter consumes a flake. These
   tools change how the adopter pins **their** inputs. They do not change what this repo's lock
   costs them.
5. **A separate library repo.** The plan's decision table rejects it. It would solve the lock text
   completely, at the cost of two repos.

### Costs to record for the subflake option

- A second `flake.lock` to maintain. The root `nix flake lock`, `nix flake update`, and
  `nix flake check` do not touch it. `flake-update.sh` and `checks` need an explicit entry.
- A drift risk against the root `nixpkgs` pin. The subflake's `nixpkgs` node is independent.
- The 4.1 MB whole-tree fetch stays. `?dir=` reduces lock nodes, not the tree copy. That is what
  `lazy-trees` would fix, and Lix will not ship it.
- Lix requires `flake.nix` to be a direct attrset (`flake.cc:330-332`,
  `file '%s' must be an attribute set`). It forces `inputs`/`outputs` only when the thunk is
  trivial (`forceTrivialValue`, `flake.cc:81-84`). Keep the subflake's `flake.nix` free of
  function calls outside `outputs`.
- The pattern is rare in the wild — two real examples in 223 sampled locks.

## The plain answer

Very little helps, and here is why. Lix's lock format is already lazy at both ends. At lock time,
`computeLocks` copies an unchanged input as metadata, with no I/O. At eval time, `call-flake.nix`
wraps every `fetchTree` in a `mapAttrs`, so Lix never fetches an unreferenced node. An adopter
therefore pays for the tree they asked for, and for the lock text. They pay for nothing else.
54 841 bytes of JSON and 0.15 s are not a problem worth a subflake.

The single real defect is one root-level `follows` line. It makes every adopter lock run fetch the
whole tree again. That is a four-line fix, not an architecture change.

## Spike decision

**Do not spike the subflake yet.**

1. Apply the `flake.nix:7` change under the Pattern V1 drvPath gate. Re-measure the adopter
   `got tree` count.
2. Record the adopter baseline in checkpoint 003's runbook: one 4.1 MB fetch, about 55 KB of lock
   text, no SSH.
3. Revisit the subflake on one of two triggers. An adopter reports the lock text as a real
   problem. Or checkpoint 002 finds an adopter-visible fault that the 3-input subflake fixes.

## Corrections to the task file

| 010 statement | Correction |
|---|---|
| "case (b) forces a fetch, because an override takes the 'creating new input' branch" | True for a URL override or `--override-input`. False for a `follows` override, which returns early at `flake.cc:633-641`. |
| Partial finding 2: `path.cc:129` "is the exact error a `?dir=` subflake would hit when it reads `../../lib`" | No. `path.cc:129` sits in `PathInputScheme::fetch`, and only a `path:` input reaches it. A read above the subflake root works; a pure eval proves it. |
| "plain Nix flakes do not support `git+file:` with a relative path" | Lix accepts it and locks it. It points the URL at the process cwd and breaks a cold consumer. So the conclusion stands, for a different reason. |
| "a `git+file://…?dir=…` metadata call resolved only that subflake's inputs" — needs a `github:` re-test | Re-tested with `github:`. Same result: 19 nodes, and the store path holds the whole 4.0 MB tree. |

## Reproduction

Every command below runs outside this repo.

```bash
# Q1 — adopter lock and re-lock, no SSH
mkdir -p /tmp/gen010/real && cd /tmp/gen010/real
printf '{\n  inputs.nix-configs.url = "github:nazarewk-iac/nix-configs";\n  outputs = { self, ... }: { };\n}\n' > flake.nix
SSH_AUTH_SOCK= GIT_SSH_COMMAND='ssh -o BatchMode=yes -o IdentitiesOnly=yes -o IdentityFile=/dev/null' \
  nix flake lock --debug 2>&1 | grep -cE 'got tree|keeping existing input'
nix flake lock --debug 2>&1 | grep 'got tree'          # the re-lock fetch
jq 'del(.nodes["nix-configs"].inputs["nixpkgs-lib"])' flake.lock > n && mv n flake.lock
nix flake lock --debug 2>&1 | grep 'got tree'          # one line fewer

# Q2 — relative input URLs
mkdir -p /tmp/gen010/b
printf '{\n  inputs.x.url = "path:../target";\n  outputs = { self, x, ... }: { };\n}\n' > /tmp/gen010/b/flake.nix
cd /tmp/gen010/b && nix flake lock                     # BadStorePath from path.cc:129

# Q3 — subflake lock scope and a read above the root
nix flake metadata 'github:nazarewk-iac/nix-configs?dir=templates/terraform' \
  --json --no-write-lock-file | jq '.locks.nodes | length'
```

The `?dir=` survey uses one loop over the store:

```bash
for f in /nix/store/*-source; do
  [ -f "$f/flake.lock" ] || continue
  jq -r '.nodes|to_entries[]|select(.value.locked.dir? != null)
         |"\(.value.locked.owner // "-")/\(.value.locked.repo // "-")|\(.value.locked.dir)"' "$f/flake.lock"
done | sort | uniq -c | sort -rn
```
