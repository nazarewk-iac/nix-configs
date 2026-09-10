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
  ];

  den.aspects.host-darwin.darwin = {
    # `system.primaryUser` now comes from `den.batteries.primary-user` on the `dev` user aspect.
    # Two definitions would conflict.

    # nix-darwin asserts this value. `7` is what it names for a new installation on 2026-09-10.
    system.stateVersion = 7;

    # The Homebrew placeholders. Each name is fictional, so no activation ever finds it.
    kdn.homebrew.taps = [ "example-org/example-tap" ];
    kdn.homebrew.casks = [ "example-cask" ];
    kdn.homebrew.brews = [ "example-brew" ];
  };
}
