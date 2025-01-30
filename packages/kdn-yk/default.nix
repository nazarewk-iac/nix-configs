{
  pkgs,
  lib,
  ...
}:
lib.kdn.mkPythonScript pkgs {
  src = ./.;
  name = "kdn-yk";
  python = pkgs.python313;
  runtimeDeps = with pkgs; [
    yubikey-manager
    pass
  ];
  packageOverrides = final: prev: {
    yubikey-manager = pkgs.yubikey-manager.override {
      python3Packages = prev;
    };
  };
}
