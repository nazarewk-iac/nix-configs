# `kdn.programs.chrome`, as a den aspect. It ports `modules/universal/programs/chrome/default.nix`.
#
# `google-chrome` is unfree. `../common/filter-packages.nix` inside the `apps` aspect drops a
# package whose `outPath` does not evaluate, so a subject with no `allowUnfree` still evaluates and
# simply gets no browser.
{ kdn, ... }:
{
  kdn.program-chrome.includes = [ kdn.apps ];

  kdn.program-chrome.homeManager =
    { pkgs, ... }:
    {
      config.kdn.apps.chrome = {
        enable = true;
        package.original = pkgs.google-chrome;
        dirs.config = [ "google-chrome" ];
      };
    };
}
