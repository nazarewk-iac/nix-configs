{ lib, ... }:
let
  # escapeShellArg = arg: "'${replaceStrings ["'"] ["'\\''"] (toString arg)}'";
  escapeShellDefaultValue = arg: ''"${builtins.replaceStrings [''"''] [''\"''] (builtins.toString arg)}"'';
  escapeShellDefault = n: v: "\"\${${n}:-${escapeShellDefaultValue v}}\"";

  escapeShellDefaultAssignment = n: v: "${n}=${escapeShellDefault n v}";
  makeShellDefaultAssignments = lib.mapAttrsToList escapeShellDefaultAssignment;
in
{
  inherit escapeShellDefaultValue escapeShellDefault makeShellDefaultAssignments escapeShellDefaultAssignment;
}
