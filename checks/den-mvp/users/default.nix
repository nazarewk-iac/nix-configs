# The one den user both build-only hosts share. It never logs in. See ../README.md.
#
# A den user is what makes the `homeManager` class reachable. den's home-manager battery imports
# `inputs.home-manager.<class>Modules.home-manager` into the host by itself, and it forwards each
# user's `homeManager` config to `home-manager.users.<userName>`. So a host needs no home-manager
# import of its own — it needs a user whose `classes` list holds `homeManager`.
#
# **`classes` defaults to `[ "user" ]`, with no `homeManager`.** den declares that default at
# `<den>/nix/lib/entities/host.nix:157`. A user that omits `homeManager` silently gets no
# home-manager generation, and the `homeManager` half of every aspect it includes goes nowhere. So
# each host states the list in full.
#
# The user is named `dev`, not `den`. `den.aspects.den` would read as den's own namespace at every
# call site.
{ den, ... }:
{
  den.aspects.dev = {
    includes = [
      # `users.users.<name>` on both OS classes, plus `home.username` and `home.homeDirectory` on
      # the home-manager side. It derives the home directory from the host system suffix.
      den.batteries.define-user

      # `darwin.system.primaryUser = "dev"`. nix-darwin asserts that option, and this battery is
      # why `host-darwin` no longer sets it by hand.
      den.batteries.primary-user

      # The four-target aspect. This inclusion is what delivers its `homeManager` half.
      #
      # The host aspect includes the same aspect for its `nixos`/`darwin` half. That is not a
      # duplicate: den partitions by scope, so a **host**-scope aspect's `homeManager` half never
      # reaches `home-manager.users.<user>`. `modules/den/README.md` records the trap. Two
      # inclusions at two scopes is the shape that works, and `den-eval-devenv-cli` asserts both
      # halves land.
      den.aspects.devenv-cli
    ];

    homeManager = {
      # home-manager asserts this option. `26.11` is the newest value the pinned home-manager
      # accepts (`<home-manager>/modules/misc/version.nix`).
      home.stateVersion = "26.11";

      # The aspect fills in a hook for each shell and enables none — a slot must not choose a
      # user's login shell. So the **test user** enables all three, and tier 2 then has a real
      # `.bashrc`, `.zshrc` and `config.fish` to grep.
      programs.bash.enable = true;
      programs.zsh.enable = true;
      programs.fish.enable = true;
    };
  };
}
