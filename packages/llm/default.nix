{
  pkgs,
  ...
}:
let
  kdn-slug = pkgs.callPackage ./kdn-slug { };
in
{
  inherit kdn-slug;

  # `zellij-llm` takes `kdn-slug` as a plain argument, so it needs no overlay.
  zellij-llm = pkgs.callPackage ./zellij-llm { inherit kdn-slug; };

  # The llama-swap statistics collector. Plain arguments only, so a host reaches it with a
  # direct `pkgs.callPackage` and needs none of this repository's overlays.
  llm-stats = pkgs.callPackage ./llm-stats { };
}
