{
  inputs,
  pkgs,
  lib,
  ...
}:
let
  # Machine-local slot settings. This is the ONLY extra file that reaches `mkSlots`.
  # Git does not track it (see `.gitignore`), so no commit chain can add or remove it.
  # Copy a `devenv.slots.local.*.example.nix` file, then re-enter the shell.
  #
  # A path literal like this one resolves against the real working directory, so an
  # untracked file is visible. Only `inputs.nix-configs` (`git+file:.`) is git-filtered.
  #
  # This directory is NOT scanned for other `devenv.*.nix` files any more. A tracked file
  # belongs to one commit chain. When the working copy moves to a chain without that file,
  # jj deletes the file, and every setting in it turns off with no warning. `kdn.jj.fork`
  # is one of these settings: the fork revset aliases and the push checks then disappear,
  # and the generated jj repo config shrinks to a stub. The failure is silent.
  #
  # Do NOT put slot settings in devenv's own `devenv.local.nix` either. devenv loads that
  # file into the devenv module set, where the `kdn.*` slot options do not exist.
  localSlots = lib.optional (builtins.pathExists ./devenv.slots.local.nix) ./devenv.slots.local.nix;
in
{
  # argc drives the subcommand dispatch in the zellij-llm/kdn-slug bash packages; keep it on
  # PATH so the standalone scripts run and get tested in the shell.
  packages = [ pkgs.argc ];

  imports = [
    (inputs.nix-configs.mkSlots {
      inherit pkgs;
      imports = localSlots;

      kdn.isSourceRepo = true;

      kdn.nix.enable = true;
      kdn.jj.enable = true;
      # These two values belong to this repository, not to the slot. The slot defaults are now
      # neutral (`origin` and an empty list), so these two lines keep the behaviour unchanged.
      kdn.jj.upstream.remote = "kdn";
      kdn.jj.alwaysBlockedMessagePatterns = [ "scratchpad" ];
      kdn.zellij.enable = true;
      kdn.gh.enable = true;

      # This repository authors the agent instruction files, so it asks for every one of them.
      # Each `installAgentRules` option defaults to false: an adopter states its own work mandate,
      # and no slot pushes this repository's mandate into another tree. The five lines below keep
      # the behaviour that the old `default = true` gave.
      #
      # They belong here, and not in `devenv.slots.local.nix`. That file holds machine-local
      # identity only, git does not track it, and a missing file would drop these settings with no
      # warning. `kdn.jj.fork.installAgentRules` stays inert until `kdn.jj.fork.enable` is true.
      kdn.nix.installAgentRules = true;
      kdn.jj.installAgentRules = true;
      kdn.jj.fork.installAgentRules = true;
      kdn.zellij.installAgentRules = true;
      kdn.mcp.basic-memory.installAgentRules = true;

      kdn.mcp = {
        enable = true;
        basic-memory.enable = true;
        # Both children now default to false, so a consumer opts in. This repository wants both, and
        # these two lines keep the behaviour that the old `default = true` gave.
        snoop.enable = true;
        pretty-print.enable = true;
      };

      # In-devenv opencode capability: generates a benign opencode.jsonc and
      # puts an `opencode` wrapper (key/svc auth) on PATH on every host. The
      # brys-specific model/proxy wiring lives in the hostname-gated profile
      # below.
      kdn.opencode.enable = true;
    }).config.devenv
  ];

  # brys-specific devenv slot instance: feeds the rich provider/model config and
  # the model proxies (requesty :9526, local llama-swap :9533). Auto-activated
  # only on a host whose hostname is "brys"; every other host keeps the benign
  # global kdn.opencode skeleton above.
  profiles.hostname."brys".module = import ./hosts/brys/devenv.nix;

  # oams-specific devenv slot instance: opencode pointed at the LAN llama-server
  # on brys over HTTPS (shared /run/configs/llms cert + API key). Auto-activated
  # only on a host whose hostname is "oams".
  profiles.hostname."oams".module = import ./hosts/oams/devenv.nix;

  overlays = [ inputs.nix-configs.overlays.packages ];
}
