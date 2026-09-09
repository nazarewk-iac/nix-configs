{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.desktop.remote-server;
in
{
  options.kdn.desktop.remote-server = {
    enable = lib.mkEnableOption "remote desktop server setup";
  };

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf cfg.enable {
      # TODO: 2026-09-09: put teamviewer back when the fetch works again.
      # `pkgs.teamviewer` is a fixed-output derivation over
      # `dl.teamviewer.com/download/linux/version_15x/teamviewer_<version>_amd64.deb`.
      # It is unfree, so Hydra never builds it and no substituter holds the output.
      # The fetch is the only source, and the current network resolves `dl.teamviewer.com`
      # to 146.112.61.106, a Cisco Umbrella / OpenDNS block address that answers HTTP 403
      # for the whole domain. nixpkgs is correct: master pins the same 15.81.5 and the
      # same hash, and the vendor still serves the file with HTTP 200 through a public
      # resolver. So there is nothing to fix upstream.
      # Two real fixes, both outside this repo:
      #   1. allow `teamviewer.com` in the network's Umbrella/OpenDNS policy, or
      #   2. give the Nix builder a public resolver for that one fetch.
      # `hosts/obler` and `hosts/pryll` still set `services.teamviewer.enable` by hand, so
      # they keep the same build failure until one of those two fixes lands.
      #services.teamviewer.enable = true;
    }
  );
}
