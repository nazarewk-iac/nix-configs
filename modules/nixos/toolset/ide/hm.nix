{
  lib,
  pkgs,
  config,
  kdn,
  ...
}:
let
  cfg = config.kdn.toolset.ide;
in
{
  options.kdn.toolset.ide = {
    enable = lib.mkEnableOption "IDEs utils";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        programs.helix.enable = true;
        programs.helix.settings.theme = "darcula-solid";
        programs.helix.defaultEditor = true;
        programs.helix.languages.language = [
          {
            name = "nix";
            auto-format = true;
            formatter = {
              command = lib.getExe pkgs.nixfmt;
            };
          }
        ];
        programs.vim.defaultEditor = false;
        stylix.targets.helix.enable = false;
        # nixpkgs.overlays = [kdn.inputs.helix-editor.overlays.default];
      }
      (lib.mkIf config.kdn.desktop.enable {
        kdn.development.jetbrains.enable = true;
      })
    ]
  );
}
