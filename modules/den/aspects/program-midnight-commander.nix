# `kdn.programs.midnight-commander`, as a den aspect.
# It ports `modules/universal/programs/midnight-commander/default.nix`.
#
# `package.install = false` keeps the app out of `home.packages`, because `programs.mc` installs the
# same package itself. The aspect reads back `kdn.apps.mc.package.final` for that write.
{ kdn, ... }:
{
  kdn.program-midnight-commander.includes = [ kdn.apps ];

  kdn.program-midnight-commander.homeManager =
    { config, ... }:
    {
      config = {
        kdn.apps."mc" = {
          enable = true;
          package.install = false;
          dirs.cache = [ "mc" ];
          dirs.config = [ "mc" ];
        };
        programs.mc.enable = true;
        programs.mc.package = config.kdn.apps."mc".package.final;
      };
    };
}
