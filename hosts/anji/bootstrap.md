---
type: Reference
description: Non-default macOS settings on host `anji` that live outside Lix and nix-darwin, with how to reproduce each one.
timestamp: 2026-10-01T17:38:07+02:00
---

# anji bootstrap

`anji` is an Apple Silicon Mac mini M2 (16 GB RAM, 256 GB internal disk). Lix and nix-darwin
manage most of the host. This file records the settings that live **outside** Lix and nix-darwin.
A setting is "outside" when a person applied it by hand, or when the macOS installer or the Nix
installer applied it. A rebuild of the nix-darwin configuration does not restore these settings.

The goal is a full rebuild from a blank disk. The table names each setting, states whether a script
can set it, and links to the detailed section below.

## Settings

| Name | Description | Programmatic? | Detail |
|---|---|---|---|
| Hostname | `ComputerName`, `LocalHostName`, `HostName` are all `anji`. | Yes — nix-darwin `networking.{computerName,hostName,localHostName}` | [Hostname](#hostname) |
| Time zone | `Europe/Warsaw`, network time on. | Yes — nix-darwin `time.timeZone` | [Time zone](#time-zone) |
| Locale | `AppleLocale` is `en_US@rg=plzzzz`; languages `en-US`, `pl-PL`. | Partial — `system.defaults.CustomUserPreferences` or a manual `defaults write` | [Locale](#locale) |
| FileVault | On. The internal disk is encrypted. | Partial — `fdesetup` on the command line; no nix-darwin option | [FileVault](#filevault) |
| SIP | Enabled. | No — Recovery Mode only | [SIP](#sip) |
| Remote Login (SSH) | On. | Yes — nix-darwin `services.openssh.enable` | [SSH](#ssh) |
| SSH daemon config | Extra `sshd_config.d` fragments, host keys, `AuthorizedKeysCommand`. | Yes — nix-darwin `services.openssh.extraConfig` plus the repo's own fragments | [SSH](#ssh) |
| Application firewall | On, stealth mode off. | Yes — nix-darwin `networking.applicationFirewall` | [Firewall](#firewall) |
| Screen Sharing | Enabled. | No nix-darwin option — `kickstart` or System Settings | [Screen Sharing](#screen-sharing) |
| Remote Management (ARD) | Not configured. | No nix-darwin option — `kickstart` | [Screen Sharing](#screen-sharing) |
| Power management | Sleep off, display sleep off, disk sleep 10 min, wake-on-LAN on, Power Nap on. | Partial — nix-darwin `power.sleep.*` covers sleep only | [Power](#power) |
| Software update | Automatic download and install on. | Partial — `system.defaults.SoftwareUpdate.AutomaticallyInstallMacOSUpdates` | [Software update](#software-update) |
| Nix store volume | A dedicated APFS volume `Nix Store` mounted at `/nix`. | No — created by the Nix installer | [Nix store volume](#nix-store-volume) |
| External volumes | `anji-ext-01`, `anji-ext-02` on `/etc/fstab` and `/etc/synthetic.conf`. | No — manual `diskutil` and `/etc/fstab` | [External volumes](#external-volumes) |
| Full Disk Access | Grants for `sshd`, the Nix bash, and UTM. | No — SIP protects the TCC database | [Full Disk Access](#full-disk-access) |
| Users | `kdn` (admin), plus `kdn-nix-remote-build` and the Nix `nixbld*` accounts. | Partial — nix-darwin `users.users`; the remote-builder account comes from the repo | [Users](#users) |
| Sudo | Touch ID and `pam_reattach` via `/etc/pam.d/sudo_local`. | Yes — nix-darwin `security.pam.services.sudo_local` | [Sudo](#sudo) |
| Homebrew | `/opt/homebrew`, managed by nix-darwin `homebrew`. | Yes — nix-darwin `homebrew` | [Homebrew](#homebrew) |
| NetBird | A launchd daemon from `/usr/local/bin/netbird`, a symlink into `NetBird.app`. | Partial — nix-darwin `services.netbird`; the app is a cask | [NetBird](#netbird) |
| Login items | `diskutil` (from `org.nixos.darwin-store`), NetBird, several `sh` jobs. | Partial — a launchd daemon registers its own item | [Login items](#login-items) |
| Shell | `kdn` uses `/bin/zsh`; `/etc/shells` adds the Nix `fish`. | Yes — nix-darwin `users.users.<name>.shell` | [Shell](#shell) |

## Hostname

All three names are `anji`. nix-darwin sets them from three options:

```nix
networking.computerName = "anji";
networking.hostName = "anji";
networking.localHostName = "anji";
```

`networking.localHostName` defaults to `networking.hostName`. To set them by hand:

```bash
sudo scutil --set ComputerName anji
sudo scutil --set LocalHostName anji
sudo scutil --set HostName anji
```

## Time zone

The time zone is `Europe/Warsaw`, and network time is on. nix-darwin sets the zone:

```nix
time.timeZone = "Europe/Warsaw";
```

To set it by hand:

```bash
sudo systemsetup -settimezone Europe/Warsaw
sudo systemsetup -setusingnetworktime on
sudo systemsetup -setnetworktimeserver time.euro.apple.com
```

## Locale

`AppleLocale` is `en_US@rg=plzzzz`. The suffix `@rg=plzzzz` sets the region to Poland while the
language stays English. `AppleLanguages` is `en-US`, then `pl-PL`.

nix-darwin has no `AppleLocale` option. Two routes:

- `system.defaults.CustomUserPreferences."com.apple.menuextra.clock"` style entries, or
- a manual write:

```bash
defaults write -g AppleLocale "en_US@rg=plzzzz"
defaults write -g AppleLanguages '(en-US, pl-PL)'
```

A full locale change needs a logout.

## FileVault

FileVault is on. `fdesetup status` returns `FileVault is On.` nix-darwin has no FileVault option.

```bash
sudo fdesetup status
sudo fdesetup enable
```

The recovery key is in the owner's KeePass. An unlock at boot uses the volume passphrase, not this
key.

## SIP

System Integrity Protection is enabled. A change needs Recovery Mode:

```bash
csrutil status
```

## SSH

Remote Login is on. nix-darwin sets `services.openssh.enable = true`. The daemon config is split
across `/etc/ssh/sshd_config.d/`:

| Fragment | Managed by | Purpose |
|---|---|---|
| `050-kdn-authorized-keys-command.conf` | repo | `AuthorizedKeysCommand` for the remote-builder account |
| `050-kdn-debug.conf` | repo | `LogLevel DEBUG` |
| `099-host-keys.conf` | nix-darwin | the three host key paths |
| `100-macos.conf` | macOS | `UsePAM`, `AcceptEnv`, `sftp` |
| `100-nix-darwin.conf` | nix-darwin | `services.openssh.extraConfig` |
| `101-authorized-keys.conf` | nix-darwin | `AuthorizedKeysCommand /bin/cat` |

The host keys live in `/etc/ssh/ssh_host_*_key`. They are **not** managed by nix-darwin and survive
a rebuild only if the disk survives. On a fresh disk, regenerate them:

```bash
sudo ssh-keygen -A
```

The remote-builder account accepts keys through
`/etc/ssh/authorized-keys-command` and `/run/configs/nix/ssh/%u/id_ed25519.pub`.

## Firewall

The application firewall is on. Stealth mode is off. nix-darwin sets both:

```nix
networking.applicationFirewall.enable = true;
networking.applicationFirewall.enableStealthMode = false;
```

To set it by hand:

```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode off
```

## Screen Sharing

Screen Sharing is enabled. Remote Management (ARD) is not configured. nix-darwin has no option for
either. Use the `kickstart` tool:

```bash
# enable Screen Sharing
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -activate -configure -access -on -restart -agent -privs -all

# disable it again
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -deactivate -configure -access -off
```

Screen Sharing also needs a Full Disk Access-style grant for screen recording. Add it in System
Settings → Privacy & Security → Screen Recording.

## Power

The power settings keep the machine awake, so it stays a builder. nix-darwin sets sleep only:

```nix
power.sleep.computer = "never";
power.sleep.display = "never";
power.sleep.harddisk = 10;
```

The rest needs `pmset`:

```bash
sudo pmset -a sleep 0
sudo pmset -a displaysleep 0
sudo pmset -a disksleep 10
sudo pmset -a womp 1
sudo pmset -a powernap 1
sudo pmset -a autorestart 1
sudo pmset -a ttyskeepawake 1
```

Current values:

| Key | Value | Meaning |
|---|---|---|
| `sleep` | 0 | never sleep |
| `displaysleep` | 0 | display never sleeps |
| `disksleep` | 10 | disk sleeps after 10 min |
| `womp` | 1 | wake on LAN |
| `powernap` | 1 | Power Nap on |
| `autorestart` | 1 | restart after power failure |
| `ttyskeepawake` | 1 | keep awake while a tty is active |

## Software update

Automatic download and install are on. nix-darwin sets one key:

```nix
system.defaults.SoftwareUpdate.AutomaticallyInstallMacOSUpdates = true;
```

To set the rest by hand:

```bash
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -bool true
```

## Nix store volume

The Nix store lives on a dedicated APFS volume named `Nix Store`
(UUID `b5b3a9c8-86a2-4aff-b45a-bf563b7152a2`) mounted at `/nix`. The Determinate Systems
nix-installer created it. A launchd daemon, `org.nixos.darwin-store`, mounts it at boot.

`/etc/fstab` holds the mount line:

```
UUID=b5b3a9c8-86a2-4aff-b45a-bf563b7152a2 /nix apfs rw,noauto,nobrowse,suid,owners
```

The installer receipt is at `/nix/receipt.json` (installer version 0.17.1, planner `macos`). A
fresh install recreates the volume. A move of the volume is a separate task — see
[docs/tasks/2026-10/nix-store-external-drive/definition.md](../../docs/tasks/2026-10/nix-store-external-drive/definition.md).

## External volumes

Two encrypted APFS volumes hold the large data. `/etc/fstab` mounts both with `noauto`. A
`preActivation` block and a launchd daemon unlock and mount them at boot. The full procedure is in
[hosts/anji/disks.md](disks.md).

`/etc/synthetic.conf` lists the mount points and the `nix` and `run` entries:

```
nix
run	private/var/run
anji-ext-01
anji-ext-02
```

## Full Disk Access

TCC grants Full Disk Access to the exact binary path. The grants on `anji`:

| Binary | Why |
|---|---|
| `/usr/libexec/sshd-keygen-wrapper` | SSH sessions inherit the grant |
| `/bin/sh` | platform binary, implicitly allowed |
| `/nix/store/...-bash-5.3p9/bin/bash` | legacy grant |
| `/nix/store/...-bash-5.3p15/bin/bash` | the stock builder daemon |
| `com.utmapp.UTM` | the UTM app |

A nixpkgs bump changes the bash path, so the grant must repeat. SIP protects the TCC database, so
no script can add a grant. The owner adds it in System Settings → Privacy & Security → Full Disk
Access. The stable-binary route in [docs/darwin-quirks.md](../../docs/darwin-quirks.md) avoids the
repeat.

## Users

| User | Kind | Source |
|---|---|---|
| `kdn` | admin, uid 501 | manual / macOS setup |
| `kdn-nix-remote-build` | service account | this repo's `kdn.profile.remote-builders` |
| `nixbld1`..`nixbld32` | build users | the Nix installer |

`kdn` is in the `admin` group. The remote-builder account is created by nix-darwin from the repo's
remote-builder module. The `nixbld*` accounts come from the Nix installer.

## Sudo

Touch ID and `pam_reattach` are wired through `/etc/pam.d/sudo_local`, which nix-darwin manages.
The host sets:

```nix
security.pam.services.sudo_local.touchIdAuth = true;
security.pam.services.sudo_local.reattach = true;
```

`pam_reattach` makes Touch ID work inside a terminal multiplexer.

## Homebrew

Homebrew lives at `/opt/homebrew`, managed by nix-darwin's `homebrew` module. The host adds casks
and taps. See [hosts/anji/default.nix](default.nix).

## NetBird

NetBird runs as a launchd daemon. `/usr/local/bin/netbird` is a symlink into
`/Applications/NetBird.app/Contents/MacOS/netbird`. The app is a cask. nix-darwin has a
`services.netbird` module that runs the CLI package instead. The plist at
`/Library/LaunchDaemons/netbird.plist` runs `netbird service run`.

## Login items

The background-task manager lists several items. `org.nixos.darwin-store` registers `diskutil`.
NetBird registers itself. Several `sh` jobs come from launchd daemons. A launchd daemon registers
its own item, so nix-darwin-managed daemons reappear after a rebuild.

## Shell

`kdn` uses `/bin/zsh`. `/etc/shells` adds `/run/current-system/sw/bin/fish` from Nix. nix-darwin
sets the shell:

```nix
users.users.kdn.shell = pkgs.zsh;
```

## Related docs

- [hosts/anji/disks.md](disks.md) — the external volumes and the boot unlock.
- [docs/darwin-quirks.md](../../docs/darwin-quirks.md) — TCC, the login keychain, APFS locking.
- [docs/multi-arch-builder.md](../../docs/multi-arch-builder.md) — the builder bootstrap.
- [docs/nix-darwin-getting-started.md](../../docs/nix-darwin-getting-started.md) — the installer.
