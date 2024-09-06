{ lib
, pkgs
, config
, ...
}:
let
  cfg = config.kdn.networking.dynamic-hosts;

  kdn-gen-hosts = pkgs.writeShellApplication {
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
in
{
  options.kdn.networking.dynamic-hosts = {
    enable = lib.mkEnableOption "dynamic /etc/hosts rendering";
  };

  config = lib.mkIf cfg.enable {
    kdn.managed.directories = [ "/etc/hosts.d" ];
    environment.etc."hosts".enable = false;
    environment.etc."hosts.d/50-kdn-nixos.hosts".source = pkgs.concatText "hosts" config.networking.hostFiles;
    environment.systemPackages = [ kdn-gen-hosts ];

    systemd.paths."kdn-dynamic-hosts" = {
      description = "Generates /etc/hosts from /etc/hosts.d directory";
      pathConfig.PathChanged = "/etc/hosts.d";
      pathConfig.TriggerLimitIntervalSec = "1s";
      pathConfig.TriggerLimitBurst = 1;
    };
    systemd.services."kdn-dynamic-hosts" = {
      description = "Generates /etc/hosts from /etc/hosts.d directory";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe kdn-gen-hosts;
      };
    };
  };
}
