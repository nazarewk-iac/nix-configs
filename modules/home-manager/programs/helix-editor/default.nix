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
        programs.helix.settings.theme = "darcula-solid";
        programs.helix.settings.editor.soft-wrap.enable = true;
        programs.helix.settings.editor.insert-final-newline = true;
        programs.helix.settings.editor.trim-final-newlines = true;
        programs.helix.settings.editor.trim-trailing-whitespace = true;
        programs.helix.settings.editor.auto-save.focus-lost = true;
        programs.helix.settings.editor.auto-save.after-delay.enable = true;
        programs.helix.settings.editor.auto-save.after-delay.timeout = 300;
        programs.helix.defaultEditor = true;
        programs.vim.defaultEditor = false;
        stylix.targets.helix.enable = false;
        # nixpkgs.overlays = [kdn.inputs.helix-editor.overlays.default];
      }
    ]
  );
}
