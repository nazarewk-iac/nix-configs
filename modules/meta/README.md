A meta-module that is evaluated before the nixos (or other) modules, then the resulting config is passed down as
`specialArgs` to be used in conditional imports `import`.

It was created primarily to preserve "optionality" of the upstream modules otherwise not hiding configs behind
`*.enable`.

It was finally written to supersede
a [half-baked custom thing](https://github.com/nazarewk-iac/nix-configs/blob/9e62780a54858181e879ddd7ed82d45dd7bd2b72/flake.nix#L246-L315),
with a full power of merging, overriding and extending configs.