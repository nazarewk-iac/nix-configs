---
type: Design
title: angrr retention — the devenv policy, the 30-day period and the report-only first state
description: The design for the angrr retention change that landed in both module trees, with a source citation per claim.
status: in-progress
authored_by: agent
timestamp: 2026-09-11T21:19:04Z
---

# angrr retention — design

Parent task: [definition.md](definition.md).

This document describes the change that **landed**. Every line number below comes from a read of
the named file on 2026-09-11. The upstream angrr citations point at
`/nix/store/cmbhn8aqg7pmd67c0sf7qq71vjiycrj4-source`. `flake.lock` pins the `angrr` node to rev
`45e0f06f3691a494d495b81e6739508657e56b5f`, and that rev maps to the store path above.

## The problem

angrr runs today and it reaps almost nothing. Three separate root classes exist, and the service
reached one of them.

| Class | Count in the incident | Did angrr reach it? |
|---|---|---|
| Temporary root of a live build | 40,671 | **No.** Never. |
| `result*` out-link of a finished build | 9 | Yes in theory. The job never ran. |
| Stale `.devenv/**` project root | 24 | **No.** No policy matched. |

A three-host build filled the disk on 2026-09-11. Free space fell from 289 GB to 33 GB. A
collector pass then freed 0 MB, because the live build held 40,671 store paths as temporary roots.
Nine stale `result*` symlinks rooted whole closures from earlier check builds. A person removed
them by hand. `/nix` reported 927 GB total, 864 GB used and 63 GB free — 94 % full.

**angrr cannot reach the first class.** It reads only the directories in its `directory` setting,
and that setting defaults to `["/nix/var/nix/gcroots/auto"]`
(`/nix/store/cmbhn8aqg7pmd67c0sf7qq71vjiycrj4-source/angrr/src/config.rs:312-314`).
`/nix/var/nix/temproots` is not in that list. An added entry fails as well, because a temproot is a
lock file, not a symlink, and angrr calls `fs::read_link` on each entry (`run.rs:315-317`). A
temproot belongs to a live process and it is correct. The fix for that class is operational, not a
retention policy.

**The third class is the largest one, and it had no policy.** 24 of the 29 auto roots of the
measured Darwin host live under `.devenv/`. 13 of them were last written between 43 and 105 days
ago. The `direnv` policy targets `/\.direnv/`, which names a different directory, and this
repository carries no `.envrc`. angrr keeps a root that matches no policy: it logs a trace line and
it continues (`run.rs:153-158`).

**The job also never woke up on Darwin.** `services.angrr.timer.enable` is the only trigger there,
because the Darwin module writes `StartCalendarInterval` under `lib.mkIf cfg.timer.enable`
(`darwin/module.nix:48-49`) and it declares no `enableNixGcIntegration`. The live plist carried
`RunAtLoad = false` and no `StartCalendarInterval`.

**NixOS behaves differently.** `enableNixGcIntegration` makes the unit `wantedBy` and `before`
`nix-gc.service` (`nixos/angrr.nix:412-415`), so a NixOS host runs angrr before every collector
pass with no timer. Two of the three NixOS hosts opt out: `hosts/brys/default.nix:462` and
`hosts/oams/default.nix:327` both set `services.angrr.enable = false`. Host `etra` sets no
override, so angrr deleted there, unreviewed.

## The design

### The `devenv` temporary-root policy

Add one temporary-root policy that matches `/\.devenv/`. It closes the largest measured class.

The existing `direnv` policy cannot do the work. `.devenv` and `.direnv` are two separate
directories, and this repository uses devenv, not nix-direnv. The new policy carries a distinct
attribute name, so it collides with no existing policy name, and the change stays additive.

A `.devenv` link is safe to remove. devenv rewrites it on the next shell entry, so a wrong removal
costs one rebuild and never loses work. A `result` link is not safe in the same way — a wrong
removal destroys the artifact link of a person. So the two classes keep separate periods.

The design writes **no raw timer unit**. `services.angrr.timer` exists on both platforms
(`nixos/angrr.nix:344-353`, `darwin/module.nix:13-26`), and the module picks the mechanism. The
design sets `timer.enable` in the Darwin branch only, because NixOS already triggers the unit
through `enableNixGcIntegration`. It never sets `timer.dates` in a shared block: the NixOS type is
`str` and the Darwin type is `listOf (attrsOf int)`, and both defaults are 03:00.

### The 30-day period

The measured age distribution of the 24 `.devenv` roots holds an empty band. No root is between 17
and 42 days old. So 30 days reaps all 13 dead project roots and it keeps every root of an active
project, with a 13-day margin below and a 12-day margin above. No case is borderline.

The `result` period stays at 5 days. The nine `result*` links of the incident were all written the
same day, so no period catches them at that moment. That class failed for a different reason — the
job never ran — and the Darwin timer fixes it.

Accept one trade-off. angrr takes the age from the metadata of the symlink **target**
(`run.rs:319`), not from the last use, and devenv rewrites a link only when the derivation changes.
So a link of an active project can age out. devenv recreates it.

### The `dryRun` first state

One new option per tree puts angrr in report-only mode, and it defaults to `true`. It adds
`--dry-run` to `services.angrr.extraArgs` and it raises `services.angrr.logLevel` to `debug`.

`--dry-run` makes angrr skip the `fs::remove_file` call (`run.rs:551-553`). `debug` adds the line
that names each root a policy skips (`policy/temporary.rs:40-45`). That miss is exactly the
`.devenv`-versus-`.direnv` defect, so the level matters for the review.

The default is `true` for one reason: the Darwin daemon had never executed. A first pass would
delete against an unreviewed 29-root set. One timer wake-up and one log read cost far less than a
wrong first pass.

The Darwin report needs a log file. launchd sends the output of a daemon to `/dev/null` when
neither `StandardOutPath` nor `StandardErrorPath` is set, and the live plist set neither. NixOS
needs no such key, because the journal holds the unit output.

Accept one regression. Host `etra` deleted today with no override. The `true` default stops that
until a person reads one report. `nix.gc.options = "--delete-older-than 7d"` keeps running there,
so the machine still collects.

## What landed

Two trees carry the change. `modules/universal/profile/machine/baseline/default.nix` is the tree
every live host evaluates. `modules/den/aspects/profile-baseline.nix` is the tree an adopter reads.
A change in one tree only either fixes no machine or re-introduces the defect at the next port
step.

`U` = `modules/universal/profile/machine/baseline/default.nix`.
`D` = `modules/den/aspects/profile-baseline.nix`.

| Option | Value | `U` line | `D` line |
|---|---|---|---|
| the `dryRun` option declaration | `bool`, default `true` | `U:59-70` (`kdn.profile.machine.baseline.garbageCollection.dryRun`) | `D:130-142` (`kdn.profile-baseline-gc.dryRun`) |
| `services.angrr.extraArgs` | `lib.mkIf dryRun [ "--dry-run" ]` | `U:197` | `D:486` (nixos), `D:536` (darwin) |
| `services.angrr.logLevel` | `lib.mkIf dryRun (lib.mkDefault "debug")` | `U:198` | `D:487` (nixos), `D:537` (darwin) |
| `…temporary-root-policies.devenv.path-regex` | `"/\\.devenv/"` | `U:224` | `D:481` (nixos), `D:533` (darwin) |
| `…temporary-root-policies.devenv.period` | `"30d"` | `U:225` | `D:482` (nixos), `D:534` (darwin) |
| `…temporary-root-policies.result.*` | `"/result[^/]*$"`, `"5d"` | `U:205-208` | `D:468-469` (nixos), `D:529-530` (darwin) |
| `…temporary-root-policies.direnv.*` | `"/\\.direnv/"`, `"7d"` | `U:201-204` | `D:466-467` (nixos), `D:527-528` (darwin) |
| `services.angrr.enable` | `lib.mkDefault true` | `U:192` | `D:461` (nixos), `D:526` (darwin) |
| `services.angrr.enableNixGcIntegration` | `lib.mkDefault cfg.garbageCollection.enable` in `U`; `lib.mkDefault true` in `D` | `U:254` | `D:465` |
| `services.angrr.timer.enable` | `lib.mkDefault true`, Darwin only | `U:279` | `D:545` |
| `launchd.daemons.angrr.serviceConfig.StandardOutPath` | `"/var/log/angrr.log"` | `U:283` | `D:548` |
| `launchd.daemons.angrr.serviceConfig.StandardErrorPath` | `"/var/log/angrr.log"` | `U:284` | `D:549` |
| `nix.gc.options` | `lib.mkDefault "--delete-older-than 7d"` | `U:191` | `D:460` (nixos), `D:515` (darwin) |
| `nix.gc.interval`, Darwin | `[ { Hour = 3; Minute = 15; } ]` | `U:265-270` | `D:520-525` |

Five details of the landed code differ from a plain reading of the plan, and they need a record.

1. **`enableNixGcIntegration` sits outside the `garbageCollection.enable` guard** in the universal
   tree (`U:249-255`). The upstream option carries no `default` of its own
   (`nixos/angrr.nix:338-343`), and upstream supplies one inside `config = lib.mkIf cfg.enable`
   (`nixos/angrr.nix:380`). A guard would leave the option undefined on a host that sets
   `services.angrr.enable = false`, and every read of it would then fail. The comment at `U:250-253`
   states this.
2. **The den tree sets `enableNixGcIntegration = lib.mkDefault true`** (`D:465`), a literal. The den
   leaf holds no `garbageCollection.enable` switch. A consumer that runs its own collector drops the
   `kdn.profile-baseline-gc` name from `kdn.profile-baseline.includes` instead.
3. **The den option lands through one shared helper.** `gcDeclaration` (`D:127-143`) declares
   `kdn.profile-baseline-gc.dryRun`, and both the `nixos` class (`D:443`) and the `darwin` class
   (`D:509`) import it. An import dedupes by path, so the declaration lands once per consumer.
4. **`logLevel` keeps a `lib.mkDefault`** (`U:198`, `D:487`, `D:537`), so a host still overrides the
   level while `dryRun` stays `true`.
5. **The check is a new, separate assertion**, not an extension of the existing one. The existing
   collector assertion stays at `checks/den-mvp/assertions/machine-profiles.nix:390-406`. The new
   assertion, `angrr reaches the devenv root class, reports before it deletes, and wakes up on
   Darwin`, occupies `checks/den-mvp/assertions/machine-profiles.nix:407-431`. It reads nine values:
   the `devenv` regex and period on both classes, `extraArgs` on both classes, the NixOS
   `logLevel`, the Darwin `timer.enable` and the Darwin `StandardOutPath`. It does **not** read
   `StandardErrorPath`.

The den edit obeys `.agents/rules/slots-standalone.md`. The aspect declares its own option name,
it takes no custom module argument, and it names no option that `modules/universal/` declares.

## Verification

### The evaluation gate on the three NixOS hosts

Measured 2026-09-11. Each command ran once per host.

```bash
nix eval --raw '.#nixosConfigurations.<host>.config.services.angrr.extraArgs' --apply builtins.toJSON
# brys / oams / etra → ["--dry-run"]

nix eval --raw '.#nixosConfigurations.<host>.config.services.angrr.logLevel'
# brys / oams / etra → debug

nix eval --raw '.#nixosConfigurations.<host>.config.services.angrr.settings.temporary-root-policies.devenv.period'
# brys / oams / etra → 30d
```

`brys` and `oams` still set `services.angrr.enable = false` (`hosts/brys/default.nix:462`,
`hosts/oams/default.nix:327`). The options above evaluate there, but no unit runs. Only `etra`
produces a report on NixOS today.

### The check gate

```bash
nix build --no-eval-cache -L '.#checks.aarch64-darwin.den-eval-machine-profiles'
```

It passes with 20 of 20 assertions.

### The build gate, and its limit

**State this limit plainly: the angrr change carries an evaluation proof, not a build proof.** The
three-host build gate for `brys`, `oams` and `etra` passed at an earlier point, **before** the
angrr edit landed. No build ran after the edit. So the evidence above proves that every host
evaluates the new option values, and that the den assertions hold. It does not prove that a system
closure builds.

One build-time gate does exist and it did not run either. `services.angrr.configFile` defaults to
`validatedConfigFile`, which calls `angrr validate --config <generated>`
(`shared/options.nix:266-267`, `:326`). That step rejects a typo in a policy name or a policy with
no `period` at build time. A host build is the only way to exercise it.

### The remaining manual steps

1. `sudo angrr run --dry-run --log-level debug --no-prompt` on each host. Read every `Keep` and
   `Remove` line, per policy and per path.
2. Confirm the Darwin plist now holds `StartCalendarInterval`, and confirm `/var/log/angrr.log`
   fills after the first wake-up.
3. Set `dryRun = false`, one host at a time.
4. Leave `services.angrr.enable = false;` in `hosts/brys/default.nix` and `hosts/oams/default.nix`
   until the predecessor task closes the `result` defect.

## Open questions

Eight questions stay open. The count matches the promise in [definition.md](definition.md).

1. **Merge or keep two tasks?** `docs/tasks/2026-09/angrr-result-retention/` already holds the
   measured `result` defect and the Darwin timer finding. This design overlaps it, and it supersedes
   three of its statements (see question 2). Should this task absorb it, or stay a sibling that
   depends on it?
2. **Three statements of the predecessor task need a correction. May I patch that file?** Its
   `definition.md:53-54` says the Darwin `timer.dates` type "cannot go in the shared block, unlike
   the NixOS `str`" — correct — but it implies NixOS carries no timer option. NixOS carries one
   (`nixos/angrr.nix:344-353`). Its `definition.md:58` names `--interactive never`; the current CLI
   spells that `--no-prompt`, and the Darwin module already passes it (`darwin/module.nix:39`). Its
   `definition.md:60-61` cites `hosts/brys/default.nix:452` and `hosts/oams/default.nix:321`; the
   lines are now 462 and 327.
3. **How much space do the 13 stale `.devenv` roots hold?** Not measured. The 30-day period rests on
   the age band, not on a size. Run `nix path-info -Sh` over the `.devenv` targets when the machine
   is idle, and confirm the payoff.
4. **Is `dryRun = true` the right default on NixOS?** Host `etra` deleted before this change. The
   default stops that until a person reads one report, and `brys` and `oams` produce no report at
   all while they keep `services.angrr.enable = false`. The alternative is `true` on Darwin and
   `false` on NixOS, which needs a platform guard and reads worse.
5. **`/var/log/angrr.log` grows without a bound.** launchd appends and nothing rotates the file. A
   dry run at `debug` writes roughly one line per root per day, so the file stays small — but it is
   unbounded. Add a `newsyslog.d` entry, or accept it?
6. **`remove-root` stays `false`.** angrr then removes the out-link of the person and it leaves the
   `gcroots/auto` entry, which dangles until the next collector pass (`run.rs:546-550`). Do you want
   `remove-root = true` instead, which removes the `gcroots/auto` entry and leaves the `result`
   symlink of the person dangling? Neither choice is obviously right.
7. **`angrr touch` is out of reach in this repository.** It installs only through
   `programs.direnv.direnvrcExtra`, and this repository carries no `.envrc`. So no mtime is ever
   renewed, and every policy stays a pure age policy over the write time. Should a devenv slot call
   `angrr touch` on shell entry?
8. **The `user` profile policy stays `enable = false`** (`U:237`, `D:495`). So
   `/nix/var/nix/profiles/per-user/root/profile-1-link` survives at 141 days. It is one generation
   and probably small. Leave it, or turn the policy on?
