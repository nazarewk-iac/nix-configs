{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.toolset.unix;
in
{
  options.kdn.toolset.unix = {
    enable = lib.mkEnableOption "linux utils";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      kdn.toolset.tracing.enable = lib.mkDefault true;
    })
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable {
        kdn.env.packages =
          (with pkgs; [
            sysstat
            iotop

            btop
            htop
            lurk # strace alternative
            pstree
            strace
            perf # moved from kernelPackages
            (lib.meta.setPrio 10 util-linux)

            (pkgs.writeShellApplication {
              name = "get-proc-env";
              runtimeInputs = with pkgs; [ jq ];
              text = ''
                jq -R 'split("\u0000") | map(split("=") | {key: .[0], value: (.[1:] | join("="))}) | from_entries' "/proc/$1/environ"
              '';
            })
          ])
          ++ (lib.pipe pkgs.unixtools [
            (
              s:
              builtins.removeAttrs s [
                "procps"
                "util-linux"
                "nettools"
                "recurseForDerivations"
              ]
            )
            builtins.attrValues
          ]);
      }
    ))
  ];
}
