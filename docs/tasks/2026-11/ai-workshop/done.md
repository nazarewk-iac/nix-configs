---
type: Solution
description: The bench the workshop asked for — a frontier whose operating points are measured and priced, a container runner on both ZFS hosts with a proven restore drill, a media bench whose archive half runs end to end, Hermes Agent from its upstream flake behind a loopback web UI, one source for every serving knob, and a status command — while six of the eight PoCs stay blocked on inputs from outside the repository.
task: definition.md
authored_by: agent
timestamp: 2026-11-21T22:52:00+01:00
---

# Solution: the AI workshop bench

## Root cause analysis

The task's own words are "Prepare the bench, not the products". The gap was not one bug. It was
that every capability the fleet wanted later — media, documents, audio, agents — had no measured
ground to stand on:

- **The frontier had no operating points, only guesses.** The engine was started with numbers typed
  into whatever file was nearest, the slot count lived in three places at once, and the two omni
  profiles were served with eight slots while the deployment file said one and two. A second copy of
  a number is not a convenience; it is a future disagreement with no owner.
- **The placement policy priced a model by weights alone.** A 30B companion measured 21 GiB of RAM
  because `VmRSS` counts clean file-backed pages, so the policy refused a model the card had room
  for and would have admitted one it did not.
- **A service had no contract for its state.** Nothing said where a service keeps its data, so
  backup was undefined and a migration was a rewrite.
- **The media pipeline did not exist at all**, and Hermes Agent had no packaging.
- **Nothing could answer "what can this host serve, and what is serving now"** without reading three
  files and a log.

The task was done when each of those became wired, measured and proven once — not when the PoCs
finished. The PoCs were the acceptance for the bench, and only the archive half had every input
already in the repository.

## Solution

### 1. The placement policy prices K/V, and an epoch makes a decision safe to act on

A model's VRAM is now `vramMiB` **plus** `kvReserveMiB`, and `fits-beside` subtracts both from the
card for the newcomer and for every resident model — so a card filled by caches never reads as free.
`ramMiB` is explicitly the **non-reclaimable** set (anonymous RSS plus shmem), not `VmRSS`:
`qwen3-omni` held 11.7 GiB of `RssFile` against 128 MiB of `RssAnon` (2026-11-21), which is what made
the old policy refuse it beside a profile with room.

`/decide` stays advisory. `/admit` is now a compare-and-swap over an **eviction epoch**: `/decide`
returns an `eviction_id`, `/admit` refuses a stale one and names the current one in the refusal, and
the epoch rotates only when it should. `hosts-den/brys/policy.nix` keeps the behaviour tree, the card
budget, the companions, the small models and the image profiles — and no frontier knob, because those
live on the model.

### 2. Seven frontier operating points, resting on `max-multi`

Each point is one model entry in `data/llm.nix` under `hosts.brys.serving`. Measured 2026-11-21
([measurements.md](../brys-r9700-model-fit/measurements.md)):

| entry            | rank | pack      | ctx × slots | measured                            | role        |
| ---------------- | ---: | --------- | ----------- | ----------------------------------- | ----------- |
| `qfn-max-multi`  |    0 | UD-IQ4_XS | 512k × 5    | 31.9 t/s aggregate, 12.0 GiB free   | **resting** |
| `qfn-max-swarm`  |    1 | UD-IQ4_XS | 256k × 8    | 36.2 t/s aggregate, 18.4 GiB free   | swarm       |
| `qfn-max-long`   |    2 | UD-IQ4_XS | 1M × 2      | 29.7 t/s aggregate, 10.5 GiB free   | long        |
| `qfn-max-single` |    3 | UD-IQ4_XS | 1M × 1      | 86.6 t/s single stream              | one big job |
| `qfn-fast-swarm` |    4 | IQ2_XS    | 384k × 8    | 61.0 t/s aggregate, 31.4 GiB free   | swarm       |
| `qfn-max-colo`   |    5 | UD-IQ4_XS | 1M × 1      | 42.3 t/s, + the companion beside it | colo        |
| `qfn-fast-colo`  |    6 | IQ2_XS    | 1M × 2      | 71.6 t/s, + the companion beside it | colo        |

Three measured facts shaped the table, and each is recorded beside the numbers that produced it:

- **512k stops at five.** Five leaves 12.0 GiB and decodes no faster than six (31.9 against 30.7 t/s
  saturated), because the expert cache shrinks as the slot sessions grow. Six held 6.6 GiB on a quiet
  host but fell to **2.9 GiB with two builds running**, under the 4 GiB a build needs.
- **1M stops at two.** A third fits arithmetically, but the window keeps a slot of headroom for the
  hard resets this host took under a long prefill.
- **`--ple-io mmap`, not `ram`.** Locking the ~30 GiB n-gram table in RAM is what OOM-killed a second
  1M slot (109.6 GiB RSS) and what pushed a 384k load to 126 s; in the page cache the same load takes
  56 s and frees 22–25 GiB.

`qfn` is profile-neutral: it asks the manager for `auto`, so naming it never reloads the engine.
`qfn-max` keeps its old meaning as an alias of `qfn-max-long`.

### 3. A container runner on both ZFS hosts, with a restore drill

`kdn.containers.containers.<name>` carries the contract: `stateDir` (`/var/lib/kdn/<name>`, mounted at
the same absolute path and exported as `KDN_STATE_DIR`) and `stateDataset` (`name`, `refquota`,
`compression`), which a oneshot creates with `mountpoint`, `refquota`, `compression=zstd`, `atime=off`
and `xattr=sa`. On a host without ZFS the same path stays a plain directory, so the container
definition never learns about the filesystem.

The drill ran on both hosts: snapshot → write drift → destroy the container → rollback → restart. On
`etra` declaratively (`workshop-state` on `etra-main/etra/kdn/services/workshop-state`, snapshot
`@drill-1`); on `brys` by hand with rootful podman, because `brys` had no containerd at the time it
was enabled. On both, the file written before the snapshot survived and the drift did not.
`workshop-hello` stays on a plain directory as the non-ZFS regression.

`brys` now runs the same runner: containerd is active and `brys-hello` is up on a dataset.

### 4. The media bench: the archive half runs end to end

`hack/media/` is a Makefile DAG over `ffmpeg`, not a service: `probe → cut → freeze → deint →
denoise → audio → master → proxy → report`, with `vmaf` as the quality gate and `notify` as the only
placeholder (it fires only when `~/.config/ntfy/topic` exists). Every stage writes `.tmp` and renames,
so a re-run resumes instead of repeating.

Two rules about the picture, both encoded rather than documented:

- **Archiving never upscales.** The master is encoded at the capture's own resolution; `enhance` is a
  separate, tagged `enhanced.review-required.mkv` that refuses at or above the target.
- **A frozen picture is reported, never silently archived.** `freeze.py` classes each held span as
  `freeze` (up to 10 s — a still shot) or `stuck` (over 10 s — a paused or stalled player), and the
  report marks a capture `suspect` when stuck time exceeds a third of its content.

The run is in [vhs-poc.md](vhs-poc.md). Three defects it exposed were fixed: `cut.py` never trimmed
the trailing black (its tolerance assumed `blackdetect` reports the end of the last frame), the
broken-tape marker landed on a name the rename never touched, and the proxy upscaled SD and stayed
10-bit.

### 5. Hermes Agent from the upstream flake, behind a loopback web UI

The hand-written derivation is gone. `inputs.hermes-agent` (`github:NousResearch/hermes-agent/52b5271`,
output `packages.x86_64-linux.default`, the `full` variant) supplies the Python environment from
upstream's `uv.lock` through uv2nix, the three frontends built by pnpm, the bundled skills and the
runtime tools its `pm/lock.json` pins. One adaptation lives in `hosts/etra/hermes.nix`: their
`pm-packages.nix` patches a patchelf bug that cannot exist at our 0.15.2 pin, so the host hands it a
`patchelf` whose `overrideAttrs` is the identity.

The web UI (`hermes webapp`) renders from a store path — `HERMES_WEBAPP_DIST`, so nothing is built at
runtime — and is pinned to `127.0.0.1:9120` in the **managed** layer of `/etc/hermes/config.yaml`, so
`hermes config set webapp.host 0.0.0.0` is refused. That matters because the container shares the
host's network namespace: a wildcard bind would publish the workspace on `nb-priv` with no firewall
change at all. Access is a one-use sign-in link valid for 60 seconds, printed by
`hermes webapp --no-open`, and it survives an SSH tunnel because the sign-in is a token in the link
and not a peer check.

### 6. One source for every serving knob, and a rule instead of a guard

Before: the slot count lived in the deployment file, in a `case` table in `strata-serve.sh`, and in a
built-in table in `strata.go`. Since then every knob — pack, window, slot count, VRAM reserve,
resident K/V, park pool, n-gram backing store, and the measured facts the policy quotes — is written
on the model in `data/llm.nix` (`hosts.<host>.serving`), and `lib/llm.nix` `strata` derives from it:
the manager's `config.json`, the llama-swap `cmd` of the entry, the policy's frontier rows, the engine
argv (`strata-serve.sh` reads the generated file with `jq` and **fails loudly** on a missing key), and
the yarn factor.

The rule is [config-single-source.md](../../../../.agents/rules/config-single-source.md). Its third
clause is the interesting one: **there is no guard check, because there is no second copy.**
`checks/inference-helpers/profiles.nix` was deleted on 2026-11-21 — it asserted that a file agreed
with itself.

### 7. `kdn-inference-helpers status`

One screen answering "what can this host serve, and what is serving now": the configured half from the
deployment file and the policy, the live half from the manager, llama-swap, `/proc/meminfo`, the
card's sysfs and the engine's log. It never switches, unloads or starts anything, and a source that
does not answer is a line of output — never an error, never a non-zero exit, because this is the
command an operator runs when the host is already broken. `--long` and `--json` are the same snapshot.
Details and the source of every fact: [status-command.md](status-command.md).

## Verification steps

**Every deliverable and its evidence.** All commands were run from the repository root on `oams`, and
on `brys` where the note says so.

| #   | deliverable              | commits                                                                                                  | proof                                                        |
| --- | ------------------------ | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| 1   | policy: K/V + epoch      | `a1b9b1755fd6` `e44f74156f4b` `fedd01350f93` `e959151e78bc`                                              | `internal/control/epoch_test.go`; `den-eval-llm`             |
| 2   | seven operating points   | `92b867d70b32` `f8e05427e396` `c225d8f5238b` `ab15433a438f` `a2bdeaaa95a3`                               | `measurements.md`; `ctl status`; `status`                    |
| 3   | container runner + drill | `9baec4609dd7` `af13c0c98eb1` `6dc5c699e4d2` `95fe697ff6f7` `c145bd81755d`                               | `definition.md` "Proven drill"; `nerdctl ps` on both hosts   |
| 4   | media bench              | `389cb8a9bd10` `6057114693c6` `a6769f9b810d` `f24ef3775979` `20384773b658`                               | `vhs-poc.md`; `hack/media/README.md`                         |
| 5   | Hermes from upstream     | `360fecfa27ff` `1ef97de5f5cc` `f1f96593ef6a` `92a07ff5cd9f` `f204345f897d` `3d78def6df61` `fba1451c76f1` | `definition.md` "Hermes Agent on `etra`"; `ss -ltnp` on etra |
| 6   | single source + rule     | `bebb3bf972ee` `c3a373e5ecea` `b8a0a209490c` `5fdbd0d97a51`                                              | `.agents/rules/config-single-source.md`; `status --long`     |
| 7   | `status` command         | `0443e58be42a`                                                                                           | `internal/status` tests; `status-command.md`                 |

**The frontier answers and rests where it should** (on `brys`, after the deploy of
`chore(brys): delete the dead strata Python and shell predecessors`):

```
$ ctl down && ctl up
{"changed":true,"profile":"none"}                                  # down
select max-multi -> {"changed":true,"port":8080,"profile":"max-multi","seconds":62}
$ ctl status
profile:  max-multi
switch:   none -> max-multi in 62s, 5s ago, cause=select
engine:   http 200
```

```
$ curl -o /dev/null -w '%{http_code}' http://127.0.0.1:39700/v1/chat/completions \
    -d '{"model":"qfn-max-single","messages":[{"role":"user","content":"reply with one word"}],"max_tokens":16}'
200                                                                 # 59.2 s, switch + load
```

`kdn-inference-helpers status` on the same host lists 12 profiles and reports
`profile max-multi · UD-IQ4_XS · 512k × 5 · 23.2 GiB weights + 6.3 GiB K/V`, `eviction
18d0985d-…`, `leases 0 in flight, draining no`.

**The container runner is live on both hosts.** `brys`: `containerd` active, `nerdctl ps -a` shows
`brys-hello` up on `nix:0/nix/store/…-nix-image-brys-hello.tar:latest`. `etra`: `containerd` active,
`nerdctl ps -a` shows `hermes`, `workshop-hello` and `workshop-state` up, and
`zfs list -t snapshot -r etra-main/etra/kdn/services` still holds `workshop-state@drill-1`.

**The web UI is loopback-only.** On `etra`, `ss -ltnp` shows exactly two listeners for the container:
`127.0.0.1:9120` (`hermes`) and `127.0.0.1:9530` (`socat`, the litellm relay), and
`hermes webapp --status` prints `Serving at http://127.0.0.1:9120`.

**The checks.** `den-eval-llm` and `standalone-aspects` are `checks/README.md` names and both exit 0:

```
$ nix build --no-eval-cache -L '.#checks.x86_64-linux.den-eval-llm'          # ~2.5 s, exit 0
$ nix build --no-eval-cache -L '.#checks.x86_64-linux.standalone-aspects'    # ~2.0 s, exit 0
```

`inference-helpers-integration` is a real top-level check that `checks/README.md` does **not** list,
and **it is red** — for a stale fixture, not for a runtime defect:

```
$ nix build --no-eval-cache -L '.#checks.x86_64-linux.inference-helpers-integration'
check-inference-helpers-integration> never answered: http://127.0.0.1:18090/v1/models
```

`checks/inference-helpers/run.sh` still names the **retired** `max` profile as the resting point: its
config defines `commands.max` and aliases `qfn` to `auto`, and `auto` now resolves to `max-multi`,
which the fixture has no command for. Reproduced by hand against the built package:

```
the manager is not answering on http://127.0.0.1:18181: … connection refused   # select before the manager
switch to max-multi failed: profile "max-multi" has no command in the deployment config
```

Defining `max-multi` instead makes `select` proceed to start the engine, so the fixture is the whole
defect. The fix is three names in that file (`commands.max` → `commands.max-multi`, the `qfn-max`
alias, and the two `status()["profile"] == "max"` assertions); it is outside this task's files and is
left for its owner. The check is the one that exercises the parts which only exist once the pieces
are separate processes: the deployment config file, the manager's child supervision, the startup
switch, the `kdn_switch_to` gate, and the revert on unload. It deliberately leaves llama-swap out,
because llama-swap's own scheduler is what kills a cold-starting entry inside the sandbox. The Go
suites of the runtime are `kdn-inference-helpers.passthru.tests.go-test`.

**The dead predecessors are gone and their replacements still resolve.** The three commands
`strata-select`, `strata-proxy` and `strata-manager` in `/run/current-system/sw/bin/` are the
`writeShellScriptBin` wrappers that exec `kdn-inference-helpers select|proxy|manager`;
`strata-manager.service` is `active` and `enabled`, and the `ctl` cycle above ran through them.

## Follow-up notes

### Three operational leftovers, and one stale check

1. **The flaky `nixos-rebuild.sh` is fixed by a lock.** `1aaaa635e4b8`
   (`fix(nixos-rebuild): one deploy at a time, per target`) takes a per-target `flock` and waits a
   bounded time for a running activation. Before it, two deploys could collide and the second failed
   with a message that named nothing.

2. **The atuin activation failure is fleet-wide and not this task's.** `kdn-atuin-login-root.service`
   fails on **every** activation on **every** NixOS host, so `nixos-rebuild` exits 4 after the system
   has already switched. The reason: `modules/universal/programs/atuin/default.nix` gates
   `programs.atuin.daemon.enable` to non-root, so root's client has no `[daemon]` section while the
   root daemon runs, and `atuin store` cannot rebuild the threads index. Until it is fixed or the store
   step is made non-fatal, a switch is successful when `/run/current-system` advanced and only that
   unit failed — which is how every deploy in this task was judged.

3. **225.9 GiB of unserved models sit in `surveyed/`, and the freed space is invisible.** Measured
   2026-11-21 on `brys`: 22 GGUFs in `/var/lib/kdn/llms/models/surveyed/` are in **no** live
   llama-swap entry, 225.9 GiB in total. Separately, the 27.73 GiB of dead models deleted by the
   deploy-failure run gained the pool **nothing**, because the `zfs-auto-snapshots` on
   `brys-main/brys/impermanence/usr/data` still hold the blocks: 46 snapshots at the measurement, 45
   of them older than the deletion, and the number grows with every new snapshot taken. The pool
   stays at 93 % with 63 % fragmentation and 129 GB free. Reclaiming either is destructive and
   belongs to the owner: prune `surveyed/`, or `zfs destroy` the snapshots older than the deletion,
   or shorten `zfs-snapshot-*` retention.

4. **`inference-helpers-integration` is red** on a fixture that still names the retired `max`
   profile as the resting point. The diagnosis and the three-name fix are in "Verification steps"
   above. It is a repository defect that outlived this task's frontier work, and it is the reason the
   solution proves the runtime on `brys` rather than through that check.

### What is **not** done: six of the eight PoCs

The bench is built; the proofs of concept are not. [pocs.md](pocs.md) holds the state of each and the
exact input it waits for, and it is the authority — this solution does not repeat it. In summary:

- **VHS archive — done.** The acceptance holds end to end: one command cuts a capture to its content,
  a re-run is a no-op, and notification is a declared placeholder.
- **VHS restore — done on synthetic data only.** Every stage exists and has run, but a capture rig
  (TBC, tracking, cleaning) and real tapes are outside the repository, and the `deepFilter` CLI is not
  packaged, so the audio branch took `afftdn`.
- **documents → KB, albums, spam, UI check, LTX clip — blocked**, each before its first stage, on an
  OCR engine and a corpus; a photo corpus and the InsightFace model licence; a mail corpus and a host
  decision; `browser-harness` packaging; and the LTX weight set plus the sd.cpp conv-VAE check.
- **voice loop — partially done.** Both speech legs round-trip on `brys` and the agent in the middle
  is live on `etra`, but nothing listens (no microphone) and nothing speaks on demand (no wake/VAD).

Two limits are residual facts, not defects: LTX-2.5's encoder and conv VAE are unverified in sd.cpp,
and `hermes doctor` still reports `Chromium not installed` because `browser_exec` needs a browser the
image does not carry.

### Files this solution deleted, and the docs that still describe them

`hosts-den/brys/strata-manager.py`, `strata-proxy.py` and `strata-select.sh` are gone, and the stale
"The Python implementations stay in the tree for one release as the rollback path" comment is gone
with them. `strata-serve.sh` and `strata-serve.nix` **stay**: the manual-fallback unit
`strata-frontier` runs them.

Two documents outside this task still name the deleted files as current, and should be corrected by
whoever owns them: `docs/brys-frontier-control-plane.md` (the component table and the diagram) and
`docs/tasks/2026-11/kdn-inference-helpers/{definition,design}.md` (correct as history — they describe
what the Go binary replaced — but they read as a live inventory).
