/* Last reviewied: 2024-05-29

  fixes issues with lack of HTTP header sanitization in .NET Core, see:
  - https://github.com/NixOS/nixpkgs/issues/315574
  - https://github.com/microsoftgraph/msgraph-cli/issues/477
*/
{ lib, options, ... }: {
  /*
    using just `readOnly` because it can contain neither of: default, example, description, apply, type
    see https://github.com/NixOS/nixpkgs/blob/aae38d0d557d2f0e65b2ea8e1b92219f2c0ea8f9/lib/modules.nix#L752-L756
   */
  options.system.nixos.codeName = lib.mkOption { readOnly = false; };
  config.system.nixos.codeName =
    let
      codeName = options.system.nixos.codeName.default;
      renames."Vicuña" = "Vicuna";
    in
      renames."${codeName}" or (throw "Unknown `codeName`: ${codeName}, please add it to `renames` in `ascii-workaround.nix`");
}
