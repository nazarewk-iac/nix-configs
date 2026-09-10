# A build-only NixOS host. It never activates and it names no hardware. See ../README.md.
{ den, kdn, ... }:
{
  # `x86_64-linux` matches the real NixOS hosts, so a comparison uses the same platform. den derives
  # `class = "nixos"` from the system suffix, and its default `instantiate` is
  # `inputs.nixpkgs.lib.nixosSystem` — an input name this repo does use, so no override is needed.
  den.hosts.x86_64-linux.host-nixos = {
    # `homeManager` must be explicit. den's default is `[ "user" ]` alone. `../users/default.nix`
    # holds the `dev` aspect.
    users.dev.classes = [
      "user"
      "homeManager"
    ];
  };

  den.aspects.host-nixos.includes = [
    # `gh` emits into the `devenv` target only, so it changes no NixOS option.
    kdn.gh

    # The first aspect that reaches this host's `nixos` target. It also delivers the `devenv` half
    # to this host's shell. Its `homeManager` half arrives through the `dev` user instead, because
    # den partitions by scope — see ../users/default.nix.
    kdn.devenv-cli

    # The first **`nixos`-only** aspect. It declares `kdn.ca` and reads it. The data below belongs
    # to this entity, not to the aspect.
    kdn.ca
  ];

  den.aspects.host-nixos.nixos =
    { config, pkgs, ... }:
    let
      # Two throwaway CA certificates, generated at build time. A test entity must carry its own
      # data: an aspect stays universal, and the creator's own certificates live in one personal
      # folder. So this host generates certificates and holds no real key.
      #
      # `-days 7300` is 20 years. It keeps the notAfter date before 2049, so the encoding stays
      # UTCTime and every parser accepts it. OpenSSL 3 marks a self-signed `req -x509` certificate
      # as a CA already; the explicit extension states the intent.
      testCerts =
        pkgs.runCommand "den-mvp-test-ca"
          {
            nativeBuildInputs = [ pkgs.openssl ];
          }
          ''
            mkdir -p "$out"
            for pair in 'a:den-mvp test CA A' 'b:den-mvp test CA B'; do
              name="''${pair%%:*}"
              subject="''${pair#*:}"
              openssl req -x509 -newkey rsa:2048 -noenc -days 7300 \
                -subj "/CN=$subject" \
                -addext 'basicConstraints=critical,CA:TRUE' \
                -keyout "$out/$name.key" -out "$out/$name.pub"
            done
          '';

      # A stand-in for a SOPS-encrypted key. The aspect mounts the blob and never decrypts it, so
      # the content only has to exist.
      fakeSopsKey = pkgs.writeText "den-mvp-ca.key.sops" ''
        # not a real sops file — the `ca` aspect mounts this blob and never reads it
      '';
    in
    {
      networking.hostName = "host-nixos";

      # `system.build.toplevel` needs a root file system, or an assertion stops the evaluation.
      # `tmpfs` needs no disk, no label and no UUID, so it names no real hardware.
      fileSystems."/" = {
        device = "none";
        fsType = "tmpfs";
      };

      # NixOS enables GRUB by default and then asserts that `devices` is not empty. This host never
      # boots, so it needs no boot loader at all.
      boot.loader.grub.enable = false;

      # Track the nixpkgs release this flake pins, because a build-only host keeps no state to
      # stay compatible with.
      system.stateVersion = config.system.nixos.release;

      # Three `kdn.ca` instances cover all three branches of the aspect:
      #   `den-mvp-test`  the plain case — one public certificate, no key
      #   `den-mvp-keyed` the optional encrypted key as well
      #   `den-mvp-off`   a disabled instance, which must mount nothing at all
      # The disabled instance holds no certificate on purpose. The system CA bundle rejects the
      # content, so a broken filter fails the build instead of passing in silence.
      kdn.ca.den-mvp-test.enable = true;
      kdn.ca.den-mvp-test.certFile = "${testCerts}/a.pub";

      kdn.ca.den-mvp-keyed.enable = true;
      kdn.ca.den-mvp-keyed.certFile = "${testCerts}/b.pub";
      kdn.ca.den-mvp-keyed.keySopsFile = fakeSopsKey;

      kdn.ca.den-mvp-off.enable = false;
      kdn.ca.den-mvp-off.certFile = pkgs.writeText "den-mvp-off.pub" "not a certificate\n";
    };
}
