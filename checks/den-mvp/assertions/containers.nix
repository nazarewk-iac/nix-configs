# Tier-1 assertions for the container-store default of the `virt-containers` aspect.
#
# Every assertion is `{ name; expected; actual; }`, and `mkEvalCheck` compares the two at evaluation
# time. Nothing here builds a system and nothing activates.
#
# ## What this file guards
#
# The aspect renders `~/.config/containers/storage.conf` and the drop-in that decides the merge.
# c/storage merges every `*.conf` file of every `storage.conf.d` directory on the search path in
# **file-name order**, and the last file to set a key wins. The directory establishes no
# precedence: a user drop-in named `00-aaa.conf` loses to `/etc/containers/storage.conf.d/
# 00-nixos.conf`, and `99-user.conf` wins. A podman 6.1.4 measurement on 2026-11-14 found these
# ways to get it wrong, and an assertion below covers each:
#
#   1. **An empty file.** The engine then takes `graphroot` and `runroot` from
#      `/etc/containers/storage.conf.d/`, which names the root-only `/var/lib/containers/storage`,
#      and every rootless command fails with `permission denied`.
#   2. **A `graphroot` written with `~`.** The engine expands `$HOME` and `$XDG_RUNTIME_DIR` in a
#      path and expands no `~`, so `~/x` becomes a directory relative to the working directory.
#   3. **A drop-in that sorts at or before `00-`.** The file name decides the winner.
#   4. **A root Home Manager profile.** `sudo podman` reads `/etc/containers/`; a per-user file in
#      root's profile redirects the privileged engine, and `runroot` collapses to `/containers`
#      at the filesystem root because `sudo` sets no `XDG_RUNTIME_DIR`.
#
# ## The subject
#
# The `homeManager` target of the aspect is Linux-gated: it writes the five container files only on
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
    username: modules:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
      modules = modules ++ [
        {
          home.username = username;
          home.homeDirectory = "/home/${username}";
          home.stateVersion = "26.11";
        }
      ];
    };

  aspects = denLib.imports {
    class = "homeManager";
    aspects = [ "virt-containers" ];
  };

  home = (linuxHomeConfiguration "den" aspects).config;

  # The same aspect under a root profile. Every container file must be absent there.
  rootHome = (linuxHomeConfiguration "root" aspects).config;

  settings = home.kdn.virtualisation.containers.storage.settings.storage;

  rendered = builtins.readFile home.xdg.configFile."containers/storage.conf".source;
  # The user drop-in is the layer that actually wins. c/storage merges all drop-in files in
  # file-name order, last writer wins per key. Read it from the same evaluated home config.
  dropin = builtins.readFile home.xdg.configFile."containers/storage.conf.d/99-user.conf".source;

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
      name = "the user drop-in (the winning layer) names the expanded per-user store";
      expected = {
        graphroot = true;
        runroot = true;
        driver = true;
        noSystemStore = true;
      };
      actual = {
        graphroot = lib.hasInfix ''graphroot = "$HOME/.local/share/containers/storage"'' dropin;
        runroot = lib.hasInfix ''runroot = "$XDG_RUNTIME_DIR/containers"'' dropin;
        driver = lib.hasInfix ''driver = "overlay"'' dropin;
        noSystemStore = !(lib.hasInfix "/var/lib/containers" dropin);
      };
    }
    {
      name = "a root home profile renders no container file, so sudo podman keeps the system store";
      expected = [ ];
      actual = builtins.filter (lib.hasPrefix "containers/") (builtins.attrNames rootHome.xdg.configFile);
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
            (linuxHomeConfiguration "den" (
              aspects
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
