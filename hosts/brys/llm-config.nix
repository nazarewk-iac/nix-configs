# The whole local-LLM serving configuration for brys, in one place.
#
# Two consumers, and they differ in exactly **one** value: the boot `profile`.
#
#   * the main profile (hosts/brys/default.nix) — a desktop that also serves the fleet,
#     booted with `profile = "desktop"` (DeepSeek 128K because it shares RAM with a browser);
#   * the `llms` appliance entry (hosts/brys/llms-frontier.nix, booted as
#     `specialisation.llms`) — a dedicated box, booted with `profile = "appliance"`
#     (DeepSeek 320K because it owns the box).
#
# Everything else is identical on purpose. The fleet is one set of models, one alias map,
# one build and one cache policy; a second copy of those settings is how the two consumers
# drift. The only honest difference is the profile, and the served context is part of the
# data (`data/llm.nix` -> `servers.brys.profiles`), not a knob here.
#
# If a second difference ever appears, add it as a named argument **and say why in this
# header** — a bare extra argument is how this file becomes a settings soup.
#
# See ./llm.nix for what each knob does. The measurements behind them are in
# docs/local-llms.md and hosts/brys/performance.md.
{
  lib,
  pkgs,
  kdnConfig,
  # The boot profile: `desktop` or `appliance`. It selects a profile from `data/llm.nix`,
  # which sets the served router set and the per-profile served context.
  profile,
}:
import ./llm.nix {
  inherit
    lib
    pkgs
    kdnConfig
    profile
    ;
}
