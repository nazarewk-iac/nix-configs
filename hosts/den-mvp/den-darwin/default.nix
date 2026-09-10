# A build-only den host for the `darwin` class.
#
# It mirrors a real Darwin workstation at the **slot** level, so a den module can be compared
# against the slot it replaces. See ../README.md for the compare commands and for the reason this
# directory is invisible to `flake.hostConfigurations`.
#
# This host never activates. It evaluates and it builds. It carries no personal data, and no
# machine uses its name.
{ den, inputs, ... }:
{
  den.hosts.aarch64-darwin.den-darwin = {
    # den's default `instantiate` for the `darwin` class is `inputs.darwin.lib.darwinSystem`, and
    # this repo names that input `nix-darwin`. `system = null` also keeps the evaluation pure:
    # nix-darwin's own default for `system` reads `builtins.currentSystem`.
    instantiate = args: inputs.nix-darwin.lib.darwinSystem (args // { system = null; });
  };

  # den finds a host's aspect by the host name, so this attribute name is the wiring.
  den.aspects.den-darwin.includes = [
    den.aspects.rosetta-builder
  ];

  # The minimum that nix-darwin itself needs. This is not personal data, and it is not a profile.
  # Without `system.primaryUser` the users module fails with `cannot coerce null to a string`,
  # because it puts that value into an assertion message.
  den.aspects.den-darwin.darwin = {
    system.primaryUser = "den";
    # nix-darwin asserts this value. `7` is what it names for a new installation on 2026-09-10.
    system.stateVersion = 7;
  };
}
