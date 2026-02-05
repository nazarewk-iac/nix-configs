{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.programs.terminal-ide;
  appCfg = config.kdn.apps."helix";
in {
  options.kdn.programs.terminal-ide = {
    enable = lib.mkEnableOption "Terminal IDE setup using Helix configuration";
    helix.enable = lib.mkEnableoption "Helix Editor" // {default = true;};
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (kdnConfig.util.ifHMParent {home-manager.sharedModules = [{kdn.programs.terminal-ide = lib.mkDefault cfg;}];})
    (kdnConfig.util.ifNotHMParent {
      kdn.env.packages = with pkgs; [
        scooter # terminal search & replace
      ];

      kdn.apps."helix" = {
        enable = true;
        dirs.cache = ["helix"];
        dirs.config = ["helix"];
        dirs.data = [];
        dirs.disposable = [];
        dirs.reproducible = [];
        dirs.state = [];
      };
    })
    (kdnConfig.util.ifHM {
      kdn.apps."helix" = {
        package.install = false;
      };
      programs.helix.enable = true;
      programs.helix.package = appCfg.package.final;

      programs.helix.settings = {
        theme = "darcula-solid";
        editor = {
          soft-wrap.enable = true;
          default-yank-register = "+";
          insert-final-newline = true;
          trim-final-newlines = true;
          trim-trailing-whitespace = true;
          auto-save.focus-lost = true;
          auto-save.after-delay.enable = true;
          auto-save.after-delay.timeout = 300;
          indent-guides.render = true;
          indent-guides.character = "╎";
          end-of-line-diagnostics = "hint";
          inline-diagnostics.cursor-line = "hint";
        };
        keys.normal = {
          x = "select_line_below";
          X = "select_line_above";
        };
      };
      programs.helix.defaultEditor = true;
      programs.vim.defaultEditor = false;
      stylix.targets.helix.enable = false;
      # nixpkgs.overlays = [kdn.inputs.helix-editor.overlays.default];
    })
  ]);
}
