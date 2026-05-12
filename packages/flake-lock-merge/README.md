# flake-lock-merge

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Ut vulputate ornare mollis. Pellentesque feugiat dictum ligula
et iaculis. Proin congue dapibus libero a suscipit. Aenean tempus urna vitae sagittis tempus.

# How to work with it?

To build Python interpreter/virtualenv for your IDE you can run:

```shell
ln -sfT "$(nom build --no-link --print-out-paths '.#flake-lock-merge.devEnv')/bin/python" nix/packages/flake-lock-merge/python
nix run '.#link-python' -- flake-lock-merge
```

To run directly:

```shell
nix run '.#flake-lock-merge' -- --help
nix run '.#flake-lock-merge' -- arg1 arg2
```
