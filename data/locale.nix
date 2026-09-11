/*
  Personal locale data for `kdn.locale`.

  This file is a module, not a data attribute set. It assigns options that
  `modules/universal/locale/default.nix` declares, so that module holds no time zone, no
  national keyboard layout and no national locale.

  `modules/universal/default.nix` imports this file behind `builtins.pathExists`. An adopter
  deletes the file and the four options fall back to a neutral English value.

  This file needs no context guard. The module forwards the whole `cfg` into Home Manager with
  `lib.mkDefault` at `locale/default.nix:83`, which is priority 1000. The assignments below sit
  at priority 100, so they win in every context and no merge conflict is possible.

  `kdn.locale.primary` and `kdn.locale.time` stay out of this file on purpose.
  `modules/universal/profile/user/{sn,bn}` assign both at priority 100, so a second
  priority-100 definition would stop the evaluation.
*/
{ ... }:
{
  config.kdn.locale.timezone = "Europe/Warsaw";
  config.kdn.locale.xkbLayout = "pl";
  config.kdn.locale.extra = [
    # see https://sourceware.org/git/?p=glibc.git;a=blob;f=localedata/SUPPORTED
    "C.UTF-8/UTF-8"
    "en_US.UTF-8/UTF-8"
    "en_GB.UTF-8/UTF-8"
    "pl_PL.UTF-8/UTF-8"
    "pl_PL/ISO-8859-2"
  ];
  config.kdn.locale.shorts = [
    "en-GB"
    "en-US"
    "en"
    "pl-PL"
    "pl"
  ];
}
