# The dynamic `/etc/hosts` renderer of the old `networking` area, as a den aspect. It ports
# `modules/universal/networking/dynamic-hosts/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It turns `/etc/hosts` into a generated file, and it makes `/etc/hosts.d` the real source. A
# `kdn-gen-hosts` command concatenates every `*.hosts` file of that directory, with a START marker
# and an END marker per file. A systemd path unit watches the directory and runs the command again
# after every change.
#
# It also moves the nixpkgs host entries into `/etc/hosts.d/50-kdn-nixos.hosts`, so a static entry
# and a dynamic entry live side by side.
#
# ## Class list: `nixos`, `darwin` and `homeManager`
#
# The old module puts the `kdn-gen-hosts` package outside its context guard, so the command reaches a
# Darwin host and a Home Manager user too. This port keeps that. Only the `nixos` target writes the
# units and the `/etc/hosts` swap, exactly as the old guard states.
#
# TODO: write the Darwin half of this aspect. The command alone does not replace `/etc/hosts` there.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **The `kdn.managed.directories` write becomes a read-only output.** The old module writes that
#    option, and the den `managed` aspect holds the cleanup service that reads it. An `includes` of
#    that aspect would add the cleanup service to every adopter of this aspect, and that is a second
#    unasked effect. So this aspect publishes `kdn.networking.dynamic-hosts.managedDirectories`
#    instead, and the consumer wires it:
#
#        kdn.managed.directories = config.kdn.networking.dynamic-hosts.managedDirectories;
#
#    This follows the read-only `persist` output of ../aspects/hw-audio.nix.
# 3. **The package goes through the native option per class.** ../common/filter-packages.nix drops a
#    package the platform cannot build, and it warns.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** Each target module takes `config`, `lib` and `pkgs` only.
{ ... }:
let
  genHosts =
    pkgs:
    pkgs.writeShellApplication {
      name = "kdn-gen-hosts";
      runtimeInputs = with pkgs; [
        coreutils
        findutils
      ];
      text = ''
        find /etc/hosts.d -name '*.hosts' \
          -exec printf '# START %s\n' {} \; \
          -exec cat {} \; \
          -exec printf '# END %s\n\n' {} \; \
          >/etc/hosts
      '';
    };

  filtered = lib: pkgs: import ../common/filter-packages.nix { inherit lib; } [ (genHosts pkgs) ];

  declaration =
    { lib, ... }:
    {
      options.kdn.networking.dynamic-hosts.managedDirectories = lib.mkOption {
        readOnly = true;
        default = [ "/etc/hosts.d" ];
        description = ''
          The directories a consumer passes to its own directory manager. It is read-only.

          Wire it in the consumer, not here:

              kdn.managed.directories = config.kdn.networking.dynamic-hosts.managedDirectories;
        '';
      };
    };

  unitDescription = "Generates /etc/hosts from /etc/hosts.d directory";
in
{
  kdn.net-dynamic-hosts.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ declaration ];

      config = {
        environment.systemPackages = filtered lib pkgs;

        environment.etc."hosts".enable = false;
        environment.etc."hosts.d/50-kdn-nixos.hosts".source =
          pkgs.concatText "hosts" config.networking.hostFiles;

        systemd.paths."kdn-dynamic-hosts" = {
          description = unitDescription;
          wantedBy = [
            "network.target"
            "default.target"
          ];
          before = [ "network.target" ];
          pathConfig.PathChanged = "/etc/hosts.d";
          pathConfig.TriggerLimitIntervalSec = "1s";
          pathConfig.TriggerLimitBurst = 1;
        };
        systemd.services."kdn-dynamic-hosts" = {
          description = unitDescription;
          wantedBy = [
            "network.target"
            "default.target"
          ];
          before = [ "network.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = false;
            ExecStart = lib.getExe (genHosts pkgs);
          };
        };
      };
    };

  kdn.net-dynamic-hosts.darwin =
    { lib, pkgs, ... }:
    {
      imports = [ declaration ];
      config.environment.systemPackages = filtered lib pkgs;
    };

  kdn.net-dynamic-hosts.homeManager =
    { lib, pkgs, ... }:
    {
      imports = [ declaration ];
      config.home.packages = filtered lib pkgs;
    };
}
