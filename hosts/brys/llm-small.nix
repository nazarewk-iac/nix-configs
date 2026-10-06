# Minimal small-model-only specialisation for brys.
#
# BOOT-SELECTED ONLY, NEVER ACTIVATED via switch-to-configuration. This is a
# clean top-level (`inheritParentConfig = false`) boot entry that serves only the
# small-model router (`kdn.llm.local.routers.small`, :39704) with no DeepSeek
# frontier model, so the small set has the whole machine. It is the counterpart
# of ./llm-minimal.nix (DS4 alone): the two are mutually exclusive, because DS4
# needs the whole box. The common appliance body lives in ./llm-appliance.nix.
{
  lib,
  pkgs,
  kdnConfig,
  ...
}:
let
  # Shared local-LLM serving config (see ./llm.nix). No frontier model and no
  # contextSize tuning: the small set carries its own per-model `perf.contextSize`
  # in ./llm-routers.nix. `cpuPinned = false` for the same llama-cpp 0.4.0
  # prefill-stall reason as the frontier entry.
  llm = import ./llm.nix {
    inherit lib pkgs kdnConfig;
    cpuPinned = false;
    withFrontier = false;
    withSmall = true;
  };
in
import ./llm-appliance.nix {
  inherit
    lib
    pkgs
    kdnConfig
    llm
    ;
  tag = "llm-small";
  banner = ''
    \e[1;33m============================================================\e[0m
    \e[1;31m  Minimal SMALL-MODEL instance  (brys / llm-small)\e[0m
    \e[1;33m============================================================\e[0m
    Booted into the small-model-only topology. The DeepSeek V4 Flash frontier
    is NOT served here; the freely-swapping small set owns the whole machine.

    qwen3-30b-a3b (fast), qwen3-next-80b (balanced), qwen3-coder-next,
    qwen3-235b, gpt-oss-120b, phi-4.
    \e[1;33m============================================================\e[0m
    Login with your usual kdn/SSH credentials. Use the normal host to do
    anything else.
  '';
}
