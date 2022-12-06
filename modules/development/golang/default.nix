{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.development.golang;
in
{
  options.kdn.development.golang = {
    enable = lib.mkEnableOption "golang development";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      go_1_19
      gccgo
      delve
      goreleaser
      golangci-lint # for netbird
    ];
    home-manager.sharedModules = [
      ({ config, lib, ... }:
        let
          cmd = ''
            for ide in ${config.xdg.dataHome}/Jetbrains/* ; do
              mkdir -p "$ide/go/lib/dlv/linux"
              ln -sf "${pkgs.delve}/bin/dlv" "$ide/go/lib/dlv/linux/dlv"
            done
          '';
        in
        {
          programs.bash.profileExtra = cmd;
          programs.zsh.profileExtra = cmd;
        })
    ];
  };
}
