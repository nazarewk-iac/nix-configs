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

    # The default hook uses just `prek` by name, which fails outside devenv shell.
    # Use the absolute store path so Claude Code can find it regardless of PATH.
    claude.code.hooks.git-hooks-run.command =
      ''cd "$DEVENV_ROOT" && ${lib.getExe config.git-hooks.package} run'';

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

    files = lib.mkIf (!config.kdn.isSourceRepo) {
      ".claude/skills/flake-update/SKILL.md".source = ./SKILL.md;
      ".claude/skills/flake-patches/SKILL.md".source = ./flake-patches-SKILL.md;
    };

    scripts.hello.exec = ''
      echo "hello from nix-configs devenv"
    '';
  };
}
