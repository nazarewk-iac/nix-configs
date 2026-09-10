# The `mcp/snoop` slot, as a den aspect. It ports `modules/slots/mcp/snoop/default.nix`.
#
# The slot stays in place and keeps working. This file is the parallel den implementation.
#
# It puts `mcpsnoop` in front of the gateway, as a transparent JSON-RPC proxy. Open a second
# terminal, run `mcpsnoop`, and read every frame live. See ../../../docs/mcpsnoop.md.
#
# The whole mechanism is one `kdn.mcp.commandOverlays` entry. The overlay takes the command the
# `mcp` aspect built and returns a script that runs the inspector in front of it, so neither aspect
# holds a copy of the other's command.
#
# ## Two differences from the slot
#
# 1. **No `enable` option.** The slot defaults `kdn.mcp.snoop.enable = true`, which breaks this
#    repository's own side-effect-free rule. Inclusion is the switch here.
# 2. **The package comes from a plain `callPackage`.** The slot reads `pkgs.kdn.mcpsnoop`, so a
#    consumer must add this repository's overlay first. A relative path needs no overlay, and it
#    stays inside the tree the evaluation already reads.
#
# `includes` names the parent aspect, so an entity includes this aspect alone and gets the gateway
# too. den dedupes the diamond — see ./mcp.nix.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** A target module below takes `config`, `lib` and `pkgs` only.
{ kdn, ... }:
{
  kdn.mcp-snoop.includes = [ kdn.mcp ];

  kdn.mcp-snoop.devenv =
    { lib, pkgs, ... }:
    let
      mcpsnoop = pkgs.callPackage ../../../packages/mcpsnoop { };
    in
    {
      kdn.mcp.commandOverlays = [
        (
          prevCmd:
          toString (
            pkgs.writeShellScript "mcp-gateway-snoop-wrapper" ''
              exec ${lib.getExe mcpsnoop} -- ${prevCmd}
            ''
          )
        )
      ];

      packages = [ mcpsnoop ];

      enterTest = ''
        echo "• mcp-snoop: the inspector binary is on PATH" >&2
        command -v mcpsnoop >/dev/null
      '';
    };
}
