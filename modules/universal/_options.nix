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

    nixConfig = lib.mkOption {
      readOnly = true;
      default = import ./nix.nix;
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
