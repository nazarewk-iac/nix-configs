{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.llm.online;
in
{
  options.kdn.development.llm.online = {
    enable = lib.mkEnableOption "tools for working with online LLMs";
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable {
        kdn.env.packages = with pkgs; [
          gpt-cli
          # haskellPackages.clod # TODO: broken due to hydra failures for xxhash-ffi https://github.com/NixOS/nixpkgs/commit/1909d9ae71b83762523d03c8e06d73575ba02356
        ];
        kdn.apps.claude-code = {
          enable = true;
          package.original = pkgs.claude-code;
          dirs.cache = [ ];
          dirs.config = [ ];
          dirs.data = [ "/.claude" ];
          dirs.disposable = [ ];
          dirs.reproducible = [ ];
          dirs.state = [ ];
          files.config = [ "/.claude.json" ];
        };
      }
    ))
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable {
        home-manager.sharedModules = [ { kdn.development.llm.online.enable = true; } ];
      }
    ))
  ];
}
