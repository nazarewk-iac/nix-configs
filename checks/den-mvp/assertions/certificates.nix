# Tier-1 assertions for the declarative-certificate aspects: `ca-dag` and `certificates`.
#
# ## The subjects
#
# | Subject | Class | What it states |
# |---|---|---|
# | `bareNixos` | `nixos` | an empty `kdn.ca-dag.cas` and an empty `kdn.certificates.certs` |
# | `bareDarwinSystem` | `darwin` | the same two empty option sets |
# | `bareHomeConfiguration` | `homeManager` | the same two empty option sets |
# | `bareShell` | `devenv` | the same two empty option sets |
#
# A second subject per class declares one CA root, one CA intermediate and one leaf, and reads the
# exact option values back. The subjects read option values only and force no `drvPath`, because
# `den-eval-instantiate` already forces every (aspect, class) pair.
#
# ## The `repoRoot` fixture
#
# `certPath` is a store path to the public certificate. The aspect builds it from the consumer's
# `repoRoot` and the repo-relative `directory` and `certFile`. Every declared subject names
# `repoRoot = ../../..`, exactly as the old host files name
# `"${kdnConfig.self}/hosts/<host>/certs/zellij.pub"`. No test subject names a real certificate, and
# a `lib.types.path` accepts a path that no file occupies yet.
#
# ## The sops-nix wiring
#
# The `nixos`, `darwin` and `homeManager` classes import the pinned sops-nix module and write one
# `sops.secrets` entry per declared key. The `devenv` class carries no sops-nix, so its `keyPath` is
# the fixed `/run/secrets/kdn/certificates/<name>.key` the CLI decrypt primitive fills.
{
  lib,
  denLib,
  bareNixos,
  bareDarwinSystem,
  bareHomeConfiguration,
  bareShell,
  ...
}:
let
  sorted = lib.sort (a: b: a < b);

  # The repository root this test tree lives in. The declared subjects name it through the
  # consumer-provided `repoRoot` option, exactly as an external adopter would name their own tree.
  repoRoot = ../../..;

  # Both aspects, resolved once per class. `denLib.imports` returns a list, so a caller wraps it in
  # `{ imports = …; }` for a `modules` list.
  aspectsFor =
    class:
    denLib.imports {
      inherit class;
      aspects = [
        "ca-dag"
        "certificates"
      ];
    };

  # The declared data. One root, one intermediate that names it, and one leaf that names the
  # intermediate. Every name and every common name is fictional.
  caData = {
    kdn.ca-dag.cas.root-ca = {
      type = "root";
      commonName = "den-mvp root CA";
      keySource = "external";
      ssh = true;
      provisioner = "den-mvp-provisioner";
      minGenerationDate = "2026";
    };
    kdn.ca-dag.cas.intermediate-ca = {
      type = "intermediate";
      parent = "root-ca";
      commonName = "den-mvp intermediate CA";
      directory = "data/den-mvp";
      certFile = "intermediate.crt";
      keyFile = "intermediate.key";
      keySource = "managed";
    };
  };

  certData = {
    kdn.certificates.repoRoot = repoRoot;
    kdn.certificates.certs.den-mvp-leaf = {
      ca = "intermediate-ca";
      type = "tls-server";
      commonName = "den-mvp.example.invalid";
      sans = [
        "den-mvp.example.invalid"
        "127.0.0.1"
      ];
      directory = "hosts/den-mvp/certs";
      certFile = "den-mvp.pub";
      keyFile = "den-mvp.key";
      keySource = "managed";
      minGenerationDate = "2026-09-01";
    };
  };

  # The consumer's own sops-nix key source, for the three classes that import sops-nix. sops-nix
  # asserts one when `sops.secrets` is not empty, and the aspect never names a key source of its
  # own. `validateSopsFiles = false` keeps the fixture offline: the declared `.sops` file does not
  # exist, and no real key is needed to read the option values. The `devenv` class carries no
  # sops-nix, so its subject names none of this.
  sopsData = {
    sops.age.keyFile = "/dev/null";
    sops.validateSopsFiles = false;
  };

  # The empty-option subjects, one per class. Each class needs its own evaluation shape.
  emptyNixos = (bareNixos (aspectsFor "nixos")).config;
  emptyDarwin = (bareDarwinSystem (aspectsFor "darwin")).config;
  emptyHome = (bareHomeConfiguration (aspectsFor "homeManager")).config;
  emptyDevenv =
    (bareShell {
      aspects = [
        "ca-dag"
        "certificates"
      ];
    }).config;

  # The declared-data subjects. `bareShell` takes `aspects` and `modules` separately, so the devenv
  # subject names the aspects and passes the data as modules.
  declaredNixos =
    (bareNixos (
      aspectsFor "nixos"
      ++ [
        caData
        certData
        sopsData
      ]
    )).config;
  declaredDarwin =
    (bareDarwinSystem (
      aspectsFor "darwin"
      ++ [
        caData
        certData
        sopsData
      ]
    )).config;
  declaredHome =
    (bareHomeConfiguration (
      aspectsFor "homeManager"
      ++ [
        caData
        certData
        sopsData
      ]
    )).config;
  declaredDevenv =
    (bareShell {
      aspects = [
        "ca-dag"
        "certificates"
      ];
      modules = [
        caData
        certData
      ];
    }).config;

  # The exact option values of the declared root and intermediate.
  caValues =
    cfg:
    let
      cas = cfg.kdn.ca-dag.cas;
    in
    {
      root = {
        inherit (cas.root-ca)
          type
          commonName
          directory
          certFile
          keyFile
          keySource
          provisioner
          ssh
          ;
        parent = cas.root-ca.parent;
        minGenerationDate = cas.root-ca.minGenerationDate;
      };
      intermediate = {
        inherit (cas.intermediate-ca)
          type
          parent
          commonName
          directory
          certFile
          keyFile
          keySource
          ;
        provisioner = cas.intermediate-ca.provisioner;
        ssh = cas.intermediate-ca.ssh;
        minGenerationDate = cas.intermediate-ca.minGenerationDate;
      };
    };

  expectedCas = {
    root = {
      type = "root";
      parent = null;
      commonName = "den-mvp root CA";
      directory = "data/ca";
      certFile = "root-ca.crt";
      keyFile = "root-ca.key";
      keySource = "external";
      provisioner = "den-mvp-provisioner";
      ssh = true;
      minGenerationDate = "2026";
    };
    intermediate = {
      type = "intermediate";
      parent = "root-ca";
      commonName = "den-mvp intermediate CA";
      directory = "data/den-mvp";
      certFile = "intermediate.crt";
      keyFile = "intermediate.key";
      keySource = "managed";
      provisioner = null;
      ssh = false;
      minGenerationDate = null;
    };
  };

  # The exact option values of the declared leaf, without the two derived paths.
  certValues =
    cfg:
    let
      leaf = cfg.kdn.certificates.certs.den-mvp-leaf;
    in
    {
      inherit (leaf)
        ca
        type
        commonName
        sans
        principals
        directory
        certFile
        keyFile
        keySource
        minGenerationDate
        ;
    };

  expectedCert = {
    ca = "intermediate-ca";
    type = "tls-server";
    commonName = "den-mvp.example.invalid";
    sans = [
      "den-mvp.example.invalid"
      "127.0.0.1"
    ];
    principals = [ ];
    directory = "hosts/den-mvp/certs";
    certFile = "den-mvp.pub";
    keyFile = "den-mvp.key";
    keySource = "managed";
    minGenerationDate = "2026-09-01";
  };

  # The sops secret name the aspect derives from one leaf key.
  secretName = name: "kdn/certificates/${name}.key";

  # The one `sops.secrets` entry the aspect writes for the declared leaf.
  sopsEntry =
    cfg:
    let
      secret = cfg.sops.secrets.${secretName "den-mvp-leaf"};
    in
    {
      format = secret.format;
      sopsFileSuffix = lib.removePrefix (toString repoRoot) (toString secret.sopsFile);
    };

  # A subject that declares a leaf but names no `repoRoot`. Reading `certPath` must fail loudly.
  repoRootMissing =
    (bareNixos (
      aspectsFor "nixos"
      ++ [
        sopsData
        {
          kdn.certificates.certs.no-root = {
            ca = "root-ca";
            type = "tls-server";
            commonName = "no-root.example.invalid";
            keySource = "managed";
          };
        }
      ]
    )).config.kdn.certificates.certs.no-root.certPath;
in
{
  instantiatedBy = {
    ca-dag = "den-eval-certificates (bare nixos, bare darwin, bare home, bare devenv)";
    certificates = "den-eval-certificates (bare nixos, bare darwin, bare home, bare devenv)";
  };

  assertions = [
    # ---- the empty option set is the no-op, on every class
    {
      name = "the four classes each carry an empty kdn.ca-dag.cas";
      expected = {
        darwin = { };
        devenv = { };
        homeManager = { };
        nixos = { };
      };
      actual = {
        darwin = emptyDarwin.kdn.ca-dag.cas;
        devenv = emptyDevenv.kdn.ca-dag.cas;
        homeManager = emptyHome.kdn.ca-dag.cas;
        nixos = emptyNixos.kdn.ca-dag.cas;
      };
    }
    {
      name = "the four classes each carry an empty kdn.certificates.certs";
      expected = {
        darwin = { };
        devenv = { };
        homeManager = { };
        nixos = { };
      };
      actual = {
        darwin = emptyDarwin.kdn.certificates.certs;
        devenv = emptyDevenv.kdn.certificates.certs;
        homeManager = emptyHome.kdn.certificates.certs;
        nixos = emptyNixos.kdn.certificates.certs;
      };
    }
    {
      name = "an empty option set writes no sops secret on any class";
      expected = {
        darwin = { };
        homeManager = { };
        nixos = { };
      };
      actual = {
        darwin = emptyDarwin.sops.secrets;
        homeManager = emptyHome.sops.secrets;
        nixos = emptyNixos.sops.secrets;
      };
    }

    # ---- the declared CA graph, on every class
    {
      name = "a declared root and intermediate return the exact option values";
      expected = expectedCas;
      actual = caValues declaredNixos;
    }
    {
      name = "the CA graph is identical on the darwin class";
      expected = caValues declaredNixos;
      actual = caValues declaredDarwin;
    }
    {
      name = "the CA graph is identical on the homeManager class";
      expected = caValues declaredNixos;
      actual = caValues declaredHome;
    }
    {
      name = "the CA graph is identical on the devenv class";
      expected = caValues declaredNixos;
      actual = caValues declaredDevenv;
    }

    # ---- the declared leaf, and the two exposed paths
    {
      name = "a declared leaf returns the exact option values";
      expected = expectedCert;
      actual = certValues declaredNixos;
    }
    {
      name = "certPath names the committed public certificate under a store path";
      expected = {
        isStorePath = true;
        suffix = "/hosts/den-mvp/certs/den-mvp.pub";
      };
      actual =
        let
          p = toString declaredNixos.kdn.certificates.certs.den-mvp-leaf.certPath;
        in
        {
          isStorePath = lib.hasPrefix builtins.storeDir p;
          suffix = lib.removePrefix (toString repoRoot) p;
        };
    }
    {
      name = "a declared leaf without repoRoot fails loudly when certPath is read";
      expected = false;
      actual = (builtins.tryEval (builtins.isString (toString repoRootMissing))).success;
    }

    # ---- the sops-nix wiring
    {
      name = "the nixos class writes one binary sops secret per declared key";
      expected = {
        format = "binary";
        sopsFileSuffix = "/hosts/den-mvp/certs/den-mvp.key.sops";
      };
      actual = sopsEntry declaredNixos;
    }
    {
      name = "the darwin class writes the same sops secret";
      expected = sopsEntry declaredNixos;
      actual = sopsEntry declaredDarwin;
    }
    {
      name = "the homeManager class writes the same sops secret";
      expected = sopsEntry declaredNixos;
      actual = sopsEntry declaredHome;
    }
    {
      name = "keyPath on nixos reads the sops-nix decrypted path";
      expected = "/run/secrets/kdn/certificates/den-mvp-leaf.key";
      actual = toString declaredNixos.kdn.certificates.certs.den-mvp-leaf.keyPath;
    }
    {
      name = "keyPath on homeManager reads the sops-nix decrypted path";
      expected = "/Users/dev/.config/sops-nix/secrets/kdn/certificates/den-mvp-leaf.key";
      actual = toString declaredHome.kdn.certificates.certs.den-mvp-leaf.keyPath;
    }
    {
      name = "keyPath on devenv falls back to the CLI decrypt path";
      expected = "/run/secrets/kdn/certificates/den-mvp-leaf.key";
      actual = toString declaredDevenv.kdn.certificates.certs.den-mvp-leaf.keyPath;
    }
    {
      name = "the devenv class declares no sops option";
      expected = false;
      actual = declaredDevenv ? sops;
    }
    {
      name = "the default directory reads kdn.hostName";
      expected = "hosts/host-nixos/certs";
      actual =
        (bareNixos (
          aspectsFor "nixos"
          ++ [
            sopsData
            {
              networking.hostName = "host-nixos";
              kdn.certificates.repoRoot = repoRoot;
              kdn.certificates.certs.by-default = {
                ca = "root-ca";
                type = "tls-server";
                commonName = "by-default.example.invalid";
                keySource = "managed";
              };
            }
          ]
        )).config.kdn.certificates.certs.by-default.directory;
    }

    # ---- the library route resolves both aspects on every class they emit
    {
      name = "the library route resolves ca-dag and certificates on all four classes";
      expected = {
        caDag = {
          darwin = 1;
          devenv = 1;
          homeManager = 1;
          nixos = 1;
        };
        certificates = {
          darwin = 1;
          devenv = 1;
          homeManager = 1;
          nixos = 1;
        };
      };
      actual = {
        caDag =
          lib.genAttrs
            [
              "darwin"
              "devenv"
              "homeManager"
              "nixos"
            ]
            (
              class:
              builtins.length (
                denLib.imports {
                  inherit class;
                  aspects = [ "ca-dag" ];
                }
              )
            );
        certificates =
          lib.genAttrs
            [
              "darwin"
              "devenv"
              "homeManager"
              "nixos"
            ]
            (
              class:
              builtins.length (
                denLib.imports {
                  inherit class;
                  aspects = [ "certificates" ];
                }
              )
            );
      };
    }
    {
      name = "denLib.pairs names all four classes of each aspect";
      expected = {
        ca-dag = [
          "darwin"
          "devenv"
          "homeManager"
          "nixos"
        ];
        certificates = [
          "darwin"
          "devenv"
          "homeManager"
          "nixos"
        ];
      };
      actual = {
        ca-dag = sorted denLib.pairs.ca-dag;
        certificates = sorted denLib.pairs.certificates;
      };
    }
  ];
}
