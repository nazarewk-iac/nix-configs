# Tier-1 assertions for the container-store default of the `virt-containers` aspect.
#
# Every assertion is `{ name; expected; actual; }`, and `mkEvalCheck` compares the two at evaluation
# time. Nothing here builds a system and nothing activates.
#
# ## What this file guards
#
# The aspect renders `~/.config/containers/storage.conf`. A rootless engine reads that file before
# the system drop-ins, so the file must name a store the calling user owns. A podman 6.1.4
# measurement on 2026-11-14 found two ways to get it wrong, and an assertion below covers each:
#
#   1. **An empty file.** The engine then falls through to `/etc/containers/storage.conf.d/`, which
#      names the root-only `/var/lib/containers/storage`, and every rootless command fails with
#      `permission denied`.
#   2. **A `graphroot` written with `~`.** The engine expands `$HOME` and `$XDG_RUNTIME_DIR` in a
#      path and expands no `~`, so `~/x` becomes a directory relative to the working directory.
#
# ## The subject
#
# The `homeManager` target of the aspect is Linux-gated: it writes the four container files only on
# a Linux platform. `harness.bareHomeConfiguration` pins Darwin and renders nothing, so this file
# states its own Linux home consumer, the same shape `./desktop-leaves.nix` uses.
{
  lib,
  inputs,
  denLib,
  ...
}:
let
  linuxHomeConfiguration =
    modules:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
      modules = modules ++ [
        {
          home.username = "den";
          home.homeDirectory = "/home/den";
          home.stateVersion = "26.11";
        }
      ];
    };

  home =
    (linuxHomeConfiguration (
      denLib.imports {
        class = "homeManager";
        aspects = [ "virt-containers" ];
      }
    )).config;

  settings = home.kdn.virtualisation.containers.storage.settings.storage;

  rendered = builtins.readFile home.xdg.configFile."containers/storage.conf".source;

  # The two path values must name a directory the calling user owns, never the system store.
  userOwned = value: lib.hasPrefix "$HOME/" value || lib.hasPrefix "$XDG_RUNTIME_DIR/" value;
in
{
  assertions = [
    {
      name = "the aspect defaults a per-user container store";
      expected = {
        driver = "overlay";
        graphrootIsUserOwned = true;
        runrootIsUserOwned = true;
      };
      actual = {
        inherit (settings) driver;
        graphrootIsUserOwned = userOwned settings.graphroot;
        runrootIsUserOwned = userOwned settings.runroot;
      };
    }
    {
      name = "the user store lives under the home directory and the runtime directory";
      expected = {
        graphroot = "$HOME/.local/share/containers/storage";
        runroot = "$XDG_RUNTIME_DIR/containers";
      };
      actual = {
        inherit (settings) graphroot runroot;
      };
    }
    {
      name = "the rendered storage.conf names no system store";
      expected = {
        graphroot = false;
        runroot = false;
      };
      actual = {
        graphroot = lib.hasInfix "/var/lib/containers" rendered;
        runroot = lib.hasInfix "/run/containers/storage" rendered;
      };
    }
    {
      name = "the rendered storage.conf writes the two expanded paths";
      expected = {
        graphroot = true;
        runroot = true;
        driver = true;
      };
      actual = {
        graphroot = lib.hasInfix ''graphroot = "$HOME/.local/share/containers/storage"'' rendered;
        runroot = lib.hasInfix ''runroot = "$XDG_RUNTIME_DIR/containers"'' rendered;
        driver = lib.hasInfix ''driver = "overlay"'' rendered;
      };
    }
    {
      name = "a consumer replaces the default with its own store";
      expected = {
        graphroot = "$HOME/other/graph";
        runroot = "$XDG_RUNTIME_DIR/other/run";
      };
      actual =
        let
          replaced =
            (linuxHomeConfiguration (
              denLib.imports {
                class = "homeManager";
                aspects = [ "virt-containers" ];
              }
              ++ [
                {
                  kdn.virtualisation.containers.storage.settings.storage = {
                    graphroot = "$HOME/other/graph";
                    runroot = "$XDG_RUNTIME_DIR/other/run";
                  };
                }
              ]
            )).config;
        in
        replaced.kdn.virtualisation.containers.storage.settings.storage;
    }
  ];

  instantiatedBy = {
    virt-containers = "den-eval-containers (linux home, the storage.conf subject)";
  };
}
