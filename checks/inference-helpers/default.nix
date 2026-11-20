# The inference runtime end to end, with one 1 MB model and no GPU.
#
# It starts real processes — our binary as the manager and as both llama-swap entries, llama-swap as
# the front door, and llama-server on `stories260K` as every engine and as the companion — and drives
# the five behaviours the design promises: the first `qfn` starts the engine, a second `qfn` does not
# switch it, the companion refuses without a reserve, the same request with `kdn_switch_to` switches
# and serves, and unloading the companion returns the engine to the whole-card profile.
#
# Why it exists above the Go tests: those use `httptest` and a shell-script engine. This one exercises
# the parts that only exist once the pieces are separate processes — llama-swap's `cmd` contract and
# `${PORT}`, the deployment config file, the manager's child supervision, and the gate owning its
# model. It needs no card, and the tiny model keeps it under a few hundred MiB.
{
  pkgs,
  lib,
  ...
}:
let
  helpers = pkgs.callPackage ../../packages/kdn-inference-helpers { };
  # The same 1 MB model the Pi harness checks use, so no extra fetch and no GPU.
  fixtures = import ../pi-harness/fixtures.nix { inherit pkgs; };
in
pkgs.runCommand "check-inference-helpers-integration"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      curl
      llama-cpp
      python3
    ];
  }
  ''
    export MODEL=${fixtures.stories260K}
    export LLAMA=${pkgs.llama-cpp}/bin/llama-server
    export HELPERS=${helpers}/bin/kdn-inference-helpers
    export WORK=$TMPDIR
    bash ${./run.sh}
    touch $out
  ''
