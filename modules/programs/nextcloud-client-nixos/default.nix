{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.programs.nextcloud-client-nixos;

  sync = pkgs.writeShellApplication {
    name = "kdn-nextcloud-nixos-sync";
    runtimeInputs = with pkgs; [
      coreutils
      nextcloud-client
    ];
    runtimeEnv.url_path = config.sops.secrets."nextcloud/nixos/url".path;
    runtimeEnv.username_path = config.sops.secrets."nextcloud/nixos/username".path;
    runtimeEnv.password_path = config.sops.secrets."nextcloud/nixos/password".path;
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
  options.kdn.programs.nextcloud-client-nixos = {
    enable = lib.mkEnableOption "nextcloud-client-nixos";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      nextcloud-client
      sync
    ];
    environment.persistence."usr/reproducible".users.root.directories = [
      "Nextcloud"
    ];
    systemd.timers."kdn-nextcloud-nixos-sync" = {
      description = "Synchronizes /root/Nextcloud directory";
      wantedBy = [ "timers.target" ];
      requires = [ "network-online.target" ];
      after = [ "network-online.target" ];
      timerConfig.OnUnitActiveSec = "5m";
    };
    systemd.paths."kdn-nextcloud-nixos-sync" = {
      description = "Synchronizes /root/Nextcloud directory";
      requires = [ "network-online.target" ];
      after = [ "network-online.target" ];
      pathConfig.PathChanged = "/root/Nextcloud";
      pathConfig.TriggerLimitIntervalSec = "10s";
      pathConfig.TriggerLimitBurst = 1;
    };
    systemd.services."kdn-nextcloud-nixos-sync" = {
      description = "Synchronizes /root/Nextcloud directory";
      requires = [ "network-online.target" ];
      after = [ "network-online.target" ];
      environment.HOME = "/root";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.escapeShellArgs [
          (lib.getExe sync)
          "--non-interactive"
        ];
      };
    };
    sops.secrets."nextcloud/nixos/url" = { };
    sops.secrets."nextcloud/nixos/username" = { };
    sops.secrets."nextcloud/nixos/password" = { };
  };
}
