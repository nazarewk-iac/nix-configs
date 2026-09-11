# The `development/golang` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It gives one user the Go tools: the compiler at high priority, `delve`, two linters, `gofumpt`,
# `gotools`, `cobra-cli`, `goreleaser` and one wrapper script that installs a second toolchain. It
# also moves the Go cache under the XDG cache directory and links `~/go` to it.
#
# It is a Home Manager opinion only. The old module puts every package behind `ifNotHMParent` and
# the rest behind `ifHM`, so a host writes nothing of its own.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`kdn.env.packages` goes.** The target writes `home.packages` through
#    ../common/filter-packages.nix. Design B.
# 3. **The old `kdn.development.jetbrains.go.enable` write goes.** That line reads
#    `kdn.desktop.enable`, and den declares no `enable` option at either end. The `dev-jetbrains`
#    aspect declares `kdn.dev-jetbrains.go.use` instead, and a machine states it.
# 4. **The persist paths become a read-only option.** The old module writes
#    `kdn.disks.persist."usr/cache".directories`, which another area declares. This aspect
#    publishes `kdn.dev-persist.dev-golang` and the consumer wires it. See the `apps` aspect for
#    the same pattern.
# 5. **The tmpfiles rules get a Linux guard.** Home Manager asserts the platform for
#    `systemd.user.tmpfiles`, and `pkgs.systemd` does not build on darwin. The old module has no
#    guard, so a darwin user with Go breaks there. Linux behaviour does not change.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.dev-golang.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      filterPackages = import ../common/filter-packages.nix { inherit lib; };

      goToolchainInstall = pkgs.writeShellApplication {
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
      };
    in
    {
      options.kdn.dev-persist.dev-golang = lib.mkOption {
        readOnly = true;
        type = lib.types.attrsOf (lib.types.attrsOf (lib.types.listOf lib.types.str));
        default = {
          "usr/cache".directories = [ ".cache/go" ];
        };
        description = ''
          The paths this aspect keeps across a wipe, in the shape the persist area takes.

          This aspect writes no persist option of its own. A consumer collects every
          `kdn.dev-persist.*` value and wires it in one line.
        '';
      };

      config = lib.mkMerge [
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

          home.packages = filterPackages (
            [ (lib.meta.hiPrio pkgs.go) ]
            ++ (with pkgs; [
              delve
              golangci-lint
              gofumpt

              gotools
              cobra-cli
              goreleaser
            ])
            ++ [ goToolchainInstall ]
          );
        }
        (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
          systemd.user.tmpfiles.rules = [
            "d ${config.xdg.cacheHome}/go - - - -"
            "L %h/go - - - - ${config.xdg.cacheHome}/go"
          ];
        })
      ];
    };
}
