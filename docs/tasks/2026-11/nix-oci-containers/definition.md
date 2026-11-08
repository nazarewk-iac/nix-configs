---
type: Task
description: Research running Nix-built containers directly from the Nix store on an OCI runtime (Podman, Docker, containerd, Kubernetes), and decide whether this is a better fit than systemd-nspawn for our auxiliary services.
status: open
authored_by: agent
timestamp: 2026-11-08T20:29:58+01:00
---

# Running Nix-built containers from the store on OCI runtimes

## Context

We run auxiliary services as `nixos-containers` (systemd-nspawn) today, see
[docs/nixos-containers.md](../../../nixos-containers.md). This works, but it has
limits:

- The image/portability story is weak. A guest is an in-repo NixOS module, not
  an image you can ship or inspect.
- There is no OCI interop. You cannot hand the guest to Podman, Docker, or a
  Kubernetes cluster.
- Networking and firewalling are manual (a private veth, one socat relay per
  port, both firewalls).
- There is no first-class image distribution. You rebuild the closure on every
  host.

We want to evaluate the opposite direction: let an OCI-capable runtime use the
Nix store as the image source, and run a Nix-built container or NixOS closure
**directly from the store**, ideally without copying images around.

The repo already has both runtimes in tree: Podman via
`modules/den/aspects/virt-containers*.nix`, and containerd plus kubeadm via
`modules/den/aspects/service-k8s*.nix`. `templates/terraform/flake.nix` already
pulls in `nix2container`.

## Scope

Research and a compatibility matrix only. No implementation. Facts that I could
not verify from a primary source are listed as open questions, not asserted.

## 1. nix-snapshotter

Source: <https://github.com/pdtpartners/nix-snapshotter> (MIT, ~864 stars, last
push 2026-02).

- **What it is.** A **containerd snapshotter** that brings native understanding
  of Nix packages to containerd. Instead of downloading image layers, it serves
  Nix store paths as the container rootfs. A package closure is either already
  in the host store or fetched from a Nix binary cache at package granularity.
- **How it works.** It is a snapshotter plug-in plus a CRI **Image Service**.
  The kubelet can "pull" an image whose reference is a Nix store path, so a
  container can run without a Docker registry. Layers are small tars that list
  store paths, not copies of the contents.
- **Runtimes it targets.** containerd (rootful and rootless), and k3s /
  Kubernetes through the CRI image service. The kubelet must point
  `--image-service-endpoint` at nix-snapshotter to resolve `nix:0<store-path>`
  references.
- **Integration.** The project's own flake ships a NixOS module and a
  Home Manager module (plus an overlay). The module enables
  `virtualisation.containerd` with snapshotter integration and
  `services.nix-snapshotter`. **This module is not in nixpkgs.** I checked the
  `nixos/modules/virtualisation` tree and `containerd.nix`; neither has a
  nix-snapshotter option. Use the flake input.
- **How an image is expressed.** `pkgs.nix-snapshotter.buildImage` takes
  `name`, `tag`, and an OCI `config` (for example `entrypoint`). With
  `resolvedByNix = true` the image reference resolves to the store path. A k8s
  Pod spec then sets `image = "nix:0${image}"`.
- **Interop.** Backwards-compatible with normal OCI images; nix-snapshotter
  layers can be interleaved with normal layers. `buildImage` can also
  `copyToRegistry` to a normal OCI registry.
- **What it does NOT support.** The Docker daemon and Podman. A snapshotter is
  a containerd concept; Podman and Docker use `containers/storage`, not
  containerd snapshotters. Rootless k3s plus nix-snapshotter does not support
  `nerdctl run` yet (containerd/nerdctl#2831).

## 2. nix-storage-plugin — the ambiguity, resolved

The name is real and highly relevant. It is **not** a Nix store/storage plugin.
It is **`bitbloxhub/nix-storage-plugin`**, described as "nix-snapshotter but for
Podman, CRI-O, and any other `container-libs/storage` based tools".
Source: <https://github.com/bitbloxhub/nix-storage-plugin>.

- **Mechanism.** The plugin uses a FUSE **Additional Layer Store** (ALS) plus a
  local registry adapter. It resolves the store paths listed in
  nix-snapshotter layers from the host Nix store.
- **The catch.** `containers/storage` normally looks up an ALS entry by TOC
  digest. nix-snapshotter layers lack that digest, so the consumer must be
  built against a patched `container-libs` branch, `als-first`. This is tracked
  in podman-container-tools/container-libs#747. The patch makes storage search
  the ALS first and match compressed-layer or uncompressed-diff digests too.
- **Integration.** An overlay plus a NixOS module:
  `services.nix-storage-plugin.enable = true`, with options `mountPath`,
  `bindAddress`, `port` (default 45123), `manageStorageConfig`,
  `manageRegistryAlias`. Images are built with **nix-snapshotter**.
- **Usage.** `podman run ghcr.io/pdtpartners/redis-shell:latest`,
  `podman run nix:0/nix/store/<hash>-nix-image-redis.tar`, and `flake-github:0/…`
  references through the registry adapter.
- **Maturity.** Young and single-maintainer: created 2026-04, last push
  2026-10-18, 9 stars, 0 forks, **no license file**. It also requires Podman
  built against the patched libraries. Treat it as the closest real thing, and
  as experimental.
- Note: `containers/storage` does have a native `additionalimagestores` feature
  (see `containers-storage.conf(5)`); that is the hook the plugin uses. The
  digest matching still needs the `als-first` patch.

## 3. Alternatives

- **nix2container** (<https://github.com/nlewo/nix2container>, Apache-2.0,
  ~945 stars, active). Builds an OCI image without writing layer tarballs to the
  store; layers are built just-in-time on export. Loads into Docker
  (`copyToDockerDaemon`) or Podman (`copyToPodman`), or pushes with the Skopeo
  `nix` transport. Content is copied into the runtime's storage; no registry is
  needed for local use.
- **dockerTools.buildImage / streamLayeredImage** (nixpkgs built-in, maintained).
  `buildImage` writes a tarball into the store, then `docker load` / `podman
  load`. `streamLayeredImage` streams the archive just-in-time, so no tarball
  sits in the store, but the content still lands in the runtime's storage. Both
  use a popularity heuristic that can duplicate packages between layers.
- **nixery** (<https://github.com/tazjin/nixery>, canonical source in TVL,
  ~2k stars, mirrored infrequently, still active). A Docker-compatible
  **registry** that builds images on demand: packages are path components of the
  image name. The consumer pulls from the registry, so the image is copied into
  runtime storage. It is not store-native at consume time.
- **NixOS OCI image** (`nixos-rebuild build-image --image-variant docker`;
  `nixos-generators` is deprecated and upstreamed into nixpkgs since 25.05).
  Produces a full NixOS system as a container image. The old generators README
  notes the `docker` variant "uses systemd to run, probably only works in
  podman". Other variants (`lxc`, `proxmox`, `proxmox-lxc`) produce a tarball or
  a VMA file. All need an import/copy; none run from the store.
- **virtualisation.oci-containers** (nixpkgs module; verified source:
  `nixos/modules/virtualisation/oci-containers.nix`). Backend `podman` (default
  when `stateVersion >= 22.05`) or `docker`, rendered as a systemd unit. It can
  load a Nix-built image without a registry via `imageFile` or `imageStream`.
  Content is copied into the runtime storage. This is the glue between
  nix2container/dockerTools and a declarative Podman/Docker service.
- **systemd-nspawn / nixos-container** (current default). The guest is a NixOS
  closure; it runs directly from the store with no image. True store-native, but
  no OCI interop and manual networking.

## 4. Compatibility matrix

Cell key: supported / not / partial / needs-copy / unknown, with a short note.

| Tool                                | containerd                          | Kubernetes / k3s                    | Podman                                | Docker                             | systemd-nspawn        |
| ----------------------------------- | ----------------------------------- | ----------------------------------- | ------------------------------------- | ---------------------------------- | --------------------- |
| nix-snapshotter                     | supported (native snapshotter)      | supported (CRI image service)       | not                                   | not                                | not                   |
| nix-storage-plugin                  | not (targets container-libs)        | partial (via CRI-O, not containerd) | partial (experimental, patched libs)  | not                                | not                   |
| nix2container                       | needs-copy (nerdctl load)           | needs-copy (push to registry)       | needs-copy (`copyToPodman`)           | needs-copy (`copyToDockerDaemon`)  | not                   |
| dockerTools / streamLayeredImage    | needs-copy (nerdctl load)           | needs-copy (push to registry)       | needs-copy (`podman load`)            | needs-copy (`docker load`)         | not                   |
| nixery                              | needs-copy (registry pull)          | needs-copy (registry pull)          | needs-copy (registry pull)            | needs-copy (registry pull)         | not                   |
| NixOS OCI image                     | partial (import image)              | needs-copy (push to registry)       | supported (systemd-in-image)          | partial (nixos-generators: partial) | not                  |
| systemd-nspawn / nixos-container    | not                                 | not                                 | not                                   | not                                | supported (store-native) |

Viable today for our hosts:

- **Podman on a single host:** nix2container or `streamLayeredImage` through
  `virtualisation.oci-containers` (needs a copy into `/var/lib/containers`, no
  registry). Store-native but experimental: nix-storage-plugin.
- **Kubernetes:** nix-snapshotter on the existing containerd/kubeadm nodes.
- **Full NixOS guest with isolation and no OCI story:** keep nixos-container.

## 5. Recommendation sketch and open questions

Not a design, only a direction.

- **(a) NixOS service from the store on one host via Podman.** The reliable
  option today is a declarative `virtualisation.oci-containers` service with a
  `nix2container.buildImage` (`.copyToPodman`) or a `dockerTools.streamLayeredImage`
  used as `imageStream`. It needs no registry, but the content is copied into
  Podman storage. The only true store-native option is nix-storage-plugin with
  nix-snapshotter images; do that as a time-boxed spike, not as production,
  because it needs a patched `container-libs` and has one maintainer and no
  license. If the unit is a whole NixOS system, keep nixos-container.
- **(b) Future Kubernetes path.** nix-snapshotter is the designed route: enable
  it on the containerd/kubeadm nodes, point the kubelet `--image-service-endpoint`
  at it, and reference images as store paths. No registry, no layer duplication.
  Expect the rootless caveat.

Open questions (top three first):

1. **Does nix-storage-plugin work with our Podman?** We need the `als-first`
   patched `container-libs`, the overlay, and `additionalimagestores` in
   `storage.conf`. Verify with a real `podman run` of a nix-snapshotter image;
   this is unproven here.
2. **GC and pinning.** Which component keeps a gcroot for store paths that a
   running container references? If nothing pins them, `nix store gc` can delete
   a live rootfs. Not verified from primary sources for either tool.
3. **containerd-only control plane.** Does nix-snapshotter co-exist with our
   custom `virtualisation.containerd.configFile` and kubeadm cluster? Its own VM
   example is the only evidence I found.

Also open:

- Does nix-snapshotter require every host to have Nix and substituter access?
  Offline and per-host binary-cache behaviour is unverified.
- Maintenance risk: nix-snapshotter last push 2026-02; nix-storage-plugin has no
  license and 9 stars. Both may need a fork-and-vendor if we depend on them.

## Sources

- nix-snapshotter: <https://github.com/pdtpartners/nix-snapshotter>
- nix-storage-plugin: <https://github.com/bitbloxhub/nix-storage-plugin>
- containers/storage `als-first` patch issue:
  <https://github.com/podman-container-tools/container-libs/issues/747>
- nix2container: <https://github.com/nlewo/nix2container>
- nixery: <https://github.com/tazjin/nixery>
- nixos-generators (deprecated, format table):
  <https://github.com/nix-community/nixos-generators>
- `virtualisation.oci-containers` (nixpkgs):
  <https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/oci-containers.nix>
- Our current approach: [docs/nixos-containers.md](../../../nixos-containers.md)
