# `kdn.programs.ydotool`, as a den aspect. It ports `modules/universal/programs/ydotool/default.nix`.
#
# NixOS only. The old module hard-codes `pkgs.ydotool` inside `ExecStart` while it installs
# `cfg.package`, so an overridden package never reached the service. This aspect uses `cfg.package` in
# both places. Mark for owner review.
{ ... }:
{
  kdn.program-ydotool.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.programs.ydotool;
    in
    {
      options.kdn.programs.ydotool.package = lib.mkPackageOption pkgs "ydotool" { };

      config = {
        environment.systemPackages = [ cfg.package ];
        environment.sessionVariables.YDOTOOL_SOCKET = "/run/ydotool.sock";

        hardware.uinput.enable = true;

        systemd.packages = [ cfg.package ];

        # A fixed gid keeps the group stable across a rebuild, so a persisted file keeps its owner.
        users.groups.ydotool.gid = 26598;

        systemd.services.ydotoold = {
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            ExecStart = [
              ""
              "${lib.getExe' cfg.package "ydotoold"} --socket-path=/run/ydotool.sock --socket-perm=0660"
            ];
            Group = "ydotool";
            RuntimeDirectory = "ydotool";
          };
        };
      };
    };
}
