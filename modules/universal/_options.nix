{
  config,
  lib,
  ...
}@args:
{
  options.kdn = {
    enable = lib.mkEnableOption "basic Nix configs for kdn";

    args = lib.mkOption {
      internal = true;
      readOnly = true;
      default = args;
    };

    hostName = lib.mkOption {
      type = with lib.types; str;
    };

    /*
      The shared `nix`/`nixpkgs` settings of this tree.

      `./default.nix` copies it into `nix.settings`, `nix.extraOptions` and `nixpkgs.config`, and
      `./_hm-bootstrap.nix` copies `nixpkgs.config` into every Home Manager user. The option is no
      longer `readOnly`: `readOnly` refuses every assignment, so an adopter could not replace the
      whole set. Nothing in this tree writes it, so the change keeps today's value.

      Prefer the narrow options below (`kdn.nixpkgs.*`, `kdn.nix.substituters`) over a full
      replacement of this attribute set.
    */
    nixConfig = lib.mkOption {
      default = import ./nix.nix { inherit config lib; };
    };

    /*
      Accept the unfree licence of a package.

      A licence is a policy decision, and an adopter may want a pure-free tree. So the value is an
      option. The default is `true`, the value this repository uses today.
    */
    nixpkgs.allowUnfree = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
    };

    /*
      Packages this tree accepts although nixpkgs marks them insecure.

      The list MUST stay an option default. It must never become a literal at the assignment site.
      `nixpkgs.config.permittedInsecurePackages` has type `listOf str`, and `types.listOf`
      concatenates every definition. A literal in this tree is therefore a definition that an
      adopter can add to but never remove. An option default goes away as soon as the adopter
      writes their own list.
    */
    nixpkgs.permittedInsecurePackages = lib.mkOption {
      type = with lib.types; listOf str;
      default = [
        "litestream-0.3.13"
        "electron-28.3.3" # loqseq dependency
        "electron-27.3.11" # loqseq dependency? 2024-07-12
        "olm-3.2.16" # required for Matrix clients
      ];
      example = [ ];
    };

    /*
      The binary caches this tree trusts, in order of preference.

      A binary cache is a trust decision, and an adopter may object to every entry. So the set is
      an option. The same `types.listOf` rule as above applies: keep the entries in the default,
      never as a literal at the assignment site.

      Each entry holds the URL together with its public key. A substituter fails at run time when
      the URL has no matching key, so the two never separate.
    */
    nix.substituters = lib.mkOption {
      type =
        with lib.types;
        listOf (submodule {
          options.url = lib.mkOption {
            type = str;
            example = "https://cache.example.invalid";
          };
          options.publicKey = lib.mkOption {
            type = str;
            example = "cache.example.invalid-1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          };
        });
      default = [
        {
          url = "https://nix-community.cachix.org";
          publicKey = "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=";
        }
        {
          url = "https://nixpkgs-update.cachix.org";
          publicKey = "nixpkgs-update.cachix.org-1:6y6Z2JdoL3APdu6/+Iy8eZX2ajf09e4EE9SnxSML1W8=";
        }
        {
          url = "https://devenv.cachix.org";
          publicKey = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
        }
      ];
      example = [ ];
    };

    /*
      Register one Homebrew tap per `brew-tap--*` flake input.

      `./default.nix` scans `kdnConfig.inputs` for that prefix and writes each match to
      `nix-homebrew.taps`. A consumer of this tree inherits the taps of whoever owns the flake, and a
      developer who manages Homebrew already objects to that. So the scan is opt-in.

      The default is `false`. This repository's own darwin hosts set it to `true`, one host file at a
      time, so the evaluated tap list of each one stays exactly what it is today.

      `modules/den/aspects/homebrew.nix` is the standalone route. It carries plain `taps`, `casks` and
      `brews` lists, and it reads no flake input.
    */
    homebrew.tapsFromFlakeInputs = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
    };
  };
}
