---
type: Reference
description: brys host — Ryzen 5950X / 128 GB DDR4 workstation. Also serves local LLMs via the kdn.llm.local slot.
timestamp: 2026-11-18T14:11:34+01:00
---

# brys host

Ryzen 9 5950X workstation, 128 GB DDR4, AMD Radeon AI PRO R9700 (32 GB, Vulkan compute for the
local LLMs). The RX 550 drives the displays.

- Host config: [`hosts-den/brys/default.nix`](default.nix)
- Build: `nix build .#denConfigurations.brys.config.system.build.toplevel`, copy it to the host, then `nix-env -p /nix/var/nix/profiles/system --set` + `switch-to-configuration switch`
- The universal twin (`hosts/brys/`) was removed on 2026-11-18; this directory is the only brys config

## Power-off recovery

brys has a motherboard or PSU fault: after any power-off (front-panel button, NanoKVM ATX
pulse, or a greeter shutdown), the machine can fail to start again. The power LED stays on, but
there is no POST, no HDMI signal, and the USB devices do not enumerate. A power-on press, a
reset pulse and a WoL magic packet do nothing.

The machine recovers only after it is fully disconnected from AC for 20-60 minutes. USB devices
backfeed enough power to keep the fault latched, so unplug the USB peripherals (including the
NanoKVM USB cable) together with the mains lead.

Observed on 2026-11-18: a greeter-initiated shutdown left brys dark for about 25 minutes; it
returned after the power lead was pulled.

**A warm `reboot` can also land in the fault.** A `reboot` on 2026-11-18 stopped at the same dead
state (no network, no HDMI, `udc` still `configured`). The NanoKVM **reset** pulse recovered it:
`echo out > /sys/class/gpio/gpio505/direction; echo 1 > .../value; sleep 1; echo 0 > .../value`
on `kvm-26e2`. The PSU stays on across a reset, so the AC-disconnect latch does not engage. Try the
reset before asking for a physical power press.

The NanoKVM reports the same fault as a dead KVM: no screenshot frame and `write /dev/hidg0: i/o
timeout`. Before touching the KVM, check `/sys/class/udc/*/state` on the KVM host. `not attached`
means the machine does not enumerate the gadget, which fits a powered-off brys. The KVM's power
LED input reads `1` even when the machine is off, so it proves nothing.

Reference and independent research:
<https://assistant.kagi.com/chat/6a8520e2-c7b2-4bb4-97d2-3c5247e1c25e>

Operational notes:

- Never pulse the NanoKVM power key to "test" a running host. A short ATX press is a clean
  shutdown request.
- The SDDM greeter puts its power control in the top-right corner. Keyboard focus can land
  there, and `Space` activates it. Change the session with the mouse, not with `Shift+Tab`.

## Local LLM serving

The fleet's llama-swap runs on `127.0.0.1:39700` as `llm-server`. The frontier
(`Qwen3.8-Flash-Next` QFN at 1M) is not a llama.cpp model any more: it is a **Strata** engine on
`:8080`, owned by `strata-manager` (`:8181`). Each frontier profile is a llama-swap entry that calls
`strata-select`, which asks the manager and then proxies: **`qfn`** (profile-neutral, sends `auto`),
**`qfn-max-multi`**, **`qfn-max-swarm`**, **`qfn-max`** and **`qfn-max-long`**, **`qfn-max-single`**,
**`qfn-fast-swarm`**, **`qfn-max-colo`**, **`qfn-fast-colo`**; **`qwen3-omni`** is the companion and
asks for no profile at all.

### Operating points and the resting profile

The card holds one engine at a time, and the VRAM reserve for the companion
(`qwen3-omni-30b-a3b`, video and audio) is a start-up argument — so a profile change is a reload,
not a slider. Measured 2026-11-21 (`docs/tasks/2026-11/brys-r9700-model-fit/measurements.md`,
"The swarm profiles"):

| profile      | pack + reserve                | aggregate t/s (concurrent callers) | omni              | RAM left     |
| ------------ | ----------------------------- | ---------------------------------: | ----------------- | ------------ |
| `max-multi`  | UD-IQ4_XS, whole card, 512k×5 |                               31.9 | 6.1 t/s co-loaded | 7-8 GiB      |
| `max-swarm`  | UD-IQ4_XS, whole card, 256k×8 |                               36.2 | 6.1 t/s co-loaded | 18.4 GiB     |
| `max-long`   | UD-IQ4_XS, whole card, 1M×2   |                               29.7 | 6.1 t/s co-loaded | 10.5 GiB     |
| `max-single` | UD-IQ4_XS, whole card, 1M×1   |                                  — | 6.1 t/s co-loaded | —            |
| `fast-swarm` | IQ2_XS, whole card, 384k×8    |                           **61.0** | 6.1 t/s co-loaded | **31.4 GiB** |
| `omni-max`   | UD-IQ4_XS + 21.5 GB reserve   |                     59-62 / 42 @1M | 96.9 t/s, ready   | 3-5 GiB      |
| `omni-fast`  | IQ2_XS + 21.5 GB reserve      |                      88 / 71.6 @1M | 98.8 t/s, ready   | 23-27 GiB    |

**The resting profile is `max-multi`** (rank 0 in `data/llm.nix`; decided 2026-11-21, it was
`omni-fast`): five 512k slots on the best pack, enough RAM left for a build, 31.9 t/s across five
concurrent callers. The colo profiles are the ones to borrow for a companion, and `fast-swarm` is the
throughput alternative (IQ2_XS is 22 GiB lighter in experts, so the same card holds more of them, and
it decodes twice as fast):

```bash
hack/brys-frontier.sh up --profile max-long --ttl 2h  # a long 1M session, then back
hack/brys-frontier.sh up --profile omni-fast          # borrow the card for the companion
hack/brys-frontier.sh up                              # back to the resting profile now
hack/brys-frontier.sh down                            # stop the engine, free the card
hack/brys-frontier.sh status                          # profile, models, RAM, VRAM
```

A flip costs 58-74 s either way (a reload plus a page-cache drop). Do not rely on omni co-loaded
beside any whole-card profile: it gets about 1 GiB of VRAM and runs at 6.1 t/s.

### The API an agent (or a person) steers it with

`strata-manager` on `:8181` is the control plane, and it is the only thing that changes the
profile. Picking a model in a harness never does: the `qfn` entry asks for `auto`, which keeps
whatever profile is current.

| call                                           | what it does                                             |
| ---------------------------------------------- | -------------------------------------------------------- |
| `GET /status`                                  | profile, last switch, loaded companions                  |
| `GET /stats`                                   | measured medians per event and per transition            |
| `GET /events?limit=N`                          | the raw timed records                                    |
| `POST /select {"profile": X}`                  | switch (any profile, `auto`, `none`)                     |
| `POST /select {"profile": X, "dry_run": true}` | what that switch would cost, without touching the engine |
| `POST /select {"profile": "auto"}`             | keep the current profile (what a harness alias sends)    |
| `POST /unload`                                 | unload the loaded companions; the engine is untouched    |
| `POST /unload {"model": "qwen3-omni"}`         | unload one companion                                     |

### The scenario it was built for

A coding session is running and a screenshot of a BIOS/boot error arrives:

1. `POST /select {"profile": "qfn-fast-colo"}` — only if `/status` says the engine is not already
   there; `dry_run` answers that without a reload.
2. Ask `qwen3-omni` for the reading. It loads beside the engine; the frontier keeps its KV and its
   conversation cache.
3. `POST /unload` when the question is answered. The VRAM comes back, the engine is untouched, and
   coding continues on the same process.
4. Return to `max-multi` when the work needs the whole card again, and do it between turns.

**A `qfn` request is never cut by a switch.** The manager drains first: it stops accepting new work,
waits for the leases the proxy holds to be released, and only then stops the engine. A request that
arrives during a switch waits for the new engine and is served by it. Measured 2026-11-20: a
streaming request answered in 6.2 s while the switch that it delayed took 72.5 s, both through the
gateway on etra and from the harness directly.

### Every step is timed

The manager appends one JSON line per event to `events.jsonl`:
`switch` (from, to, seconds, cause, ok), `engine_load`, `engine_stop`, `cache_drop`,
`companion_up`, `companion_down`. `GET /stats` aggregates n/median/p90/max per event and per
transition, so a future switching skill quotes measured costs rather than guesses. First day of
data (2026-11-19): switch median 42 s, `max → omni-fast` 50 s, `omni-fast → max` 69 s, engine load
42-60 s, engine stop 3.7 s, cache drop 4.2 s, companion load 90 s, companion unload 0.6 s.

The `llms` appliance specialisation from the universal tree is **not ported** to the den host
yet. Only the `desktop` boot profile exists, so the served context sizes are the ones that share
RAM with a browser (see `data/llm.nix` `servers.brys.profiles.desktop`).

## WAN shaping

A model download from Hugging Face reaches ~105 MB/s (845 Mbit/s) on this host, which is more
than the 1 Gbit/s WAN carries together with anything else: every other host then sees stalled
handshakes. `wan-shaping.nix` caps **inbound TCP/443** at 600 Mbit/s on `kdn-eth-2g`, with an
`ifb` device and a `tbf` qdisc. A 100 GB quant then lands in about 25 minutes and the other
400 Mbit/s stay free. LAN, SSH, the llama-swap API and uploads are not shaped.

Measured 2026-11-18: a 300 Mbit setting delivered 34.5 MB/s; the shipped 600 Mbit setting
delivers 68-70 MB/s with the qdisc reporting `overlimits`. Service: `kdn-wan-shaping`
(`systemctl disable --now kdn-wan-shaping` turns it off).

Rejected alternatives: `trickle` under-delivers by 3x at these rates; the `drek` border router
(OpenWrt, Cortex-A53) shapes, but its DSA port counters do not report the shaped traffic and a
200 Mbit cake setting delivered 446 Mbit/s, so it cannot be tuned there.

The exact deployed state — models, serving endpoint, download mode and rate
cap, persistence, and secrets — is documented in
[`docs/local-llms.md`](../../docs/local-llms.md). The box hardware and the
measured performance are in [`performance.md`](performance.md).
