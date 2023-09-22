{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.development.data;
in
{
  options.kdn.development.data = {
    enable = lib.mkEnableOption "tools for working with data";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      miller
      yq
      jq
      yj

      kdn.data-converters

      gojq
      jiq # interactive JQ
      jc # convert commands output to JSON
      gron # JSON to/from list of path-value assignments
      (pkgs.writeShellApplication {
        name = "ungron";
        text = ''${gron}/bin/gron --urgron "$@"'';
      })

      cue
      conftest

      gnused

      # Convert HCL <-> JSON
      python3Packages.bc-python-hcl2
      hcl2json
    ];
  };
}
