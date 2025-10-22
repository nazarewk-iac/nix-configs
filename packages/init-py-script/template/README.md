DOCUMENTATION PLACEHOLDER

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
