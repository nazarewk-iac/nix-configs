# The `development/java` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It turns on the Home Manager Java program, installs Maven and a Gradle with three Java
# toolchains, and it moves the Gradle home to the cache directory with a symbolic link.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **One class only.** The old module holds a Home Manager half and a NixOS half, and the NixOS
#    half only forwards the `enable`. den needs no forward.
# 3. **`kdn.env.packages` goes.** The target writes `home.packages`, through
#    ../common/filter-packages.nix. Design B.
# 4. **The persist path becomes a read-only option.** The old module writes
#    `kdn.disks.persist."usr/cache".directories`, which another area declares. This aspect publishes
#    `kdn.dev-persist.dev-java` and the consumer wires it.
# 5. **The tmpfiles rules take a Linux guard.** `systemd.user.tmpfiles` asserts a Linux platform and
#    it reads `pkgs.systemd`, so a Darwin Home Manager evaluation fails without the guard. The old
#    module holds the same defect, because it never runs on Darwin. Linux behaviour does not change.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.dev-java.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.kdn.dev-persist.dev-java = lib.mkOption {
        readOnly = true;
        type = lib.types.attrsOf (lib.types.attrsOf (lib.types.listOf lib.types.str));
        default = {
          "usr/cache".directories = [ ".cache/gradle" ];
        };
        description = ''
          The paths this aspect keeps across a wipe, in the shape the persist area takes.

          This aspect writes no persist option of its own. A consumer collects every
          `kdn.dev-persist.*` value and wires it in one line.
        '';
      };

      config = lib.mkMerge [
        {
          programs.java.enable = true;
          programs.java.package = pkgs.jdk;

          home.packages = import ../common/filter-packages.nix { inherit lib; } (
            with pkgs;
            [
              maven
              # gradle-completion # TODO: 2025-10-21 the source failed
              # It used to be `gradle_7`, but that became insecure.
              (gradle-packages.gradle.override {
                javaToolchains = [
                  jdk8
                  jdk11
                  jdk17
                ];
              })
            ]
          );
        }
        (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
          systemd.user.tmpfiles.rules = [
            "d ${config.xdg.cacheHome}/gradle - - - -"
            "L %h/.gradle - - - - ${config.xdg.cacheHome}/gradle"
          ];
        })
      ];
    };
}
