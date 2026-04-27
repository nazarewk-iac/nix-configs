{
  lib,
  config,
  kdnConfig,
  pkgs,
  ...
}:
{
  options.kdn.env.packages = lib.mkOption {
    type = with lib.types; listOf package;
    default = [ ];
    apply =
      let
        warnAndFilter =
          { predicate, mkMessage }:
          pkgs:
          let
            parts = lib.partition predicate pkgs;
            # parts.right = matched predicate  → warn & discard
            # parts.wrong = didn't match       → keep
          in
          if parts.right == [ ] then parts.wrong else lib.warn (mkMessage parts.right) parts.wrong;

        listRepr = lib.flip lib.pipe [
          (map lib.getName)
          (lib.lists.sort (p: q: p < q))
          (lib.strings.concatStringsSep ", ")
        ];
      in
      lib.flip lib.pipe [
        (warnAndFilter {
          predicate = p: p.meta.broken or false;
          mkMessage = packages: "Excluding broken (meta.broken = true) packages: ${listRepr packages}.";
        })
        (warnAndFilter {
          predicate = p: p.meta.unsupported or false;
          mkMessage =
            packages: "Excluding unsupported (meta.unsupported = true) packages: ${listRepr packages}.";
        })

        (warnAndFilter {
          predicate = p: !(p.meta.available or true);
          mkMessage =
            packages: "Excluding unavailable (meta.available = false) packages: ${listRepr packages}";
        })

        (warnAndFilter {
          predicate = p: !(builtins.tryEval p.outPath).success;
          mkMessage =
            packages: "Excluding packages that fail to evaluate (broken dependencies?): ${listRepr packages}";
        })
      ];
  };
  options.kdn.env.variables = lib.mkOption {
    type = with lib.types; attrsOf str;
    default = { };
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHM {
      home.packages = config.kdn.env.packages;
      home.sessionVariables = config.kdn.env.variables;
    })
    (kdnConfig.util.ifTypes [ "darwin" ] {
      environment.systemPackages = config.kdn.env.packages;
      environment.variables = config.kdn.env.variables;
    })
    (kdnConfig.util.ifTypes [ "nixos" ] {
      environment.systemPackages = config.kdn.env.packages;
      environment.sessionVariables = config.kdn.env.variables;
    })
  ];
}
