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
}
