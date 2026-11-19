---
type: Reference
description: A minimal FHS sandbox that runs the installed Strata Terminal on NixOS, the measured library set, the comparison with steam-run, programs.nix-ld and autoPatchelfHook repackaging, and the test log from host brys.
timestamp: 2026-11-19T05:45:00+01:00
---

# `strata` — a minimal FHS sandbox for the installed Terminal

`pkgs.kdn.strata` builds a bubblewrap FHS environment and runs the **installed**
Strata Terminal inside it. It packages no Strata code. The Terminal and the
engine stay where the installer put them.

## Why the bundle fails on NixOS

The Terminal ships a relocatable CPython and a shell launcher. The engine ships
prebuilt HIP libraries. The bundled interpreter and both engine executables ask
for the generic interpreter `/lib64/ld-linux-x86-64.so.2`:

```
$ file .../terminal/0.1.62/python/bin/python3.12
ELF 64-bit LSB executable, x86-64, ... interpreter /lib64/ld-linux-x86-64.so.2
```

On NixOS that path is `stub-ld`. It refuses every unpatched ELF:

```
$ .../terminal/0.1.62/python/bin/python3.12 -V
Could not start dynamically linked executable: .../python/bin/python3.12
NixOS cannot run dynamically linked executables intended for generic
linux environments out of the box.
```

`pkgs.kdn.strata` puts a real glibc, with a real `/lib64/ld-linux-x86-64.so.2`,
in front of the bundle. It then adds the few libraries the bundle cannot find
itself.

## The measured library set

Measured on host `brys` with `ldd`, on 2026-11-19. The command walked every
`.so` of both trees, plus the two engine ELF files and the bundled interpreter,
and printed each `not found` line:

```
# terminal tree
find <terminal>/python \( -name '*.so' -o -name '*.so.*' \) -type f |
  while read -r f; do ldd "$f" 2>/dev/null; done | grep 'not found'
# engine tree
find <engine> \( -name '*.so' -o -name '*.so.*' -o -name 'strata' \
  -o -name 'strata-*' \) -type f | while read -r f; do ldd "$f" 2>/dev/null; done |
  grep 'not found'
```

Result — three names in total:

| Missing library  | Found by these files                                                                                                                                                                |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `libstdc++.so.6` | the engine `strata` and `strata-split-2-amd`; numpy `_multiarray_umath`, `_pocketfft_umath`; PIL `_avif` and its bundled `libavif`                                                  |
| `libz.so.1`      | numpy `_multiarray_umath`, `_umath_linalg`, `lapack_lite`, bundled `libgfortran` and `libscipy_openblas`; PIL `_imaging`, `_imagingft`, bundled freetype, harfbuzz, libpng, libtiff |
| `libcrypt.so.1`  | the stdlib `_crypt` module of the bundled CPython                                                                                                                                   |

numpy (with `np.linalg`), Pillow, and the API server path (`strata serve`,
`strata bench`, which imports numpy and Pillow) load these modules, so the
sandbox carries all three.

The realistic list is shorter than it looks, because `buildFHSEnvBubblewrap`
already adds a base set. That base set provides glibc with
`/lib64/ld-linux-x86-64.so.2`, `gcc.cc.lib` (which is `libstdc++.so.6` and
`libgcc_s.so.1`), `bashInteractiveFHS` and `coreutils`. So the package adds only
`zlib` and `libxcrypt`.

### Libraries that are _not_ needed

The usual FHS suspects are absent from the `ldd` output on purpose:

| Candidate                                     | Result                                                                                                                                                                                                                                                                                                  |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `libdrm`, `libelf`, `numactl`, `libpciaccess` | The engine ships its own renamed copies (`librocm_sysdeps_drm.so.2`, `librocm_sysdeps_drm_amdgpu.so.1`, `librocm_sysdeps_elf.so.1`, `librocm_sysdeps_numa.so.1`) and its own `libatomic.so.1`. The HIP runtime `dlopen`s those names, not the host ones.                                                |
| `vulkan-loader`                               | Nothing in either tree names `libvulkan.so.1`. The HIP engine does not use Vulkan.                                                                                                                                                                                                                      |
| `libxcb`, `libxkbcommon`, `libX11`            | The Terminal links no X library. Its Tk build has no X11 dependency (`ldd libtcl9tk9.0.so` lists only libc, libm, libdl and libpthread). `libamdhip64` does name `libGL.so.1` and `libX11.so.6` in its `dlopen` table for graphics interop, but neither is a `NEEDED` entry, so `ldd` asks for neither. |

The engine binary also needs no help to find its own libraries: its `RUNPATH`
points at its own directory, which the sandbox exposes unchanged.

### What the sandbox shows inside

```
$ ldd <engine>/strata | grep -E 'libstdc|libgcc|ld-linux'
	libstdc++.so.6 => /lib/libstdc++.so.6
	libgcc_s.so.1  => /lib/libgcc_s.so.1
	/lib64/ld-linux-x86-64.so.2 => /nix/store/…-glibc-2.44-57/lib64/ld-linux-x86-64.so.2
```

## Host paths inside the sandbox

`buildFHSEnvBubblewrap` binds every top-level directory of the host root
(`--bind $dir $dir` for each `/…`), and it binds `/nix` and `/dev` itself. No
extra bind is needed. Measured inside the sandbox — `STRATA_TERMINAL=/usr/bin/bash`
points the launcher at the sandbox bash, so the sandbox answers the command
itself:

```
$ STRATA_TERMINAL=/usr/bin/bash /nix/store/kvxg…-strata-0/bin/strata \
    -c 'ls -d /var/lib/kdn/llms/models/.bench; ls -d /sys/class/kfd; ls -l /dev/kfd'
/var/lib/kdn/llms/models/.bench
/sys/class/kfd
crw-rw-rw- 1 nobody nogroup 241, 0 /dev/kfd
```

So the Terminal path, the engine path and `/nix/store` all work as host paths.
The KFD node and the DRM nodes stay visible to the HIP runtime.

## Use

```
nix build .#strata
./result/bin/strata doctor
./result/bin/strata components engine
./result/bin/strata launch --data-dir /var/lib/kdn/llms/models/.bench/strata
```

The launcher parses no arguments. `launch`, `components`, `update`, `doctor`,
`monitor`, `serve` and `--help` go to the Terminal unchanged, so the Terminal's
own `--data-dir`, `--components-dir` and `--feed` options keep working.

Three settings select an install:

| Setting                 | Effect                                                       | Default                                                                           |
| ----------------------- | ------------------------------------------------------------ | --------------------------------------------------------------------------------- |
| `STRATA_TERMINAL`       | the Terminal launcher to run                                 | `/var/lib/kdn/llms/models/.bench/strata/terminal/current/bin/strata`              |
| `STRATA_COMPONENTS_DIR` | the component folder that holds the engine                   | `/var/lib/kdn/llms/models/.bench/xdg/strata/components`, computed from `dataHome` |
| `STRATA_DATA_DIR`       | the model and run-config folder; read by the Terminal itself | unset, passed through                                                             |

A caller value always wins. `strata` sets the second one only when the caller
set nothing, because Home Manager on `brys` already exports an unrelated
`XDG_DATA_HOME`. A different install needs no new file:

```
pkgs.kdn.strata.override {
  terminal = "/srv/strata/terminal/current/bin/strata";
  dataHome = "/srv/strata-xdg";
}
```

`extraPkgs` adds packages to the sandbox the same way.

## Test log — host `brys`, 2026-11-19

Built on `oams`, copied with `nix copy --to ssh://brys`, then run on `brys`
(Lix 2.95.4, glibc 2.44-57). Store path of the tested wrapper:
`/nix/store/kvxg49ar4h8bqqf0qpi1sdvzw4y96l32-strata-0`.

`steam-run` is the baseline, because that is the route in use today.

### `strata doctor`

```
$ /nix/store/kvxg…-strata-0/bin/strata doctor
              ok  terminal_cli
              ok  monitor_tui  version 8.2.8
info: PROFILE_NOT_SELECTED: select a run config or saved profile for model-specific checks
$ echo $?
0
```

`diff` against `steam-run <terminal>/bin/strata doctor` prints nothing: the
output is identical.

### `strata components engine`

```
$ /nix/store/kvxg…-strata-0/bin/strata components engine
component folder  /var/lib/kdn/llms/models/.bench/xdg/strata/components
this PC           linux-x86_64, hip (sysfs pci vendor)
  installed       0.1.62 linux-x86_64-hip  /var/lib/kdn/llms/models/.bench/xdg/strata/components/engine/0.1.62-linux-x86_64-hip-rx9070
engine            /var/lib/kdn/llms/models/.bench/xdg/strata/components/engine/0.1.62-linux-x86_64-hip-rx9070/strata  (version 0.1.62)
nothing was downloaded or changed
$ echo $?
0
```

`diff` against the `steam-run` run prints nothing: the output is identical.

### Further checks

| Command                                                                          | Result                                                                                    |
| -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `strata --version`                                                               | `strata 0.2.16 (build 0.1.62; python 3.12.15 at …/terminal/0.1.62/python/bin/python3.12)` |
| `strata components engines`                                                      | lists `0.1.62  2.3 GB  hip-rx9070  in use, newest`                                        |
| `strata update --help`                                                           | full usage text, `diff` against `steam-run` identical                                     |
| `strata launch --help`                                                           | full usage text, includes the Terminal's own `--data-dir DIR`                             |
| `STRATA_TERMINAL=<engine>/strata /nix/store/kvxg…-strata-0/bin/strata --version` | `strata 0.1.62`, so the engine binary itself loads inside the sandbox                     |
| `STRATA_COMPONENTS_DIR=/tmp/empty-dir … components engine`                       | reports `component folder /tmp/empty-dir`, so a caller value wins                         |

No model ran, no server started, and the installed Terminal and engine were only
read.

Size on `brys`, from `nix path-info -Sh`:

| Route             | Closure   | Store paths |
| ----------------- | --------- | ----------- |
| `steam-run`       | 4.2 GiB   | 562         |
| `pkgs.kdn.strata` | 322.9 MiB | 63          |

## The four routes compared

| Route                                      | What it does                                                                                              | Cost                                                                                                                              | Verdict                                               |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| **`steam-run`**                            | a large general FHS environment, made for Steam and its 32-bit game libraries                             | 4.2 GiB and 562 paths for every Strata command; no relation to what Strata needs; one global FHS for every such program           | Works, but heavy and unrelated                        |
| **This wrapper** (`buildFHSEnvBubblewrap`) | one FHS environment sized to the measured library set, with a launcher that runs the installed Terminal   | 323 MiB, 63 paths; no change to any host module; survives `strata update`                                                         | **Recommended**                                       |
| **`programs.nix-ld`**                      | a host-wide replacement for `/lib64/ld-linux-x86-64.so.2` plus a global library list                      | every unpatched ELF on the host then resolves through it; needs a host module edit; one shared library list for all such programs | Second choice; a host-wide switch for one application |
| **`autoPatchelfHook` repackaging**         | copies the Terminal and the engine into the store and rewrites the interpreter and `RUNPATH` of every ELF | a new hash per engine release; breaks the signed manifest; the Terminal refuses the patched tree                                  | **Do not do this**                                    |

### Why repackaging the engine is a bad idea

The engine is a signed component, not a tarball to vendor. Its manifest
`engine-component.json` records `sha256` and `bytes` for **830 files**, plus an
ed25519 `signature` (`key_id` `5d1bc23abbeffd0d`) over that manifest.
`autoPatchelfHook` changes the interpreter and the `RUNPATH` of `strata` and of
many of those 830 files, so every patched file fails its recorded hash. The
result is a tree that `strata components verify` and the update path must reject
as modified. The next `strata update` also replaces the whole engine directory,
so the patched copy is discarded and the work is lost.

A store copy has two further problems. Someone must supply a hash and a source
per release (`0.1.62`, `0.1.63`, …). And a store path is read-only, but the
component folder must accept writes: `strata update` installs the new engine
there, keeps the old one for `strata components rollback`, and
`strata components remove` deletes from it.

The wrapper avoids all of it. It holds no Strata file, so a new Terminal or a new
engine needs no rebuild, no hash and no review of a patched tree.

## What this package does not do

- It does not touch any host configuration. No module imports it.
- It does not replace `steam-run` anywhere. A script that uses `steam-run` keeps
  working.
- It does not copy, patch, verify or download Strata files.

## Recommendation

Use `pkgs.kdn.strata` for the Strata Terminal on NixOS. Keep `steam-run` as the
fallback for programs that have no measured package of their own. Do not
repackage the engine.
