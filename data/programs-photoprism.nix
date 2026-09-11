/*
  Personal photo source for `kdn.programs.photoprism`.

  This file is a module, not a data attribute set. It assigns an option that
  `modules/universal/programs/photoprism/default.nix` declares, so that module names no personal
  account and no personal host.

  `modules/universal/default.nix` imports this file behind `builtins.pathExists`. An adopter
  deletes the file, `originalsDevice` falls back to `null`, and the module binds no directory.

  This file needs no context guard. `programs/photoprism` runs no Home Manager forward, and only
  its `ifTypes [ "nixos" ]` branch reads the option. So a darwin host and a Home Manager user
  hold the value and write no `fileSystems` entry.
*/
{
  config,
  ...
}:
{
  config.kdn.programs.photoprism.originalsDevice =
    "${config.kdn.profile.user.kdn.homeDir}/Nextcloud/drag0nius@nc.nazarewk.pw";
}
