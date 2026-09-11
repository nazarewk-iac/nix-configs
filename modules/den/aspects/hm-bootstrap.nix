# The Home Manager bootstrap of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation of
# the **portable part** of `modules/universal/_hm-bootstrap.nix`.
#
# ## Class list: `homeManager` alone
#
# The whole old file is Home Manager plumbing.
#
# ## What it does
#
# It turns the XDG base directory support on, and it makes Home Manager only **suggest** a systemd
# user service restart instead of a real restart.
#
# ## What the port drops, and why
#
# The old file holds five things. Two port, and three do not:
#
# | Old line | Verdict |
# |---|---|
# | `xdg.enable = true` | ported. The Home Manager default is `false`, so the line is real. |
# | `systemd.user.startServices = "suggest"` | ported. The Home Manager default is `true`, so the line is real. |
# | `home.enableNixpkgsReleaseCheck = true` | dropped. The Home Manager default is already `true`, so the line is a no-op. |
# | the `nixpkgs.config` and `nixpkgs.overlays` bridge | dropped. See below. |
# | the three generated `config.nix` files | dropped. See below. |
#
# ### The nixpkgs bridge
#
# The old file reads `osConfig` or `darwinConfig`, and it falls back to `config.kdn.nixConfig.nixpkgs`.
# Neither source survives the port:
#
# - `kdn.nixConfig` is gone by design. ./nix-config.nix:26-28 states that it is an intermediate
#   attribute set of the old tree, and it has no den counterpart.
# - `osConfig` reaches a **nested** Home Manager only. An aspect must work in a standalone Home
#   Manager too, so it cannot depend on a parent.
#
# The den route for a nested user is one line on the host, and it needs no aspect:
#
#     home-manager.useGlobalPkgs = true;
#
# That gives the child the parent's whole package set, overlays and config together. It replaces the
# whole bridge.
#
# ### The three generated files
#
# The old file writes `xdg.configFile."nix/nix.nix"`, `xdg.configFile."nixpkgs/config.nix"` and
# `home.file.".nixpkgs/config.nix"`, all from the same `kdn.nixConfig` value. That option is gone,
# so the files have no content to hold. A consumer that wants a `~/.config/nixpkgs/config.nix` writes
# it from its own value.
#
# ## Priorities
#
# Both ported lines use `lib.mkDefault`, and the old file uses a plain value. `mkDefault` is 1000 and
# an option's own `default` is 1500, so `mkDefault` still wins over Home Manager. A consumer may then
# override with a plain value, which the old shape did not allow.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ user, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. This aspect declares no option at all.
# 3. **No custom module argument.** The target module below takes `lib` only.
{ ... }:
{
  kdn.hm-bootstrap.homeManager =
    { lib, ... }:
    {
      xdg.enable = lib.mkDefault true;

      # "suggest" prints the restart command instead of running it. A real restart during activation
      # can stop the session that runs the activation.
      systemd.user.startServices = lib.mkDefault "suggest";
    };
}
