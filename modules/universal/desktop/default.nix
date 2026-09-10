{
  lib,
  config,
  kdnConfig,
  ...
}:
{
  options.kdn.desktop.enable = lib.mkOption {
    type = with lib.types; bool;
    default = false;
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHMParent {
      # The parent is the authority for this machine fact, so the forward uses plain priority
      # (100). `modules/universal/profile/machine/desktop/default.nix` also sets this option
      # inside the home-manager context, at the same plain priority. Both definitions then hold
      # the same value, because that module forwards its own enable from the parent as well.
      # `lib.types.bool` accepts two equal definitions.
      home-manager.sharedModules = [ { kdn.desktop.enable = config.kdn.desktop.enable; } ];
    })
  ];
}
