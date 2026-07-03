# Nix Development Notes

> **Agent summary:** [.agents/rules/nix-conventions.md](../.agents/rules/nix-conventions.md)

Practical notes for working on this repo's Nix code. For formatting and module design rules
see the agent rule; this doc covers the hands-on workflows.

---

## Building and testing

```bash
devenv build          # evaluate + build devenv packages (fast check)
devenv build shell    # build the full devenv shell (slower; catches package build failures)
nix run .#kdn-nix-fmt -- <files>   # format Nix files
```

Always run `devenv build shell` before declaring work done — `devenv build` only checks
evaluation, not that packages actually compile.

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
