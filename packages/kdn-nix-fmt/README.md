# kdn-nix-fmt

Chooses the right formatter based on the `git remote -v` result, default to `alejandra` or `nixfmt` for
NixOS/nix-community projects.

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
