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
    enable = lib.mkEnableOption "unix utils";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      kdn.toolset.tracing.enable = lib.mkDefault true;
      kdn.env.packages = with pkgs; [
        btop
        htop
        pstree
        (lib.meta.setPrio 10 util-linux)
        pv
      ];
    })
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable {
        kdn.env.packages =
          (with pkgs; [
            sysstat
            iotop

            lurk # strace alternative
            pstree
            strace
            perf # moved from kernelPackages

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
