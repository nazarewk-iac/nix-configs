{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.development.llm.online;
in {
  options.kdn.development.llm.online = {
    enable = lib.mkEnableOption "tools for working with online LLMs";
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      gpt-cli
      # haskellPackages.clod # TODO: broken due to hydra failures for xxhash-ffi https://github.com/NixOS/nixpkgs/commit/1909d9ae71b83762523d03c8e06d73575ba02356
    ];
    kdn.apps.claude-code = {
      enable = true;
      package.original = pkgs.claude-code;
      dirs.cache = [];
      dirs.config = [];
      dirs.data = ["/.claude"];
      dirs.disposable = [];
      dirs.reproducible = [];
      dirs.state = [];
      files.config = ["/.claude.json"];
    };
  };
}
