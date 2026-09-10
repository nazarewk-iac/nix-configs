---
type: Research
title: lume unattended macOS guest — boot and shell verification
description: A real run of lume 0.5.3 unattended IPSW install on macOS 26.6.2, and the shell access result.
task: definition.md
authored_by: agent
timestamp: 2026-09-10T05:30:00Z
tags: [lume, macos, virtualization, tart-alternative]
---

# Verdict

**Yes.** A fresh lume guest gives a usable shell on macOS 26.6.2. The guest reports user `lume`,
macOS 26.6.2 (25G83), and SIP enabled.

Two important qualifications apply:

1. `lume create --unattended` **fails and deletes the guest** on this host. Its own SSH health
   check never passes. You must split the work into `lume create` plus `lume setup`, because
   `lume setup` keeps the guest after a failure.
2. Upstream issue #1440 **reproduces**. The console stays parked on a Setup Assistant pane. SSH
   works at the same time, so the park does not block shell access.

# Host baseline

`verified` — command:

```
lume --version ; lume ls ; df -h / ; sw_vers ; uname -m
```

Output:

```
0.5.3
No virtual machines found
/dev/disk3s3s1  927G  648G  279G  70% /
ProductName:		macOS
ProductVersion:		26.6.2
BuildVersion:		25G83
arm64
```

# Step 1 and 2 — the exact command, run 1

`verified` — command (through the repo zellij helper, pane `lume-create`):

```
lume create rehearse --ipsw latest --unattended tahoe --cpu 4 --memory 8GB --disk-size 60GB --network nat
```

Result: **failure**. lume deleted the guest. Full log: `.cache/agent-notes/lume-create.log`
(369 lines).

Timeline, from the log:

| Phase | Start (UTC) | End (UTC) | Duration |
|---|---|---|---|
| IPSW download | 04:08:07 | 04:13:40 | 5 min 33 s |
| macOS install | 04:13:44 | 04:16:25 | 2 min 41 s |
| Offline unattended patch | 04:16:28 | 04:16:53 | 25 s |
| Verify boot plus SSH health check | 04:16:54 | 04:22:05 | 5 min 11 s |
| Total | 04:08:02 | 04:22:06 | **14 min 04 s** |

Key log lines, `verified`:

```
[2026-09-10T04:16:53Z] INFO: Offline macOS unattended setup completed name=rehearse mountPoint=/Volumes/Data
[2026-09-10T04:16:58Z] INFO: Running SSH health check timeout=5s retries=60 host=192.168.64.6 user=lume
[2026-09-10T04:22:05Z] ERROR: SSH health check failed after all retries retries=60 host=192.168.64.6
[2026-09-10T04:22:06Z] INFO: Cleaning up VM after failed unattended setup name=rehearse
[2026-09-10T04:22:06Z] ERROR: Failed to create VM error=Health check failed: Health check 'ssh' failed
```

`verified` — the delete is real. Command `lume ls` printed `No virtual machines found`, and
`ls -la ~/.lume/rehearse` printed `No such file or directory`. lume also kept no IPSW copy, so a
retry pays the 19 GB download again.

`verified` — lume's own SSH to the guest succeeded **inside** the same failed window:

```
[2026-09-10T04:17:02Z] INFO: Wrote VNC config to VM via SSH port=53643 name=rehearse
[2026-09-10T04:17:04Z] INFO: Wrote VNC config to VM via SSH port=53644 name=rehearse
```

This is 4 s after health-check attempt 1. So SSH already worked while the health check reported
60 failures. The health check is the defect, not the guest.

# Step 2b — a guest that survives, run 2

lume deletes the guest only in the `create` error path. `lume setup` keeps it. So run 2 splits the
work. Two deviations from the exact command apply, and both are deliberate:

- `--ipsw <local path>` replaces `--ipsw latest`. The local file is the same image that
  `lume ipsw` names: `UniversalMac_26.6.2_25G83_Restore.ipsw`.
- `--unattended tahoe` moves to a separate `lume setup` call.

CPU, memory, disk size, network mode and the `tahoe` preset stay unchanged.

`verified` — the IPSW URL:

```
lume ipsw
→ https://updates.cdn-apple.com/2026SummerFCS/fullrestores/140-75212/A2A24B94-1FC1-45A3-93F7-C51B02AF1F4D/UniversalMac_26.6.2_25G83_Restore.ipsw
```

`verified` — download 04:29:57 → 04:34:24 UTC, **4 min 27 s**, 19 GB.

`verified` — create without the preset:

```
lume create rehearse --ipsw "$IPSW" --cpu 4 --memory 8GB --disk-size 60GB --network nat
```

Output tail:

```
[2026-09-10T04:37:04Z] INFO: VM created successfully name=rehearse
RUN2_CREATE_END 2026-09-10T04:37:04Z rc=0
rehearse  macOS  4  8.00G  21.3GB/60.0GB  1024x768  stopped  nat  home
```

Duration 04:34:24 → 04:37:04 = **2 min 40 s**. Log: `.cache/agent-notes/lume-run2.log`.

`verified` — the preset, as a separate step:

```
lume setup rehearse --unattended tahoe --vnc-port 5999
```

It fails the same way, but it keeps the guest. Log: `.cache/agent-notes/lume-setup.log`.

```
[2026-09-10T04:40:11Z] INFO: Offline macOS unattended setup completed mountPoint=/Volumes/Data name=rehearse
[2026-09-10T04:40:16Z] INFO: Running SSH health check host=192.168.64.7 user=lume timeout=5s retries=60
[2026-09-10T04:40:21Z] INFO: Wrote VNC config to VM via SSH port=5999 name=rehearse
[2026-09-10T04:45:23Z] ERROR: SSH health check failed after all retries host=192.168.64.7 retries=60
[2026-09-10T04:45:23Z] INFO: VM stopped after failure name=rehearse
[2026-09-10T04:45:23Z] ERROR: Failed to run unattended setup error=Health check failed: Health check 'ssh' failed
```

No `Cleaning up VM` line appears. That absence is the whole reason run 2 leaves a guest behind.
Duration 04:39:47 → 04:45:23 = **5 min 36 s**.

# Step 3 — boot

`verified` — command and output:

```
lume run rehearse --detach --display none --vnc-port 5999 --vnc-password secret123
→ Started 'rehearse' in the background (PID 32360).

lume ls
→ rehearse  macOS  4  8.00G  24.1GB/60.0GB  1024x768  running  nat  home  -  192.168.64.7  yes  vnc://:secret123@127.0.0.1:5999
```

The guest IP is `192.168.64.7`.

# Step 4 — the decisive check

`verified` — through lume's own client:

```
lume ssh rehearse 'id -un; sw_vers; csrutil status; uname -m; echo lume | sudo -S -p "" id -un 2>&1 | tail -2'
```

Output:

```
lume
ProductName:		macOS
ProductVersion:		26.6.2
BuildVersion:		25G83
System Integrity Protection status: enabled.
arm64
root
```

`verified` — through the system `ssh` binary, with my own config bypassed:

```
sshpass -p lume /usr/bin/ssh -F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o PreferredAuthentications=password -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 \
  -o ConnectTimeout=10 lume@192.168.64.7 'id -un && sw_vers && csrutil status && uname -m'
```

Output:

```
Warning: Permanently added '192.168.64.7' (ED25519) to the list of known hosts.
lume
ProductName:		macOS
ProductVersion:		26.6.2
BuildVersion:		25G83
System Integrity Protection status: enabled.
arm64
```

All three success criteria hold: user `lume`, the guest macOS version, and SIP enabled.

## A macOS 26 trap: a Nix `ssh` cannot reach the guest

`verified` — the Nix-provided `ssh` fails every time, even with `-F /dev/null`:

```
sshpass -p lume ssh -F /dev/null ... lume@192.168.64.7 'id -un'
→ ssh: connect to host 192.168.64.7 port 22: No route to host
→ exit 255
```

`verified` — that `ssh` is the Home Manager one:

```
command -v ssh
→ /etc/profiles/per-user/kristof.nazarewski/bin/ssh
ls -la /etc/profiles/per-user/kristof.nazarewski/bin/ssh
→ ... -> /nix/store/j7dh9jjnpjjvb2yi7wmshh37mcw3pl6d-home-manager-path/bin/ssh
```

`verified` — a Nix `bash` fails the same way, and Apple's `nc` succeeds at the same moment:

```
timeout 8 bash -c "exec 3<>/dev/tcp/192.168.64.7/22 && head -c 40 <&3"
→ bash: connect: No route to host

timeout 8 nc -v -w 5 192.168.64.7 22 </dev/null
→ Connection to 192.168.64.7 port 22 [tcp/ssh] succeeded!
→ SSH-2.0-OpenSSH_10.3
```

`verified` — `/usr/bin/ssh` succeeds, as the block above shows. So the split is per binary, not
per host or per route.

`unverified` — the cause is macOS local-network privacy. Apple-signed binaries hold the
permission; ad-hoc-signed Nix binaries do not. **One step to settle it:** read
`/Library/Preferences/com.apple.networkextension.necp.plist` or the TCC local-network records,
or grant the permission to the Nix `ssh` and retest.

`unverified` — `ping` never works, even when TCP works. `netstat -rn -f inet` shows a reject flag
on the subnet route:

```
192.168.64         link#27            UC              bridge100      !
```

**One step to settle it:** delete that route as root and retest ICMP. That needs sudo on the host,
which this run does not use.

## The screen the guest is parked on — #1440 reproduces

`verified` — command:

```
vncdo -s 127.0.0.1::5999 -p secret123 capture .cache/agent-notes/shots/desktop.png
```

The screenshot shows a Setup Assistant pane:

- Title: **Update Mac Automatically**
- Body: "Future software updates will be automatically downloaded and installed for you as
  they're released. You can manage this in Software Update settings."
- Buttons: **Only Download Automatically** and **Continue**

`verified` — the park survives a cold boot. A second capture after a full stop and start
(`.cache/agent-notes/shots/after-coldboot.png`) shows the identical pane.

`verified` — the park is the **post-login** assistant, not the pre-login one:

```
lume ssh rehearse 'uptime; who; ls /var/db/.AppleSetupDone 2>&1; sysctl -n hw.memsize'
→ 22:24  up 7 mins, 1 user, load averages: 0.66 3.84 3.09
→ lume             console       9 Sep 22:18
→ /var/db/.AppleSetupDone
→ 8589934592
```

So the offline patch does most of its job. It creates the `lume` account, it writes
`/var/db/.AppleSetupDone`, and autologin puts `lume` on the console. Only the per-user first-login
assistant stays on screen. This matches issue #1440 exactly: a button-label match fails, and the
guest holds on a Setup Assistant pane after the installer reports success.

The consequence in #1440 does **not** follow here. The park does not block SSH.

# Step 5a — wall clock from `lume run` to an answered SSH command

`verified` — two independent measurements, each from a confirmed `stopped` state, and each with
the SSH multiplex socket deleted first:

| Run | Result |
|---|---|
| `.cache/agent-notes/lume-timing.log` | `SSH_ANSWERED_AFTER=10s` |
| `.cache/agent-notes/lume-timing3.log` | `SSH_ANSWERED_AFTER=11s` |

The second log records the pre-conditions:

```
VM_STATE_BEFORE=1        # `lume ls` matched "rehearse ... stopped"
0                        # count of ~/.ssh/master-* sockets
RUN_T0 2026-09-10T05:17:55Z
Started 'rehearse' in the background (PID 47802).
t=0s not-yet
SSH_ANSWERED_AFTER=11s
TIMING3_END 2026-09-10T05:18:07Z
```

A separate run proves the stopped state is genuine. `lume ssh rehearse 'echo STILL_UP'` printed
`Error: VM 'rehearse' is not running` before the boot.

**So a warm guest answers SSH about 11 s after `lume run`.** The health check allows 60 attempts
at 5 s, about 5 min. The guest is far inside that budget. This strengthens the conclusion that the
health check itself is broken.

# Step 5b — piped stdin, issue #1514

`verified` — `lume ssh` drops piped stdin. The system `ssh` does not.

```
echo 'echo PIPED_OK' | lume ssh rehearse 'bash -s'
→ (no output)
→ exit 0

echo 'echo PIPED_OK' | sshpass -p lume /usr/bin/ssh -F /dev/null ... lume@192.168.64.7 'bash -s'
→ PIPED_OK
→ exit 0
```

**#1514 reproduces on 0.5.3.** The exit code stays 0, so a script cannot detect the loss.

# Step 5b extra — binary stdout, issue #1513

`verified` — `lume ssh` adds one byte and changes the checksum:

```
lume ssh rehearse 'head -c 64 /dev/zero' | wc -c
→ 65
sshpass -p lume /usr/bin/ssh -F /dev/null ... lume@192.168.64.7 'head -c 64 /dev/zero' | wc -c
→ 64
```

md5 comparison against a local 64-zero-byte reference:

```
/usr/bin/ssh   3b5d3c7d207e37dceeedd301e35e2e58
lume ssh       803890308739b772467ba67f49e4015a
reference      3b5d3c7d207e37dceeedd301e35e2e58
```

**#1513 reproduces on 0.5.3.** The system `ssh` is byte-exact.

# Step 5c — Rosetta 2 and nested virtualization

`verified` — Rosetta 2 installs in the guest:

```
lume ssh rehearse 'echo lume | sudo -S -p "" softwareupdate --install-rosetta --agree-to-license 2>&1 | tail -12'
```

Output tail:

```
2026-09-09 22:01:58.629 softwareupdate[893:9033] Package Authoring Error: 140-93590: Package reference com.apple.pkg.RosettaUpdateAuto is missing installKBytes attribute
By using the agreetolicense option, you are agreeing that you have run this tool with the license only option and have read and agreed to the terms.
Installing: 0.0%...Installing: 100.0%
Install of Rosetta 2 finished successfully
```

The "Package Authoring Error" line is a warning only. The install reports success.

`verified` — Rosetta works after the install:

```
lume ssh rehearse 'ls -la /Library/Apple/usr/libexec/oah | head -5; arch -x86_64 /usr/bin/true; echo "ARCH_X86_RC=$?"'
→ lrwxr-xr-x  1 root  wheel      32  9 Sep 22:02 debugserver -> /usr/libexec/rosetta/debugserver
→ -rwxr-xr-x  1 root  wheel  461648 31 Jul 18:53 libRosettaRuntime
→ ARCH_X86_RC=0
```

`verified` — nested virtualization is **not** exposed:

```
lume ssh rehearse 'sysctl -a 2>/dev/null | grep -i -E "hv_support|vmm"'
→ kern.hv_support: 0
→ kern.hv_vmm_present: 1
```

`kern.hv_support: 0` means the guest cannot host its own VM. `kern.hv_vmm_present: 1` means the
guest knows a hypervisor runs it. No Nix install and no build ran in the guest.

# Disk cost

`verified` — measurements:

| Point | Free on `/` |
|---|---|
| Before the work | 279 GB |
| Peak use in run 1 | 235 GB |
| After the run-1 delete | 260 GB |
| Now | 208 GB |

Free space never fell below 208 GB, so the 40 GB abort threshold never came close.

`verified` — current cost:

```
du -sh ~/.lume/rehearse ~/Library/Caches/lume-ipsw
→  25G	/Users/kristof.nazarewski/.lume/rehearse
→  19G	/Users/kristof.nazarewski/Library/Caches/lume-ipsw
```

# Final state — the guest stays

`verified`:

```
lume ls
→ rehearse  macOS  4  8.00G  24.4GB/60.0GB  1024x768  running  nat  home  -  192.168.64.7  yes  vnc://:secret123@127.0.0.1:5999
```

The guest `rehearse` is **running**. Nothing deleted it.

## Rollback

```bash
export PATH="$HOME/.local/bin:$PATH"
lume stop rehearse            # optional; delete also stops it
lume delete rehearse          # frees 25 GB
rm -rf ~/Library/Caches/lume-ipsw   # frees 19 GB (the cached IPSW this run added)
```

The zellij session `llm:nix-configs:d80e7c83` holds six panes with the raw output. Close it with
`zellij delete-session --force llm:nix-configs:d80e7c83` when you no longer need it.

# What I could not verify

| Claim | Why not | One step that settles it |
|---|---|---|
| macOS local-network privacy blocks the Nix `ssh`. | The permission database needs root, and this run uses no host sudo. | Grant local network access to the Nix `ssh` binary, then retest the same command. |
| The reject flag on the `192.168.64` route explains the `ping` failure. | `route delete` needs root. | Delete the route as root, then retest `ping 192.168.64.7`. |
| The exact reason lume's SSH health check fails. | lume ships as a binary. I read no source. | Read the health-check code in the trycua/cua repository, or run lume under a traced `ssh`. |
| `lume create --unattended` also fails with a cached IPSW. | Run 2 split the create and the setup on purpose, to keep a guest. | Rerun the exact run-1 command with `--ipsw <local path>`. It costs about 9 min, no download. |
| `--ipsw latest` and the local IPSW give an identical guest. | I compared no disk image. | Compare `sw_vers` and `system_profiler` output from a guest of each path. |
| Whether a later boot ever clears the Setup Assistant pane. | I booted the guest three times only. | Boot it several more times, or press `Continue` over VNC, then capture again. |
| Whether `nc -z` gave false positives in the run-1 observer. | `nc -z` reported port 22 open while `ping` failed, so I distrust it. | Repeat the probe with `nc -v`, which prints the real banner. |

# Practical guidance for an external adopter

1. Do **not** use `lume create --unattended` on macOS 26.6.2. It deletes a good guest after a
   14-minute build.
2. Use `lume create` first, then `lume setup`. `lume setup` keeps the guest after its health check
   fails.
3. Download the IPSW once with `lume ipsw` plus `curl`, then pass the local path. This saves about
   4.5 min for each retry.
4. Do not use a Nix-installed `ssh` on the host to reach the guest. Use `/usr/bin/ssh` or
   `lume ssh`.
5. Do not pipe stdin into `lume ssh`, and do not read binary from it. Both corrupt silently and
   still exit 0.
6. Expect no nested virtualization in the guest. Rosetta 2 installs and works.
