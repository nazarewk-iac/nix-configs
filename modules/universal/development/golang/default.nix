{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.development.golang;
in {
  options.kdn.development.golang = {
    enable = lib.mkEnableOption "golang development";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (kdnConfig.util.ifHMParent {
      home-manager.sharedModules = [{kdn.development.golang.enable = true;}];
    })
    (kdnConfig.util.ifHM (lib.mkMerge [
      {kdn.development.jetbrains.go.enable = config.kdn.desktop.enable;}
      {
        #systemd.user.tmpfiles.settings.kdn-golang.rules."${config.xdg.cacheHome}/go".d = {};
        #systemd.user.tmpfiles.settings.kdn-golang.rules."%h/go".L.argument = "${config.xdg.cacheHome}/go";
        systemd.user.tmpfiles.rules = [
          "d ${config.xdg.cacheHome}/go - - - -"
          "L %h/go - - - - ${config.xdg.cacheHome}/go"
        ];

        kdn.disks.persist."usr/cache".directories = [
          ".cache/go"
        ];
      }
      {
        # see https://github.com/helix-editor/helix/wiki/Language-Server-Configurations#go
        programs.helix.extraPackages = with pkgs; [
          gopls
          delve
          gofumpt # stricter gofmt
          gotools # goimports
          golangci-lint-langserver # linting
        ];
        programs.helix.languages.language-server.gopls.config = {
          gofumpt = true;
          "ui.documentation.hoverKind" = "SynopsisDocumentation";
        };
      }
    ]))
    (kdnConfig.util.ifNotHMParent {
      kdn.env.packages = with pkgs; [
        (lib.meta.hiPrio go)
        #gccgo
        delve
        golangci-lint
        gofumpt

        gotools
        cobra-cli
        goreleaser

        (pkgs.writeShellApplication {
          name = "go-toolchain-install";
          runtimeInputs = with pkgs; [
            go
            jq
          ];
          text = ''
            set -xeEuo pipefail
            version="$1"
            shift 1
            go install "golang.org/dl/go$version@latest"
            ~/.cache/go/bin/"go$version" download
            "go$version" env --json | jq -S "$@"
          '';
        })
      ];
    })
  ]);
}
