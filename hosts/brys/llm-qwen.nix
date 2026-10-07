# Qwen-only specialisation for brys.
#
# BOOT-SELECTED ONLY, NEVER ACTIVATED via switch-to-configuration. This is a
# clean top-level (`inheritParentConfig = false`) boot entry that serves the
# Qwen3.8-Flash-Next frontier model with as little RAM/CPU/service overhead as
# possible, so the model has the whole machine. The default "brys" boot entry is
# unaffected. The common appliance body lives in ./llm-appliance.nix.
{
  lib,
  pkgs,
  kdnConfig,
  ...
}:
let
  # Shared local-LLM serving config, also used by the main brys profile
  # (hosts/brys/default.nix, see ./llm.nix). The specialisation gets the whole
  # box and runs Qwen3.8-Flash-Next with 128K context, F16 KV, single slot
  # (the QSA cache is patched for one slot only). `withFrontier = false` and
  # `withSmall = false` keep Qwen alone on the box.
  llm = import ./llm.nix {
    inherit lib pkgs kdnConfig;
    withFrontier = false;
    withSmall = false;
    withQwen = true;
    qwenContextSize = 1048576;
    # Upstream v0.6.0: it carries the long-context QSA indexer memory/mask
    # fixes the Unsloth fork lacks. MTP stays on (the v0.6.0 build has it too).
    llamaPackage = pkgs.kdn.llama-cpp-v0_6_0;
    qwenMtp = true;
    qwenSpecDraftNMax = 5;
    # YaRN x4: 256K native -> 1M. F16 KV (~24 GiB) is tight; fall back to
    # q8_0 KV if the load OOMs.
    qwenRopeScaling = "yarn";
    qwenRopeScale = 4.0;
    qwenRopeFreqBase = 10000000;
    qwenYarnOrigCtx = 262144;
  };
in
import ./llm-appliance.nix {
  inherit
    lib
    pkgs
    kdnConfig
    llm
    ;
  tag = "llm-qwen";
  banner = ''
    \e[1;33m============================================================\e[0m
    \e[1;31m  Qwen-only instance  (brys / llm-qwen)\e[0m
    \e[1;33m============================================================\e[0m
    Booted into the isolated Qwen-serving topology. Freeing the whole
    machine for local LLM inference; no desktop, no workstation services.

    Qwen3.8-Flash-Next @ 1M ctx (YaRN x4), F16 KV, single slot, UD-IQ4_XS.
    \e[1;33m============================================================\e[0m
    Login with your usual kdn/SSH credentials. Use the normal host to do
    anything else.
  '';
}
