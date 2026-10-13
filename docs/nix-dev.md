---
type: Reference
description: Hands-on notes for building, testing, and formatting this repo's Nix code.
timestamp: 2026-07-09T15:32:54+02:00
---

# Nix Development Notes

> **Agent summary:** [.agents/rules/nix-conventions.md](../.agents/rules/nix-conventions.md)

Practical notes for working on this repo's Nix code. For formatting and module design rules
see the agent rule; this doc covers the hands-on workflows.

---

## Building and testing

```bash
devenv eval '<option.path>'   # evaluate a single option's value (fastest — no derivation build)
devenv build                  # evaluate + build devenv packages (fast check)
devenv build shell             # build the full devenv shell (slower; catches package build failures)
nix run .#kdn-nix-fmt -- <files>   # format Nix files
```

Use `devenv eval` for a quick, targeted check that a specific option wired up correctly (e.g.
after adding a `claude.code.hooks.*`/`claude.code.agents.*` entry — `devenv eval
'claude.code.hooks.jj-guard'`). It's much faster than a full build since it only evaluates the
Nix expression tree, no derivations are built.

Always run `devenv build shell` before declaring work done on anything touching package builds
or derivations — `devenv eval`/`devenv build` alone only check evaluation, not that packages
actually compile.

---

## Vendored lockfiles (e.g. `packages/jj-mcp/package-lock.json`)

Some packages vendor a lockfile next to `default.nix` because upstream doesn't ship one.
These files are **gitignored** and must exist on disk. They can be lost after a `jj workspace`
checkout or other working-tree surgery.

### Restore from nix store (fastest)

If the package was recently built, the lockfile is still in the nix store:

```bash
pkg="jj-mcp"   # adjust to the package name
store_path=$(ls /nix/store | grep "${pkg}.*npm-deps" | head -1)
cp "/nix/store/${store_path}/package-lock.json" "packages/${pkg}/"
```

### Regenerate from the pinned revision

If the store path is gone, regenerate from the `rev` in `packages/<pkg>/default.nix`:

```bash
rev=$(grep 'rev = ' packages/jj-mcp/default.nix | grep -o '"[^"]*"' | tr -d '"')
git clone --depth=1 https://github.com/kmarxican/jj-mcp.git /tmp/jj-mcp-src
cd /tmp/jj-mcp-src
git fetch --depth=1 origin "$rev" && git checkout "$rev"
npm install --package-lock-only
cp package-lock.json /path/to/nix-configs/packages/jj-mcp/
```

### Updating the hash after lockfile change

If the lockfile content changed (e.g. after pinning to a new rev), the `npmDepsHash` in
`default.nix` will be stale. Run `devenv build shell`, copy the `got: sha256-…` value from
the error, and update the field:

```nix
npmDepsHash = "sha256-<new-hash-here>";
```

---

## Store garbage collection and the booted system

A small cloud server (40 GB disk or less) fills its store fast. The store keeps every generation
until a collection. The active kernel holds one extra closure alive.

### The active kernel pins its closure

`/run/booted-system` holds the generation that the running kernel came from. The kernel executes
its own image from the store, so the kernel cannot release that store path while it runs. That
closure therefore survives every collection until the next boot.

`switch` moves `/run/current-system` to the new generation. It does not move `/run/booted-system`.
So a collection after a switch cannot free the closure of the generation that the machine booted.

### Procedure and effect

| Step | Effect on disk |
|---|---|
| `switch` | The new closure lands in the store. The old and the new closure both stay. |
| garbage collection after the switch | Frees every generation and every unreachable path, **except the booted closure**. |
| reboot (or `systemctl kexec`) | `/run/booted-system` moves to the new generation. The kernel releases the old image. |
| garbage collection after the reboot | Frees the old booted closure. Disk use drops to the current closure plus a small margin. |

A `kexec` boot is a fast reboot. It is the only way to move the booted generation without a full
power cycle.

### Rules

- Run a collection after a reboot to reclaim the full amount. A collection right after a switch
  leaves the old booted closure in place.
- Do not expect one collection to free a fresh switch. The release needs the reboot first.
- `nix.gc` and angrr run on a schedule. They free the booted closure on the first run after the
  next boot. So the space returns on its own, but not before that boot.
- You cannot delete the booted store path by hand. `rm /run/booted-system` removes one symlink.
  The kernel still holds the file, and the path stays reachable.

### Worked measurement (`moss`, 38 GB disk)

| Point | Store | Free |
|---|---|---|
| Start | 22 GB | 9.7 GB |
| After switch and collection | 18 GB | 14 GB |
| After reboot and collection | 6.8 GB | 24 GB |

The system closure fell from 10.4 GiB to 6.06 GiB through the `kdn.minimalServer` switches. The
store now holds the closure plus a small margin.

