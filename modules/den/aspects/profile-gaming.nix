# The `profile/machine/gaming` module of the old tree, as one den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It runs Steam, it installs the non-Steam launchers and the Proton and Wine tools, it points the
# Vulkan loader at one GPU, and it keeps the game data across a boot.
#
# ## Class list: `nixos` and `homeManager`
#
# The old module is nixos-only (`gaming/default.nix:25`), and it reaches Home Manager through
# `home-manager.sharedModules` for the persist entries alone. den splits that: the `nixos` class
# carries Steam and the packages, and the `homeManager` class carries the persist entries. So a
# user gets the paths with no host module at all.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`home-manager.sharedModules` goes.** A `homeManager` target replaces it. The old route makes
#    the host own the user's paths; den lets the user own them.
# 3. **`kdn.env.variables` and `kdn.env.packages` go.** The `nixos` class writes
#    `environment.sessionVariables` and `environment.systemPackages` directly.
# 4. **`nixpkgs.config.allowUnfreePredicate` goes.** The old line **replaces** the predicate of the
#    whole system, so any other unfree package stops building. An aspect must not do that to a
#    consumer. The consumer allows the three Steam names itself. `programs.steam.enable` already
#    fails with a clear message when the predicate refuses.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.**
# 2. **No reachable `enable` option.** `programs.steam.enable` belongs to nixpkgs, and the walk of
#    `checks/standalone.nix:240` inspects the `kdn` prefix alone.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
let
  declaration =
    { lib, ... }:
    {
      options.kdn.profile-gaming.vulkan.deviceId = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        example = "1002:1478";
        description = ''
          Which GPU the Mesa Vulkan loader picks, as a `vendor:device` pair. `null` leaves the
          choice to Mesa.
        '';
      };
      options.kdn.profile-gaming.vulkan.deviceName = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        description = ''
          Which GPU DXVK and VKD3D pick, by name. `null` leaves the choice to the loader.
        '';
      };
    };
in
{
  kdn.profile-gaming.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.profile-gaming;
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      imports = [ declaration ];

      config = {
        # see https://nixos.wiki/wiki/Steam
        programs.steam.enable = lib.mkDefault true;
        programs.steam.remotePlay.openFirewall = lib.mkDefault true;
        programs.steam.localNetworkGameTransfers.openFirewall = lib.mkDefault true;
        programs.steam.protontricks.enable = lib.mkDefault true;

        environment.sessionVariables =
          lib.optionalAttrs (cfg.vulkan.deviceName != null) {
            DXVK_FILTER_DEVICE_NAME = cfg.vulkan.deviceName;
            VKD3D_FILTER_DEVICE_NAME = cfg.vulkan.deviceName;
          }
          // lib.optionalAttrs (cfg.vulkan.deviceId != null) {
            MESA_VK_DEVICE_SELECT = cfg.vulkan.deviceId;
          };

        environment.systemPackages = filterPackages (
          with pkgs;
          [
            # `steam` and `steam-run` arrive through programs.steam.enable
            steamcmd
            steam-tui

            steamtinkerlaunch

            # non-steam
            lutris
            heroic # a native GOG, Epic and Amazon games launcher

            # proton utils
            protonup-qt
            protonup-ng
            protontricks

            # wine utils
            winetricks
            bottles
            wine-wayland

            dxvk
          ]
        );
      };
    };

  kdn.profile-gaming.homeManager =
    { ... }:
    {
      imports = [
        declaration
        ../common/persist.nix
      ];

      config = {
        kdn.disks.persist."usr/data".directories = [
          ".config/heroic"
          ".local/share/bottles"
          ".local/share/Steam"
          # TODO: split these up per program
          ".local/share/lutris"
          ".local/share/umu" # a Steam compatibility tool
          "/Games"
        ];
        kdn.disks.persist."usr/cache".directories = [
          ".cache/umu"
          ".cache/umu-protonfixes"
          ".config/heroic/Cache"
          ".local/share/lutris/runtime"
          ".local/share/bottles/runners"
          ".local/share/bottles/temp"
          ".local/share/bottles/dxvk"
          ".local/share/Steam/steamapps"
        ];
      };
    };
}
