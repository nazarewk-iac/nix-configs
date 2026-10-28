# The stats collector for a llama-swap host. It is a plain shell script wrapped by
# `writeShellApplication`, so `shellcheck` runs over it at build time: a collector that silently
# stops writing is worse than none, so the build must reject an obvious bug.
#
# It reads only documented endpoints, needs no database, and holds no state beyond a cursor file
# in its own state directory.
{
  pkgs,
  lib,
  ...
}:
pkgs.writeShellApplication {
  name = "llm-stats";
  runtimeInputs = with pkgs; [
    curl
    jq
    coreutils
    findutils
    gnused
  ];
  text = builtins.readFile ./llm-stats.sh;
  meta = {
    description = "Collect llama-swap per-request performance into JSONL and a Prometheus textfile";
    license = lib.licenses.mit;
    mainProgram = "llm-stats";
  };
}
