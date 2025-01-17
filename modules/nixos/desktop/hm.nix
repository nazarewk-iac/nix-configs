{
  lib,
  config,
  ...
}: {
  options.kdn.desktop.enable = lib.mkOption {
    type = with lib.types; bool;
    default = false;
  };
}
