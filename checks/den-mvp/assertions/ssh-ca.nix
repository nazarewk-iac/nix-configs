# Tier-1 assertions for the `ssh-ca` aspect.
#
# ## The subjects
#
# | Subject | Class | What it states |
# |---|---|---|
# | `bareNixos` | `nixos` | an empty CA set and an empty leaf set write no server directive |
# | `bareHome` | `homeManager` | an empty CA set writes no client drop-in |
# | `serverNixos` | `nixos` | a declared SSH CA and host cert write both server directives |
# | `serverDarwin` | `darwin` | the same two directives, through `services.openssh.extraConfig` |
# | `clientHome` | `homeManager` | the client drop-in and the `@cert-authority` fragment |
#
# The aspect derives the SSH public key of the CA from its X.509 certificate, so every declared
# subject names a real certificate path. The path does not have to exist at evaluation time: the
# aspect builds the derivation, and `den-eval-instantiate` forces the body. The `repoRoot` fixture
# is the same one the `certificates` area uses.
#
# The server half sets `services.openssh.settings` on `nixos` and `services.openssh.extraConfig` on
# `darwin`, as design § 7.1 states. nix-darwin declares no `services.openssh.settings`.
{
  lib,
  denLib,
  bareNixos,
  bareDarwinSystem,
  bareHomeConfiguration,
  ...
}:
let
  repoRoot = ../../..;

  aspectsFor =
    class:
    denLib.imports {
      inherit class;
      aspects = [ "ssh-ca" ];
    };

  # One root CA that also signs SSH certificates, and one `ssh-host` leaf it signs. Every name is
  # fictional.
  caData = {
    kdn.ca-dag.cas.kdn = {
      type = "root";
      commonName = "ssh-ca root CA";
      keySource = "external";
      ssh = true;
    };
  };

  certData = {
    kdn.certificates.repoRoot = repoRoot;
    kdn.certificates.certs.host = {
      ca = "kdn";
      type = "ssh-host";
      commonName = "host.ssh-ca.example.invalid";
      principals = [ "host.ssh-ca.example.invalid" ];
      keySource = "managed";
    };
  };

  # The sops-nix key source, for the classes that import sops-nix. The `certificates` aspect
  # asserts one when `sops.secrets` is not empty.
  sopsData = {
    sops.age.keyFile = "/dev/null";
    sops.validateSopsFiles = false;
  };

  # The client half needs no sops-nix: it declares no leaf.
  clientData = [
    caData
    { kdn.certificates.repoRoot = repoRoot; }
  ];

  emptyNixos = (bareNixos (aspectsFor "nixos")).config;
  emptyHome = (bareHomeConfiguration (aspectsFor "homeManager")).config;

  serverNixos =
    (bareNixos (
      aspectsFor "nixos"
      ++ [
        caData
        certData
        sopsData
        { networking.hostName = "host-nixos"; }
      ]
    )).config;

  serverDarwin =
    (bareDarwinSystem (
      aspectsFor "darwin"
      ++ [
        caData
        certData
        sopsData
      ]
    )).config;

  clientHome = (bareHomeConfiguration (aspectsFor "homeManager" ++ clientData)).config;

  # The two client files the aspect writes.
  dropInPath = ".ssh/config.d/50-kdn-ssh-ca.config";
  knownHostsPath = ".ssh/known_hosts.d/50-kdn-ssh-ca";
in
{
  instantiatedBy = {
    ssh-ca = "den-eval-ssh-ca (bare and declared nixos, darwin, homeManager)";
  };

  assertions = [
    # ---- the empty option set is the no-op
    {
      name = "an empty CA set writes no TrustedUserCAKeys on nixos";
      expected = false;
      actual = emptyNixos.services.openssh.settings ? TrustedUserCAKeys;
    }
    {
      name = "an empty CA set writes no HostCertificate on nixos";
      expected = false;
      actual = emptyNixos.services.openssh.settings ? HostCertificate;
    }
    {
      name = "an empty CA set writes no client drop-in";
      expected = false;
      actual = emptyHome.home.file ? ${dropInPath};
    }

    # ---- the nixos server half
    {
      name = "a declared SSH CA writes TrustedUserCAKeys as a store path";
      expected = true;
      actual =
        let
          p = serverNixos.services.openssh.settings.TrustedUserCAKeys;
        in
        lib.hasPrefix builtins.storeDir p;
    }
    {
      name = "a declared host cert writes HostCertificate";
      expected = true;
      actual = lib.hasSuffix "/hosts/host-nixos/certs/host.pub" (
        serverNixos.services.openssh.settings.HostCertificate
      );
    }

    # ---- the darwin server half, through extraConfig
    {
      name = "the darwin class writes both directives through extraConfig";
      expected = {
        trusted = true;
        host = true;
      };
      actual = {
        trusted = lib.hasInfix "TrustedUserCAKeys " serverDarwin.services.openssh.extraConfig;
        host = lib.hasInfix "HostCertificate " serverDarwin.services.openssh.extraConfig;
      };
    }
    {
      name = "the darwin class declares no services.openssh.settings";
      expected = false;
      actual = serverDarwin.services.openssh ? settings;
    }

    # ---- the homeManager client half
    {
      name = "a declared SSH CA writes the client drop-in";
      expected = true;
      actual = clientHome.home.file ? ${dropInPath};
    }
    {
      name = "the drop-in names CertificateFile and the managed known-hosts fragment";
      expected = {
        certificate = true;
        knownHosts = true;
      };
      actual =
        let
          text = clientHome.home.file.${dropInPath}.text;
        in
        {
          certificate = lib.hasInfix "CertificateFile " text;
          knownHosts = lib.hasInfix "UserKnownHostsFile " text;
        };
    }
    {
      name = "the known-hosts fragment is a store path";
      expected = true;
      actual = lib.hasPrefix builtins.storeDir (toString clientHome.home.file.${knownHostsPath}.source);
    }

    # ---- the library route resolves the aspect on all three classes
    {
      name = "the library route resolves ssh-ca on all three classes";
      expected = {
        darwin = 1;
        homeManager = 1;
        nixos = 1;
      };
      actual = {
        darwin = builtins.length (aspectsFor "darwin");
        homeManager = builtins.length (aspectsFor "homeManager");
        nixos = builtins.length (aspectsFor "nixos");
      };
    }
    {
      name = "denLib.pairs names the three classes of ssh-ca";
      expected = [
        "darwin"
        "homeManager"
        "nixos"
      ];
      actual = lib.sort (a: b: a < b) denLib.pairs.ssh-ca;
    }
  ];
}
