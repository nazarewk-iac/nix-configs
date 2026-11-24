{
  pkgs,
  lib,
  __inputs__ ? { },
  ...
}:
let
  llm = import ./llm { inherit pkgs lib; };
  llama-cpp = import ./llama-cpp { inherit pkgs lib; };
in
(import ./netbird { inherit pkgs lib; })
// llm
// llama-cpp
// {
  inherit llm;

  link-python = pkgs.callPackage ./link-python { };
  init-py-script = pkgs.callPackage ./init-py-script { };

  ik-llama-cpp = pkgs.callPackage ./ik-llama-cpp { };

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
  kdn-certs = pkgs.callPackage ./kdn-certs { };
  kdn-nix-darwin-helper = pkgs.callPackage ./kdn-nix-darwin-helper { };
  # Compatibility alias for callers that still name the old attribute. The new binary is the
  # helper; the old *path* on anji is preserved separately by `hosts/anji/default.nix`.
  kdn-nix-bootstrap = pkgs.callPackage ./kdn-nix-darwin-helper { };
  kdn-cidata-iso = pkgs.callPackage ./kdn-cidata-iso { };
  kdn-inference-helpers = pkgs.callPackage ./kdn-inference-helpers { };
  kdn-nix = pkgs.callPackage ./kdn-nix { };
  kdn-ssh-access = pkgs.callPackage ./kdn-ssh-access { };
  kdn-yk = pkgs.callPackage ./kdn-yk { };
  klg = pkgs.callPackage ./klg { };
  klog-time-tracker = pkgs.callPackage ./klog-time-tracker { };
  lnav = pkgs.callPackage ./lnav/package.nix { };
  pinentry = pkgs.callPackage ./pinentry { };
  rambox = pkgs.callPackage ./rambox { };
  ss-util = pkgs.callPackage ./ss-util { };
  tc-redirect-tap = pkgs.callPackage ./tc-redirect-tap { };
  whicher = pkgs.callPackage ./whicher { };

  basic-memory = pkgs.callPackage ./basic-memory { inherit __inputs__; };
  kdn-disko-zfs = pkgs.callPackage ./kdn-disko-zfs { inherit __inputs__; };
  jj-mcp = pkgs.callPackage ./jj-mcp { };
  kdn-jj-meta = pkgs.callPackage ./kdn-jj-meta { };
  kdn-okf = pkgs.callPackage ./kdn-okf { };
  okf-agent-memory = pkgs.callPackage ./okf-agent-memory { };
  okf-guard = pkgs.callPackage ./okf-guard { };
  okf-rs = pkgs.callPackage ./okf-rs { };
  okflint = pkgs.callPackage ./okflint { };
  okph = pkgs.callPackage ./okph { };
  ai-xf = pkgs.callPackage ./ai-xf { };
  mcpsnoop = pkgs.callPackage ./mcpsnoop { };
  opencode-compat-proxy = pkgs.callPackage ./opencode-compat-proxy { inherit __inputs__; };
  clank-talk = pkgs.callPackage ./clank-talk { };
  kdn-journal = pkgs.callPackage ./kdn-journal { };
  kdn-knowledge = pkgs.callPackage ./kdn-knowledge { };
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

  # Each package below needs a Linux-only dependency, and a Linux guard covers each consumer.
  # The guard is `kdnConfig.util.ifTypes [ "nixos" ]`, or `pkgs.stdenv.hostPlatform.isLinux`.
  # So no Darwin evaluation reads any of them.
  #
  # `kdn-keepass` runs `sway` and `systemd`.
  # Consumers: modules/universal/programs/keepassxc/default.nix and
  # modules/universal/profile/user/kdn/default.nix.
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

  # `kdn-audio` drives the PipeWire graph through `pw-dump`, `pw-cli`, `pw-metadata` and
  # `pw-link`, starts transient user units through `systemd-run`, and connects Bluetooth devices
  # through `bluetoothctl`. Consumer: modules/universal/programs/kdn-audio/default.nix, enabled
  # on hosts/oams.
  kdn-audio = pkgs.callPackage ./kdn-audio { };
}
# x86_64-linux-only packages.
#
# The guard above is not enough for a package with an x86_64-only dependency. Measured 2026-09-10:
# `nix flake check --all-systems` stopped at `packages.aarch64-linux.kdn-gamingctl`.
// lib.optionalAttrs (pkgs.stdenv.hostPlatform.isLinux && pkgs.stdenv.hostPlatform.isx86_64) {
  # `kdn-gamingctl` runs `systemd`, `supergfxctl` and `sway`. nixpkgs gives `supergfxctl`
  # `meta.platforms = [ "x86_64-linux" ]`, so an `aarch64-linux` evaluation refuses it.
  # Consumer: hosts/oams/default.nix:280, an x86_64-linux host.
  kdn-gamingctl = pkgs.callPackage ./kdn-gamingctl { };

  # `strata` builds an FHS sandbox, and Strata publishes engine packages for
  # linux-x86_64 only, so the package has no other target. `buildFHSEnvBubblewrap`
  # does not exist on Darwin at all, hence the guard, not just `meta.platforms`.
  # Consumer: none yet. `packages/strata/README.md` holds the measurements.
  strata = pkgs.callPackage ./strata { };
}
