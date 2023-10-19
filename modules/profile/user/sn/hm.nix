{ config, pkgs, lib, ... }@arguments:
let
  cfg = config.kdn.profile.user.sn;
  systemUser = cfg.nixosConfig;
in
{
  options.kdn.profile.user.sn = {
    enable = lib.mkEnableOption "sn account setup";

    nixosConfig = lib.mkOption { default = { }; };
  };
  config = lib.mkIf (cfg != { }) (lib.mkMerge [
    {
      home.stateVersion = "23.11";

      home.packages = with pkgs; [
        vlc
      ];

      # pam-u2f expects a single line of configuration per user in format `username:entry1:entry2:entry3:...`
      # `pamu2fcfg` generates lines of format `username:entry`
      # For ease of use you can append those pamu2fcfg to ./yubico/u2f_keys.parts directly,
      #  then below code will take care of stripping comments and folding it into a single line per user
      xdg.configFile."Yubico/u2f_keys".text =
        let
          stripComments = lib.filter (line: (builtins.match "\w*" line) != [ ] && (builtins.match "\w*#.*" line) != [ ]);
          groupByUsername = input: builtins.mapAttrs (name: map (lib.removePrefix "${name}:")) (lib.groupBy (e: lib.head (lib.splitString ":" e)) input);
          toOutputLines = lib.mapAttrsToList (name: values: (builtins.concatStringsSep ":" (lib.concatLists [ [ name ] values ])));

          foldParts = path: lib.trivial.pipe path [
            builtins.readFile
            (lib.splitString "\n")
            stripComments
            groupByUsername
            (lib.attrsets.filterAttrs (n: v: n == config.home.username))
            toOutputLines
            (builtins.concatStringsSep "\n")
          ];
        in
        foldParts ./yubico/u2f_keys.parts;

      xdg.mime.enable = true;
    }
  ]);
}
