# Coverage for the aspects that no other area file instantiates.
#
# `den-eval-coverage` requires every aspect in `denLib.aspectModules` to appear in the merged
# `instantiatedBy` table. Seven aspects had no row, so the check failed and `bundle-core` could not
# pass. This file gives each one a real evaluation: its target module is forced on a bare consumer,
# which is the same shape every other area file uses.
#
# ## The stubs
#
# Two aspects read a consumer option that a bare harness does not declare, and `user-profiles`
# touches `options.kdn.profile-baseline` inside its own condition. Instead of inventing profile data
# for them, the subject below declares the minimum option the aspect probes:
#
# - `net-rustdesk-forward` needs a target host name; a placeholder domain is enough.
# - `pi-client` reads `kdn.hostName`; the home class declares no such option, so the subject declares
#   one with a placeholder value.
# - `user-profiles` tests `options.kdn.profile-baseline ? rootHashedPasswordFile`; the subject
#   declares an empty `kdn.profile-baseline`, so the condition is false and no profile data is read.
#
# None of the values names a real host, address or account.
{
  lib,
  denLib,
  harness,
  ...
}:
let
  inherit (harness) bareNixos bareHomeConfiguration;

  nixosSubject =
    aspect: extra:
    bareNixos (
      denLib.imports {
        class = "nixos";
        aspects = [ aspect ];
      }
      ++ extra
    );

  homeSubject =
    aspect: extra:
    bareHomeConfiguration (
      denLib.imports {
        class = "homeManager";
        aspects = [ aspect ];
      }
      ++ extra
    );

in
{
  assertions = [
    {
      name = "build-farm evaluates on a bare nixos";
      expected = true;
      actual = builtins.isString (nixosSubject "build-farm" [ ]).config.system.build.toplevel.drvPath;
    }
    {
      name = "net-rustdesk-forward evaluates with a target host";
      expected = true;
      actual =
        builtins.isString
          (nixosSubject "net-rustdesk-forward" [
            { kdn.net-rustdesk-forward.target = "relay.example.invalid"; }
          ]).config.system.build.toplevel.drvPath;
    }
    {
      name = "prometheus-container evaluates on a bare nixos";
      expected = true;
      actual =
        builtins.isString
          (nixosSubject "prometheus-container" [ ]).config.system.build.toplevel.drvPath;
    }
    {
      name = "service-rustdesk evaluates on a bare nixos";
      expected = true;
      actual =
        builtins.isString
          (nixosSubject "service-rustdesk" [ ]).config.system.build.toplevel.drvPath;
    }
    {
      name = "web-exposure evaluates on a bare nixos";
      expected = true;
      actual = builtins.isString (nixosSubject "web-exposure" [ ]).config.system.build.toplevel.drvPath;
    }
    {
      name = "user-profiles evaluates with no profile data";
      expected = true;
      actual =
        builtins.isString
          (bareNixos (
            denLib.imports {
              class = "nixos";
              aspects = [
                "user"
                "profile-baseline"
                "user-profiles"
              ];
            }
            # The bare harness defines no root password, and the `user` aspect turns on the NixOS
            # user module, which asserts on that. The explicit allow flag makes the assertion pass.
            ++ [ { users.allowNoPasswordLogin = true; } ]
          )).config.system.build.toplevel.drvPath;
    }
    {
      name = "pi-client evaluates on a bare home with a host name";
      expected = true;
      actual =
        builtins.isString
          (homeSubject "pi-client" [
            {
              options.kdn.hostName = lib.mkOption {
                type = lib.types.str;
                default = "dev";
              };
            }
          ]).config.home.activationPackage.drvPath;
    }
  ];

  instantiatedBy = {
    build-farm = "den-eval-coverage-gaps (bare nixos)";
    net-rustdesk-forward = "den-eval-coverage-gaps (bare nixos, placeholder target)";
    prometheus-container = "den-eval-coverage-gaps (bare nixos)";
    service-rustdesk = "den-eval-coverage-gaps (bare nixos)";
    web-exposure = "den-eval-coverage-gaps (bare nixos)";
    user-profiles = "den-eval-coverage-gaps (bare nixos with profile-baseline, no profile data)";
    pi-client = "den-eval-coverage-gaps (bare home, placeholder host name)";
  };
}
