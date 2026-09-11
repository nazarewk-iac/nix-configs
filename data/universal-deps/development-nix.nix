/*
  Personal checkout path for `kdn.development.nix.flake.path`.

  This file is a module, not a data attribute set. It assigns an option that
  `modules/universal/development/nix/default.nix` declares, so that module names no personal
  repository.

  `modules/universal/default.nix` imports this file behind `builtins.pathExists`. An adopter
  deletes the file, `flake.path` falls back to `null`, and the baseline writes no
  `/etc/nixos/flake.nix` link.

  `kdnConfig.util.ifHMParent` is mandatory. `development/nix/default.nix:47` forwards the whole
  `cfg` into Home Manager at priority 100, so an unguarded assignment gives two priority-100
  definitions in a Home Manager evaluation and stops it. The guard keeps this file in the host
  context, and the forward carries the value down. All 16 hosts are `nixos` or `darwin`, so no
  host loses the value.
*/
{
  config,
  kdnConfig,
  ...
}:
kdnConfig.util.ifHMParent {
  config.kdn.development.nix.flake.path =
    "${config.kdn.profile.user.kdn.homeDir}/dev/github.com/nazarewk-iac/nix-configs";
}
