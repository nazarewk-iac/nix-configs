{
  pkgs,
  ...
}:
{
  kdn-slug = pkgs.callPackage ./kdn-slug { };
  zellij-llm = pkgs.callPackage ./zellij-llm { };
}
