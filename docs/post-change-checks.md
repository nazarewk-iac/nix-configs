---
type: Reference
description: "Which checks a change needs, by blast radius, with an ETA and a resource estimate per check. Prefers a direct agent or human check over a codified bundle, and covers harness loads, host builds, activation, service verification, the supervised boot check, and the skip and defer controls."
authored_by: agent
timestamp: 2026-11-10T05:55:00+01:00
---

# Post-change checks

Every change gets the checks its blast radius demands: nothing more, because checks cost minutes,
and nothing less, because an unverified change is not done.

**A direct check beats a codified one.** The `checks/` tree holds tripwires for broad changes: shared
plumbing, cross-cutting refactors, flake inputs. Most of them exercise one narrow property and cost
far more than the direct command that proves the same thing. For a narrow change, run the command
that exercises the change: build the package, load the harness, build the host, call the service. Use
a codified bundle when the change is wide enough that you cannot name every affected path.

**Never run a bare `nix flake check`.** It takes about 11 minutes. The bundle catalog and its
measured times live in [checks/README.md](../checks/README.md).

## 1. Pick the blast radius

Read the changed paths, then take the highest class that matches.

| Class                 | Trigger                                                                                                                  | Checks                                                                                                |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| 0 — docs              | `*.md` only, outside `checks/`                                                                                           | [C1](#c1)                                                                                             |
| 1 — package           | `packages/**`                                                                                                            | [C1](#c1), [C2](#c2), [C5](#c5)                                                                       |
| 2 — shell and harness | `devenv.nix`, `modules/slots/**`, `modules/den/aspects/**` for the `devenv` class, `.opencode/**`, the pi extension list | [C1](#c1), [C3](#c3), [C4](#c4), [C6](#c6), [C7](#c7)                                                 |
| 3 — host module       | `hosts/**`, `modules/universal/**`, `modules/den/**` for the `nixos` or `darwin` class                                   | [C1](#c1), [C3](#c3), [C8](#c8), [C9](#c9), [C10](#c10)                                               |
| 4 — inputs            | `flake.nix`, `flake.lock`, `.flake.patches/**`                                                                           | [C1](#c1) and the full [flake update](flake-update.md) procedure: every host, then activation of each |

A change that spans classes takes the sum. A comment-only edit inside a host module is still class 3.

## 2. Check catalog

ETA is for a warm store and a warm evaluation cache. Resources are per check, not per run.

| id                  | Check                                 | Command                                                                            | ETA                         | Resources                                     |
| ------------------- | ------------------------------------- | ---------------------------------------------------------------------------------- | --------------------------- | --------------------------------------------- |
| <a id="c1"></a>C1   | Parse every changed Nix file          | `nix-instantiate --parse <file>`                                                   | < 1 s per file              | negligible                                    |
| <a id="c2"></a>C2   | Render or link-check changed Markdown | editor preview, or the repo's markdown check                                       | < 5 s                       | negligible                                    |
| <a id="c3"></a>C3   | Evaluate one aspect's assertions      | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-<aspect>"`                   | 2–4 s warm, 1–3 min cold    | 1–2 cores, < 1 GB                             |
| <a id="c4"></a>C4   | Bundle of the touched aspect family   | `nix build --no-eval-cache -L ".#checks.$SYS.bundle-den"`                          | ~108 s warm                 | 4 cores, 2–4 GB                               |
| <a id="c5"></a>C5   | Build one package                     | `nix build --no-link --print-out-paths .#<pkg>`                                    | 10 s–15 min                 | 4–8 cores, 2–8 GB, 1–10 GB disk               |
| <a id="c6"></a>C6   | Enter the devenv shell                | `devenv shell -- true`                                                             | 20 s warm, 5–20 min cold    | 4–8 cores, 4–8 GB, 5–30 GB disk               |
| <a id="c7"></a>C7   | Harness load check                    | `opencode plugin list`, `opencode models`, `pi --list-models`                      | 5–30 s                      | 1 core, < 1 GB, one model call if used        |
| <a id="c8"></a>C8   | Evaluate one host toplevel            | `nix eval --raw .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath` | 1–3 min                     | 2 cores, 2–4 GB                               |
| <a id="c9"></a>C9   | Build one host toplevel               | `nix build --impure --no-link --option builders "" --expr …`                       | 5–40 min cold, 1–5 min warm | 8+ cores, 8–16 GB, 20–60 GB disk              |
| <a id="c10"></a>C10 | Activate one host, then verify        | `ssh <host> nixos-rebuild switch …`, then `systemctl` checks                       | 1–3 min (plus the build)    | network to the host, 1 core                   |
| <a id="c11"></a>C11 | Boot check (reboot + verify)          | reboot, then [C10](#c10)'s verification                                            | 3–10 min                    | supervised; the host is unavailable meanwhile |
| <a id="c12"></a>C12 | Call the service the change touches   | `curl`/`client` against the endpoint                                               | 2–30 s                      | network, small                                |

`$SYS` is `x86_64-linux` for `oams`, `brys`, `etra`, `moss` and `briv`, and `aarch64-darwin` for
`anji`. `bundle-core` (~11 s) is the cheap tripwire; `bundle-pkgs` (~18 s) covers `packages/`.
`bundle-slow` (~710 s) belongs to a hand-off, not to a normal change.

## 3. Harness load checks (C7)

A class-2 change must prove both harnesses still load what they claim to load.

**opencode**

```sh
devenv shell -- true                     # rewrites the generated .opencode/ files
opencode plugin list                     # one row per plugin, with an id in the first column
opencode models | grep -c '^<provider>/' # every provider the change touches is listed
grep -a 'failed to load plugin' ~/.local/share/opencode/log/opencode.log | tail -3
```

A plugin whose id column shows `-` did not load. After an upgrade from a failed plugin, the running
service keeps the failed module cached per absolute path: call
`opencode api delete /api/debug/location --param location="$PWD"` (or restart the service) before you
conclude that the new file is broken.

After the OpenCode 1 → 2 upgrade, two things make a correct plugin look broken. First, the generated
`.opencode/plugins/*.ts` symlinks may still point at the V1 store paths; `readlink -f` them and check
that the content imports from `@opencode/plugin`, not `@opencode-ai/plugin`. Second, the service cache
above survives a file change at the same path, so a fixed file still reports the old error until the
location is evicted.

**pi**

```sh
pi --version
pi --list-models                          # vision, context and alias columns for the touched models
```

## 4. Host builds and activation (C8–C11)

Build the host without switching it:

```sh
nix build --impure --no-link --print-out-paths --option builders "" \
  --expr 'let f = builtins.getFlake "path:'"$PWD"'"; in f.nixosConfigurations.<host>.config.system.build.toplevel'
```

Use `darwinConfigurations.<host>` on `anji`. `--option builders ""` forces a local build; drop it only
when the builder is known good. Builds are the expensive step: prefer a warm store, and do not build a
host the change cannot reach.

Activate only the hosts the change reaches, in the order the owner names. With no order given, use
`moss`, `brys`, `etra`, `oams`, then `briv`, then `anji`.

```sh
sudo nixos-rebuild switch --flake .#<host> --option builders ""
ssh <host> 'systemctl is-system-running; systemctl --failed --no-legend --plain'
```

Then check the services the change touches (C12), for example `caddy`, `litellm`, `llama-swap`, or
the `llama-server` unit. A host is verified when the system state is `running` or `degraded` with no
failed unit that the change introduced.

A host that runs NixOS containers needs one extra check: a switch can restart `systemd-machined` and
leave `systemd-machined.socket` dead, which reports exit status 4 even though the containers still
run. Restore it with `systemctl stop systemd-machined.service` then
`systemctl start systemd-machined.socket`, and confirm the containers are still active.

A switch also restarts the user units of an active graphical session. On `oams` the Sway unit then
failed to start without a seat (`Failed to start a DRM session`, `Could not open target tty`), the
desktop dropped to the SDDM greeter, and the switch reported exit status 4. Activate a graphical host
when a fresh login is acceptable, and check the session afterwards with `loginctl list-sessions` and
`systemctl --user --failed`.

A **boot check** (C11) reboots the machine and repeats the verification. It is **supervised by
default**: ask the owner before a reboot, and never reboot a remote host you cannot watch. Run it
unattended only when the owner said the run is self-sufficient or asked for the reboot. After a
reboot, check `nix-daemon.socket` first: an ordering cycle in the unit graph makes systemd delete
that job, and then every `nix` command fails even though the system looks up.

## 5. Skipping and deferring

The owner can reduce the checks for a run:

- **A direct instruction wins.** "build only", "skip the checks", "defer checks", "do not activate"
  are honoured for the rest of the run.
- **`KDN_AGENT_CHECKS`** is the scriptable fallback: `skip` runs nothing, `defer` leaves the checks
  for the owner, `build-only` builds but never activates.

When checks are skipped or deferred, say which ones in the worklog and in the final report. Never
describe an unrun check as passed.

## 6. Record the result

The board gets one row per host or check with its state; the worklog gets one entry per run with the
exact command and the result. Both files are described in
[agent-journal.md](../.agents/rules/agent-journal.md).
