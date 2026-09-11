# The `jsonTemplate` helper of the old tree, as a plain function.
#
# ## Why this file exists
#
# The old tree adds `pkgs.jsonTemplate` through `nixpkgs.overlays`, and one option gates that
# overlay. An aspect must need no overlay, so the router carries its own copy of the helpers it
# uses. The old definition sits in the secrets module of the deprecated tree.
#
# ## What the three helpers do
#
# `type` is the option type of a JSON document. `unwrap txt` marks a string. `generateText value`
# renders the value as JSON and drops the quotes around every marked string, so a consumer can put
# a raw JSON number, list or object where the option type expects a string.
#
# ## Why `builtins.toJSON`, not `formats.json.generate`
#
# The old helper calls `json.generate`, then `builtins.readFile` on the result. The router then
# calls `builtins.readFile` a second time. Each read is an import-from-derivation: it builds a
# derivation during the evaluation. `builtins.toJSON` gives the same JSON with no build. The only
# difference is the layout — `formats.json` runs `jq .` and prints two-space indent, and this
# function prints compact JSON. Kea parses both.
{ lib, pkgs }:
let
  prefix = "<UNWRAP:";
  suffix = ":UNWRAP>";
in
{
  inherit prefix suffix;

  # The option type of a JSON document. `pkgs.formats.json` needs no overlay.
  type = (pkgs.formats.json { }).type;

  # Mark a string, so `generateText` drops the quotes around it.
  unwrap = txt: "${prefix}${txt}${suffix}";

  # Render a value as JSON text, and unwrap every marked string.
  generateText =
    value:
    lib.pipe value [
      builtins.toJSON
      (builtins.replaceStrings [ "\"${prefix}" "${suffix}\"" ] [ "" "" ])
    ];
}
