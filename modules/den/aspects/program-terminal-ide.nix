# `kdn.programs.terminal-ide`, as a den aspect.
# It ports `modules/universal/programs/terminal-ide/default.nix`.
#
# Home Manager only. The old module writes the packages and the app entry from a shared branch, but
# every consumer of it is a user evaluation.
{ kdn, ... }:
{
  kdn.program-terminal-ide.includes = [ kdn.apps ];

  kdn.program-terminal-ide.homeManager =
    {
      config,
      lib,
      options,
      pkgs,
      ...
    }:
    let
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      config = lib.mkMerge [
        {
          home.packages = filterPackages (
            with pkgs;
            [
              scooter # terminal search and replace
            ]
          );

          kdn.apps."helix" = {
            enable = true;
            # `programs.helix` installs the package.
            package.install = false;
            dirs.cache = [ "helix" ];
            dirs.config = [ "helix" ];
          };

          programs.helix.enable = true;
          programs.helix.package = config.kdn.apps."helix".package.final;

          programs.helix.settings = {
            theme = "darcula-solid";
            editor = {
              soft-wrap.enable = true;
              default-yank-register = "+";
              insert-final-newline = true;
              trim-final-newlines = true;
              trim-trailing-whitespace = true;
              auto-save.focus-lost = true;
              auto-save.after-delay.enable = true;
              auto-save.after-delay.timeout = 300;
              indent-guides.render = true;
              indent-guides.character = "╎";
              end-of-line-diagnostics = "hint";
              inline-diagnostics.cursor-line = "hint";
              file-picker.hidden = false;
            };
            keys.normal = {
              x = "select_line_below";
              X = "select_line_above";
            };
          };

          # A `lib.mkDefault`, so a consumer names another editor with a plain assignment.
          programs.helix.defaultEditor = lib.mkDefault true;
          # This line stays plain on purpose. The headless base module writes
          # `programs.vim.defaultEditor = lib.mkDefault true`. A second `lib.mkDefault` here holds the
          # other value at the same priority 1000, so the evaluation stops with a conflict.
          programs.vim.defaultEditor = false;
        }

        # stylix is optional in a den evaluation, so the write tests the option tree first.
        (lib.optionalAttrs (options ? stylix) { stylix.targets.helix.enable = false; })
      ];
    };
}
