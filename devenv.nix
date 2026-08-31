{
  inputs,
  pkgs,
  lib,
  ...
}:
let
  extraDevenvFiles = lib.pipe (builtins.readDir ./.) [
    builtins.attrNames
    (builtins.filter (
      name:
      name != "devenv.nix"
      && name != "devenv.local.nix"
      && lib.hasPrefix "devenv." name
      && lib.hasSuffix ".nix" name
    ))
    (map (name: ./. + "/${name}"))
  ];
in
{
  # argc drives the subcommand dispatch in the zellij-llm/kdn-slug bash packages; keep it on
  # PATH so the standalone scripts run and get tested in the shell.
  packages = [ pkgs.argc ];

  imports = [
    (inputs.nix-configs.mkSlots {
      inherit pkgs;
      imports = extraDevenvFiles;

      kdn.isSourceRepo = true;

      kdn.nix.enable = true;
      kdn.jj.enable = true;
      kdn.zellij.enable = true;
      kdn.gh.enable = true;

      kdn.mcp = {
        enable = true;
        basic-memory.enable = true;
      };

      # In-devenv opencode capability: generates a benign opencode.jsonc and
      # puts `opencode` + `opencode-kdn` on PATH on every host. The brys-specific
      # model/proxy wiring lives in the hostname-gated profile below.
      kdn.opencode.enable = true;
    }).config.devenv
  ];

  # brys-specific devenv slot instance: feeds the rich provider/model config and
  # the model proxies (requesty :9526, local llama-swap :9533). Auto-activated
  # only on a host whose hostname is "brys"; every other host keeps the benign
  # global kdn.opencode skeleton above.
  profiles.hostname."brys".module = import ./hosts/brys/devenv.nix;

  overlays = [ inputs.nix-configs.overlays.packages ];
}
