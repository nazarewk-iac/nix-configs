# `kdn.programs.keepass`, as a den aspect. It ports `modules/universal/programs/keepass/default.nix`.
#
# NixOS only, and it holds an overlay. The overlay body takes `final` and not the module's own `pkgs`,
# because an overlay that reads the finished `pkgs` inside itself makes an infinite recursion. The old
# module reads `pkgs` there and works only because the plugin set holds no overridden package.
{ ... }:
{
  kdn.program-keepass.nixos.nixpkgs.overlays = [
    (final: prev: {
      keepass = prev.keepass.override {
        plugins = with final; [
          keepass-keeagent
          keepass-keepassrpc
          keepass-keetraytotp
          keepass-charactercopy
          keepass-qrcodeview
        ];
      };
    })
  ];
}
