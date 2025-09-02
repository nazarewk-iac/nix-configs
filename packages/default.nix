{
  pkgs,
  lib,
  ...
}: let
  withGoBuildDebug = pkg: attrs:
    pkg.overrideAttrs (old:
      attrs
      // {
        # don't delete the build dir, a tip from https://discourse.nixos.org/t/how-to-look-at-the-build-directory-after-successful-build/14007/3?u=kdn
        nativeBuildInputs = old.nativeBuildInputs ++ [pkgs.keepBuildTree];
      }
      // {
        /*
        fixes errors due to `disallowedReferences` in https://github.com/NixOS/nixpkgs/blob/94def634a20494ee057c76998843c015909d6311/pkgs/build-support/go/module.nix#L389-L389:
          error: output '/nix/store/3vmljz5lsyrchdcy0k26vjig0g2vjrq0-netbird-0.49.0' is not allowed to refer to the following paths:
                   /nix/store/y4awwzp30ka130wmjrpaqjmjdf9p010w-go-1.24.5
        */
        allowGoReference = true;
        disallowedReferences = [];
      }
      // {
        buildPhase = lib.pipe old.buildPhase [
          (prev: ''
            kdn_debug_dir="$out/.debug" # $NIX_BUILD_TOP doesn't include `pkgs.keepBuildTree`
            kdn_go_cmd="$(command -v go)"
            kdn_tracer="strace"
            kdn_tracing_idx=0
            mkdir -p "$kdn_debug_dir"

            run_with_tracing() {
              local trace_output="$kdn_debug_dir/$kdn_tracer.$((++kdn_tracing_idx)).$cmd.out"
              kdn_common_args=(
                --follow-forks
                --syscall-number
              )
              kdn_lurk_args=(
                "''${kdn_common_args[@]}"
                --summary
                --syscall-times
                --file="$trace_output"
              )
              kdn_strace_args=(
                "''${kdn_common_args[@]}"
                --output="$trace_output"
                --syscall-times=ns
                --absolute-timestamps=precision:ns
              )
              # those are exclusive
              if false ; then
                kdn_strace_args+=( --output-separately )
              else
                kdn_strace_args+=( --summary-wall-clock --summary )
              fi

              case "$kdn_tracer" in
                lurk)
                  ${lib.getExe pkgs.lurk} "''${kdn_lurk_args[@]}" "$@" |& tee "$kdn_debug_dir/outputs.$kdn_tracing_id.log"
                ;;
                strace)
                  ${lib.getExe pkgs.strace} "''${kdn_strace_args[@]}" "$@" |& tee "$kdn_debug_dir/outputs.$kdn_tracing_id.log"
                ;;
                *)
                  "$@"
                ;;
              esac
            }

            go() {
              GOFLAGS="$GOFLAGS -debug-trace="$kdn_debug_dir/go-debug-trace.$kdn_tracing_id.json" -x" run_with_tracing "$kdn_go_cmd" "$@"
            }

            ${prev}
          '')
          (prev: ''
            (
              set -x
              ${prev}
            )
          '')
          /*
          https://github.com/NixOS/nixpkgs/blob/17f6bd177404d6d43017595c5264756764444ab8/pkgs/build-support/go/module.nix#L315-L315
              if ! OUT="$(go $cmd "''${flags[@]}" $dir 2>&1)"; then
          */
          # (lib.strings.replaceString ''OUT="$(go $cmd'' ''OUT="$(run_with_tracing go $cmd'')
        ];
      });
in
  (import ./netbird {inherit pkgs lib;})
  // {
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

    debug-netbird = withGoBuildDebug pkgs.netbird {};
    debug-terraform = withGoBuildDebug pkgs.terraform {};
    debug-usql = withGoBuildDebug pkgs.usql {};
    /*
    TODO: long build packages on `disposable` ZFS:
      - argocd
      - cmctl
      - sops-install-secrets
      - usql (2h+)
      - terraform (4h+)
      - conftest
      - cmctl (10h+!)
    */
  }
