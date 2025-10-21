{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.services.nextcloud-client-nixos;

  sync = pkgs.writeShellApplication {
    name = "kdn-nextcloud-nixos-sync";
    runtimeInputs = with pkgs; [
      coreutils
      nextcloud-client
    ];
    runtimeEnv.url_path = config.sops.secrets."default/nextcloud/nixos/url".path;
    runtimeEnv.username_path = config.sops.secrets."default/nextcloud/nixos/username".path;
    runtimeEnv.password_path = config.sops.secrets."default/nextcloud/nixos/password".path;
    text = ''
      url="$(cat "$url_path")"
      username="$(cat "$username_path")"
      domain="''${url##*://}"
      domain="''${domain%%/*}"
      domain="''${domain##*@}"
      dir="$HOME/Nextcloud/$username@$domain"
      mkdir -p "$dir"
      nextcloudcmd -u "$username" -p "$(cat "$password_path")" "$@" "$dir" "$url"
    '';
  };
in
{
  options.kdn.services.nextcloud-client-nixos = {
    enable = lib.mkEnableOption "nextcloud-client-nixos";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      nextcloud-client
      sync
    ];
    kdn.hw.disks.persist."usr/reproducible".users.root.directories = [
      "Nextcloud"
    ];
    systemd.timers."kdn-nextcloud-nixos-sync" = {
      description = "Synchronizes /root/Nextcloud directory";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      timerConfig.OnUnitActiveSec = "15m";
    };
    systemd.paths."kdn-nextcloud-nixos-sync" = {
      description = "Synchronizes /root/Nextcloud directory";
      wantedBy = [ "multi-user.target" ];
      pathConfig.PathChanged = "/root/Nextcloud";
      pathConfig.TriggerLimitIntervalSec = "10s";
      pathConfig.TriggerLimitBurst = 1;
    };
    systemd.services."kdn-nextcloud-nixos-sync" = {
      description = "Synchronizes /root/Nextcloud directory";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      environment.HOME = "/root";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.escapeShellArgs [
          (lib.getExe sync)
          "--non-interactive"
        ];
      };
    };
  };
}
