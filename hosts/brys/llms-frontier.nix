# The single boot entry, `specialisation.llms` (see hosts/brys/default.nix). It serves the whole
# fleet from one llama-swap process: the grunt and surveyed sets, which co-reside on the R9700 by
# tier. It used to carry the frontier models (DeepSeek V4 Flash, dropped as too slow, then
# Qwen3.8-Flash-Next, retired 2026-11-13 on electricity grounds); with no frontier left the
# appliance entry remains for its kernel tuning (`isolcpus`) and ARC settings, which the desktop
# profile does not apply.
#
# BOOT-SELECTED ONLY, NEVER ACTIVATED via switch-to-configuration. This is a
# clean top-level (`inheritParentConfig = false`) boot entry that serves the
# grunt and surveyed sets through the primary router, which co-reside on the
# R9700 by tier. The default "brys" entry serves the same models without the
# isolcpus/ARC tuning. The common appliance body lives in ./llm-appliance.nix.
{
  lib,
  pkgs,
  kdnConfig,
  ...
}:
let
  # The whole local-LLM serving config, shared with the main brys profile (./llm-config.nix). The
  # appliance boots the `appliance` profile; it now serves the same models as `desktop`, but keeps
  # this boot entry for the isolcpus/ARC kernel tuning in ./llm-appliance.nix.
  llm = import ./llm-config.nix {
    inherit lib pkgs kdnConfig;
    profile = "appliance";
  };
in
import ./llm-appliance.nix {
  inherit
    lib
    pkgs
    kdnConfig
    llm
    ;
  tag = "llms-frontier";
  banner = ''
    \e[1;33m============================================================\e[0m
    \e[1;31m  APPLIANCE instance  (brys / llms-frontier)\e[0m
    \e[1;33m============================================================\e[0m
    The local LLM fleet on the primary router. Grunt + surveyed sets
    co-reside on the R9700 by tier.
    \e[1;33m============================================================\e[0m
    Login with your usual kdn/SSH credentials. Use the normal host to do
    anything else.
  '';
  # The runtime graphics/ICD config is owned by llm.nix (`llm.gpu`) so the
  # dedicated and combined Qwen specialisations cannot drift.
  extraConfig = llm.gpu;
}
