{
  lib,
  pkgs,
  ...
}: let
  python3 = pkgs.python3.override {
    self = python3;
    packageOverrides = final: prev: {
      # https://github.com/NixOS/nixpkgs/issues/197408
      dbus-next = prev.dbus-next.overridePythonAttrs (old: {
        checkPhase = builtins.replaceStrings ["not test_peer_interface"] ["not test_peer_interface and not test_tcp_connection_with_forwarding"] old.checkPhase;
      });

      pypass = prev.pypass.overridePythonAttrs (o: let
        pbr_version = "0.2.2dev";
        version = "6f51145a3bc12ee79d2881204b88a82d149f3228";
        sha256 = "sha256-iJZe/Ljae9igkpfz9WJQK48wZZJWcOt4Z3kdp5VILqE=";
      in {
        /*
        TODO: fix tests, probably requires key larger than 1024 RSA
            > gpg: encrypted with rsa1024 key, ID 6C8110881C10BC07, created 2014-11-06
            >       "pypass testing (testing key) <test@key.com>"
            > gpg: 86B4789B: skipped: Unusable public key
            > gpg: [stdin]: encryption failed: Unusable public key
            > gpg: can't open '/build/tmp2obio5_s/Email/should_use_secondary_key.gpg'
         keys are at:
         - https://github.com/aviau/python-pass/blob/master/pypass/tests/test_key_2_sec.asc
         - https://github.com/aviau/python-pass/blob/master/pypass/tests/test_key_sec.asc
        */
        inherit version;

        src = pkgs.fetchFromGitHub {
          owner = "nazarewk";
          # see https://github.com/aviau/python-pass/pull/34
          repo = "python-pass";
          rev = version;
          inherit sha256;
        };
        doInstallCheck = false;
        patches = [
          (with pkgs;
            substituteAll {
              src = ./pypass-mark-executables.patch;
              version = pbr_version;
              git_exec = "${git}/bin/git";
              grep_exec = "${gnugrep}/bin/grep";
              gpg_exec = "${gnupg}/bin/gpg2";
              tree_exec = "${tree}/bin/tree";
              xclip_exec = "${xclip}/bin/xclip";
            })
        ];
      });
    };
  };
in
  pkgs.pass-secret-service.override {
    python3 = python3;
  }
