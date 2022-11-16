{ lib, ... }:
let
  # escapeShellArg = arg: "'${replaceStrings ["'"] ["'\\''"] (toString arg)}'";
  escapeShellDefaultValue = arg: ''"${builtins.replaceStrings [''"''] [''\"''] (builtins.toString arg)}"'';
  escapeShellDefault = n: v: "\"\${${n}:-${escapeShellDefaultValue v}}\"";

  escapeShellDefaultAssignment = n: v: "${n}=${escapeShellDefault n v}";
  makeShellDefaultAssignments = lib.mapAttrsToList escapeShellDefaultAssignment;

  writeShellScript = pkgs: path: { runtimeInputs ? [ ], checkPhase ? null, ... }@args:
    let
      name = args.name or (lib.pipe path [
        builtins.toString
        builtins.baseNameOf
        (lib.removeSuffix ".sh")
      ]);

      dropFirst = line: lines:
        if (builtins.head lines) == line
        then (builtins.tail lines)
        else lines;

      drv = pkgs.writeShellApplication {
        inherit name runtimeInputs checkPhase;
        text = lib.pipe path [
          builtins.readFile
          (lib.strings.splitString "\n")
          (dropFirst "#!/usr/bin/env bash")
          (dropFirst "set -eEuo pipefail")
          (dropFirst "set -xeEuo pipefail")
          (dropFirst "")
          (l: [ args.prefix or "" ] ++ l ++ [ args.suffix or "" ])
          (builtins.concatStringsSep "\n")
        ];
      };
    in
    drv // { bin = "${drv}/bin/${name}"; };
in
{
  inherit
    escapeShellDefault
    escapeShellDefaultAssignment
    escapeShellDefaultValue
    makeShellDefaultAssignments
    writeShellScript
    ;
}
