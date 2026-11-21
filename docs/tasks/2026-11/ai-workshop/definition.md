---
type: Task
description: Umbrella task for the AI workshop — the engine/client split, the shared bench, the model catalogue, and the end-to-end PoCs that prove each capability before it is needed.
status: open
authored_by: agent
timestamp: 2026-11-21T08:00:00+01:00
---

# AI workshop

## Purpose

Prepare the bench, not the products. Every future media, document, audio or agent task should be a
target on an existing bench with measured models behind it, so starting the work is a decision, not
a build.

The coding and infrastructure work stays the primary mode. Everything else is a capability that is
_ready_ — wired, measured, and proven once — and idle until it is needed.

## The split that everything hangs on

| side          | hosts                                                   | what runs there                                                                                                                     |
| ------------- | ------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| **engine**    | brys (R9700, 32 GB)                                     | strata profiles (`qfn`), `sd-server` editors, `llama-server` companions and small models, the placement tree                        |
| **client**    | oams (12 GB 6800M), etra (no GPU), later GPU-less boxes | harnesses (OpenCode, Pi), Hermes Agent gateway, ComfyUI UI, browser, MCP clients, CPU models (Kokoro, DeepFilterNet, whisper-turbo) |
| **transport** | etra                                                    | litellm gateway, Caddy with auth, ntfy                                                                                              |

A PoC declares which side each step runs on. Anything that needs a GPU is engine; anything that is a
UI, a harness, a scheduler or a CPU model is client. That line is what lets a future 4-core box join
without redesign.

## Slots

| slot        | contents                                                                                                                                                      | state                       |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------- |
| `engine`    | profiles, the placement tree, `/decide` + `/admit`, response identity headers                                                                                 | live                        |
| `client`    | harnesses on oams; Hermes Agent on etra; ComfyUI decision pending                                                                                             | partly                      |
| `bench`     | `hack/media/` DAG runner, asset layout, ntfy, resumable stages                                                                                                | **this task**               |
| `catalogue` | 10 models with fast/quality variants, all measured                                                                                                            | 23 registered, 15 estimated |
| `services`  | every long-running service as an OCI image built by Nix, run by `virtualisation.oci-containers`: devices, volumes and environment declared in the host module | **rule**                    |
| `gateway`   | Hermes Agent (MIT, self-hosted) as the phone/cron/browser front door                                                                                          | live on `etra`              |
| `crew`      | multi-agent orchestration: LangGraph _or_ Hermes sub-agents, one only                                                                                         | missing                     |
| `spam`      | agent-driven development loop for a mail classifier                                                                                                           | missing                     |
| `policy`    | the tree extended with the new kinds (audio, OCR, restoration, LTX)                                                                                           | live, facts incomplete      |

## PoCs, each with an acceptance

| PoC                | steps                                                                                                                     | acceptance                                                                                       |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| **VHS archive**    | capture → black/silence detect → cut → probe → notify                                                                     | one command cuts a capture to its content; re-running is a no-op (notification is a placeholder) |
| **VHS restore**    | deinterlace → video denoise → audio denoise (DeepFilterNet) → optional upscale/interpolate → encode (SVT-AV1 + VMAF gate) | a 5-minute capture produces a master whose VMAF is above the floor and whose audio has no hiss   |
| **documents → KB** | OCR (dots.ocr) → chunk → embed (qwen3-embedding) → index → search                                                         | a scanned PDF is findable by a paraphrase of its content                                         |
| **albums**         | EXIF + embeddings + face clusters → VLM captions → narrative                                                              | a trip folder becomes one album with a written summary                                           |
| **voice loop**     | wake/VAD → whisper-turbo → agent → Kokoro                                                                                 | a spoken command reaches an agent session and the answer is spoken back                          |
| **spam**           | corpus → rules/model → sealed eval → reviewer                                                                             | precision and recall on the sealed split both improve, and the split hash is unchanged           |
| **LTX clip**       | text → LTX-2.3 (or 2.5) → mp4 with audio                                                                                  | one 5-second clip with synchronised audio, timed                                                 |
| **UI check**       | browser driver → screenshot → VLM verdict                                                                                 | a broken layout is reported with the element that broke                                          |

## Measurements the scheduler needs

The placement tree is only as good as its facts. For every model the bench can invoke, stage 0
records VRAM, RAM, load seconds, switch seconds, decode t/s alone and beside each colo profile, and
`minResidencySeconds`. Until a model has numbers it is refused (I22), which is deliberate.

Known gaps today: 15 catalogue models are estimated from GGUF size; the audio, OCR, restoration and
LTX models have no numbers at all.

## Attack review (five rounds)

**R1 — capacity and co-residency.**

- **A1** a `make` step that needs a GPU model knows nothing about the placement tree and fails
  mid-run. _Fix_: every GPU step goes through a wrapper that calls `/admit`, records the decision
  and waits on `wait` verdicts. The bench never starts a model directly.
- **A2** two PoCs at once both want the reviewer or the upscaler, and only one is admissible.
  _Fix_: a job lock per GPU class, taken for the duration of a GPU step, so the second job waits
  instead of being refused halfway.

**R2 — time and concurrency.**

- **A3** a tape is hours long and a run can die halfway; a half-written output must not count as
  done. _Fix_: every stage writes `.tmp` and renames, which is what `make` needs to resume safely.
- **A4** a long upscale blocks interactive `qfn`. _Fix_: heavy GPU steps run as `class: batch` (the
  cooldown exemption) and, by default, under a Hermes cron window at night.

**R3 — engine/client split.**

- **A5** the capture lands on brys but review happens on oams. _Fix_: the asset layout defines
  `incoming/`, `proxies/`, `masters/`, `archive/`; masters stay on brys, proxies are rsynced to
  oams by a bench target.
- **A6** Hermes on etra dies when litellm is down. _Fix_: two endpoints configured — litellm first,
  brys direct as fallback — and a health check in the gateway unit.

**R4 — operability.**

- **A7** the new models need ~35 GB (LTX ~30, audio ~5, OCR ~2, restoration ~2) against ~152 GB
  free. _Fix_: a disk budget step in the bench and a prune list kept in the task.
- **A8** adding eight more estimated models would make the tree a fiction. _Fix_: stage 0 is a
  blocker for every model the bench can invoke; `allowUnmeasured` stays false.

**R5 — semantics and quality.**

- **A9** multi-agent roles multiply calls and can hammer the card. _Fix_: a per-job call budget and
  the tree's cooldown; the crew declares its model set up front so the tree can refuse it whole.
- **A10** the spam loop can cheat by tuning on the eval set. _Fix_: a sealed split the builder never
  reads, and a check that fails when its hash changes.

**Convergence.** R1–R4 found real gaps (GPU admission for bench steps, atomic outputs, the asset
share, the disk budget, measured facts). R5 found two (call budget, sealed split). A sixth pass with
the same lens found no new class, so the loop stops. Residual, not defects: LTX-2.5's encoder and
conv VAE are unverified in sd.cpp. (Hermes Agent's missing Nix packaging is closed — see
[Hermes Agent on `etra`](#hermes-agent-on-etra-live).)

## Order of work

1. **bench** — `hack/media/` runner, asset layout, ntfy, atomic stages, GPU admission wrapper.
2. **audio** — Kokoro, whisper-turbo, DeepFilterNet, Demucs; they unlock the VHS audio half and the
   voice loop, and most run on a GPU-less host.
3. **catalogue prune + stage-0 measurements** — the tree stops guessing.
4. **gateway** — _done_: Hermes Agent on etra, wired to the fleet, with the VHS watcher as its
   first cron (the watcher is still open).
5. **PoCs in order**: VHS archive → VHS restore → documents → albums → spam → voice → UI → LTX.
6. **crew** — only when a PoC has shown that one agent is not enough.

## Services are containers: nix-snapshotter first, nspawn as the interim

The long-term target is **containerd + nix-snapshotter**: OCI-native, store-path layers, the same
artefact on a laptop, a server or a cluster, and no image tarballs. NixOS containers are the interim
because they are the shortest path today, not because they are the destination.

| tier                                  | role                                               | duplication                   | portability                    |
| ------------------------------------- | -------------------------------------------------- | ----------------------------- | ------------------------------ |
| **containerd + nix-snapshotter**      | **target**: every service that may move            | none — layers are store paths | OCI: `nerdctl`, k3s, plain k8s |
| NixOS container (`containers.<name>`) | interim: get a service running in an afternoon     | none — shares the store       | NixOS only                     |
| third-party OCI pull                  | only when something ships nothing but a Dockerfile | unavoidable                   | OCI                            |

The snapshotter does not need a cluster: `virtualisation.containerd.nixSnapshotterIntegration` plus
`nerdctl` runs single containers with store-path images today, and the same image becomes a Pod when
k3s arrives. `pkgs.nix-snapshotter.buildImage` is the image builder; the reference is `nix:0${image}`.

**`dockerTools.buildImage` and `imageFile` are out.** They stream the store into compressed tarballs
and duplicate what the binary cache already holds, which is the cost nix-snapshotter exists to
remove.

The contract that makes the interim disposable — every service declares these once, and the runner
is the only thing that changes:

| field             | nspawn                                               | nerdctl              | Pod                   |
| ----------------- | ---------------------------------------------------- | -------------------- | --------------------- |
| name              | `containers.<name>`                                  | `nerdctl run --name` | `metadata.name`       |
| entrypoint + args | `config.systemd.services`                            | the image config     | `command` / `args`    |
| environment       | `environment.etc` / `systemd.services.*.environment` | `-e`                 | `env` / ConfigMap     |
| state             | `bindMounts`                                         | `-v`                 | PVC                   |
| devices           | `bindMounts` of `/dev/dri`, `/dev/kfd`               | `--device`           | hostPath + node label |
| health            | a systemd unit check                                 | `--health-cmd`       | `readinessProbe`      |

Rules that hold for both tiers:

- **CPU-only hosts run the same definition.** Kokoro, DeepFilterNet and whisper-turbo have no device
  requirement, so the identical container runs on a 4-core box with no GPU.
- **The bench stays host-native** — a shell of `ffmpeg` calls and file targets, not a service. The
  tools it calls are Nix packages or containers, never a hand-installed binary.
- **A container does not bypass the policy**: if it starts a model server it is an engine profile
  like any other, and `admit` still decides.

## Kubernetes later (k3s or plain NixOS kubernetes)

The cluster is a deployment target, not a redesign. Four rules make every service cluster-ready
today, while it still runs as a NixOS container:

1. **One contract per service**: name, entrypoint, environment, ports, health path, volumes,
   devices. Declared once, consumed by whichever runner — nspawn now, a Pod later.
2. **State is a volume**, never the container filesystem: a bind mount now, a PVC later.
3. **Config through environment and files**, never baked into the image: a ConfigMap and a Secret
   later.
4. **No host path inside the service**, only through the contract, so a PVC can replace a bind
   mount without touching the service.

The scheduler rule does not change: **kubernetes schedules containers, the placement tree schedules
the card.** A Pod that starts a model server still calls `admit`, and GPU work is pinned to the
engine node with a label (`kdn.io/engine=r9700`) plus `/dev/dri` and `/dev/kfd` as hostPaths. One
authority for the card, across nspawn, podman and k8s.

Image path when the cluster arrives:

- **k3s** with the embedded containerd and nix-snapshotter (`services.k3s.setEmbeddedContainerd`,
  `virtualisation.containerd.nixSnapshotterIntegration`); k3s support landed in the March 2026
  release cycle.
- Images are `pkgs.nix-snapshotter.buildImage`, the Pod spec names `nix:0${image}`, and nothing is
  pulled from a registry.
- **Plain NixOS kubernetes** uses the same snapshotter and the same images.

That moves nix-snapshotter from "not a dependency" to "the cluster's image path", but it stays out
of today's path: tier 1 and tier 2 cover everything until the cluster exists.

## Migration to snapshotter containers

Once the path is proven (it is, on `etra`: one image, one `nerdctl` unit, `Hello, world!` in the
journal), move as much as possible into it. Two reasons, in this order: **segregation** — a service
owns its state and nothing else — and **backup** — a service is one directory plus a pinned image
revision.

### What moves, and what does not

| moves                                  | why                                                                    |
| -------------------------------------- | ---------------------------------------------------------------------- |
| Kokoro, whisper, DeepFilterNet, Demucs | CPU-only, no devices, tiny state; the natural first four               |
| `dots.ocr`, Real-ESRGAN/RIFE, LTX-2.3  | GPU but via a device bind, state is a models directory                 |
| Hermes Agent, ComfyUI (if adopted)     | long-running services with their own state                             |
| the media bench                        | _no_ — it is a shell of `ffmpeg` calls and file targets, not a service |

| stays native                     | why                                                                                                           |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| **strata** (the frontier engine) | a HIP engine tuned to this card, with the ROCm shim; containerising it would cost the tuning and gain nothing |
| **llama-swap**                   | the front door and process owner; it is what starts the containers' siblings                                  |
| **the manager / placement tree** | it schedules the card; it must outlive everything it schedules                                                |

### The contract a migrated service must satisfy

1. **One state root**, declared in the contract, under `/var/lib/kdn/<service>/` — bind-mounted now,
   a PVC later. No state anywhere else: not in the image, not in `$HOME`, not in `/tmp`.
2. **Config through env and files**, so a ConfigMap and a Secret can replace them.
3. **No host path inside the service** except the state root and declared devices.
4. **A health command**, so the unit, `nerdctl`, and a later `readinessProbe` share one definition.
5. **A backup drill**: stop the unit, copy the state root, restore it into a fresh container, and the
   service comes back. A service that fails the drill is not migrated.

Backup then has two halves and no third: the **data** (one directory per service) and the
**definition** (the image revision, already in the repo). A restore is `restore the directory` +
`nixos-rebuild switch`.

### State is a dataset, not a directory

Where the host has ZFS (`brys` and `etra` today), each service's state root is its **own dataset**, not a
directory inside a shared one:

```
tank/kdn/services/<name>   mountpoint=/var/lib/kdn/<name>   refquota=20G   compression=zstd
tank/kdn/models            mountpoint=/var/lib/kdn/models   ro in containers, not backed up
```

What that buys, all of it from the dataset boundary rather than from a backup script:

- **Backup is `zfs snapshot` + `zfs send -R`** (or `syncoid` to another host): atomic, incremental,
  and cheap because only the service's own state changes — the models dataset is shared read-only
  and re-downloadable, so it is deliberately outside the backup set.
- **Restore is `zfs receive` + `nixos-rebuild`**: the data back in place, the image revision from the
  repo. No file-level copy, no ordering.
- **Per-service accounting and quota** come free: `zfs list -o used` answers "what does this service
  cost", and `refquota` stops one service from filling the pool.
- **`zfs diff` answers "what changed since the last snapshot"**, which is the question a migration
  actually asks.
- **The container root stays disposable.** The writable layer holds nothing; a container that
  writes outside its volume is a bug the contract already forbids, and the dataset makes it visible.

Caveats that must be written per service:

- a snapshot is **crash-consistent**, not application-consistent. SQLite and most file-based
  services are fine; a database needs a dump or an `fsfreeze` in the snapshot hook, and that fact
  belongs in the service's contract entry.
- **Only ZFS hosts get this.** A host without a pool uses a plain directory under the same path and
  `restic`; the contract (one state root) is unchanged, which is why the switch is a mount, not a
  migration. Measured 2026-11-21: `etra` **does** have a pool (`etra-main`), so it gets datasets too.
  What it lacks is a persisted `/var/lib` (tmpfs root), so a plain directory there is ephemeral.
- **The dataset mount is the volume.** The container definition does not learn about ZFS; it is
  handed `/var/lib/kdn/<name>` and that is all.

### Proven drill

Proven 2026-11-21 on `etra` (pool `etra-main`) and `brys` (pool `brys-main`). The module is
`kdn.containers.containers.<name>.stateDataset`; the container gets `stateDir` mounted at the same
absolute path and exported as `KDN_STATE_DIR`.

**Declarative path, `etra`.** `workshop-state` declares a dataset; the module's oneshot creates it
before the container starts:

```sh
zfs create -p -o mountpoint=/var/lib/kdn/workshop-state -o compression=zstd \
  -o atime=off -o xattr=sa -o refquota=1G etra-main/etra/kdn/services/workshop-state

sudo zfs snapshot etra-main/etra/kdn/services/workshop-state@drill-1
echo DRIFT | sudo tee -a /var/lib/kdn/workshop-state/starts.log
sudo systemctl stop container-workshop-state.service   # ExecStopPost removes the container
sudo zfs rollback etra-main/etra/kdn/services/workshop-state@drill-1
sudo systemctl start container-workshop-state.service
```

```
=== 3. destroy the container ===
workshop-hello Up                 # workshop-state is gone from `nerdctl ps -a`
=== 6. the state after rollback + restart ===
2026-11-21T14:02:27+00:00
2026-11-21T14:05:54+00:00
2026-11-21T14:06:21+00:00         # the restarted container; DRIFT is gone
```

**By hand, `brys`.** containerd is not enabled there (it needs `hosts-den/brys/**`), so the dataset
was created with the same `zfs create` and the container ran under rootful `podman` on an `alpine`
image. Same result: a file written by the container survived `podman rm -f` + `zfs rollback`, and a
file written after the snapshot did not. Dataset, snapshot and the `-p` parents were destroyed
afterwards, so the drill leaves nothing outside the config.

**Plain directory, `etra`.** `workshop-hello` declares no dataset: `tmpfiles` creates
`/var/lib/kdn/workshop-hello`, the module mounts it, and the container appends a start line to
`starts.log` that the host reads back. It runs, but the directory is tmpfs — a plain state root
needs a persisted parent, and a dataset is the better answer wherever a pool exists.

### Risks

- **Containers do not isolate RAM.** Measured 2026-11-21: a 16.4 GB mmap in a second process
  OOM-killed the frontier on a 125 GiB host. A container changes nothing about that; the placement
  tree's RAM check is the only defence, and it must count mapped file size, not RSS.
- **GPU containers need explicit device binds** (`/dev/dri`, `/dev/kfd`) and the host's driver
  libraries from the shared store; a container that forgets them fails at the first tensor.
- **No CNI on a GPU-less host yet**, so `etra`'s containers run `--net=none` or `--net=host`; a
  container that needs one narrow endpoint gets a loopback relay instead of a bridge (`hermes` is
  the first: `127.0.0.1:9530` → the LiteLLM guest).
- **The policy still decides.** A container that starts a model server is an engine profile; `admit`
  is unchanged by the migration.

### Order

1. Audio (four services, CPU, smallest state) — proves the contract and the backup drill.
2. OCR and restoration (GPU, device binds) — proves a GPU container.
3. Hermes gateway and ComfyUI — proves a long-running service with real state.
4. Only then consider the media pipelines, which are a runner problem, not a container problem.

## Hermes Agent on `etra` (live)

Hermes Agent (MIT, `NousResearch/hermes-agent`) is the workshop's phone/cron front
door: a Python CLI agent with a tool shell, plus a messaging gateway that keeps its
memory in one directory. It runs as the nix-snapshotter container `hermes` on `etra`
— the **client** side of the split: no GPU, no cluster, no model of its own.

| what        | where                                                                                                      |
| ----------- | ---------------------------------------------------------------------------------------------------------- |
| package     | `packages/hermes-agent/default.nix` — `fetchFromGitHub` at a pinned commit + `python314.withPackages`      |
| container   | `hosts/etra/hermes.nix` → `kdn.containers.containers.hermes`, unit `container-hermes`                      |
| state root  | `/var/lib/kdn/hermes` — the container's `stateDir`, `HERMES_HOME` and `KDN_STATE_DIR`                      |
| model       | `http://127.0.0.1:9530/v1` — a loopback relay to the LiteLLM guest (`10.233.100.2:4000`)                   |
| credentials | `CUSTOM_API_KEY` in `/var/lib/kdn/hermes/litellm.env`, rendered at boot from the sops `litellm/client-key` |

### Log in and use it

```sh
sudo nerdctl exec -it hermes hermes                          # interactive CLI
sudo nerdctl exec hermes hermes -z "reply with one word"     # one-shot: only the answer on stdout
sudo nerdctl exec hermes hermes --version
```

`-z` / `--oneshot` is the scriptable mode: no banner, no spinner, no session line.
`-p` is **not** a prompt flag — it is `--profile`. Verified on `etra` 2026-11-21:

```
$ sudo nerdctl exec hermes hermes -z "reply with one word"
Okay
```

The gateway log names the route it took, which is the check that the wiring is real:

```
run_agent: OpenAI client created (agent_init, shared=True) … provider=custom base_url=http://127.0.0.1:9530/v1 model=qfn
agent.conversation_loop: API call #1: model=qfn provider=custom in=8521 out=31 total=8552 latency=9.2s
```

`-z` does not run the agent in its own process: it starts (or attaches to) the
gateway and sends the prompt through it as the `local` platform, so one gateway
serves every caller. On a container that is idling (see the next section) it starts
a gateway for the run and that gateway exits after 600 s with no clients.

The default model is `qfn` — the fleet frontier on `brys`, 393k context, and
profile-neutral (it asks the engine manager for `auto`, so it never forces a reload).
Switch for one call (flags go **before** `-z`, which takes the prompt as its value)
or persistently:

```sh
sudo nerdctl exec hermes hermes -m qfn-max -z "reply with one word"
sudo nerdctl exec -it hermes hermes config set model.default chat-std-mid
```

**Only models above 64k context work.** Hermes refuses anything smaller
(`Model X has a context window of 32,768 tokens, which is below the minimum
64,000`), which rules out the 32k "fast" pool (`chat-fast`, `code-std-fast`, …). The
usable names today are `qfn`, `qfn-max`, `qfn-colo`, `qfn-fast-colo` (393k) and
`chat-std-mid` (262k), plus the `requesty/*` ids.

A `429 … Limit resets at HH:MM` reply is the fleet, not the wiring: a model group
with one deployment goes into a 30 s cooldown after two failed requests
(`allowed_fails`/`cooldown_time` in `hosts/etra/litellm.nix`), and the frontier is
unavailable whenever the engine on `brys` is restarting.

### The messaging gateway

The gateway is the container's long-lived process. With **no** platform token the
entrypoint prints how to configure one and sleeps, so nothing polls anything. Add a
token and the entrypoint runs `hermes gateway run` instead:

```sh
sudo nerdctl exec -it hermes hermes gateway setup   # wizard: Telegram / Discord / Slack / …
sudo systemctl restart container-hermes
sudo journalctl -u container-hermes -f
```

The wizard writes the token to the profile's `.env`, **`/var/lib/kdn/hermes/.env`**:
`TELEGRAM_BOT_TOKEN`, `DISCORD_BOT_TOKEN` or `SLACK_BOT_TOKEN`. That file is the
token file and the only place a token lives. The entrypoint looks for exactly those
three names (in `.env` or in the container environment) to decide gateway-or-sleep.
Nix never writes `.env`, so the wizard's edits and any hand-added variable survive a
rebuild.

### State and backup

Everything the agent must keep is in one directory, `/var/lib/kdn/hermes`:

```
config.yaml    model/provider selection; seeded once from the store, then yours
.env           platform tokens (written by `hermes gateway setup`)
litellm.env    CUSTOM_API_KEY (managed: re-rendered on every boot)
sessions/  state.db  memories/  skills/  kanban.db  projects.db  …   memory and history
```

The directory is declared in `kdn.disks.persist."sys/state"`, so on `etra` it lives
inside the ZFS dataset `etra-main/etra/impermanence/sys/state` and is bind-mounted
over the tmpfs root — it already survives a reboot.

Backup today, the directory:

```sh
sudo systemctl stop container-hermes
sudo zfs snapshot etra-main/etra/impermanence/sys/state@hermes-$(date +%F)
sudo systemctl start container-hermes
```

A file-level copy of that one directory works too
(`sudo tar -C /var/lib -caf … kdn/hermes`). Stop the unit first: a snapshot of a
running SQLite database is only crash-consistent, and stopping costs nothing.

Restore: stop `container-hermes`, put the directory back (`zfs rollback` or the
tar), start the unit. The image comes from the repo, so a restore is the directory
plus `nixos-rebuild switch`.

Later, as its own dataset: set `stateDataset` on the container **and** drop the
`kdn.disks.persist` entry — both are documented at the top of
`hosts/etra/hermes.nix`. The module then creates
`etra-main/etra/kdn/services/hermes` with `mountpoint=/var/lib/kdn/hermes` and
mounts it before the container starts. Backup becomes `zfs snapshot` + `zfs send -R`
of that dataset, restore becomes `zfs receive` plus `nixos-rebuild switch`, and the
container definition does not change: it is handed the path either way.

### What the package does not ship

- **`browser-harness`** — not in nixpkgs at all. It is the engine of the
  `browser_exec` tool, whose own `check_fn` hides the tool when the import fails
  (`check_fn browser_exec_available returned False` in the container log), so only
  that tool is unavailable.
- **`nemo-relay`** — nixpkgs has 0.7.3, the project pins `>=0.11,<0.12`, and 0.7.3
  does not build here (`aws-lc-sys` asks for a system AWS-LC that the crate override
  does not supply). The runtime treats a missing module as a supported platform
  condition, so only Relay telemetry is off.
- **the npm frontends** (`--tui`, `hermes web`, `hermes webapp`) — they need a pnpm
  build of `ui-tui/`, `web/` and `webapp/`. The classic REPL and every headless path
  (`-z`, `gateway run`) are Python-only and work.
- **`hermes pm …`** — it installs Python packages into a writable tree, which a
  read-only store cannot provide. The `[messaging]` extra is baked in instead, so the
  Telegram/Discord/Slack adapters work without a lazy install.

### Container shape

- `--net=host`: `etra` has no CNI, so a nerdctl bridge is unavailable (the same
  reason `workshop-hello` runs `--net=none`). The agent's only endpoint is the
  loopback relay, so host networking adds no reachable surface beyond the host's own.
- `hermes-litellm-relay.service` — socat on `127.0.0.1:9530` → `10.233.100.2:4000`,
  bound to loopback so nothing off-host reaches the gateway through it.
- `hermes-env.service` — renders `litellm.env` from
  `/run/configs/llms/litellm/client-key` (sops) before the container starts, so no
  secret is in the repository, the store or the unit file.
- The image links one merged `/bin` (`runtimeTools` in `hosts/etra/hermes.nix`):
  bash, coreutils, git, ripgrep, curl, jq, python3 and friends. A nix-snapshotter
  image starts empty, so a tool that is not in that list does not exist inside the
  container — the first version of the entrypoint died on `install: command not
found`.
- `config.yaml` names a **named** provider (`providers.litellm` +
  `model.provider: litellm`). A bare `provider: custom` resolves through a fallback
  rung that never reads `CUSTOM_API_KEY`, which surfaces as a plain `HTTP 401:
Invalid API key` (measured 2026-11-21).

## Non-goals

ComfyUI is not adopted until a PoC needs a tensor graph sd.cpp cannot express; etra never runs
inference; no hosted service becomes a dependency.
