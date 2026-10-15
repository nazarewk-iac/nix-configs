---
type: Research
description: Measured facts about launchd socket activation, TCC cdhash binding, and the rosetta-builderd interaction with the bootstrap wrapper on macOS 27.0.1.
task: definition.md
authored_by: agent
timestamp: 2026-10-15T23:10:00+02:00
---

# Rosetta builderd under the bootstrap — measured launchd/TCC behaviour

Source: the stage 1–3 runs of 2026-10-15 on `anji` (macOS 27.0.1), the sub-agent cutover report,
and the follow-up debugging of the denied-FDA state. Verbatim sub-agent reports are in the task's
`.worklog.md`.

## 1. Socket activation: no fd 3, per-job `launch_activate_socket`

- The design assumption "launchd hands the socket-activation listener at descriptor 3 to the job's
  top-level process, so the wrapper must re-pass it" is **wrong on macOS 27**. The wrapper never
  receives fd 3. (A first implementation with `passFds:1` failed with `descriptor 3 is not open`
  and crash-looped `rosetta-builderd` — 453 recorded runs between the 05:00 stage-1 swap and the
  diagnosis.)
- `lima` 2.2.0 (the `rosetta-builder-vm` ssh listener) fetches the socket itself: the guest yaml
  sets `ssh.launchdSocketName: Listener`, and the daemon calls
  `launch_activate_socket("Listener")`.
- launchd resolves that call **per job, for every process of the job** — a grandchild of the
  job's top-level binary is still "the job". A plain spawn through the bootstrap therefore works:
  verified live — `kdn-nix-bootstrap run rosetta-builderd` → builderd binds → guest VM starts →
  a cache-less x86_64-linux source build ran on the guest via `ssh-ng://rosetta-builder`.
- Consequence: the bootstrap needs no fd machinery at all (removed in `refactor(kdn-nix-bootstrap)`).

## 2. Socket-activated jobs reject stdout/stderr paths

Adding `StandardOutPath`/`StandardErrorPath` to a socket-activated job's plist makes launchd
refuse the spawn with `EX_CONFIG` on 27. nix-darwin does not set them for socket jobs; debug
plists that add them must drop them. Debugging such a job needs a separate non-socket probe job
pointing at the same payload.

## 3. TCC binds the grant to path AND cdhash — replacement = revocation

- The FDA grant on `/usr/local/bin/kdn-nix-bootstrap` records the binary's cdhash at grant time.
  When different bytes appeared at the path (stage-1c activation reinstalled a rebuilt binary),
  macOS **flipped the entry to DENIED** (`auth_value=0`, `auth_reason=5` = code-signature
  mismatch) at 20:04 — no re-prompt — and every launchd job through the wrapper lost external-
  volume access. The failure mode inside the tree is dyld: `file system sandbox blocked open()`
  on `liblix.dylib`, exit code 1.
- Worse before that: `cp -f` onto the running binary truncates the vnode in place. The kernel
  then kills *every* exec of that path — even after the ORIGINAL bytes are restored — with
  `CODE SIGNING: ... rejecting invalid page ... (tainted:1)`, until the file is replaced
  atomically (`cp` sibling + `mv`).
- The DB does not self-heal on restoring a matching cdhash: the toggle must come back from the
  GUI. `tccutil reset SystemPolicyAllFiles` would also clear it but nukes every other grant.
- Config response: activation now installs the bootstrap **only when the path is empty**
  (`feat(anji): install the bootstrap once`). Rotating it is an explicit move: `rm` the file,
  activate, owner re-grants, then the boot chain continues.
- Open idea (if rebuilds ever need to rotate freely): sign the Go binary with a stable self-signed
  identity at build time; a grant to an identity-based designated requirement survives content
  changes, the way app grants survive app updates.

## 4. Builder guest image drift (pre-existing, to look into)

The cutover report flagged: the guest's instance yaml (generated 2026-09-08 image) and the current
config (1011 nixpkgs) differ, so builderd's consistency check **deletes and recreates the lima
guest** when it notices. That is orthogonal to the store move but delays the first build after
every boot, and it will fire on every nixpkgs bump while the drift persists. Candidate fixes:
pin the guest image to the config revision, or teach the fork's check to migrate in place.
Cross-reference: `hosts/anji/default.nix` comment about `minFree`/`maxFree` triggering
`limactl delete --force`.

## 5. Practical notes from the runs

- launchd throttles a crash-looped job by 10 s per attempt and accumulates `runs` across
  swaps; `bootout` + `bootstrap` resets the counter and clears backoff.
- `log show --predicate 'eventMessage CONTAINS[c] "<name>"'` is the only way to see a wrapped
  job's stderr when the real plist must stay untouched.
- Root's own `security`/`diskutil` calls from an ssh session behave differently from the launchd
  context (user login inherits `sshd`'s exemption) — a green manual run proves nothing about TCC.
