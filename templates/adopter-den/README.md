---
type: How-To
description: A copy-ready devenv starting point for an external adopter of this repository's den aspects.
timestamp: 2026-09-11T10:05:00+02:00
authored_by: agent
---

# Adopter template — the den route

This directory is the smallest devenv shell that consumes a **den aspect**. It is for an
**external adopter** — anybody other than the author of this repository.

The full prose is in [docs/den-for-adopters.md](../../docs/den-for-adopters.md). Read that first.
The two files here carry the same facts as comments, so the template stands alone.

`templates/adopter/` is the older **slots** route. Prefer this directory. The den route needs one
input fewer and no overlay.

## Read this before you copy anything

**The published `main` branch does not carry the den tree yet.** Measured on 2026-09-11: the last
commit that touches `modules/den/` is on no remote branch. So
`url: github:nazarewk-iac/nix-configs` gives you `attribute 'denModules' missing` today. Wait for
the den tree to reach `main`, or point the input at a local clone:

```yaml
nix-configs:
  url: git+file:///absolute/path/to/your/clone/of/nix-configs
