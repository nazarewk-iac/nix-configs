# The QMK and ZSA keyboard tools, as a den aspect. It ports the `qmk` module of the old hardware
# area.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs the QMK toolchain, the ZSA `wally-cli` flasher and two helper commands that pull a
# layout from the Oryx web configurator. On NixOS it also installs the QMK and ZSA udev rules, so a
# keyboard is writable without root.
#
# ## Class list: `nixos` and `darwin`
#
# The old module holds the package list **outside** every context guard, and only the udev block sits
# behind the `nixos` guard. So the port emits both classes. Every package in the shared list is
# available on `aarch64-darwin`, measured 2026-09-11: `keymapviz`, `qmk`, `wally-cli`, `curl` and
# `unzip` all resolve. The udev packages and `vial` are unsupported on Darwin, and both stay in the
# `nixos` target.
#
# The old module has no `ifHMParent` forward, so a Home Manager child never turned it on. The port
# emits no `homeManager` target for the same reason.
#
# ## What the port changes
#
# 1. **The desktop read becomes an own option.** The old module installs `vial` behind
#    `config.kdn.desktop.enable`. A den aspect declares no reachable `enable`, so the port declares
#    `kdn.hw.qmk.graphical` instead. A consumer that runs a desktop sets it to `true`.
#    `graphical` is declared for both classes, so a consumer sets it without a class check, but only
#    the `nixos` target acts on it, because `vial` is unsupported on Darwin.
# 2. **The two Oryx scripts move into this file.** The old module reads `./oryx-flash.sh` and
#    `./oryx-src.sh` next to itself, in the deprecated module tree. An aspect reads no file of that
#    tree, and this tree keeps one flat `.nix` file per aspect with no sibling data file. Each script
#    holds 15 to 17 lines, so the text is inline. The commands and the runtime inputs do not move.
# 3. **The native option replaces the cross-platform package list.** A den target names its class, so
#    each target below writes `environment.systemPackages`.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. See change 1 above.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
let
  declaration =
    { lib, ... }:
    {
      options.kdn.hw.qmk.graphical = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = ''
          This machine runs a desktop, so the aspect adds the graphical layout editor `vial`.

          The old module reads `kdn.desktop.enable` here. A den aspect declares no reachable
          `enable`, so a consumer sets this option instead.

          The option exists for the `darwin` class too, so a consumer sets it with no class check.
          The `darwin` target ignores it, because `vial` is unsupported on `aarch64-darwin`.
        '';
      };
    };

  # The shared package list. Every entry resolves on `x86_64-linux` and on `aarch64-darwin`.
  oryxPackages =
    pkgs:
    let
      # A Nix indented string writes a literal `$` as `''$`. So `''${1}` reaches the shell as
      # `${1}`.
      layoutSplit = ''
        #!/usr/bin/env bash
        set -eEuo pipefail

        if [[ "''${1}" = */* ]] ; then
          layout_id="''${1%/*}"
          revision="''${1#*/}"
        else
          layout_id="''${1}"
          revision=latest
        fi
      '';
    in
    [
      (pkgs.writeShellApplication {
        name = "oryx-flash";
        runtimeInputs = with pkgs; [
          wally-cli
          curl
        ];
        text = layoutSplit + ''

          file="''$(mktemp -t oryx-flash.XXXX.bin)"
          trap 'rm $file || :' EXIT
          curl -L "https://oryx.zsa.io/''${layout_id}/''${revision}/binary" -o "''${file}"
          wally-cli "''${file}"
        '';
      })

      (pkgs.writeShellApplication {
        name = "oryx-src";
        runtimeInputs = with pkgs; [
          curl
          unzip
        ];
        text = layoutSplit + ''

          output_dir="''${2:-"."}"

          file="''$(mktemp -t oryx-src.XXXX.zip)"
          trap 'rm $file || :' EXIT
          curl -L "https://oryx.zsa.io/''${layout_id}/''${revision}/source" -o "''${file}"
          unzip -d "''${output_dir}" "''${file}"
        '';
      })
    ];

  basePackages =
    pkgs:
    (with pkgs; [
      keymapviz
      qmk
      wally-cli
    ])
    ++ oryxPackages pkgs;
in
{
  kdn.hw-qmk.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.hw.qmk;

      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      imports = [ declaration ];

      config.environment.systemPackages = filterPackages (
        basePackages pkgs ++ lib.optional cfg.graphical pkgs.vial
      );

      config.services.udev.packages = with pkgs; [
        qmk-udev-rules
        zsa-udev-rules
      ];
    };

  kdn.hw-qmk.darwin =
    { lib, pkgs, ... }:
    let
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      imports = [ declaration ];

      # `vial` is unsupported on `aarch64-darwin`, so the graphical editor stays out of this class.
      config.environment.systemPackages = filterPackages (basePackages pkgs);
    };
}
