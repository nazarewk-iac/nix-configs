{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.security.secrets;
in {
  options.kdn.security.secrets = {
    package.original = lib.mkOption {
      type = with lib.types; package;
      default = pkgs.kdn.kdn-secrets;
    };
    package.final = lib.mkOption {
      type = with lib.types; package;
      default = cfg.package.original.override {
        extraRuntimeDeps = config.sops.age.plugins;
        inherit (pkgs) sops age;
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      environment.systemPackages = [
        cfg.package.final
      ];
      #kdn.fs.watch.instances.kdn-secrets-render = {
      #  initialRun = true;
      #  extraArgs = [
      #    "--filter=*.sops.*"
      #  ];
      #  recursive = [cfg.config.path];
      #  exec = [(lib.getExe pkgs.kdn.kdn-secrets) "debug"];
      #};
      #systemd.services."kdn-secrets" = {};
    }
  ]);
}
