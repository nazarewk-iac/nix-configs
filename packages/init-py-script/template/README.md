---
type: Template
description: Placeholder template README for scaffolded Python script packages.
timestamp: 2025-10-22T12:03:53+02:00
---

# package-placeholder

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Ut vulputate ornare mollis. Pellentesque feugiat dictum ligula
et iaculis. Proin congue dapibus libero a suscipit. Aenean tempus urna vitae sagittis tempus.

# How to work with it?

To build Python interpreter/virtualenv for your IDE you can run:

```shell
ln -sfT "$(nom build --no-link --print-out-paths '.#package-placeholder.devEnv')/bin/python" nix/packages/package-placeholder/python
nix run '.#link-python' -- package-placeholder
```

To run directly:

```shell
nix run '.#package-placeholder' -- --help
nix run '.#package-placeholder' -- arg1 arg2
```
