---
type: Task
description: Set up the mini-PC for the owner's mother as a simple, self-maintaining KDE desktop for user `bn`, installed from this repo's ISO over LAN with a NanoKVM, and using the same supervised-fleet harness.
status: open
authored_by: agent
timestamp: 2026-10-27T20:35:00+01:00
---

# The mother's mini-PC (`pryll`): a desktop that must not need care

This is the third host task with the same harness. The other two are
[../gaz-den-workstation/definition.md](../gaz-den-workstation/definition.md)
(blocked on firmware write-protect hardware) and
[../minipc-den-host/definition.md](../minipc-den-host/definition.md) (an
etra-style host with an SFP uplink). The owner picks which of the two mini-PC
candidates goes to which task later; **this task and the etra-style one are the
two that need no hardware purchase**.

The harness, the model ladder, the watch loop and the hand-off protocol are not
repeated here. They live in
[../gaz-den-workstation/design.md](../gaz-den-workstation/design.md). The
evaluation is
[../gaz-den-workstation/003-fleet-evaluation/definition.md](../gaz-den-workstation/003-fleet-evaluation/definition.md)
and measures whichever run happens first. Verified fleet, ISO and KVM facts are
in [../gaz-den-workstation/research.md](../gaz-den-workstation/research.md) and
[../minipc-den-host/research.md](../minipc-den-host/research.md).

## What makes this one different

Every other host in this repository has an owner who can read a stack trace. This
one has a user who cannot. That single fact decides most of the design:

| Constraint | Consequence |
|---|---|
| The user cannot repair the system | It must update itself, and a failed update must not leave a dead desktop. |
| The user cannot diagnose a network fault | The NanoKVM stays plugged in, permanently. It is the only remote way in. |
| The user will not report a subtle fault | Prefer boring, stable, and few moving parts over new and clever. |
| The machine is the user's whole computer | Her documents and photos matter more than any feature. Backups are a requirement, not a nice-to-have. |
| Support happens rarely and remotely | Unattended remote access must work before the machine leaves the bench. |

## Premises the owner has already set

| Item | State |
|---|---|
| A mini-PC, plugged in and powered. | owner |
| The machine boots this repo's ISO from USB. | `nix build .#install-iso` → `result/iso/kdn-nixos-install-iso.iso` |
| A NanoKVM is plugged into it (HDMI and USB). | owner |
| A plain **LAN** connection, no SFP, no VLAN. | owner |
| Host name: `pryll`, unless the owner says otherwise. | owner |

## Usability decisions the owner must make first

These are **not** agent decisions. The agent may propose a default for each, but
the owner answers them before the run starts, because every one of them shapes
`bn`'s daily experience and cannot be judged by a model. They are asked once, in
one message, and recorded in the task before phase 3.

| Decision | Why it cannot be delegated | Suggested default |
|---|---|---|
| **Interface language** (Polish, English, both) | It sets the system, the browser and the office suite at once. A wrong choice is a constant irritation. | Polish (`pl_PL.UTF-8`), as the current profile does |
| **Keyboard layout** | The physical keyboard decides it; a symbol in the wrong place is a daily papercut. | Plain `pl`, unless she needs the ChromeOS-style layout |
| **Time zone and clock format** | Small, and permanent. | Europe/Warsaw, 24-hour |
| **Desktop look** (light or dark, wallpaper) | Purely taste. | Light theme, the current image, or her own photo |
| **Autologin** (yes or no) | Convenience against privacy: anyone who opens the lid gets in. | Yes, it is the whole point of a desktop she cannot log into |
| **Applications on day one** | An empty menu is as bad as a cluttered one. | Browser, office suite, PDF reader, image viewer, file manager, VLC |
| **Browser** (Firefox or Chromium) | Her bookmarks and habits live in one. | Firefox, with the `bn` profile |
| **Remote support tool** (TeamViewer or RustDesk) | Licensing and her consent to be watched. | RustDesk if it tests clean, else TeamViewer |
| **Backup target** (USB disk, network, cloud) | Where her photos may live. | A local USB disk, plugged in permanently |
| **Any peripheral** (printer, scanner, webcam, speakers) | It must work on day one or it is a support call. | none assumed |

If the owner answers only some, the agent starts with the defaults for the rest
and says so in the worklog.

## The starting point is not blank

`hosts/pryll/` already exists and already describes a desktop for this user:

```nix
kdn.hw.cpu.intel.enable = true;
kdn.hw.gpu.intel.enable = true;
kdn.profile.machine.desktop.enable = true;
kdn.desktop.kde.enable = true;
kdn.profile.user.bn.enable = true;
services.displayManager.sddm.settings.Autologin = { Session = "plasma.desktop"; User = "bn"; };
services.teamviewer.enable = true;
kdn.disks.luks.volumes."hs-e100-pryll" = { … targetSpec = ata-HS-SSD-E100_256G_30023586951 … };
kdn.hw.nanokvm.enable = true;
```

So the pieces to keep are known: **KDE Plasma 6**, **SDDM autologin** into
`plasma.desktop` as `bn`, **TeamViewer**, `plasma` + Polish locale, and a
`kdn.disks` LUKS volume.

Three things in that file are evidence of trouble and must be handled
deliberately, not copied:

1. `systemd.services."home-manager-bn".serviceConfig` carries a `Restart =
   on-failure` hack with the comment `# fails on wallpaper`. The KDE wallpaper
   step fails. That is a defect to fix, not to paper over on a machine nobody
   can debug.
2. It is written against the **old tree** (`kdn.profile.user.bn`,
   `kdn.desktop.kde.enable`). The den equivalents are a `kdn.users.bn` row plus
   the `desktop-kde` and `user` aspects. Decide which route this host takes; see
   the open questions.
3. The disk is identified by `ata-HS-SSD-E100_256G_30023586951`. If this is not
   the same physical machine, every value is wrong and the recon in phase 1 tells
   us so.

## Phases

| Phase | Work | Gate |
|---|---|---|
| 0 | Harness up as in the sibling tasks. | a test delegation returns |
| 1 | Recon over the KVM: `dmidecode`, `lspci`, `lsblk -o NAME,SIZE,MODEL,TRAN`, RAM, NIC, Wi-Fi, firmware mode, Secure Boot. Does this match `hosts/pryll`? | a committed hardware profile, and a yes/no on "same machine" |
| 2 | **Ask the owner the usability decisions above**, and decide the route: port `hosts/pryll` to `hosts-den/pryll`, or keep the old tree and repair it. Recommendation: port, because a fresh install happens anyway. | the answers are recorded, and the route decision carries its reason |
| 3 | Desktop shape: KDE Plasma 6, SDDM autologin, `bn`'s locale and browser profile, and **only** the applications she uses. | the aspect list is committed and matches the recorded answers |
| 4 | Disk and install: `kdn.disks` for the real device, install over the KVM. | first boot reaches the desktop without a keyboard |
| 5 | Autonomy: automatic updates and garbage collection that cannot brick the boot, plus a working remote-support channel. | a reboot after an update, unattended, verified over the KVM |
| 6 | Safety net: a snapshot or backup of home directories, and a documented way to restore the machine from the KVM alone. | a restore is demonstrated once |
| 7 | Evaluation write-up. | the shared evaluation is done |

## Requirements

### Hard

1. The desktop appears with no keyboard and no login: SDDM autologin to Plasma as
   `bn`.
2. Updates happen without the user. A failed update falls back to the previous
   generation at boot, and the NanoKVM remains reachable throughout.
3. Unattended remote support works from outside the LAN. TeamViewer is used
   today; RustDesk is the alternative already in this repository. Pick one, and
   prove it after a reboot.
4. No aspect that exists only to look good or to be clever. No LLM serving, no
   gaming, no development toolset, no second desktop.
5. The disk layout is declarative and rebuildable from this repository.
6. No secret in the repo, a log, or a screenshot. The TeamViewer credential goes
   through the existing secret mechanism, never a plaintext option.
7. The NanoKVM is registered and left connected. The user's machine is supported
   over it, so it is not a temporary tool.

### Soft

- Polish locale and a light theme, unless the owner decided otherwise in the
  usability decisions above.
- A browser with her bookmarks profile, and an office suite and PDF reader that
  open her file types without asking.
- Keep the host name `pryll` unless the owner renames it.
- Prefer a wired ethernet connection; keep Wi-Fi configured as a fallback only.

## Known defect to fix, not to copy

`hosts/pryll/default.nix` restarts `home-manager-bn` up to three times because
the KDE wallpaper step fails. On this machine that hack is worse than the bug:
it hides a real failure in the unit that also applies her settings. Phase 3 must
find the actual cause (Stylix image fetch or a missing Plasma wallpaper plugin)
and make the unit succeed on the first run.

## Open questions

- **Is `hosts/pryll` the same physical machine?** The SSD serial and the Intel
  CPU are the only clues. Recon decides it.
- Old tree or den tree for this host? The owner's other hosts are moving to den.
  A desktop nobody debugs is an argument for the older, proven path; a fresh
  install is an argument for den. The phase 2 decision records the reason.
- TeamViewer or RustDesk for support? TeamViewer is proprietary and needs a
  licence for commercial use; RustDesk is in the tree and self-hostable. This is
  one of the usability decisions above.
- Automatic updates: `system.autoUpgrade` with a reboot window, or neither, with
  the owner doing it over the KVM? The user cannot be asked to reboot.
- Backup target: a local USB disk, or a network target? Nothing exists today.
  This is one of the usability decisions above.

## Acceptance

- `bn` logs in by switching the machine on. No password prompt at boot.
- A reboot after an update lands on the desktop with no intervention, verified
  over the KVM.
- Remote support connects after a reboot.
- A backup exists and a restore has been demonstrated.
- The host is defined in the repository, and the machine can be rebuilt from it.
- The shared fleet evaluation has real numbers from this run, or is marked "not
  observed".
