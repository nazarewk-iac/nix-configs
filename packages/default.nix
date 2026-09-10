{
  pkgs,
  lib,
  __inputs__ ? { },
  ...
}:
let
  llm = import ./llm { inherit pkgs lib; };
in
(import ./netbird { inherit pkgs lib; })
// llm
// {
  inherit llm;

  link-python = pkgs.callPackage ./link-python { };
  init-py-script = pkgs.callPackage ./init-py-script { };

  # changed to manual list due to infinite recursion errors
  darwin-rebuild = pkgs.callPackage ./darwin-rebuild { };
  data-converters = pkgs.callPackage ./data-converters { };
  ff-ctl = pkgs.callPackage ./ff-ctl { };
  fortitoken-decrypt = pkgs.callPackage ./fortitoken-decrypt { };
  git-credential-keyring = pkgs.callPackage ./git-credential-keyring { };
  git-utils = pkgs.callPackage ./git-utils { };
  gpg-smartcard-reset-keys = pkgs.callPackage ./gpg-smartcard-reset-keys { };
  kagi-cli = pkgs.callPackage ./kagi-cli/package.nix { };
  kdnctl = pkgs.callPackage ./kdnctl { };
  kdn-anonymize = pkgs.callPackage ./kdn-anonymize { };
  kdn-cidata-iso = pkgs.callPackage ./kdn-cidata-iso { };
  kdn-nix = pkgs.callPackage ./kdn-nix { };
  kdn-ssh-access = pkgs.callPackage ./kdn-ssh-access { };
  kdn-yk = pkgs.callPackage ./kdn-yk { };
  klg = pkgs.callPackage ./klg { };
  klog-time-tracker = pkgs.callPackage ./klog-time-tracker { };
  lnav = pkgs.callPackage ./lnav/package.nix { };
  pinentry = pkgs.callPackage ./pinentry { };
  ss-util = pkgs.callPackage ./ss-util { };
  tc-redirect-tap = pkgs.callPackage ./tc-redirect-tap { };
  whicher = pkgs.callPackage ./whicher { };

  basic-memory = pkgs.callPackage ./basic-memory { inherit __inputs__; };
  jj-mcp = pkgs.callPackage ./jj-mcp { };
  mcpsnoop = pkgs.callPackage ./mcpsnoop { };
  opencode-compat-proxy = pkgs.callPackage ./opencode-compat-proxy { };
  # AUTO_PACKAGE_PLACEHOLDER #
  aws-sso = pkgs.callPackage ./aws-sso { };
  flake-lock-merge = pkgs.callPackage ./flake-lock-merge { };
  kdn-nix-fmt = pkgs.callPackage ./kdn-nix-fmt { };
}
# Linux-only packages.
#
# `nix flake check` reads every entry of `packages.<system>`, so a package that cannot exist on
# this platform fails the whole check. Keep such a package out of the set instead.
// lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  # `pass-secret-service` serves the freedesktop Secret Service D-Bus API. macOS uses Keychain,
  # so the package has no purpose there. nixpkgs states the same limit on the dependency:
  # `pypass` sets `meta.broken = stdenv.hostPlatform.isDarwin`
  # (<nixpkgs>/pkgs/development/python-modules/pypass/default.nix:78). The override below keeps
  # `overridePythonAttrs`, which does not clear `meta.broken`.
  #
  # The one consumer is `modules/universal/programs/gnupg/default.nix:101`, inside a NixOS-only
  # block, so no Darwin evaluation reads this attribute.
  pass-secret-service = pkgs.callPackage ./pass-secret-service { };

  # Each package below needs a Linux-only dependency, and each consumer sits inside a
  # `kdnConfig.util.ifTypes [ "nixos" ]` block. So no Darwin evaluation reads any of them.
  #
  # `kdn-gamingctl` runs `systemd`, `supergfxctl` and `sway`.
  # Consumer: hosts/oams/default.nix:280.
  kdn-gamingctl = pkgs.callPackage ./kdn-gamingctl { };

  # `kdn-keepass` runs `sway` and `systemd`.
  # Consumers: modules/universal/programs/keepassxc/default.nix:33,105 and
  # modules/universal/profile/user/kdn/default.nix:405.
  kdn-keepass = pkgs.callPackage ./kdn-keepass { };

  # `sway-vnc` runs `wayvnc` and `sway`, both Wayland programs.
  # Consumer: modules/universal/desktop/sway/remote/default.nix:29.
  sway-vnc = pkgs.callPackage ./sway-vnc { };

  # `systemd-cryptsetup` symlinks `${systemd}/lib/systemd/systemd-cryptsetup`.
  # Consumer: modules/universal/toolset/fs/encryption/default.nix:12.
  systemd-cryptsetup = pkgs.callPackage ./systemd-cryptsetup { };

  # `systemd-find-cycles` reads the output of `systemd-analyze dot`.
  # Consumer: modules/universal/profile/machine/baseline/default.nix:248.
  systemd-find-cycles = pkgs.callPackage ./systemd-find-cycles { };
}
