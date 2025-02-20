{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.kdn.services.iperf3;
in {
  options.kdn.services.iperf3 = {
    enable = lib.mkOption {
      type = with lib.types; bool;
      default = true;
    };
    server.enable = lib.mkOption {
      type = with lib.types; bool;
      default = cfg.enable;
    };
    client.enable = lib.mkOption {
      type = with lib.types; bool;
      default = cfg.enable;
    };
  };

  config = lib.mkIf (config.kdn.security.secrets.allowed) (lib.mkMerge [
    (lib.mkIf (cfg.server.enable) {
      services.iperf3.enable = true;
      services.iperf3.openFirewall = true;
      systemd.services.iperf3.after = ["kdn-secrets.target"];
      systemd.services.iperf3.requires = ["kdn-secrets.target"];
      systemd.services.iperf3.serviceConfig = {
        LoadCredential = [
          "private.pem:${config.kdn.security.secrets.sops.secrets.default.networking.iperf-server.rsa.priv.path}"
          "users.csv:${config.kdn.security.secrets.sops.secrets.default.networking.iperf-server."users.csv".path}"
        ];
      };
      #systemd.services.iperf3.serviceConfig.WorkingDirectory = "$CREDENTIALS_DIRECTORY";
      services.iperf3.rsaPrivateKey = null;
      services.iperf3.authorizedUsersFile = null;
      services.iperf3.extraFlags = builtins.concatLists [
        ["--rsa-private-key-path" "%d/private.pem"]
        ["--authorized-users-path" "%d/users.csv"]
      ];
    })
    (lib.mkIf (cfg.client.enable) {
      environment.systemPackages = [
        (pkgs.writeShellApplication {
          name = "kdn-iperf3-client";
          runtimeInputs = [config.services.iperf3.package];
          text = let
            defaultUsername = lib.pipe config.kdn.security.secrets.sops.secrets.default.networking.iperf-server.users [
              builtins.attrNames
              builtins.head
            ];
          in ''
            : "''${IPERF3_USERNAME:="${defaultUsername}"}"

            args=(
              --username "$IPERF3_USERNAME"
              --rsa-public-key-path "/run/configs/networking/iperf-server/rsa/pub"
            )
            IPERF3_PASSWORD="$(cat "/run/configs/networking/iperf-server/users/$IPERF3_USERNAME")" \
              iperf3 "''${args[@]}" --client "$@"
          '';
        })
      ];
    })
  ]);
}
