{ lib, ... }:
{
  forFlake =
    self:
    let
      overlayedInputs =
        {
          system,
          overlay ? self.overlays.default,
        }:
        let
          # adapted from https://github.com/nix-community/nixpkgs-wayland/blob/b703de94dd7c3d73a03b5d30b248b8984ad8adb7/flake.nix#L119-L127
          pkgsFor =
            pkgs: overlays:
            import pkgs {
              inherit system overlays;
              config.allowUnfree = true;
              config.allowAliases = true;
            };
          _overlayedInputs =
            overlays:
            lib.genAttrs (builtins.attrNames self.inputs) (inp: pkgsFor self.inputs."${inp}" overlays);
        in
        _overlayedInputs [ overlay ];
    in
    {
      inherit
        overlayedInputs
        ;
    };
}
