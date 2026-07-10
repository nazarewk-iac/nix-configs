{
  lib,
  pkgs,
  config,
  inputs,
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

    # Read-only/evaluation-only commands — safe to always allow, no side effects. `nix run`
    # itself is deliberately NOT allowed as a bare wildcard (it executes arbitrary flake apps);
    # only this repo's own idempotent formatter is allow-listed by exact invocation.
    claude.code.permissions.rules.Bash.allow = [
      "nix build *"
      "nix eval *"
      "nix flake metadata*"
      "nix flake show *"
      "nix search *"
      "nix path-info *"
      "nix log *"
      "nix why-depends *"
      "devenv build *"
      "devenv eval *"
      "nix run .#kdn-nix-fmt -- *"
    ];

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
      ".claude/skills/flake-update/SKILL.md".source =
        "${inputs.nix-configs}/.agents/skills/flake-update/SKILL.md";
      ".claude/skills/flake-patches/SKILL.md".source =
        "${inputs.nix-configs}/.agents/skills/flake-patches/SKILL.md";
      ".claude/rules/okf-format.md".source = "${inputs.nix-configs}/.agents/rules/okf-format.md";
    };

    scripts.hello.exec = ''
      echo "hello from nix-configs devenv"
    '';

    kdn.mcp.programs.nixos.enable = true;
    kdn.mcp.extraBackends.devenv = {
      command = "devenv mcp";
      description = "devenv — search nixpkgs packages and devenv options";
      env.DEVENV_ROOT = toString inputs.nix-configs;
    };
  };
}
