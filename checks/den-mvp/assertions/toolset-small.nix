# The assertion set of batch 5: the `toolset`, `packaging`, `emulation`, `outputs` and `monitoring`
# areas.
#
# It reads back one measured value per port decision. Every consumer below is bare: it names the
# leaf aspects only, so an `includes` edge must supply `toolset-tracing`, `toolset-fs-encryption`,
# `toolset-network`, `toolset-essentials` and `apps`.
#
# The caller supplies the bare consumers. `checks/den-mvp/harness.nix` exports them.
{
  lib,
  denLib,
  bareNixos,
  bareDarwinSystem,
  bareHomeConfiguration,
  ...
}:
let
  # The leaf aspects a host names. Each list leaves out every included aspect on purpose.
  nixosAspects = [
    "monitoring-prometheus-stack"
    "outputs-host"
    "packaging-asdf"
    "toolset-fs"
    "toolset-logs-processing"
    "toolset-mikrotik"
    "toolset-network-gui"
    "toolset-nix"
    "toolset-unix"
  ];

  darwinAspects = [
    "packaging-asdf"
    "toolset-fs"
    "toolset-logs-processing"
    "toolset-mikrotik"
    "toolset-network-gui"
    "toolset-unix"
  ];

  homeAspects = [
    "apps"
    "emulation-wine"
    "packaging-asdf"
    "toolset-diagrams"
    "toolset-fs"
    "toolset-logs-processing"
    "toolset-mikrotik"
    "toolset-network-gui"
    "toolset-nix"
    "toolset-unix"
  ];

  nixosModules = denLib.imports {
    class = "nixos";
    aspects = nixosAspects;
  };

  nixosPlain = (bareNixos nixosModules).config;

  # One consumer that sets every option of the two host aspects.
  nixosTuned =
    (bareNixos (
      nixosModules
      ++ [
        {
          kdn.monitoring.prometheus-stack.caddy.grafana = "grafana.example.com";
          kdn.monitoring.prometheus-stack.pushgateway.use = true;
          kdn.monitoring.prometheus-stack.retentionSize = "1GB";
          kdn.outputs.host.luksVolumes = [
            {
              name = "main";
              keyFile = "/var/lib/secrets/main.key";
              cryptsetupName = "main-crypted";
              headerPath = "/dev/disk/by-partlabel/main-header";
            }
          ];
        }
      ]
    )).config;

  darwinPlain =
    (bareDarwinSystem (
      denLib.imports {
        class = "darwin";
        aspects = darwinAspects;
      }
    )).config;

  homePlain =
    (bareHomeConfiguration (
      denLib.imports {
        class = "homeManager";
        aspects = homeAspects;
      }
    )).config;

  has = name: packages: lib.elem name (map lib.getName packages);
in
[
  # ---- `toolset`, the `includes` edges, nixos class
  {
    name = "an includes edge supplies tracing, encryption and the network base to a nixos consumer";
    expected = {
      bcc = true;
      bpftrace = true;
      cryptsetup = true;
      nftables = true;
      wireshark = true;
    };
    actual = {
      bcc = nixosPlain.programs.bcc.enable;
      bpftrace = has "bpftrace" nixosPlain.environment.systemPackages;
      cryptsetup = has "cryptsetup" nixosPlain.environment.systemPackages;
      nftables = has "nftables" nixosPlain.environment.systemPackages;
      wireshark = nixosPlain.programs.wireshark.enable;
    };
  }

  # ---- `toolset`, the two shell hooks, nixos class
  {
    name = "the nix group and the asdf aspect each write one nixos shell hook";
    expected = {
      fish = "complete -c kdn-nix-which --wraps which\n";
      shims = true;
    };
    actual = {
      fish = nixosPlain.programs.fish.interactiveShellInit;
      shims = lib.hasInfix ".asdf/shims" nixosPlain.environment.interactiveShellInit;
    };
  }

  # ---- `toolset`, the relative callPackage, nixos class
  {
    name = "a nixos consumer gets the three packages of this repository with no overlay";
    expected = {
      systemdCryptsetup = true;
      whicher = true;
      zfsDecrypt = true;
    };
    actual = {
      systemdCryptsetup = has "systemd-cryptsetup" nixosPlain.environment.systemPackages;
      whicher = has "whicher" nixosPlain.environment.systemPackages;
      zfsDecrypt = has "kdn-systemd-zfs-decrypt" nixosPlain.environment.systemPackages;
    };
  }

  # ---- `monitoring`, the defaults, nixos class
  {
    name = "a bare nixos consumer gets the whole prometheus and grafana opinion of the aspect";
    expected = {
      grafanaAddr = "127.0.0.1";
      grafanaDomain = "grafana.localhost";
      grafanaPort = 2342;
      prometheusFlags = [ "--storage.tsdb.retention.size=5GB" ];
      prometheusPort = 9090;
      pushgateway = false;
      retentionTime = "90d";
      secretKey = "$__file{/var/lib/grafana/secret-key}";
    };
    actual = {
      grafanaAddr = nixosPlain.services.grafana.settings.server.addr;
      grafanaDomain = nixosPlain.services.grafana.settings.server.domain;
      grafanaPort = nixosPlain.services.grafana.settings.server.port;
      prometheusFlags = nixosPlain.services.prometheus.extraFlags;
      prometheusPort = nixosPlain.services.prometheus.port;
      pushgateway = nixosPlain.services.prometheus.pushgateway.enable;
      retentionTime = nixosPlain.services.prometheus.retentionTime;
      secretKey = nixosPlain.services.grafana.settings.security.secret_key;
    };
  }

  # ---- `monitoring`, the renamed flag, nixos class
  {
    name = "the pushgateway use flag replaces the old nested enable, and the caddy host follows";
    expected = {
      caddyHosts = [ "grafana.example.com" ];
      grafanaDomain = "grafana.example.com";
      prometheusFlags = [ "--storage.tsdb.retention.size=1GB" ];
      pushgateway = true;
      pushgatewayListen = "127.0.0.1:9091";
    };
    actual = {
      caddyHosts = builtins.attrNames nixosTuned.services.caddy.virtualHosts;
      grafanaDomain = nixosTuned.services.grafana.settings.server.domain;
      prometheusFlags = nixosTuned.services.prometheus.extraFlags;
      pushgateway = nixosTuned.services.prometheus.pushgateway.enable;
      pushgatewayListen = nixosTuned.services.prometheus.pushgateway.web.listen-address;
    };
  }

  # ---- `outputs`, the host contract, nixos class
  {
    name = "the luks volume list defaults to empty and keeps the four key names a host tool reads";
    expected = {
      plain = [ ];
      tuned = [
        {
          cryptsetupName = "main-crypted";
          headerPath = "/dev/disk/by-partlabel/main-header";
          keyFile = "/var/lib/secrets/main.key";
          name = "main";
        }
      ];
    };
    actual = {
      plain = nixosPlain.kdn.outputs.host.luksVolumes;
      tuned = nixosTuned.kdn.outputs.host.luksVolumes;
    };
  }

  # ---- the nixos force
  {
    name = "the nine leaf aspects of the nixos class build one toplevel derivation";
    expected = true;
    actual = lib.isString nixosPlain.system.build.toplevel.drvPath;
  }

  # ---- `toolset`, darwin class
  {
    name = "a darwin consumer keeps every cross-platform tool and drops every linux-only one";
    expected = {
      bpftrace = false;
      cryptsetup = false;
      inotifyTools = false;
      ncdu = true;
      nftables = false;
      whicher = true;
      wiresharkQt = true;
    };
    actual = {
      bpftrace = has "bpftrace" darwinPlain.environment.systemPackages;
      cryptsetup = has "cryptsetup" darwinPlain.environment.systemPackages;
      inotifyTools = has "inotify-tools" darwinPlain.environment.systemPackages;
      ncdu = has "ncdu" darwinPlain.environment.systemPackages;
      nftables = has "nftables" darwinPlain.environment.systemPackages;
      whicher = has "whicher" darwinPlain.environment.systemPackages;
      wiresharkQt = has "wireshark-qt" darwinPlain.environment.systemPackages;
    };
  }

  # ---- the darwin force
  {
    name = "the six leaf aspects of the darwin class build one toplevel derivation";
    expected = true;
    actual = lib.isString darwinPlain.system.build.toplevel.drvPath;
  }

  # ---- `toolset`, the home opinion
  {
    name = "the fs group and the essentials group each keep their home opinion";
    expected = {
      difftastic = true;
      difftasticBackground = "dark";
      superfileTheme = "dracula";
      yazi = true;
      yaziWrapper = "y";
      zoxide = true;
    };
    actual = {
      difftastic = homePlain.programs.difftastic.enable;
      difftasticBackground = homePlain.programs.difftastic.options.background;
      superfileTheme = homePlain.programs.superfile.settings.theme;
      yazi = homePlain.programs.yazi.enable;
      yaziWrapper = homePlain.programs.yazi.shellWrapperName;
      zoxide = homePlain.programs.zoxide.enable;
    };
  }

  # ---- `toolset` and `emulation`, the `apps` entries
  {
    name = "three aspects write four application entries, and wine stays out of a non-x86 home";
    expected = {
      appNames = [
        "lnav"
        "winbox4"
      ];
      lnavConfig = [ ".config/lnav" ];
      winboxData = [ ".local/share/MikroTik/WinBox" ];
    };
    actual = {
      appNames = builtins.attrNames homePlain.kdn.apps;
      lnavConfig = homePlain.kdn.apps.lnav.dirs.config;
      winboxData = homePlain.kdn.apps.winbox4.dirs.data;
    };
  }

  # ---- `packaging`, the home hooks
  {
    name = "the asdf aspect adds one home activation entry and one fish path line";
    expected = {
      activation = true;
      fishPath = true;
      package = "asdf-vm";
    };
    actual = {
      activation = homePlain.home.activation ? asdfReshim;
      fishPath = lib.hasInfix ".asdf/shims" homePlain.programs.fish.interactiveShellInit;
      package = lib.getName homePlain.kdn.packaging.asdf.package;
    };
  }

  # ---- `toolset`, the home lists
  {
    name = "a home consumer gets the diagram group, the nix group and the repository's own tool";
    expected = {
      drawio = true;
      kdnNix = true;
      mermaid = true;
      plantuml = true;
    };
    actual = {
      drawio = has "drawio" homePlain.home.packages;
      kdnNix = has "kdn-nix" homePlain.home.packages;
      mermaid = has "mermaid-cli" homePlain.home.packages;
      plantuml = has "plantuml" homePlain.home.packages;
    };
  }

  # ---- the home force
  {
    name = "the ten leaf aspects of the homeManager class build one activation derivation";
    expected = true;
    actual = lib.isString homePlain.home.activationPackage.drvPath;
  }
]
