---
type: README
description: A thin wrapper around nixfmt, the Nix formatter that `nix fmt` runs.
timestamp: 2026-11-19T06:30:00+01:00
---

# kdn-nix-fmt

Formats the named paths with `nixfmt`. It no longer chooses a formatter by git remote: `treefmt.nix`
names `nixfmt` for every Nix file in this tree, and a second Nix formatter (`alejandra`) would
rewrite the same bytes in another style and make `nix fmt` flip them back. The wrapper stays because
an editor command wants a stable name and a per-file argument.

# How to work with it?

To build Python interpreter/virtualenv for your IDE you can run:

```shell
ln -sfT "$(nom build --no-link --print-out-paths '.#kdn-nix-fmt.devEnv')/bin/python" nix/packages/kdn-nix-fmt/python
nix run '.#link-python' -- kdn-nix-fmt
```

To run directly:

```shell
nix run '.#kdn-nix-fmt' -- --help
nix run '.#kdn-nix-fmt' -- arg1 arg2
```
