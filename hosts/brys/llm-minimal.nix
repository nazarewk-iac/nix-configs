# Minimal DeepSeek-only specialisation for brys.
#
# BOOT-SELECTED ONLY, NEVER ACTIVATED via switch-to-configuration. This is a
# clean top-level (`inheritParentConfig = false`) boot entry that serves the
# DeepSeek V4 Flash frontier model with as little RAM/CPU/service overhead as
# possible, so the model has the whole machine. The default "brys" boot entry is
# unaffected. The common appliance body lives in ./llm-appliance.nix; the small
# models are spun out to the sibling ./llm-small.nix entry.
{
  lib,
  pkgs,
  kdnConfig,
  ...
}:
let
  # Shared local-LLM serving config, also used by the main brys profile
  # (hosts/brys/default.nix, see ./llm.nix). The specialisation gets the whole
  # box and runs the full 320K DeepSeek context as one shared KV pool across 4
  # slots (unified KV). `cpuPinned = false` though the boot params still add
  # isolcpus=1-15: the `--cpu-range`/`--cpu-strict` flags stall prefill on
  # llama-cpp 0.4.0, so the scheduler places the threads itself (see ./llm.nix).
  # `withSmall = false` keeps DS4 alone on the box.
  llm = import ./llm.nix {
    inherit lib pkgs kdnConfig;
    contextSize = 327680;
    cpuPinned = false;
    withFrontier = true;
    withSmall = false;
  };
in
import ./llm-appliance.nix {
  inherit
    lib
    pkgs
    kdnConfig
    llm
    ;
  tag = "llm-minimal";
  banner = ''
    \e[1;33m============================================================\e[0m
    \e[1;31m  Minimal LLM-ONLY instance  (brys / llm-minimal)\e[0m
    \e[1;33m============================================================\e[0m
    Booted into the isolated DeepSeek-serving topology. Freeing the whole
    machine for local LLM inference; no desktop, no workstation services.

    DeepSeek V4 Flash @ 320K ctx, DSpark draft, reasoning off, 4 shared slots.
    \e[1;33m============================================================\e[0m
    Login with your usual kdn/SSH credentials. Use the normal host to do
    anything else.
  '';
}
