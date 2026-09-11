# Adopter template — a devenv shell that consumes modules/slots.
#
# Read docs/slots-for-adopters.md first. This file is the minimum that works.
#
# THE API is `inputs.nix-configs.mkSlots` (flake.nix:309). You pass `pkgs` plus your
# own slot settings as one attrset, and you read back one target:
#   .config.devenv  .config.nixos  .config.darwin  .config.home  .config.users
# Everything you pass other than `pkgs` becomes a module, so `imports` works too.
# You do NOT pass your own `inputs`: mkSlots threads this repository's inputs in
# itself, with `nix-configs` bound to the repository. So a slot always finds the
# files it reads.
#
# HARD REQUIREMENT: the packages overlay.
#   Seven slots reference `pkgs.kdn.*` — jj, llm, llm/proxy, mcp/basic-memory,
#   mcp/snoop, ssh-access, zellij. They do not evaluate without the overlay.
#   Use `overlays.packages`, NOT `overlays.default`. The default one also composes
#   NUR, microvm, angrr, nix-darwin, devenv and oh-my-pi, which you do not want.
#   devenv's `overlays` option needs devenv 1.4.2 or newer.
#
# WHAT A SLOT WRITES INTO YOUR REPO: several slots install agent rules and skills
#   under `.claude/` as symlinks into /nix/store. `kdn.jj` installs the author's
#   jj-only mandate, which forbids nearly all raw `git` use. `kdn.isSourceRepo` is
#   `false` by default, and `false` means "install those files". Leave it `false`
#   only when you want them. Enable a slot only when you want its policy.
{
  inputs,
  pkgs,
  ...
}:
{
  imports = [
    (inputs.nix-configs.mkSlots {
      inherit pkgs;

      # One small slot as a worked example.
      kdn.zellij.enable = true;

      # `kdn.mcp.snoop.enable` and `kdn.mcp.pretty-print.enable` both default to false, so this
      # template needs no line for either. Set one to true only when you want that child.
    }).config.devenv
  ];

  overlays = [ inputs.nix-configs.overlays.packages ];

  enterShell = ''
    echo "adopter template: the devenv target rendered and the kdn overlay is present"
  '';
}
