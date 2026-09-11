{
  config,
  pkgs,
  lib,
  kdnConfig,
  ...
}:
let
  # Route switch for the one thing this host installs: the devenv CLI and its shell hooks.
  #
  # `false` keeps the slot route, the live route on every other host.
  # `true`  selects the den route — `modules/den/aspects/devenv-cli.nix`.
  #
  # Both routes stay in this file, so a flip of this one line moves the host either way. Nix is
  # lazy, so the unused route costs no evaluation: with `true` the `mkSlots` call below never runs.
  #
  # Measured on 2026-09-11 against this host. The two routes give an identical
  # `environment.systemPackages`, an identical `home.packages` for both users, and an identical
  # bash, zsh and fish hook for both users. They differ in one option, `nix.extraOptions`, where
  # the same three definitions arrive in a different order. See the risk note on the imports below.
  useDenRoute = false;

  slots = kdnConfig.self.mkSlots {
    inherit pkgs;
    # devenv CLI and shell hooks.
    kdn.devenv.enable = true;
  };

  # The den route. `devenv-cli` is the den aspect that ports `modules/slots/devenv/`.
  #
  # `denLib.imports` is the general form, and this host needs it: `denModules.devenv-cli` does not
  # exist. That zero-argument form names one class per aspect, and `devenv-cli` serves four —
  # `modules/den/flake-module.nix:158-162` states the reason.
  #
  # den names the home-manager class `homeManager`; the slot names the same target `home`.
  denNixos = kdnConfig.self.denLib.imports {
    class = "nixos";
    aspects = [ "devenv-cli" ];
  };
  denHome = kdnConfig.self.denLib.imports {
    class = "homeManager";
    aspects = [ "devenv-cli" ];
  };
in
{
  # The den imports stay **last**. A variant with them first changes the list order of
  # `environment.systemPackages` and of `home.packages`, and that alone moves the toplevel
  # `drvPath`. Measured on 2026-09-11.
  imports = [
    kdnConfig.self.nixosModules.default
    kdnConfig.inputs.nixos-avf.nixosModules.avf
  ]
  ++ lib.optional (!useDenRoute) slots.config.nixos
  ++ lib.optionals useDenRoute denNixos;

  config = lib.mkMerge [
    {
      # den names this class `homeManager`, and the slot names the target `home`. Both deliver the
      # same `home.packages` entry and the same bash, zsh and fish hook. Measured byte-identical
      # on 2026-09-11, for the `kdn` user and for `root`.
      home-manager.sharedModules =
        lib.optional (!useDenRoute) slots.config.home ++ lib.optionals useDenRoute denHome;
    }
    {
      kdn.hostName = "orr";

      system.stateVersion = "26.05";
      home-manager.sharedModules = [ { home.stateVersion = "26.05"; } ];
      networking.hostId = "b2601b4f"; # cut -c-8 </proc/sys/kernel/random/uuid
    }
    {
      # preserving nixos-avf networking tweaks
      networking.networkmanager.enable = false;
      services.avahi.enable = true;
      services.resolved.llmnr = "false";
      kdn.networking.resolved.multicastDNS = "false";

      # turn off some incompatible features
    }
    {
      kdn.profile.machine.baseline.enable = true;
      kdn.profile.machine.dev.enable = true;
      security.sudo.wheelNeedsPassword = false;
    }

    {
      # thin out dependencies

      kdn.desktop.enable = false;
      kdn.profile.machine.desktop.enable = false;
      kdn.development.llm.claude-code.enable = false;
      kdn.development.llm.opencode.enable = false;
      kdn.development.llm.pi.enable = false;
      kdn.development.llm.omp.enable = false;
    }
    # TODO: add SSH host keys (using kdnctl?)
  ];
}
