# A build-only nix-darwin host. It never activates. See ../README.md.
{
  den,
  inputs,
  kdn,
  ...
}:
{
  den.hosts.aarch64-darwin.host-darwin = {
    # den's default `instantiate` for the `darwin` class is `inputs.darwin.lib.darwinSystem`, and
    # this repo names that input `nix-darwin`. `system = null` also keeps the evaluation pure:
    # nix-darwin's own default for `system` reads `builtins.currentSystem`. den itself passes
    # `{ modules }` and nothing else.
    instantiate = args: inputs.nix-darwin.lib.darwinSystem (args // { system = null; });

    # `homeManager` must be explicit. den's default is `[ "user" ]` alone, so a user that omits it
    # gets no home-manager generation and every aspect's `homeManager` half goes nowhere.
    # `../users/default.nix` holds the `dev` aspect.
    users.dev.classes = [
      "user"
      "homeManager"
    ];
  };

  # den finds a host's aspect by the host name, so this attribute name is the wiring.
  den.aspects.host-darwin.includes = [
    kdn.rosetta-builder

    # `gh` emits into the `devenv` target only. It proves a devenv aspect reaches the shell that
    # `den.policies.host-to-devenv` derives from this host, and it changes no darwin option.
    kdn.gh

    # The four-target aspect. This inclusion delivers its `darwin` and `devenv` halves. Its
    # `homeManager` half arrives through the `dev` user, because den partitions by scope — see
    # ../users/default.nix.
    kdn.devenv-cli

    # `zellij` is `devenv`-only, like `gh`. Both routes must give one identical Claude Code
    # allowlist, and ../tests.nix asserts that equality.
    kdn.zellij

    # The Homebrew concern. The aspect names no tap, no cask and no formula, so the three
    # placeholders below are the whole set. ../tests.nix asserts each list exactly, and that
    # equality proves the aspect adds nothing of its own.
    kdn.homebrew

    # The two aspects of batch 1. They give this host the `darwin` class subject for both: the
    # `nix.conf` opinion, and the 18 remote-builder declarations. `hosts-den/orr/` is the `nixos`
    # class subject for the same pair.
    kdn.nix-config
    kdn.nix-remote-builder
  ];

  # The `devenv` half of this host aspect. `den.policies.host-to-devenv` derives one shell from the
  # list above, and the `zellij` aspect installs its skill file into that shell. The option defaults
  # to false, so an adopter opts in; this host asks for the file, and its shell keeps the file it had.
  den.aspects.host-darwin.devenv = {
    kdn.zellij.installAgentRules = true;
  };

  den.aspects.host-darwin.darwin = {
    # `system.primaryUser` now comes from `den.batteries.primary-user` on the `dev` user aspect.
    # Two definitions would conflict.

    # nix-darwin asserts this value. `7` is what it names for a new installation on 2026-09-10.
    system.stateVersion = 7;

    # The one restore of this batch. `kdn.nix-config` imports `../common/host-name.nix`, and that
    # option defaults to `networking.hostName`. nix-darwin types that option `nullOr (strMatching …)`
    # and defaults it to **null**, so `kdn.hostName` would be the empty string on this host. The
    # NixOS side needs no such line: ../host-nixos/default.nix already sets it.
    # Measured on 2026-09-11: without this line `kdn.hostName` is ""; with it the value is
    # "host-darwin".
    networking.hostName = "host-darwin";

    # The Homebrew placeholders. Each name is fictional, so no activation ever finds it.
    kdn.homebrew.taps = [ "example-org/example-tap" ];
    kdn.homebrew.casks = [ "example-cask" ];
    kdn.homebrew.brews = [ "example-brew" ];

    # The restore. The aspect defaults `cleanup` to nix-darwin's safe `"none"`, so that a stranger
    # keeps a cask they installed by hand. This repository manages Homebrew from Nix alone, and
    # `modules/universal/default.nix` sets `"zap"` for every darwin host. This line keeps the den
    # route on the same value, and it also proves the `lib.mkDefault` in the aspect: a plain value
    # here overrides the aspect with no `lib.mkForce`.
    kdn.homebrew.onActivation.cleanup = "zap";
  };
}
