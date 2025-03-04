{
  lib,
  pkgs,
  config,
  kdn,
  ...
}: let
  cfg = config.kdn.virtualization.microvm.guest;
in {
  imports =
    kdn.self.lib.lists.optionals (!kdn.features.microvm-guest)
    [kdn.inputs.microvm.nixosModules.microvm-options];

  options.kdn.virtualization.microvm.guest = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = kdn.features.microvm-guest;
    };
  };

  config = lib.mkMerge [
    # `microvm.guest.enable` defaults to `true`
    {microvm.guest.enable = cfg.enable;}
    (lib.mkIf cfg.enable (lib.mkMerge [
      {
        kdn.profile.machine.baseline.enable = lib.mkDefault true;
        kdn.security.secrets.enable = false;
        security.sudo.wheelNeedsPassword = lib.mkDefault false;
      }
      {
        microvm.shares = [
          {
            # shared /nix/store
            proto = "virtiofs";
            tag = "ro-store";
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
          }
          /*
          journal needs to be disabled on the first start of VM o.O
          see https://github.com/astro/microvm.nix/issues/200
          */
          #{
          #  # centralized journal, see https://astro.github.io/microvm.nix/faq.html#how-to-centralize-logging-with-journald
          #  source = "/var/lib/microvms/${config.kdn.hostName}/journal";
          #  mountPoint = "/var/log/journal";
          #  tag = "journal";
          #  proto = "virtiofs";
          #  socket = "journal.sock";
          #}
        ];
      }
    ]))
  ];
}
