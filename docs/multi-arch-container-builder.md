---
type: How-To
description: Build per-arch OCI images with nix2container and stitch them into one multi-arch image index locally, in a Nix build step, with no container runtime or registry.
timestamp: 2026-07-30T16:14:54+02:00
---

# Multi-arch container images from Nix (no runtime, no registry)

> **Agent summary:** produce a single multi-arch container image (an OCI *image index*
> covering `aarch64-linux` + `x86_64-linux`) entirely inside Nix — no Docker/podman daemon, no
> registry round-trip. Requires the dual-arch builder from
> [multi-arch-builder.md](./multi-arch-builder.md) so both per-arch images can be realised on one
> Apple Silicon host. This is a handover doc presenting the viable approaches with tradeoffs.

---

## The problem, in two halves

1. **Build each arch's image.** `nix2container.buildImage` (and `dockerTools.buildImage`) are
   **single-arch**: the resulting image contents are whatever the `pkgs` you pass were built for.
   `buildImage` has an `arch` parameter, but it only stamps metadata — it does **not**
   cross-compile. To get a real `x86_64-linux` image you must build it with an `x86_64-linux`
   `pkgs`, which needs an `x86_64-linux` builder (that's the companion doc's job).
2. **Combine them.** A "multi-arch image" on a registry is an **OCI image index** (a.k.a. Docker
   manifest list): one manifest whose entries point at each arch's image manifest by digest +
   `platform`. The goal here is to assemble that index **locally**, in a Nix derivation, without
   pushing to a registry or talking to a daemon first.

Half 1 is solved by the builder doc. This doc is mostly about half 2.

---

## Half 1 — build both per-arch images

Parameterize the image derivation by system and instantiate it once per arch. Sketch:

```nix
# image.nix — a single-arch image factory
{ pkgs, nix2container }:
nix2container.buildImage {
  name = "example-app";
  # copyToRoot / config / layers … all built from `pkgs`, i.e. this arch.
}
```

```nix
# flake / devenv wiring — one instance per target Linux system
let
  forSystem = system: import ./image.nix {
    pkgs        = inputs.nixpkgs.legacyPackages.${system};
    nix2container = inputs.nix2container.packages.${system}.nix2container;
  };
  images = {
    "aarch64-linux" = forSystem "aarch64-linux";
    "x86_64-linux"  = forSystem "x86_64-linux";
  };
in ...
```

- On an `aarch64-darwin` host with the dual-arch builder in place, `forSystem "x86_64-linux"` is
  realised on the Rosetta/QEMU builder and copied back to the host store (see builder doc).
- **Known blocker without the x86_64 builder:** nix2container emits tiny config derivations
  (`history.json`, `group.json`, …) with `allowSubstitutes = false`, so they must be *built* on
  `x86_64-linux` — they can't be substituted from a cache. No x86_64 builder / no binfmt ⇒
  `a 'x86_64-linux' with features {} is required to build ...` failure. This is the single reason
  the whole thing needs the companion doc.
- **Copy wrappers run on the host, not in the image.** nix2container's `copyTo*` passthru wrappers
  are skopeo apps built from the *image's* (Linux) `pkgs`; on a darwin host they die with
  `exec format error`. Rebuild them from the **host** package set
  (`hostPkgs.writeShellApplication` wrapping `hostSkopeo`), pointing skopeo at `nix:${image}` (the
  `nix:` transport only needs the arch-neutral image-json path). Pass `hostPkgs`/`hostSkopeo` into
  the image factory alongside `pkgs`/`nix2container`.

---

## Half 2 — stitch the index locally (options)

Requirement recap: assemble an OCI image index **in a Nix build step**, **no registry**, **no
daemon**. The tools below are all in nixpkgs. Only some can *create* an index against a local
`oci-layout` directory — that distinction is the whole decision.

| Tool | Create index into a **local** `oci-layout`? | Notes |
|------|--------------------------------------------|-------|
| **`regctl index create`** | ✅ yes (`ocidir://`) | Purpose-built; works fully offline. **Recommended.** |
| `crane index append` | ❌ registry-oriented | `--append`/filter work against **remote** refs; not a local-layout index creator. |
| `skopeo copy` | ⚠️ copies *into* a layout, but | **cannot create** the index manifest that ties arches together. |
| `manifest-tool push` | ❌ push-only | Designed to push a list to a registry. |
| `umoci` | ⚠️ layout-aware | Image/layout surgery, not a convenient index-builder for this. |
| `buildah manifest` | ⚠️ needs storage | Works, but pulls in a container-storage backend — heavier, less "pure Nix step". |

### Option 1 — `regctl index create` against `ocidir://` *(recommended)*

`regctl` (from `regclient`) creates an image index directly in a local OCI layout directory with
no network and no daemon. Proven pattern in a `runCommand`:

```nix
# stitch.nix — combine per-arch nix2container images into one OCI index, offline
{ hostPkgs, images }:   # images = { "aarch64-linux" = <img>; "x86_64-linux" = <img>; }
hostPkgs.runCommand "multi-arch-index"
  { nativeBuildInputs = [ hostPkgs.regctl hostPkgs.skopeo ]; }
  ''
    layout=$out
    mkdir -p "$layout"

    # 1. copy each per-arch image into the SAME oci-layout dir under a distinct tag.
    #    `nix:${img}` is the arch-neutral nix2container transport; the image's own
    #    metadata carries the correct platform.
    skopeo --insecure-policy copy nix:${images."aarch64-linux"} "oci:$layout:arm64"
    skopeo --insecure-policy copy nix:${images."x86_64-linux"}  "oci:$layout:amd64"

    # 2. create the index referencing both, selecting platform per source tag.
    regctl index create "ocidir://$layout:index" \
      --ref "ocidir://$layout:arm64" --platform linux/arm64 \
      --ref "ocidir://$layout:amd64" --platform linux/amd64
  ''
```

Result is a valid `application/vnd.oci.image.index.v1+json` in `$out` (an oci-layout dir). Push it
later with `skopeo copy oci:$out:index docker://<registry>/<repo>:<tag>` (or regctl), or
`podman load` a specific arch. **This exact flow was validated end-to-end** (two nix2container
images → one offline OCI index) — it's the known-good path.

- **Pros:** fully offline, no daemon, pure `runCommand`; smallest, most direct tool for the job.
- **Cons:** one extra host tool (`regctl`); index digests are content-addressed, so re-pushing is
  cheap but the layout dir is a build output you then push separately.

### Option 2 — `buildah manifest create/add` + `buildah manifest push`

`buildah` can build a manifest list and push it (`--all`) without a running daemon. Viable if
buildah is already in the toolchain, but it wants a container-storage backend, which is awkward to
sandbox cleanly inside a pure Nix `runCommand` and heavier than Option 1.

- **Pros:** familiar OCI tooling; one tool does build+list+push.
- **Cons:** storage backend inside the build sandbox is fiddly; larger closure than `regctl`.

### Option 3 — build the layout with `nix2container` per arch, index with `crane`/`skopeo` at push time

Skip local index creation: keep the two per-arch images separate in the store, and create the
manifest list **at push time** against the registry (`crane index append` or `regctl index create`
with `docker://` refs). Only choose this if a local (no-registry) index is genuinely not needed —
it violates the "no registry" requirement, so it's a fallback, not the target.

- **Pros:** avoids assembling a local layout.
- **Cons:** needs a registry to form the index — fails the offline requirement.

---

## Recommendation

1. **Half 1:** parameterize the image by system, instantiate per arch, realise `x86_64-linux` on
   the dual-arch builder from the companion doc. Rebuild `copyTo*` from the host package set.
2. **Half 2:** **Option 1 (`regctl index create` against `ocidir://` in a `runCommand`)** — it's
   the only tool that cleanly creates the index locally with no runtime/registry, and it's the
   validated path.

End-to-end shape:

```
per-arch nix2container images (aarch64 + x86_64, both in host store)
        │  skopeo copy nix:<img>  →  oci:<layout>:<arch>
        ▼
   local oci-layout dir (both images, two tags)
        │  regctl index create ocidir://<layout>:index --ref … --platform …
        ▼
   OCI image index (multi-arch)  →  skopeo/regctl copy → registry (later)
```

**Notes for the implementer:**

- All of `regctl`, `skopeo`, `crane`, `manifest-tool`, `umoci`, `buildah` are in nixpkgs — no new
  flake input needed for the stitch step; it's a `runCommand` with `nativeBuildInputs`.
- Keep the stitch derivation host-arch (`hostPkgs`): skopeo/regctl run on the host, only the image
  *contents* are Linux.
- Verify the result offline before pushing:
  ```bash
  skopeo inspect --raw oci:$out:index | jq '.mediaType, .manifests[].platform'
  # expect application/vnd.oci.image.index.v1+json and both linux/arm64 + linux/amd64
  ```
- Pushing to a registry is a separate, later step (and typically needs registry creds) — the Nix
  build stops at the local layout.
