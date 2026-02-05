{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.helix-editor;
  appCfg = config.kdn.apps."helix";
in {
  options.kdn.programs.helix-editor = {
    enable = lib.mkEnableOption "Helix Editor configuration";
  };
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.apps."helix" = {
          enable = true;
          package.install = false;
          dirs.cache = ["helix"];
          dirs.config = ["helix"];
          dirs.data = [];
          dirs.disposable = [];
          dirs.reproducible = [];
          dirs.state = [];
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
        };
        programs.helix.defaultEditor = true;
        programs.vim.defaultEditor = false;
        stylix.targets.helix.enable = false;
        # nixpkgs.overlays = [kdn.inputs.helix-editor.overlays.default];
      }
    ]
  );
}
