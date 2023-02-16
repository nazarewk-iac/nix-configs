{ lib, pkgs, config, system, ... }:
with lib;
let
  cfg = config.kdn.development.db.mysql;
in
{
  options.kdn.development.db.mysql = {
    enable = lib.mkEnableOption "MySQL development";
  };

  config = mkIf cfg.enable {

    environment.systemPackages = with pkgs; [
      mysql80
      # TODO: requires v8_8_x, but it's currently broken https://github.com/NixOS/nixpkgs/blob/68f8b25beaec793642edd731e45594498955acc9/pkgs/development/libraries/v8/8_x.nix#L170-L170
      #mysql-shell
      # mysql-workbench # errors out with: No rule to make target '/nix/store/rzinfpv5fmr3iq2rn5mijjwphsx5d9w4-mysql-8.0.31/lib/mysql/libmysqlclient.so', needed by 'libgdal.so.32.3.6.0'.  Stop.
    ];
  };
}
