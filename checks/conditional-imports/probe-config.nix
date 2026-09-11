# Route 1 of the conditional-imports requirement: module `config` drives `imports`.
#
# This expression MUST fail. `checks/conditional-imports.nix` runs it through
# `nix-instantiate --eval` and requires the exit code and the `infinite recursion` message.
# `builtins.tryEval` cannot catch this error, so no in-Nix assertion can express it. Measured on
# 2026-09-11: `builtins.tryEval (let x = x; in x)` also aborts the whole evaluation.
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
    (
      { config, ... }:
      {
        imports = lib.optionals config.flag [ { marker = "present"; } ];
      }
    )
    { flag = true; }
  ];
}).config.marker
