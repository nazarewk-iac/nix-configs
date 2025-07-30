{
  pkgs,
  lib,
  ...
}: let
  withGoBuildDebug = pkg: attrs:
    pkg.overrideAttrs (old:
      attrs
      // {
        buildPhase = lib.pipe old.buildPhase [
          (prev: ''
            kdn_tracing_id=0
            kdn_go_cmd="$(command -v go)"
            mkdir -p "$out/debug"
            kdn_tracer="strace"

            run_with_tracing() {
              local trace_output="$out/debug/$kdn_tracer.$((++kdn_tracing_id)).$cmd.out"
              local common_args=(
                --follow-forks
                --syscall-number
                --summary
              )
              local lurk_args=(
                "''${common_args[@]}"
                --syscall-times
                --file="$trace_output"
              )
              local strace_args=(
                "''${common_args[@]}"
                --output-separately
                --output="$trace_output"
                --syscall-times=ns
                --summary-wall-clock
              )
              case "$kdn_tracer" in
                lurk)
                  ${lib.getExe pkgs.lurk} "''${lurk_args[@]}" "$@"
                ;;
                strace)
                  ${lib.getExe pkgs.strace} "''${strace_args[@]}" "$@"
                ;;
                *)
                  "$@"
                ;;
              fi
            }

            go() {
              GOFLAGS="$GOFLAGS -debug-trace="$out/debug/go-debug-trace.$kdn_tracing_id.json" -x" run_with_tracing "$kdn_go_cmd" "$@"
            }

            ${prev}
          '')
          /*
          https://github.com/NixOS/nixpkgs/blob/17f6bd177404d6d43017595c5264756764444ab8/pkgs/build-support/go/module.nix#L315-L315
              if ! OUT="$(go $cmd "''${flags[@]}" $dir 2>&1)"; then
          */
          # (lib.strings.replaceString ''OUT="$(go $cmd'' ''OUT="$(run_with_tracing go $cmd'')
        ];
      });
in {
  # changed to manual list due to infinite recursion errors
  data-converters = pkgs.callPackage ./data-converters {};
  ff-ctl = pkgs.callPackage ./ff-ctl {};
  fortitoken-decrypt = pkgs.callPackage ./fortitoken-decrypt {};
  git-credential-keyring = pkgs.callPackage ./git-credential-keyring {};
  git-utils = pkgs.callPackage ./git-utils {};
  gpg-smartcard-reset-keys = pkgs.callPackage ./gpg-smartcard-reset-keys {};
  kdn-anonymize = pkgs.callPackage ./kdn-anonymize {};
  kdn-cidata-iso = pkgs.callPackage ./kdn-cidata-iso {};
  kdn-keepass = pkgs.callPackage ./kdn-keepass {};
  kdn-nix = pkgs.callPackage ./kdn-nix {};
  kdn-secrets = pkgs.callPackage ./kdn-secrets {};
  kdn-yk = pkgs.callPackage ./kdn-yk {};
  klg = pkgs.callPackage ./klg {};
  klog-time-tracker = pkgs.callPackage ./klog-time-tracker {};
  lnav = pkgs.callPackage ./lnav/package.nix {};
  pass-secret-service = pkgs.callPackage ./pass-secret-service {};
  pinentry = pkgs.callPackage ./pinentry {};
  ss-util = pkgs.callPackage ./ss-util {};
  sway-vnc = pkgs.callPackage ./sway-vnc {};
  systemd-find-cycles = pkgs.callPackage ./systemd-find-cycles {};
  tc-redirect-tap = pkgs.callPackage ./tc-redirect-tap {};
  whicher = pkgs.callPackage ./whicher {};

  terraform-debug = withGoBuildDebug pkgs.terraform {};

  netbird-go123-debug = withGoBuildDebug (pkgs.netbird.override {buildGoModule = pkgs.buildGo123Module;}) {
    subPackages = ["client"];
    preBuild = ''
      set -x
    '';

    postInstall = ''
      mv $GOPATH/bin/client $out/bin/netbird
    '';
  };
  netbird-debug = withGoBuildDebug pkgs.netbird {
    subPackages = ["client"];
    preBuild = ''
      # set -x
    '';

    postInstall = ''
      mv $GOPATH/bin/client $out/bin/netbird
    '';
  };
}
