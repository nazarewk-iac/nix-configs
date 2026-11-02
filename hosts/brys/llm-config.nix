# The whole local-LLM serving configuration for brys, in one place.
#
# Two consumers, and they differ in exactly **one** value: the boot `profile`.
#
#   * `desktop` — the main brys host (hosts/brys/default.nix), a desktop that also serves
#     the fleet;
#   * `appliance` — the `llms` boot entry (hosts/brys/llms-frontier.nix, booted as
#     `specialisation.llms`), a dedicated box with isolcpus/ARC kernel tuning.
#
# The two profiles now serve the SAME models; they remain separate boot entries for the
# appliance-only kernel tuning. Everything else is identical on purpose: one set of models,
# one alias map, one build and one cache policy.
#
# The served model set and the per-profile served context are part of the data
# (`data/llm.nix` -> `servers.brys.profiles`), not knobs here. If a second difference ever
# appears, add it as a named argument **and say why in this header** — a bare extra argument
# is how this file becomes a settings soup.
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
