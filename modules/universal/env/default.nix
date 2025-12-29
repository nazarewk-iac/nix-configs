{lib, ...}: {
  options.kdn.env.packages = lib.mkOption {
    type = with lib.types; listOf package;
    default = [];
  };
  options.kdn.env.variables = lib.mkOption {
    type = with lib.types; attrsOf str;
    default = {};
  };
}
