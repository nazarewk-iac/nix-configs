{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.nix;

  checkNixStoreSymlinks = pkgs.writeShellApplication {
    name = "check-nix-store-symlinks";
    runtimeInputs = [ pkgs.git ];
    text = builtins.readFile ./check-nix-store-symlinks.sh;
  };
in
{
  options.kdn.nix = {
    enable = lib.mkEnableOption "nix development tooling in devenv";
  };

  config = lib.mkIf cfg.enable {
    claude.code.enable = true;

    packages = with pkgs; [
      nil
      nixd
      nixfmt
    ];

    git-hooks.hooks.check-nix-store-symlinks = {
      enable = true;
      name = "check-nix-store-symlinks";
      description = "Reject commits that include symlinks into /nix/store (managed by devenv/NixOS/HM)";
      entry = lib.getExe checkNixStoreSymlinks;
      stages = [
        "pre-commit"
        "pre-push"
      ];
      pass_filenames = false;
      always_run = true;
    };

    files.".claude/skills/flake-update/SKILL.md".source = ./SKILL.md;
    files.".claude/skills/flake-patches/SKILL.md".source = ./flake-patches-SKILL.md;

    scripts.hello.exec = ''
      echo "hello from nix-configs devenv"
    '';
  };
}
