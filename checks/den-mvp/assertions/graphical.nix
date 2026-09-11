# Tier-1 assertions for the shared graphical switch of batch 11.
#
# `../../../modules/den/common/graphical.nix` declares one option, `kdn.graphical`. Four landed
# aspects read it as the default of their own switch. This file proves the two end states.
#
# ## The subjects
#
# | Subject | Class | What it states |
# |---|---|---|
# | `plain` | `nixos` | the four aspects, no consumer opinion at all |
# | `desktop` | `nixos` | the same four aspects plus `kdn.graphical = true` |
#
# Two `bareNixos` evaluations of four aspects. Each one reads option values only and forces no
# `drvPath`, so this area stays the cheapest one after `harness-split`.
# `den-eval-instantiate` already forces every (aspect, class) pair.
#
# ## Why `dev-k8s.lens.install` sits in this list
#
# The four switches do not share one name. Three are named `graphical`; the fourth is
# `kdn.dev-k8s.lens.install`. Each name stays as the landed batch chose it. The shared default is
# the only thing they now have in common.
#
# ## No coverage row
#
# This file ports no aspect, so `instantiatedBy` stays empty. A row must name a registry aspect, and
# `common/graphical.nix` is a shared option file. `modules/den/lib.nix` names no `common/` file at
# all.
{
  denLib,
  harness,
  ...
}:
let
  inherit (harness) bareNixos;

  graphicalAspects = [
    "dev-k8s"
    "hw-audio"
    "hw-qmk"
    "hw-yubikey"
  ];

  nixosModules = denLib.imports {
    class = "nixos";
    aspects = graphicalAspects;
  };

  plainSystem = bareNixos nixosModules;
  plain = plainSystem.config;

  desktop = (bareNixos (nixosModules ++ [ { kdn.graphical = true; } ])).config;

  # The four aspect switches, read from one subject. One key set, so both sides of a comparison hold
  # the same order.
  switchesOf = c: {
    "dev-k8s.lens.install" = c.kdn.dev-k8s.lens.install;
    "hw.audio.graphical" = c.kdn.hw.audio.graphical;
    "hw.qmk.graphical" = c.kdn.hw.qmk.graphical;
    "hw.yubikey.graphical" = c.kdn.hw.yubikey.graphical;
  };
in
{
  instantiatedBy = { };

  assertions = [
    {
      name = "the shared switch is declared once and it defaults to false";
      expected = {
        declared = true;
        type = "bool";
        default = false;
        value = false;
      };
      actual = {
        declared = plainSystem.options.kdn ? graphical;
        type = plainSystem.options.kdn.graphical.type.name;
        default = plainSystem.options.kdn.graphical.default;
        value = plain.kdn.graphical;
      };
    }
    {
      name = "a consumer that states nothing leaves every graphical extra off";
      expected = {
        "dev-k8s.lens.install" = false;
        "hw.audio.graphical" = false;
        "hw.qmk.graphical" = false;
        "hw.yubikey.graphical" = false;
      };
      actual = switchesOf plain;
    }
    {
      name = "kdn.graphical = true flips all four aspect switches";
      expected = {
        "dev-k8s.lens.install" = true;
        "hw.audio.graphical" = true;
        "hw.qmk.graphical" = true;
        "hw.yubikey.graphical" = true;
      };
      actual = switchesOf desktop;
    }
  ];
}
