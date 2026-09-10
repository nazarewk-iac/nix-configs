# A build-only nix-darwin host. It never activates. See ../README.md.
{ den, inputs, ... }:
{
  den.hosts.aarch64-darwin.host-darwin = {
    # den's default `instantiate` for the `darwin` class is `inputs.darwin.lib.darwinSystem`, and
    # this repo names that input `nix-darwin`. `system = null` also keeps the evaluation pure:
    # nix-darwin's own default for `system` reads `builtins.currentSystem`. den itself passes
    # `{ modules }` and nothing else.
    instantiate = args: inputs.nix-darwin.lib.darwinSystem (args // { system = null; });
  };

  # den finds a host's aspect by the host name, so this attribute name is the wiring.
  den.aspects.host-darwin.includes = [
    den.aspects.rosetta-builder

    # `gh` emits into the `devenv` target only. It proves a devenv aspect reaches the shell that
    # `den.policies.host-to-devenv` derives from this host, and it changes no darwin option.
    den.aspects.gh
  ];

  den.aspects.host-darwin.darwin = {
    system.primaryUser = "den";
    # nix-darwin asserts this value. `7` is what it names for a new installation on 2026-09-10.
    system.stateVersion = 7;
  };
}
