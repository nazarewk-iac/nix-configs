/*
  Assemble `/etc/nix/netrc` from the `/etc/nix/netrc.d/*.conf` drop-in
  directory, on every change. The fragments come from sops templates (for
  example `/etc/nix/netrc.d/kdn-github.conf` from the `nix/access-tokens`
  secret), so no credential is ever written by hand.

  This is the same shape as `kdn.networking.dynamic-hosts` for `/etc/hosts`:
  a `find`-based generator, a systemd path unit that watches the directory, and
  a oneshot service that runs the generator. NixOS must not manage
  `/etc/nix/netrc` itself, and the file must not be persisted (it is rebuilt
  from the drop-ins on every activation).
*/
{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.security.dynamic-netrc;

  kdn-gen-netrc = pkgs.writeShellApplication {
    name = "kdn-gen-netrc";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
    ];
    text = ''
      mkdir -p /etc/nix/netrc.d
      {
        find /etc/nix/netrc.d -name '*.conf' \
          -exec printf '# START %s\n' {} \; \
          -exec cat {} \; \
          -exec printf '# END %s\n\n' {} \;
      } >/etc/nix/netrc.tmp
      chmod 0644 /etc/nix/netrc.tmp
      # Replace any pre-existing file or symlink (the old sops template put a
      # symlink at this path) atomically.
      mv -f /etc/nix/netrc.tmp /etc/nix/netrc
    '';
  };
in
{
  options.kdn.security.dynamic-netrc = {
    enable = lib.mkEnableOption "dynamic /etc/nix/netrc rendering from /etc/nix/netrc.d";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.env.packages = [ kdn-gen-netrc ];
      }
      (kdnConfig.util.ifTypes [ "nixos" ] {
        kdn.managed.directories = [ "/etc/nix/netrc.d" ];

        systemd.paths."kdn-dynamic-netrc" = {
          description = "Generates /etc/nix/netrc from /etc/nix/netrc.d directory";
          wantedBy = [ "default.target" ];
          pathConfig.PathChanged = "/etc/nix/netrc.d";
          pathConfig.TriggerLimitIntervalSec = "1s";
          pathConfig.TriggerLimitBurst = 1;
        };
        systemd.services."kdn-dynamic-netrc" = {
          description = "Generates /etc/nix/netrc from /etc/nix/netrc.d directory";
          wantedBy = [ "default.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = false;
            ExecStart = lib.getExe kdn-gen-netrc;
          };
        };
      })
    ]
  );
}
