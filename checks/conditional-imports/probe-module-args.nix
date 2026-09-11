# Route 2 of the conditional-imports requirement: `_module.args` drives `imports`.
#
# `_module.args` is part of `config`, so this route recurses exactly like ./probe-config.nix. A
# framework that hands static entity data to a target module through `_module.args` alone
# therefore CANNOT satisfy the requirement. den sets `_module.args.host` at
# `nix/lib/entities/host.nix:154`, inside its own entity submodule. Whether a den target class
# module also receives `host` that way is an open measurement for 004.
{ lib }:
(lib.evalModules {
  modules = [
    {
      options.flag = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      options.marker = lib.mkOption {
        type = lib.types.str;
        default = "absent";
      };
    }
    { _module.args.hostData.flag = true; }
    (
      { hostData, ... }:
      {
        imports = lib.optionals hostData.flag [ { marker = "present"; } ];
      }
    )
  ];
}).config.marker
