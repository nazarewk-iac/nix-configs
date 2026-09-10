---
type: Research
description: Landscape review of automated nix-darwin tests in ephemeral macOS VMs on Apple Silicon — Tart license terms, GPU exposure, alternatives, Nix-in-guest feasibility, and a timing budget.
task: definition.md
timestamp: 2026-09-09T00:00:00+02:00
authored_by: agent
---

# Automated nix-darwin tests in ephemeral macOS VMs on Apple Silicon

Owning task: [darwin-vm-testing.md](definition.md).

Every claim below carries a tag. `verified` means a primary source: a file in the project's own
repository, an official reference document, an issue or pull request body, or a command that ran on
`<private-host>`. `unverified` means a blog post, a vendor summary, an absence of evidence, or an
inference. Each claim gives a URL or a file path.

Local host facts, all `verified` by command on `<private-host>`:
`sw_vers` → macOS 26.6.2 (build 25G83); `sysctl hw.model` → `Mac16,5`; `hw.optional.arm64` → 1;
`nix --version` → Lix 2.95.2, `aarch64-darwin`; `csrutil status` → SIP enabled.
`which tart` → not found. No VM tool is present yet.

## Verdict

1. **Licensing is not a blocker. Tart is clean for a company-owned laptop.** Since version 2.33.0
   Tart carries **FSL-1.1-ALv2** with `Copyright 2022-2026 OpenAI`. The license grants "your
   internal use and access" as an explicit Permitted Purpose. It sets **no** employee-count, revenue,
   or CPU-core threshold. The old paid tiers are dead: the OpenAI docs update **deleted**
   `docs/licensing.md`, the subscription-agreement PDF, and the legal terms. Every practical
   alternative is Apache-2.0, MIT, BSD-2, or GPL. Only Anka and Parallels stay commercial.
2. **The real cap comes from Apple, not from Tart.** The macOS Tahoe 26 SLA permits **two (2)**
   guest copies per Apple-branded computer, and it lists "testing during software development" as a
   permitted purpose. That caps test parallelism at two concurrent guests.
3. **Nix in a Tart macOS guest works. This is a go.** At least eight public repositories install Nix
   and activate nix-darwin inside a Tart guest. No reboot is needed before activation. The guest disk
   survives a guest reboot; two independent harnesses prove it.
4. **A warm loop costs minutes, not tens of minutes — after a one-time cost of about 40 minutes and
   a 27 GB pull.** Bake a golden image once. Then clone, activate, and destroy per checkpoint.
5. **GPU does not matter.** A headless config test touches no Metal API. One small caveat: the macOS
   *installer* wants a display device present, so keep one 1024x768 device attached and never open a
   window.

## Q1 licensing

### Timeline of the Tart license

| Period | License | Copyright holder | Evidence |
|---|---|---|---|
| 2022-03-07 → 2023-02-28 | AGPL-3.0 | Cirrus Labs, Inc. | commit `dd40717c0` "Create LICENSE (#10)" |
| 2023-02-28 → **2.32.1** (2026-04-12) | **Fair Source License 0.9** | Cirrus Labs, Inc. | commit `4339a0310` "Relicensed under Fair Source License (#415)" |
| **2.33.0** (2026-07-17) → now | **FSL-1.1-ALv2** | **OpenAI** | commit `5ad172e7f` "Relicense under FSL-1.1-ALv2 (#1238)", merged 2026-06-05T22:37:02Z |

`verified` — `gh api "repos/cirruslabs/tart/commits?path=LICENSE"` returns exactly these three
commits. https://github.com/openai/tart/commits/main/LICENSE

`verified` — the exact version boundary. I read `LICENSE` at each tag:
`?ref=2.32.0` → `Fair Source License, version 0.9`; `?ref=2.32.1` → `Fair Source License, version
0.9`; `?ref=2.33.0` → `# Functional Source License, Version 1.1, ALv2 Future License`. The relicense
commit landed 2026-06-05 but no release shipped between 2026-04-12 (2.32.1) and 2026-07-17 (2.33.0).
So **2.33.0 is the first release with the new license**.
https://github.com/openai/tart/blob/2.33.0/LICENSE

### What FSL-1.1-ALv2 actually says

`verified` — I read the current `LICENSE` file in full. https://github.com/openai/tart/blob/main/LICENSE

The operative text:

> ### Permitted Purpose
>
> A Permitted Purpose is any purpose other than a Competing Use. A Competing Use means making the
> Software available to others in a commercial product or service that:
>
> 1. substitutes for the Software;
> 2. substitutes for any other product or service we offer using the Software that exists as of the
>    date we make the Software available; or
> 3. offers the same or substantially similar functionality as the Software.
>
> Permitted Purposes specifically include using the Software:
>
> 1. for your internal use and access;
> 2. for non-commercial education;
> 3. for non-commercial research; and
> 4. in connection with professional services that you provide to a licensee using the Software in
>    accordance with these Terms and Conditions.

Three facts follow directly:

- **No threshold of any kind.** `verified` — the license text contains no number. There is no
  employee count, no revenue figure, no CPU-core cap, and no user cap. This is a structural change
  from Fair Source 0.9, which did carry a number.
- **Internal use is explicitly permitted.** `verified` — Permitted Purpose item 1. A local developer
  workstation that tests a personal open-source config repository is internal use. It is not a
  Competing Use, because it does not make Tart available to others in a commercial product.
- **Each version turns Apache-2.0 two years after release.** `verified` — the "Grant of Future
  License" section: "an additional license to use the Software under the Apache License, Version 2.0
  that is effective on the second anniversary of the date we make the Software available." So 2.33.0
  becomes ALv2 around 2028-07-17.

`unverified` — FSL is a Fair Source license, not an OSI-approved open-source license, until the ALv2
grant takes effect. https://fsl.software/ does not state OSI conformance either way.

### The old regime — and why the prior baseline overstated the risk

The prior baseline feared a "free for open source, paid for commercial use" model. That model existed
but it **never applied to a single-person laptop**, and it no longer exists at all.

`verified` — Fair Source License 0.9 text at `?ref=2.32.1`:

> Use Limitation: 100 users. User is defined as a single core of a central processing unit (CPU) used
> by the product. **The Use Limitation does not apply to CPUs installed in devices used by a single
> individual.**

`verified` — the retired `docs/licensing.md` at tag `2.32.1` states: "Usage on personal computers
including personal workstations is royalty-free, but organizations that exceed a certain number of
server installations (100 CPU cores for Tart and/or 4 hosts for Orchard) will be required to obtain a
paid license." The tiers were Gold $12,000/yr (500 cores), Platinum $36,000/yr (3,000 cores), and
Diamond $12 per core per year.
https://github.com/openai/tart/blob/2.32.1/docs/licensing.md

So the threshold was **CPU cores across an organization's fleet**, not headcount or revenue, and a
single individual's device was carved out by name. A laptop test loop sat inside the free grant even
under the old license.

### The OpenAI move, and what it changed

- **The repository moved.** `verified` — `gh api repos/cirruslabs/tart --jq .full_name` returns
  `openai/tart`. GitHub redirects the old path. https://github.com/openai/tart
- **Orchard moved too.** `verified` — `gh api repos/cirruslabs/orchard --jq .full_name` returns
  `openai/orchard`.
- **The announcement.** `verified` — PR #1223 (2026-04-07) added a site banner: "Big milestone for
  Cirrus Labs — we're joining OpenAI to work on Agent Infrastructure".
  https://github.com/openai/tart/pull/1223
- **The paid regime was retired, not merely renamed.** `verified` — PR #1240 "Update docs after
  OpenAI move" (merged 2026-06-06) marks these files `removed`: `docs/licensing.md`,
  `docs/assets/TartLicenseSubscription.pdf`, `docs/legal/terms.md`, `docs/legal/privacy.md`, and
  `docs/blog/posts/2025-10-27-press-release-fair-enforcement.md`.
  https://github.com/openai/tart/pull/1240/files
- **The maintainers say so in plain words.** `verified` — an editorial note now heads the 2023
  license-change blog post:

  > **Current license.** This post describes a historical license change announced on February 11,
  > 2023. As of June 5, 2026, Tart is maintained by OpenAI and licensed under FSL-1.1-ALv2. The usage
  > limits, paid tiers, pricing, support commitments, and contact details described below no longer
  > apply.

  https://github.com/openai/tart/blob/main/docs/blog/posts/2023-02-11-changing-tart-license.md
- **The install path changed.** `verified` — the README now says `brew install openai/tools/tart`.
  Commit "[codex] Publish Tart to openai/homebrew-tools (#1277)", 2026-07-17.
  https://github.com/openai/tart/blob/main/README.md

`unverified` — no license key, activation, or telemetry requirement appears anywhere in the license or
the docs. I did not audit the Swift sources for a phone-home call.

### The public GHCR base images

- **They are still public and still anonymous.** `verified` — I requested an anonymous pull token from
  `ghcr.io/token` and fetched the manifest for three images. Each returned `HTTP 200`:
  `cirruslabs/macos-tahoe-base`, `cirruslabs/macos-sequoia-base`, `cirruslabs/macos-sonoma-base`. The
  images stayed under the `cirruslabs/` namespace after the move.
- **They are current.** `verified` — the Tahoe manifest annotation
  `org.cirruslabs.tart.upload-time` reads `2026-09-05T09:08:42Z`.
- **Size.** `verified` — 96 layers, **27.31 GB compressed** (sum of layer sizes), and annotation
  `org.cirruslabs.tart.uncompressed-disk-size` = `50000000000`, so a **50 GB** guest disk. The
  quick-start doc says "will download a 25 GB image", which understates it slightly.
  https://tart.run/quick-start/
- **The build templates are MIT.** `verified` — `gh api repos/cirruslabs/macos-image-templates` →
  `license.spdx_id` = `MIT`. https://github.com/cirruslabs/macos-image-templates
- **The images carry no separate terms of their own.** `verified (absence)` — no `LICENSE`, EULA, or
  terms annotation appears on the manifests or in the templates repository beyond the MIT file. But
  each image contains a full macOS installation, so **Apple's SLA governs the contents**, not the
  MIT file. That is the binding constraint, and the next section covers it.

### Apple's macOS SLA — the two-VM clause

`verified` — I downloaded the macOS Tahoe 26 SLA PDF from Apple and converted it with `pdftotext`.
Section 2B, "Permitted License Uses and Restrictions", verbatim:

> (iii) to install, use and run up to two (2) additional copies or instances of the Apple Software, or
> any prior macOS or OS X operating system software or subsequent release of the Apple Software,
> within virtual operating system environments on each Apple-branded computer you own or control that
> is already running the Apple Software, for purposes of: (a) software development; (b) testing during
> software development; (c) using macOS Server; or (d) personal, non-commercial use.

And the restriction that follows it:

> Except as expressly permitted in Section 3, the grant set forth in Section 2B(iii) above does not
> permit you to use the virtualized copies or instances of the Apple Software in connection with
> service bureau, time-sharing, terminal sharing, relay service or other similar types of services.

Source: https://www.apple.com/legal/sla/docs/macOSTahoe.pdf — page header reads "APPLE INC. SOFTWARE
LICENSE AGREEMENT FOR macOS Tahoe 26".

Reading of the clause:

- **The number is two, and it is per host.** `verified` — "up to two (2) additional copies … on each
  Apple-branded computer".
- **The clause applies to Apple Silicon.** `verified` — the text says "each Apple-branded computer".
  It carves out no architecture. It does exclude iOS, iPadOS, watchOS, and tvOS guests, not macOS.
- **Our purpose is named.** `verified` — item (b) "testing during software development" covers a
  nix-darwin config test directly. Item (d) "personal, non-commercial use" is a second, independent
  basis for a personal config repository.
- **"Own or control" is the one soft edge.** `unverified (legal reading, not a source)` — a
  company-issued Mac is controlled by the employee who holds it, and Section 2B(ii) grants a
  commercial enterprise one copy per Mac it owns. The VM grant in 2B(iii) attaches to the computer,
  not to the person. So a company-owned Mac carries the two-VM grant. This report cannot settle
  employer policy, which is separate from the Apple license.
- **Do not expose the guests as a service.** `verified` — the service-bureau restriction. A local
  test loop is unaffected. A shared build farm is not.

`verified` — Mirage's README repeats the same number: "The host enforces Apple's limit of **2
concurrently running macOS VMs**." https://github.com/solcreek/mirage#readme
`verified as a vfkit claim, unverified as an Apple statement` — vfkit says "Due to hardcoded
limitations in the Apple Virtualization framework, it's not possible to run more than two macOS VMs at
a time." Apple does not state the number in the API reference.
https://github.com/crc-org/vfkit/blob/main/doc/usage.md
`unverified` — stopped VMs do not count toward the cap. Asserted by third-party harnesses; no primary
Apple source found.

### nixpkgs packaging state — a practical snag

`verified` — command on `<private-host>`: `nix eval nixpkgs#tart.version` → **2.30.6**. And
`nix eval nixpkgs#tart.meta` → `license.shortName = "fairsource09"`, `license.free = false`,
`unfree = true`, `platforms = ["aarch64-darwin"]`, `broken = false`.

Two consequences:

- **The pinned nixpkgs Tart predates the relicense.** 2.30.6 is a Fair Source 0.9 build. To get the
  FSL build, either bump the package or install from the Homebrew tap `openai/tools`.
- **nixpkgs metadata is stale.** It still marks Tart `unfree` as `fairsource09`. So `nix build` needs
  `allowUnfree` or an `allowUnfreePredicate` entry. This is an upstream nixpkgs bug worth a patch
  under `.flake.patches/`: the license attribute should become FSL-1.1-ALv2.

`verified` — other tools in the pinned nixpkgs, by `nix eval nixpkgs#<p>.version`: `vfkit` 0.6.3,
`lima` 2.2.0, `utm` 4.7.5, `krunkit` 1.3.2. **`lume`, `mirage`, and `macosvm` are not in nixpkgs.**

### Verdict per tool

| Tool | License | Evidence | Usable on a company-owned laptop for personal open-source tests? |
|---|---|---|---|
| **Tart** ≥ 2.33.0 | FSL-1.1-ALv2 | LICENSE file, read in full | **Yes.** Internal use is an explicit Permitted Purpose. No threshold. |
| **Tart** ≤ 2.32.1 | Fair Source 0.9 | LICENSE at tag `2.32.1` | **Yes.** The Use Limitation exempts "devices used by a single individual". |
| **Mirage** | Apache-2.0 | `gh api repos/solcreek/mirage` → `Apache-2.0` | **Yes.** Unconditional. |
| **Lima** | Apache-2.0 | `gh api repos/lima-vm/lima` → `Apache-2.0` | **Yes.** Unconditional. |
| **UTM** | Apache-2.0 | https://docs.getutm.app/ | **Yes.** |
| **vfkit** | Apache-2.0 | https://github.com/crc-org/vfkit | **Yes.** |
| **krunkit** | Apache-2.0 | https://github.com/containers/krunkit | **Yes**, but no macOS guest. |
| **VirtualBuddy** | BSD-2-Clause | LICENSE file read | **Yes**, but no CLI. |
| **macosvm** | GPL-2.0-or-3.0 | LICENSE file read | **Yes.** |
| **packer-plugin-tart** | MPL-2.0 | `gh api` → `MPL-2.0` | **Yes.** |
| **macos-image-templates** | MIT | `gh api` → `MIT` | **Yes.** |
| **cua** (trycua) | MIT | repository README | **Yes.** |
| **Veertu Anka** | Commercial subscription | https://docs.veertu.com/anka/licensing/ | **No.** No free tier for company hardware. Anka Develop is for individual devs on supported MacBooks only. |
| **Parallels Desktop** | Commercial | https://www.parallels.com/products/desktop/buy/ | **No.** And `prlctl` needs the Pro or Business edition. |
| **VMware Fusion** | Free for all users, commercial included | https://blogs.vmware.com/cloud-foundation/2024/11/11/vmware-fusion-and-workstation-are-now-free-for-all-users/ | License is fine, but it runs **no macOS guest** on Apple Silicon. Irrelevant. |

## Q2 GPU and alternatives

### What a macOS guest gets

| Claim | Tag | Source |
|---|---|---|
| `VZMacGraphicsDeviceConfiguration` (macOS 12.0+) holds only `displays: [VZMacGraphicsDisplayConfiguration]` | verified | https://developer.apple.com/documentation/virtualization/vzmacgraphicsdeviceconfiguration |
| `VZMacGraphicsDisplayConfiguration` exposes only `widthInPixels`, `heightInPixels`, `pixelsPerInch`. No GPU knob, no VRAM knob | verified | https://developer.apple.com/documentation/virtualization/vzmacgraphicsdisplayconfiguration |
| `VZGraphicsDevice` (macOS 14.0+) is the runtime class. `VZMacGraphicsDeviceConfiguration` → `VZMacGraphicsDevice`; `VZVirtioGraphicsDeviceConfiguration` → `VZVirtioGraphicsDevice` | verified | https://developer.apple.com/documentation/virtualization/vzgraphicsdevice |
| The whole `Graphics` API topic — 12 symbols — never mentions Metal, GPU, or hardware acceleration | verified (absence across the full symbol list) | https://developer.apple.com/documentation/virtualization/graphics |
| Apple states Metal support for macOS guests in WWDC22, not in the API reference: "We have built a graphic device that exposes the GPU capabilities to the virtual Mac. This means you can run Metal in the virtual machine, and get great graphics performance in macOS." | verified | https://developer.apple.com/videos/play/wwdc2022/10002/ |
| So a macOS guest gets a **paravirtual, hardware-accelerated, Metal-capable** device backed by the host GPU — not a software rasterizer | verified (same transcript) | https://developer.apple.com/videos/play/wwdc2022/10002/ |
| Vendor corroboration: on ARM hosts "Metal acceleration is enabled automatically by default" for macOS guests | verified (vendor doc) | https://docs.veertu.com/anka/anka-virtualization-cli/graphics-acceleration-apple-metal/ |

### What a Linux guest gets

| Claim | Tag | Source |
|---|---|---|
| `VZVirtioGraphicsDeviceConfiguration` (macOS 13.0+) is "the configuration of a Virtio graphics device **for a Linux VM**". Its only member is `scanouts` (width and height) | verified | https://developer.apple.com/documentation/virtualization/vzvirtiographicsdeviceconfiguration |
| It is **2D only**. Apple: "In macOS Ventura, we have added support for Virtio GPU **2D** … **Linux renders the content**, gives the rendered frame to Virtualization framework, which can then display it." Guest-side render means llvmpipe or swrast | verified | https://developer.apple.com/videos/play/wwdc2022/10002/ |
| No virgl, Venus, 3D, or Vulkan class exists in the framework today | verified (absence) | https://developer.apple.com/documentation/virtualization/graphics |
| vfkit exposes only `--device virtio-gpu,width=…,height=…`. No 3D option | verified | https://github.com/crc-org/vfkit/blob/main/doc/usage.md |
| **krunkit does not use Virtualization.framework.** It launches **libkrun**, and libkrun uses HVF (Hypervisor.framework) on macOS/ARM64 | verified | https://github.com/containers/libkrun and https://github.com/containers/krunkit |
| libkrun implements virtio-gpu in userspace "with venus and native-context", and lists "GPU-enabled (via venus) lightweight VMs on macOS" as a use case | verified | https://github.com/containers/libkrun |
| krunkit boots EFI only and documents no macOS guest: "krunkit only supports the EFI bootloader configuration" | verified | https://github.com/containers/krunkit/blob/main/docs/usage.md |
| **Net:** real 3D or Vulkan for a Linux guest on an Apple Silicon host exists only *outside* Virtualization.framework, through libkrun and Venus. Virtualization.framework gives a Linux guest a 2D framebuffer | verified (composite of the two rows above) | as above |

### Does GPU matter for a headless nix-darwin test? No.

The expectation is **confirmed**, with one trap.

| Claim | Tag | Source |
|---|---|---|
| A VM is valid with **no graphics device at all**: `VZVirtualMachineConfiguration.graphicsDevices` — "The default value of this property is an empty array." | verified | https://developer.apple.com/documentation/virtualization/vzvirtualmachineconfiguration/graphicsdevices |
| **Trap:** the macOS *installer* seems to need a display device even in a headless flow. Lima's macOS template carries the comment `# The installer seems to require the display device to be present.` and sets `video: {display: "default"}` | verified | https://github.com/lima-vm/lima/blob/master/templates/macos-26.yaml |
| Lima lists "No video display toggle capability" as a macOS-guest limitation. You cannot switch the display off later | verified | https://lima-vm.io/docs/usage/guests/macos/ |
| Nix evaluation, derivation builds, and `darwin-rebuild switch` are CPU-, IO-, and APFS-bound. They call no Metal API | unverified (inference) | — |
| A second reason to keep SIP-disabled base images: `screencapture` and `osascript` over SSH need the console session. That is GUI automation, not a build need | verified | https://github.com/hausfold/haus/blob/main/script/build-golden-vm.sh |

**Practical rule** (`unverified`, inference from the rows above): attach one minimal
`VZMacGraphicsDeviceConfiguration` at 1024x768 so install and first boot succeed. Never open a
`VZVirtualMachineView`. Drive everything over ssh or over the guest-agent vsock channel. Tart's
`--no-graphics` flag already does this; `JoelFrancisco/nix-darwin-config` uses it.

### Two Apple primitives worth a flag

| Claim | Tag | Source |
|---|---|---|
| `VZMacOSInstaller` (macOS 12.0+) installs macOS from an IPSW restore image programmatically. `install()` is async and reports `progress`. No user interaction | verified | https://developer.apple.com/documentation/virtualization/vzmacosinstaller |
| `VZMacGuestProvisioningOptions` — **beta, macOS 27.0+** — sets `username`, `password`, `fullName`, `logsInAutomatically`, and **`enablesRemoteLogin`** (SSH) on the guest. It needs macOS 27+ *in the guest*, and it applies only on the **first boot after restore** | verified | https://developer.apple.com/documentation/virtualization/vzmacguestprovisioningoptions and https://developer.apple.com/documentation/virtualization/vzmacosvirtualmachinestartoptions |
| This removes the Setup Assistant screen-scrape that every current tool performs. It is the reason older tools ship click scripts | unverified (inference) | — |
| `startUpFromMacOSRecovery` on `VZMacOSVirtualMachineStartOptions` lets a script toggle SIP | verified | https://developer.apple.com/documentation/virtualization/vzmacosvirtualmachinestartoptions |

### Alternatives matrix

Host is Apple Silicon in every row.

| Tool | macOS guest? | Unattended macOS install? | CLI-scriptable? | License | Maturity | Source |
|---|---|---|---|---|---|---|
| **Tart** | **yes** | **yes** — public base images plus a Packer plugin | yes (`tart`, plus `tart exec` over vsock) | FSL-1.1-ALv2 | 6718 stars, 2.36.0 (2026-08-25) | https://github.com/openai/tart |
| **Lima** | **yes** — experimental since v2.1.0; `vmType: vz` is "the exclusive supported option for macOS guests" | **yes** — `limactl start template:macos` downloads the pinned IPSW, installs, generates a random password, and gives ssh | yes (`limactl`) | Apache-2.0 | very active; v2.2.0 (2026-07-21) | https://lima-vm.io/docs/usage/guests/macos/ |
| **UTM** | **yes** — macOS 12+ guests on Apple Silicon via the Apple Virtualization backend | **no** — install runs through the GUI wizard; the scripting suite has no OS-install command | yes (`utmctl`, an AppleScript wrapper) | Apache-2.0 | very active; v4.7.5 (2026-01-03) | https://docs.getutm.app/guest-support/macos/ |
| **VirtualBuddy** | **yes** — macOS 12 and later, betas included | **partly** — the wizard downloads a restore image, but it is GUI-driven | **no** — the repository has no CLI target | BSD-2-Clause | slower cadence; 2.1 (2025-09-14) | https://github.com/insidegui/VirtualBuddy |
| **macosvm** | **yes** — arm64 macOS guests | **yes** — `macosvm --disk … --aux … --restore …ipsw vm.json`, then headless run | yes, CLI-only by design | GPL-2.0-or-3.0 | low volume but alive; 0.2-3 (2026-06-22) | https://github.com/s-u/macosvm |
| **Veertu Anka** | **yes** | **yes** — `anka create my-ci-vm 26.6.2` sets up macOS, creates a user, disables SIP, enables VNC, and stops the VM. 20-60+ min | yes (`anka`) | **Commercial.** Host-based on Apple Silicon. 30-day trial. No free tier for Anka Build | commercial, maintained | https://docs.veertu.com/anka/licensing/ |
| **Parallels (`prlctl`)** | **yes** — Desktop 18+, and the guest must match the host macOS version | **partly** — `prlctl create -o macos --restore-image <ipsw>` is scriptable, but the doc does not claim Setup Assistant is skipped | yes, but `prlctl` needs the Pro or Business edition | **Commercial**, no free tier | commercial, actively shipped | https://kb.parallels.com/en/125561/ |
| **VMware Fusion (`vmrun`)** | **no** — ARM Linux and ARM Windows guests only; it uses its own VMM | N/A | yes (`vmrun`) | Free for all users, commercial included | maintained by Broadcom | license `verified`: https://blogs.vmware.com/cloud-foundation/2024/11/11/vmware-fusion-and-workstation-are-now-free-for-all-users/ · the macOS-guest row is `unverified` — every Broadcom techdocs path returned 404 |
| **krunkit** | **no** — EFI bootloader only, Linux guests | N/A | yes | Apache-2.0 | active; v1.3.2 (2026-07-03) | https://github.com/containers/krunkit/blob/main/docs/usage.md |
| **vfkit** | **yes, but run-only** — `--bootloader macos` needs pre-made `machineIdentifierPath`, `hardwareModelPath`, and `auxImagePath` | **no** — vfkit cannot install macOS from an IPSW | yes; also a Go API | Apache-2.0 | active; v0.6.4 (2026-07-07); adopters include podman, minikube, crc | https://github.com/crc-org/vfkit/blob/main/doc/usage.md |
| **Mirage** | **yes** — "macOS guests today"; needs M1+ and macOS 14+ | **yes** — "zero-touch create": offline user, auto-login, guest agent, and no Setup Assistant clicks | yes — `create`, `clone`, `run`, `start`, `exec`, `snapshot`, `stop`, `rm`, `ls`, all with `--json`; plus an MCP server | Apache-2.0 | **early, self-declared v0.1**; latest commit 2026-06-23 | https://github.com/solcreek/mirage |
| **NixThePlanet** | yes, via QEMU + OCR | yes, but ~40-50 min and x86_64-focused | yes | MIT | niche | baseline, not re-checked |

`vfkit` note for this repository: `docs/generalization-plan.md:99` already records
`hypervisorsOnDarwin = [ "qemu" "vfkit" ]` for microvm.nix. That path boots a **NixOS** guest on a
Darwin host. It cannot boot a macOS guest without a separate provisioner.

### Two corrections to the brief's premises

1. **`macosvm` is not Apple's own sample.** `verified` — `github.com/s-u/macosvm` is a third-party
   project by Simon Urbanek, licensed GPL-2.0-or-3.0. Apple's sample is the article "Running macOS in
   a virtual machine on Apple silicon", under the Apple Sample Code License.
   https://github.com/s-u/macosvm and
   https://developer.apple.com/documentation/virtualization/running-macos-in-a-virtual-machine-on-apple-silicon
2. **Lima does support macOS guests.** `verified` — the answer to the key question is yes, not "Linux
   only". Support is experimental, arrived in v2.1.0 (2026-03-17, "Experimentally support macOS guests
   (#4595)"), and works on Apple Silicon with the `vz` driver only. Limits: no display toggle, manual
   port forward, no custom certificates, no containerd, no host mounts in plain mode.
   https://lima-vm.io/docs/usage/guests/macos/ and https://lima-vm.io/docs/config/vmtype/

### cua — a desktop-automation fallback, nothing more

`verified` — https://github.com/trycua/cua. cua is an open-source stack for computer-use agents: it
supplies desktop automation, cloud desktops, and local macOS VMs. It drives macOS guests on Apple
Silicon through **Lume**, its own wrapper over Apple's Virtualization.framework — not through Tart.
License is **MIT**, so it clears the corporate-laptop bar. Its GUI automation (screenshot, click,
keyboard) could in principle replace the OCR-plus-Expect loop that NixThePlanet uses for an
unattended macOS setup. **But a nix-darwin test runs fully headless over ssh, so desktop automation is
unnecessary.** Keep cua only as a fallback for a step that truly needs the GUI — a Setup Assistant
screen, or a system-settings permission dialog. The Tart base images already skip both.

## Q3 Nix in a Tart guest

**Answer: yes, and the prior art is substantial.** At least eight public repositories install Nix and
activate nix-darwin inside a Tart macOS guest.

### The Nix installer needs no reboot

- `verified` — **the Determinate installer is validated end-to-end inside a Tart VM.** nix-installer
  PR **#1818** (merged 2026-05-05) states: "Validated end-to-end against `main` at v3.19.0 inside a
  `tart` VM." It ran probe processes and `fs_usage -w -f filesys`, exercised both the `.pkg` and the
  direct `nix-installer install --determinate` paths, and had `/nix` mounted at `/dev/disk3s7`.
  https://github.com/DeterminateSystems/nix-installer/pull/1818
- `verified` — **synthetic-object creation materializes `/nix` live.**
  `CreateSyntheticObjects::execute` runs `apfs.util -t` then `apfs.util -B` and ignores errors from
  both. No reboot.
  https://github.com/DeterminateSystems/nix-installer/blob/main/src/action/macos/create_synthetic_objects.rs
- `verified` — **the `/run` firmlink is nix-darwin's concern, not Nix's.** nix-darwin's
  `system.activationScripts.createRun` appends `run\tprivate/var/run` to `/etc/synthetic.conf`, runs
  `apfs.util -t`, and hard-aborts activation when `/run` is not a symlink.
  https://github.com/nix-darwin/nix-darwin/blob/master/modules/system/base.nix
  - `verified` — the historical failure is a **bare-metal** report, not a VM one: nix-installer #275,
    "`ln: failed to create symbolic link '/run': Read-only file system`", and the reporter says "The
    `/run` issue was solved by rebooting the mac."
    https://github.com/DeterminateSystems/nix-installer/issues/275
  - `verified (absence)` — **every Tart harness found activates nix-darwin with no prior reboot and
    reports no `/run` problem.** `openai/tart` issues return 0 hits for `nix-darwin` and 0 for
    `synthetic.conf`. https://github.com/openai/tart/issues
- `verified` — `--no-confirm` matters for a non-interactive run; every harness passes it.
  `--determinate` matters a great deal, but as a **conflict with nix-darwin**, not as an installer
  problem. See the gotchas below.

### The guest disk survives a guest reboot

Two independent proofs, both `verified`:

- `spa5k/pkg` reboots the guest, then confirms a changed raw `kern.boottime` plus passwordless `sudo`,
  an owner marker, and **two staged file SHA-256 hashes**.
  https://github.com/spa5k/pkg/blob/main/spikes/s6-determinate-installer/macos-vm/README.md
- `JoelFrancisco/nix-darwin-config` runs `sudo shutdown -r now` after first activation, waits for SSH,
  then asserts `test -f /var/db/nix-darwin-first-activation-complete`.
  https://github.com/JoelFrancisco/nix-darwin-config/blob/main/tests/vm-test.sh

### SIP state: disabled in `base`, present in `vanilla`, and irrelevant to Nix

- `verified` — the `base` images **disable SIP**. The `base.yml` workflow runs a dedicated "Disable
  SIP" Packer step between `tart clone …-vanilla` and `packer build templates/base.pkr.hcl`.
  `disable-sip.pkr.hcl` boots recovery and types `csrutil disable`.
  https://github.com/cirruslabs/macos-image-templates/blob/master/.github/workflows/base.yml and
  https://github.com/cirruslabs/macos-image-templates/blob/master/templates/disable-sip.pkr.hcl
- `verified` — the `vanilla` images keep SIP **on**. `yasyf/yclaw` records: "It is SIP-ON: their
  `*-base` images run `csrutil disable` ON TOP of this vanilla base, but metal does not."
  https://github.com/yasyf/yclaw/blob/main/packer/metal.pkr.hcl
- `verified` — **SIP state does not matter for Nix.** `yclaw` clones the **SIP-on vanilla** Tahoe base,
  installs Determinate Nix, and runs `darwin-rebuild build` successfully. Same file.
- `verified` — SIP-disabled *does* matter for GUI automation. `hausfold/haus`: "Everything here works
  because the cirruslabs base ships with SIP disabled … That is what lets `screencapture` and
  `osascript` run over SSH at all."
  https://github.com/hausfold/haus/blob/main/script/build-golden-vm.sh
- `verified` — the base images also disable Gatekeeper (`sudo spctl --global-disable`).
  https://github.com/cirruslabs/macos-image-templates/blob/master/templates/vanilla-sequoia.pkr.hcl

### sudo, users, and ssh — confirmed

All `verified`. I read both the official doc and the Packer template.

- **`admin` / `admin`.** The quick-start says: "All images above use the following credentials:
  Username: `admin`, Password: `admin`. These credentials work both for logging in via GUI, console
  (Linux) and SSH." https://tart.run/quick-start/ and
  https://github.com/openai/tart/blob/main/docs/quick-start.md
- **Passwordless sudo.** The template runs
  `echo 'admin ALL=(ALL) NOPASSWD: ALL' | EDITOR=tee visudo /etc/sudoers.d/admin-nopasswd`. The
  quick-start also documents the manual step for a from-IPSW build: "add `admin ALL=(ALL) NOPASSWD:
  ALL` to allow sudo without a password."
  https://github.com/cirruslabs/macos-image-templates/blob/master/templates/vanilla-sequoia.pkr.hcl
- **SSH is enabled in the prebuilt image.** The `boot_command` navigates System Settings → Sharing and
  enables Remote Login. Same template.
- **Access convention:** `ssh admin@$(tart ip <vm>)`. No fixed port. `tart ip` accepts
  `--wait <sec>` and `--resolver arp|agent`. https://tart.run/quick-start/
- **Better than ssh: `tart exec`.** The guest agent runs commands over a gRPC stream, with no SSH and
  no networking. It ships in all non-vanilla Cirrus Labs images. It also does automatic disk resize
  and clipboard share. https://github.com/openai/tart/blob/main/docs/blog/posts/2025-06-01-tart-guest-agent.md
- The image also pre-sets auto-login, no sleep, no screen lock, a `/Users/runner` → `/Users/admin`
  symlink, and a seeded `TCC.db`.

### `trusted-users`

`verified` — **a fresh install does not add the user.** nix-installer writes `trusted-users` only when
you pass `--extra-conf`. With `--determinate` it skips the standard config entirely, because
`determinate-nixd` owns it.
https://github.com/DeterminateSystems/nix-installer/blob/main/src/action/common/place_nix_configuration.rs

`verified` — **nix-darwin does not need it.** `nix.settings.trusted-users` is an `mkOption` with an
`example` and **no `default`**. nix-darwin's own CI runs `sudo darwin-rebuild switch`, so root does the
work, and root is always trusted.
https://github.com/nix-darwin/nix-darwin/blob/master/modules/nix/default.nix and
https://github.com/nix-darwin/nix-darwin/blob/master/.github/workflows/test.yml

`verified` — **you need it for `nix copy` into the guest.** nix-darwin's own draft Tart PR does exactly
this: `echo "trusted-users = ${username}" | sudo tee -a /etc/nix/nix.conf` with the comment
`# Necessary for nix-copy-closure`, then reverts the file so it matches `knownSha256Hashes`.
https://github.com/nix-darwin/nix-darwin/pull/1000

So a fresh guest **does not** satisfy `trusted-users`, and the harness must add one line. That is the
whole cost.

### Prior art

**The `iamruinous` document is a working template, not a stuck report.** `verified` — I read
https://raw.githubusercontent.com/iamruinous/nix-config/main/docs/research/tart-image-building.md in
full. It builds `macos-sequoia-nix` from `macos-sequoia-base` with the Determinate installer, then
optionally bootstraps nix-darwin from a flake. Real files exist:
`packer/macos-nix-base.pkr.hcl`, `packer/scripts/install-nix.sh` (`install --no-confirm`), and
`packer/scripts/bootstrap-nix-darwin.sh`. What it says cannot be automated: **Apple ID sign-in,
iMessage activation, and keychain-dependent operations** — all GUI-only, and all irrelevant to a
config test. It also notes "Tart does NOT support Docker-style layering." Its one nix-darwin gotcha:
`sudo mv /etc/nix/nix.conf /etc/nix/nix.conf.before-darwin` to avoid an interactive prompt. It
publishes no timings. Its internal link to `docs/TART-IMAGE-BUILDING.md` is dead; the file lives at
`docs/research/tart-image-building.md`.

Other Tart plus nix-darwin harnesses, all `verified` and all read directly:

| Repository | What it does | Installer |
|---|---|---|
| **nix-darwin PR #1000** "Add tart based VMs" (Enzime) — **draft, created and last touched 2024-07-10, stale for two years** | `modules/virtualisation/tart-vm.nix` plus `pkgs/ipsw`: `tart create --from-ipsw`, VNC-drives Setup Assistant, `ssh-copy-id`, passwordless sudo, `nix-installer install --no-confirm`, adds `trusted-users`, `nix-copy-closure` of the prebuilt `toplevel`, `darwin-rebuild activate`, asserts `realpath /run/current-system`. **No reboot anywhere.** https://github.com/nix-darwin/nix-darwin/pull/1000 | nix-installer |
| **JoelFrancisco/nix-darwin-config** `tests/vm-test.sh` — closest match to our need | `tart clone macos-tahoe-base`, `tart set --disk-size 120`, `--no-graphics`, poll `tart ip` and `nc -z :22`, `expect` to plant a throwaway ed25519 key, build on the host, `nix copy --to ssh-ng://`, activate, **reboot**, re-verify. https://github.com/JoelFrancisco/nix-darwin-config/blob/main/tests/vm-test.sh | upstream, `--daemon --yes` |
| **ccycle/dotfiles** `.agents/skills/vm-verify/` | An agent skill: clone or reuse `macos-sequoia-base`, `sshpass` admin/admin, rsync the worktree, install Nix, `darwin-rebuild switch`, verify `mkOutOfStoreSymlink` targets, stop instead of delete for reuse. https://github.com/ccycle/dotfiles/blob/main/.agents/skills/vm-verify/scripts/run.sh | upstream (deliberately not Determinate) |
| **hausfold/haus** `script/build-golden-vm.sh` | A golden-image bake with the deepest measured notes of any source. https://github.com/hausfold/haus/blob/main/script/build-golden-vm.sh | Determinate |
| **AidanWright/nixy** `modules/system/virtualization/tart-base-image.nix` | A nix-darwin module that bakes and pushes a base image. Has `determinate` **and** `lix` variants. Uses `tart exec`, no SSH. Pushes to ghcr with `--chunk-size 3`. https://github.com/AidanWright/nixy/blob/main/modules/system/virtualization/tart-base-image.nix | Determinate / Lix |
| **yasyf/yclaw** `packer/metal.pkr.hcl` | SIP-**on** vanilla Tahoe base pinned by digest, Determinate install, `darwin-rebuild build` at bake time, and a first-boot LaunchDaemon that does the `switch`. https://github.com/yasyf/yclaw/blob/main/packer/metal.pkr.hcl | Determinate |
| **spa5k/pkg** `spikes/s6-determinate-installer/macos-vm/` | A rigorous install, uninstall, and crash-recovery evidence harness. Base pinned by digest, Tart 2.35.0, installer SHA pinned, `tart exec` instead of SSH. https://github.com/spa5k/pkg/tree/main/spikes/s6-determinate-installer/macos-vm | Determinate 3.22.1 |
| **vicyap/dotfiles** `vms/darwintest/README.md` | A manual runbook with a real gotcha: nix-darwin runs `brew` as `system.primaryUser`, so an `admin`-owned `/opt/homebrew` fails with `Permission denied` on `/opt/homebrew/var/homebrew/locks`. https://github.com/vicyap/dotfiles/blob/main/vms/darwintest/README.md | upstream |
| **gfmio/nix-modules** `packer/macos-nix.pkr.hcl` | The same shape as `iamruinous`. Uses `--net-bridged=en0` with `--resolver=arp`. https://github.com/gfmio/nix-modules/blob/main/packer/macos-nix.pkr.hcl | Determinate |

### Upstream CI and framework status

- `verified` — **nix-darwin's own CI does not use Tart.** `.github/workflows/test.yml` is
  `runs-on: macos-14` with `cachix/install-nix-action@v30`, pinned `NIX_VERSION: 2.24.11`, jobs
  `test-stable` / `install-against-stable` / `install-flake`, all with `sudo darwin-rebuild switch`,
  and `timeout-minutes: 30`.
  https://github.com/nix-darwin/nix-darwin/blob/master/.github/workflows/test.yml
- `verified (absence)` — **no Nix use in Cirrus CI's Tart-backed macOS docs.** `cirrus-ci.org` no
  longer resolves in DNS from `<private-host>` (`getaddrinfo ENOTFOUND cirrus-ci.org`).
- `verified` — **nix-darwin #1552 "VM tests"** is **open, zero comments**, created and last touched
  2025-07-28. Its body only points at the nixpkgs PR.
  https://github.com/nix-darwin/nix-darwin/issues/1552
- `verified` — **nixpkgs #429189 "NixOS test framework: Add macOS VMs"** (roberth) is **open and still
  a draft**. Created 2025-07-28, last touched 2026-09-05, +502/-16 across 7 files. Done:
  `nixosTests.nixos-test-driver.multi-os.driverInteractive` launches macOS. Unchecked TODOs: add the
  test backdoor service, add `requiredFeatures = ["apple-branded-computer"]`, stop the use of
  `getFlake`, and factor generic parts out of `qemu-vm.nix`. It uses NixThePlanet and QEMU, not Tart.
  roberth (2025-07-30): "I'd adopted the qemu approach because I could reuse a working example, but I
  don't think it needs to be qemu." Latest comment (2026-02-22) asks "Is there any progress happening
  elsewhere for this?" — so the effort is **stalled**. The prior baseline's "not ready" holds.
  https://github.com/NixOS/nixpkgs/pull/429189

### Gotchas you will hit, all primary-sourced

1. **Determinate conflicts with nix-darwin.** `verified` — nix-darwin aborts when
   `/usr/local/bin/determinate-nixd` exists: `error: Determinate detected, aborting activation`. Fix
   with `nix.enable = false;`. Either use the **upstream** installer, or Determinate plus
   `nix.enable = false; determinateNix.enable = true;` and
   `inputs.determinate.darwinModules.default`.
   https://github.com/nix-darwin/nix-darwin/blob/master/modules/system/checks.nix
2. **Rename the shell rc files.** `verified` — `/etc/{bashrc,zshrc,zshenv,zprofile}` must become
   `*.before-nix-darwin` or activation refuses to overwrite them. Seen in yclaw, JoelFrancisco, and
   nixy. nixy also moves `/etc/nix/nix.custom.conf`.
3. **Home Manager aborts on the base image's own dotfiles.** `verified` — the image ships
   `~/.zprofile` (brew shellenv) plus a `~/.profile` symlink to it. Move both aside.
   https://github.com/hausfold/haus/blob/main/script/build-golden-vm.sh
4. **A guest-agent and installer deadlock over APFS.** `verified` — hausfold: "On the one bake where
   the two overlapped they deadlocked for good: partition grown, container not, the installer stuck at
   'Create an encrypted APFS volume' and every new ssh session wedged behind them (2026-09-05)."
   Mitigation: poll `df -k /`, a plain syscall — never `diskutil`, which queues on
   `diskmanagementd`. Same URL.
5. **Homebrew ownership.** `verified` — nix-darwin runs `brew` as `system.primaryUser`; casks fail on
   `/opt/homebrew/var/homebrew/locks` when `admin` installed brew.
   https://github.com/vicyap/dotfiles/blob/main/vms/darwintest/README.md
6. **`tart clone` is CoW, and it auto-prunes.** `verified` — "Due to copy-on-write magic in Apple File
   System, a cloned VM won't actually claim all the space right away … This also speeds up clones
   enormously." Auto-prune evicts the least-recently-accessed cached VMs, capped at 100 GB
   (`--prune-limit`), and `TART_NO_AUTO_PRUNE` disables it. **Set that variable in a test harness, or
   a prune can evict your base image mid-run.**
   https://github.com/openai/tart/blob/main/Sources/tart/Commands/Clone.swift and
   https://github.com/openai/tart/blob/main/docs/faq.md
7. **`tart login/clone/pull/push` over SSH hits the Keychain.** `verified` —
   `Keychain returned unsuccessful status -25308`, because the Keychain unlocks only in a GUI session.
   The same FAQ documents the headless workaround: `security create-keychain` plus
   `security unlock-keychain`. macOS 15+ needs an unlocked `login.keychain` before any VM starts.
   https://github.com/openai/tart/blob/main/docs/faq.md
8. **VirtioFS read-write mounts corrupt data, git repositories especially.** `verified` — openai/tart
   #1271, open since 2026-06-18. Prefer `rsync` or `nix copy` over a `--dir` share.
   https://github.com/openai/tart/issues/1271
9. **A headless `diskutil` hang exists outside Tart.** `verified` — nix-installer #1796: the installer
   hangs at `create_fstab_entry` → `diskutil info -plist "Nix Store"` on macOS 15.5+ in headless CI.
   Expo: "this is related to changes in macOS 15.5 to the TCC system." The Cirrus Labs base images
   pre-seed `TCC.db`, which `unverified (inference)` likely explains why Tart guests avoid it.
   https://github.com/DeterminateSystems/nix-installer/issues/1796 and
   https://github.com/cirruslabs/macos-image-templates/blob/master/scripts/update-tcc-database.sh

### Recommended shape

`unverified (judgement)` — copy `JoelFrancisco/nix-darwin-config/tests/vm-test.sh`. It builds the
system closure **on the host**, runs `nix copy --to ssh-ng://` into the guest, then
`nix-env -p /nix/var/nix/profiles/system --set` and `$target_system/activate`. That avoids a slow Nix
build inside the guest and keeps `trusted-users` to a single added line. Add hausfold's guard: wait for
the APFS container to finish its grow before you install Nix. Decide the Determinate-versus-upstream
question first, because gotcha 1 is a hard abort.

## Q4 timing budget

| Phase | Time | Tag | Source |
|---|---|---|---|
| **Pull the base image, first time** | 27.31 GB over the network | **verified** (size, not wall clock) | Sum of layer sizes from the GHCR manifest for `cirruslabs/macos-tahoe-base:latest`. At 200 Mbit/s that is ~18 min; at 1 Gbit/s ~4 min |
| **Pull, cached** | 0 s | verified | Tart stores remote images in `~/.tart/cache/OCIs/`. https://github.com/openai/tart/blob/main/docs/faq.md |
| **CoW clone** | "APFS copy-on-write, **seconds**" | **verified (cited)** | https://github.com/hausfold/haus/blob/main/script/build-golden-vm.sh · Tart: "a cloned VM won't actually claim all the space right away … speeds up clones enormously" |
| Mirage clone, for contrast | **~10 ms** | verified (project claim) | "Instant clones — copy-on-write (APFS clonefile); a fresh VM in ~10 ms regardless of disk size." https://github.com/solcreek/mirage |
| **Boot to ssh** | **not published** | **not found** | No source gives a measured number. The prior baseline's "~26 s to exec-ready on an M4" stays **unverified** — I found no primary source for it. Harness timeouts bracket it: `create_grace_time` 120 s (yclaw), a 120×5 s ssh poll (JoelFrancisco), `ssh_timeout` 120 s in the base template |
| Boot to ssh, warm restore | "straight back to the logged-in desktop, skipping the cold boot" | verified (project claim, no number) | Mirage warm memory snapshot. https://github.com/solcreek/mirage |
| **Nix install** in the guest | part of the ~40 min bake below; no isolated figure published | **not found** | — |
| **Determinate `/nix` unlock at boot** | `determinate-nixd` mounts `/nix` from the keychain at **~41 s**; after `diskutil apfs decryptVolume`, `/nix` is mounted and ssh is up **~10 s** after reboot. Online decrypt of a ~12 GB store: **~1 min** | **verified (cited)** | https://github.com/hausfold/haus/blob/main/script/build-golden-vm.sh |
| **nix-darwin bootstrap plus first `darwin-rebuild switch`, from a clean base** | **~40 min total**, together with the Nix install | **verified (cited)** — stated three times in the script as the cost of a late failure | https://github.com/hausfold/haus/blob/main/script/build-golden-vm.sh |
| **Disk that the result needs** | full clone plus Nix store **~25-30 GB**; the preflight demands ≥ 40 GB free. `tart set --disk-size 90` gives an 83 GiB container with 42 GiB free after the switch | **verified (cited)** | same URL |
| This repository's own closure, for scale | **33.0 GB** | **verified** — `nix path-info -Sh /run/current-system` on `<private-host>` | A `nix copy` of that closure into a guest dominates any per-loop budget unless the guest reuses a warm store |
| **Incremental `darwin-rebuild switch`** on a warm golden image | **estimated 30-120 s** | **estimated** | Only changed paths copy. nix-darwin's own CI budgets `timeout-minutes: 30` for a full cold job. https://github.com/nix-darwin/nix-darwin/blob/master/.github/workflows/test.yml |
| **Assertions** (`realpath /run/current-system`, marker files, symlink checks) | **estimated 1-5 s** | **estimated** | The pattern comes from nix-darwin PR #1000 and JoelFrancisco's script |
| **Stop plus delete** | **estimated < 1 s** | **estimated** | CoW clone deletion frees only the delta. The prior baseline's "<1 s" is plausible but I found no primary source |

### Timing verdict

Two very different loops. Do not confuse them.

- **Cold loop, from the public base image: tens of minutes.** ~40 min for the Nix install plus first
  activation (`verified`, hausfold), on top of a one-time 27 GB pull. Never do this per checkpoint.
- **Warm loop, from your own golden image: minutes.** Bake the golden image once — base image, Nix,
  Determinate or upstream chosen, the rc files renamed, the store pre-warmed. Then each checkpoint
  costs: clone (seconds) + boot (`not found`, bracketed under ~2 min) + incremental `nix copy` and
  activate (**estimated** 30-120 s) + assertions (seconds) + delete (< 1 s). That lands at roughly
  **2-5 minutes per checkpoint**, `estimated`.

So a per-checkpoint loop is practical, **but only after the golden-image investment**. The honest
summary: minutes per loop, tens of minutes once, and 27 GB of network once.

## Open questions

1. **Boot-to-ssh wall clock in a Tart guest.** No source publishes a measured number, and I could not
   confirm the baseline's "~26 s to exec-ready on an M4". **Settles it:**
   `time (tart clone ghcr.io/cirruslabs/macos-tahoe-base:latest t && tart run --no-graphics t & until tart exec t true; do sleep 1; done)`
   on `<private-host>`. This needs the 27 GB pull, so it was out of scope here.
2. **Incremental `darwin-rebuild switch` time in a guest for this repository.** The 33.0 GB closure is
   verified; the per-checkpoint delta is not. **Settles it:** `nix copy --to ssh-ng://admin@<ip>` of
   two adjacent checkpoints' `system` outputs, then `time $target/activate`.
3. **Whether `nix copy` beats a build inside the guest.** Untested. **Settles it:** run the
   `JoelFrancisco` script once and compare it against a guest-side `darwin-rebuild switch --flake`.
4. **The Apple SLA "own or control" question for company-issued hardware.** The Apple license grants
   two guests per computer, and testing is a named purpose. Employer policy is a separate matter and no
   public source can settle it. **Settles it:** the external adopter's own IT policy, not a URL.
5. **Whether Tart phones home or requires a key.** The license names no key and the docs name none,
   but I did not audit the Swift sources. **Settles it:**
   `grep -rniE 'license|activation|telemetry|analytics' Sources/tart/` on a checkout of `openai/tart`.
6. **The stale nixpkgs Tart metadata.** `nixpkgs#tart` is 2.30.6 with `license = fairsource09` and
   `unfree = true`, but upstream is now FSL-1.1-ALv2. **Settles it:** a nixpkgs pull request that bumps
   the version and the license attribute. Worth a `.flake.patches/` entry in the meantime.
7. **Mirage's real maturity.** Apache-2.0, ~10 ms clones, warm snapshot and restore, zero-touch create,
   and an MCP server make it the best fit on paper, and its license is cleaner than Tart's. But it is
   v0.1, its last commit is 2026-06-23, it is absent from nixpkgs, and it has no public image
   registry, so it needs a one-time IPSW download. **Settles it:** build it from source and time
   `mirage create base --ipsw … --headless` against a Tart bake.
8. **Whether stopped Tart VMs count against Apple's two-VM cap.** Third parties say no; no primary
   Apple statement found. **Settles it:** start three VMs, stop one, and start a third — observe
   whether `Virtualization.framework` refuses.
9. **`VZMacGuestProvisioningOptions` on macOS 27.** It sets a user, a password, and `enablesRemoteLogin`
   on first boot after restore, which would delete every Setup Assistant screen-scrape. It is beta and
   needs macOS 27 in the guest. **Settles it:** Apple's release notes when macOS 27 ships, plus whether
   Tart adopts it.
10. **Lima as a Tart replacement.** `limactl start template:macos` does the IPSW download, the install,
    and the ssh setup in one Apache-2.0 command, with far higher project activity than Mirage. It has
    no OCI image registry, so every guest starts from an IPSW install. **Settles it:** time
    `limactl start template:macos` once and compare it against `tart clone` from GHCR.
