{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.toolset.unix;
in {
  options.kdn.toolset.unix = {
    enable = lib.mkEnableOption "linux utils";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages =
      (with pkgs; [
        btop
        htop
        lurk # strace alternative
        pstree
        strace
        (lib.meta.setPrio 10 util-linux)

        (pkgs.writeShellApplication {
          name = "get-proc-env";
          runtimeInputs = with pkgs; [jq];
          text = ''
            jq -R 'split("\u0000") | map(split("=") | {key: .[0], value: (.[1:] | join("="))}) | from_entries' "/proc/$1/environ"
          '';
        })
      ])
      ++ (lib.pipe pkgs.unixtools [
        (s:
          builtins.removeAttrs s [
            "procps"
            "util-linux"
            "nettools"
            "recurseForDerivations"
          ])
        builtins.attrValues
      ]);
  };
}
