# `kdn.programs.office`, as a den aspect. It ports `modules/universal/programs/office/default.nix`.
{ kdn, ... }:
{
  kdn.program-office.includes = [ kdn.apps ];

  kdn.program-office.homeManager =
    { pkgs, ... }:
    {
      config.kdn.apps.libreoffice = {
        enable = true;
        package.original =
          if pkgs.stdenv.hostPlatform.isDarwin then pkgs.libreoffice-bin else pkgs.libreoffice;
        dirs.config = [ "libreoffice" ];
      };
    };
}
