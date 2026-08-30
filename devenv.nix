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

      # Requesty DSML proxy instance, reachable at 127.0.0.1:9532. The local
      # model proxy (127.0.0.1:9533) is run by the opencode slot itself.
      kdn.llm.proxy.enable = true;
      kdn.llm.proxy.instances.requesty = {
        enable = true;
        upstreamUrl = "https://router.requesty.ai";
        port = 9526;
        forwardClientAuth = true;
      };

      # In-devenv opencode: generates opencode.jsonc with the requesty/local
      # providers and runs opencode-kdn on PATH. Pointed at the local brys model
      # via the local DSML proxy.
      kdn.opencode.enable = true;
    }).config.devenv
  ];

  overlays = [ inputs.nix-configs.overlays.packages ];
}
