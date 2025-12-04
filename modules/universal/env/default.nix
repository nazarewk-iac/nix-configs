{lib, ...}: {
  options.kdn.env.packages = lib.mkOption {
    type = with lib.types; listOf package;
    default = [];
  };
}
