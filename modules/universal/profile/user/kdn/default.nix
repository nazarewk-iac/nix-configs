{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.kdn.profile.user.kdn;
in {
  options.kdn.profile.user.kdn = {
    enable = lib.mkEnableOption "enable my user profiles";
    ssh = lib.mkOption {
      readOnly = true;
      default = let
        authorizedKeysPath = ./.ssh/authorized_keys;
        authorizedKeysList = lib.trivial.pipe authorizedKeysPath [
          builtins.readFile
          (lib.strings.splitString "\n")
        ];
      in {
        inherit authorizedKeysList authorizedKeysPath;

        authorizedKeysText = builtins.concatStringsSep "\n" authorizedKeysList;
      };
    };
    gpg.publicKeys = lib.mkOption {
      type = with lib.types; path;
      readOnly = true;
      default = pkgs.writeText "kdn-gpg-pubkeys.txt" (builtins.readFile ./gpg-pubkeys.txt);
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.env.packages = with pkgs; [
        (yt-dlp.overrideAttrs (final: {
          version = "2025.09.26";
          src = pkgs.fetchFromGitHub {
            owner = "yt-dlp";
            repo = "yt-dlp";
            tag = final.version;
            hash = "sha256-/uzs87Vw+aDNfIJVLOx3C8RyZvWLqjggmnjrOvUX1Eg=";
          };
        }))
      ];
    }
  ]);
}
