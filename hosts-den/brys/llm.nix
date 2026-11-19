# Shared LLM serving configuration for brys.
#
# Two consumers share it: the main host (hosts-den/brys/default.nix), which also runs a
# desktop, and the single appliance entry (hosts-den/brys/llms-frontier.nix, booted as
# `specialisation.llms`), which gives the box to the models. This file owns that shared
# wiring so the two cannot drift: the slot assignments, the LLM secrets, the leaf-key
# service, the model persistence directory and the ZFS ARC cap all live here.
#
# The model data itself — which models exist, their alias map, what each host serves and
# which router it lands on — lives in `data/llm.nix`. This file only projects it into
# `kdn.llm.local` and adds the few values that need `pkgs`/`self` (the package, the TLS
# cert path). See docs/tasks/2026-11/fleet-llm-data-model/.
#
# The two consumers differ only in the boot PROFILE (`profile`): `desktop` shares RAM with a
# browser, so DeepSeek serves 128K; `appliance` owns the box and serves 320K. The profile is
# a value in `data/llm.nix` (`servers.brys.profiles`), not a knob here.
{
  lib,
  pkgs,
  kdnConfig,
  # The boot profile to serve: `desktop` or `appliance`. It selects `servers.brys.profiles.<p>`
  # from `data/llm.nix`, which decides the served router set and the per-profile served context.
  profile,
  # The build-farm `agent-check` curve (see `kdn-build-farm-agent`). Absolute free memory, in GiB:
  # at or above `fullFreeGiB` brys takes full build capacity; at or below `oneFreeGiB` it takes a
  # single build; in between it scales linearly. A build's own peak is a few GiB whatever the box
  # size, so an absolute reserve is the honest unit. `maxSlots` is the full-capacity `maxconn`.
  buildProbe ? {
    fullFreeGiB = 30;
    oneFreeGiB = 3;
    maxSlots = 12;
  },
}:
let
  # The single LLM source of truth and its projections.
  data = import ../../data/llm.nix;
  llm = import ../../lib/llm.nix { inherit lib; };
  srv = data.servers.brys;

  # brys always runs llama-swap on the matrix engine and always exports the R9700 Vulkan runtime.
  # These were `withSwap` / (`qwenVulkan || withGrunt || withSurveyed`) flags; the shipping host
  # fixed them, so they are constants here and every `lib.mkIf` below stays truthful.
  withSwap = true;
  withGpu = true;
in
{
  # The `kdn.llm.local.*` slot assignments. Merge this into the host's own `mkSlots` call: a
  # second `mkSlots` call would collide on the read-only `slots` option.
  slot = {
    kdn.llm.local = {
      # The host maps the data's package key to a `pkgs` attr; this keeps `pkgs` out of the data.
      package = pkgs.kdn.${srv.package};
      defaultThreads = srv.defaultThreads;
      modelsDir = srv.modelsDir;
      download = srv.download;
      apiKeyDir = srv.apiKeyDir;
      sessionStore = srv.sessionStore;
      routers = srv.routers;
      swap = srv.swap;

      # The routed model set for this boot profile, projected from the data.
      models = llm.mkServerModels data "brys" profile;
    };
  };

  # Runtime graphics/ICD config for the R9700 Vulkan path: expose the Mesa RADV Vulkan ICD to the
  # loader and pin the llama-cpp process tree to the R9700 (`1002:7551`) so the 4 GB Lexa
  # (`Vulkan1`) is never selected. The `device = Vulkan0` preset key is the in-process belt.
  gpu = lib.optionalAttrs withGpu {
    hardware.graphics.enable = true;
    hardware.graphics.extraPackages = [ pkgs.mesa ];
    systemd.services.llama-cpp.environment.MESA_VK_DEVICE_SELECT = "1002:7551!";
  };

  # The NixOS-side LLM configuration. Import this as a module. It owns the
  # secrets, the leaf-key service, the model persistence directory and the ZFS
  # ARC cap.
  nixos = {
    # Keep local LLM models on the persistent usr/data dataset.
    kdn.disks.persist."usr/data".directories = [
      {
        directory = "/var/lib/kdn/llms/models";
        # World-readable so any user (and the llama-cpp DynamicUser) can read
        # the models; the download script keeps files 644 / dirs 755.
        mode = "0755";
      }
      {
        # HOME for the `llm-server` account that runs Strata and llama-swap. Same dataset as the
        # models, so a second machine can share the whole LLM tree by mounting it.
        directory = "/var/lib/kdn/llms/home";
        mode = "0750";
        user = "llm-server";
        group = "llm-server";
      }
    ];

    # Keep the llama-server session cache on the persistent usr/cache dataset.
    # Mode 0770 with the llama-cpp-sessions group: the llama-cpp DynamicUser
    # joins that group (the slot wires it), so the persisted directory stays
    # writable without world access. A session file holds plaintext prompt
    # tokens and KV, so it must not be world-readable.
    kdn.disks.persist."usr/cache".directories = [
      {
        directory = "/var/lib/kdn/llms/sessions";
        mode = "0770";
        group = "llama-cpp-sessions";
      }
    ];

    # --- Observability: per-request stats, durable -----------------------------
    #
    # llama-swap keeps its per-request performance in a ring buffer (25 records,
    # measured), so it survives neither a burst nor a restart. `llm-stats` polls
    # that ring every two seconds and appends one JSONL line per request, then
    # rewrites a Prometheus textfile. It only issues GETs: it never loads, evicts or
    # unloads a model, so it cannot disturb the fleet.
    #
    # /var/lib/llm-stats must survive a boot. brys has a tmpfs root, so an unlisted
    # path is a tmpfs directory and every sample dies at reboot; the `disposable`
    # bucket is rolled back, so it is not a home either. `sys/state` is the right
    # bucket. Mode 0755 because node_exporter (a different user) must read the
    # textfile, and the data is model ids and timings, never request bodies.
    kdn.disks.persist."sys/state".directories = [
      {
        directory = "/var/lib/llm-stats";
        mode = "0755";
        user = "llm-stats";
        group = "llm-stats";
      }
      {
        directory = "/var/lib/prometheus2";
        mode = "0750";
        user = "prometheus";
        group = "prometheus";
      }
      # The TPM age identity blob. This is now the ONLY unattended decryptor at boot: the
      # SSH host key is itself a sops secret, so its generator cannot help before the
      # decrypt, and no YubiKey is present. A tmpfs copy here would vanish at reboot and
      # take `sops-install-secrets` and sshd with it. 0700, root-only.
      {
        directory = "/var/lib/sops-tpm";
        mode = "0700";
      }
    ];

    # The container's writable root (`/var/lib/nixos-containers/<name>`): rebuilt
    # data, not state. `sys/cache` is the right bucket, and it keeps the container
    # from writing into a tmpfs root.
    kdn.disks.persist."sys/cache".directories = [
      {
        directory = "/var/lib/nixos-containers";
        mode = "0755";
      }
    ];

    users.groups.llm-stats = { };

    users.users.llm-stats = {
      isSystemUser = true;
      group = "llm-stats";
      description = "llama-swap statistics collector";
    };

    systemd.services.llm-stats = lib.mkIf withSwap {
      description = "Collect llama-swap per-request performance into JSONL";
      wantedBy = [ "multi-user.target" ];
      wants = [ "llama-swap.service" ];
      after = [ "llama-swap.service" ];
      serviceConfig = {
        User = "llm-stats";
        Group = "llm-stats";
        StateDirectory = "llm-stats";
        StateDirectoryMode = "0755";
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.kdn.llm-stats}/bin/llm-stats"
          "collect"
          "--state-dir /var/lib/llm-stats"
          "--prom-textfile /var/lib/llm-stats/llamaswap.prom"
          "--interval 2"
        ];
        Restart = "always";
        RestartSec = 5;
        # A collector that can write anywhere is a liability; it needs one directory and a socket.
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
      };
    };

    # --- A small Prometheus, confined in a NixOS container ---------------------
    #
    # Deliberately not `kdn.monitoring-prometheus-stack`: that aspect also brings
    # Grafana, a secret key and a Caddy vhost, and this is one scrape target pair on
    # a box that must give its RAM to the models.
    #
    # Prometheus runs in its own NixOS container rather than on the host, because it
    # is the least trusted thing on this box: it parses untrusted text from two HTTP
    # endpoints and writes an unbounded directory. The container gives it its own
    # filesystem, process table and network namespace, so a bug there cannot touch
    # the models, the session cache or the secrets.
    #
    # Network: `privateNetwork = true`, so the container sees only its veth to the
    # host. llama-swap and node_exporter stay bound to 127.0.0.1, so two socat relays
    # expose exactly two ports on the container bridge address and nothing else.
    # This is the confinement pattern to copy: the guest gets a narrow ingress, not
    # a shared host network.
    containers.prometheus = lib.mkIf withSwap {
      autoStart = true;
      restartIfChanged = true;
      privateNetwork = true;
      hostAddress = "10.233.90.1";
      localAddress = "10.233.90.2";
      # The TSDB lives on the host, in the persistent state bucket, and is bind
      # mounted in. Metrics are state, not cache: they must survive a reboot.
      bindMounts."/var/lib/prometheus2" = {
        hostPath = "/var/lib/prometheus2";
        isReadOnly = false;
      };
      config = { pkgs, ... }: {
        # The guest's own firewall, which is a second `policy drop` input chain. Only
        # node_exporter's traffic and the host's scrapes need to reach it; nothing else
        # in the network namespace is exposed. The host reaches the guest for queries and
        # so the acceptance test can ask the guest for its own target health.
        networking.firewall = {
          enable = true;
          allowedTCPPorts = [ 9090 ];
        };

        services.prometheus = {
          enable = true;
          listenAddress = "0.0.0.0";
          port = 9090;
          retentionTime = "30d";
          extraFlags = [ "--storage.tsdb.retention.size=2GB" ];
          scrapeConfigs = [
            {
              job_name = "llama-swap";
              scrape_interval = "15s";
              static_configs = [ { targets = [ "10.233.90.1:39700" ]; } ];
            }
            {
              job_name = "node";
              scrape_interval = "30s";
              static_configs = [ { targets = [ "10.233.90.1:9100" ]; } ];
            }
          ];
        };
        # Inside the container the TSDB is a private path; the bind mount makes it
        # the host's persistent directory. Keep the same directory name so a reader
        # of either config sees one path.
        system.stateVersion = "26.05";
        users.users.prometheus.group = "prometheus";
      };
    };

    # The two narrow relays. `bind=` keeps each listener on the container bridge
    # address, so these two ports are reachable from the guest and from nowhere
    # else. This is the pattern to copy for a containerised service: a narrow
    # ingress, never a shared host network.
    systemd.services."llm-metrics-relay-swap" = lib.mkIf withSwap {
      description = "Relay llama-swap /metrics to the prometheus container bridge";
      wantedBy = [ "multi-user.target" ];
      after = [ "llama-swap.service" ];
      wants = [ "llama-swap.service" ];
      serviceConfig = {
        ExecStart = "${pkgs.socat}/bin/socat -d TCP-LISTEN:39700,bind=10.233.90.1,fork,reuseaddr TCP:127.0.0.1:39700";
        Restart = "always";
        RestartSec = 3;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        DynamicUser = true;
      };
    };

    # Expose llama-swap to the NetBird mesh so etra's LiteLLM gateway can reach it.
    # llama-swap binds 127.0.0.1:39700 (loopback) and 10.233.90.1:39700 (the prometheus
    # relay below); neither is reachable from the mesh. This narrow relay listens on
    # 39704 (a distinct port, so no clash with either) and the firewall only opens it on
    # `nb-priv`, so it is mesh-only. Litellm on etra points at <brys-netbird>:39704.
    networking.firewall.interfaces."nb-priv".allowedTCPPorts = lib.mkIf withSwap [ 39704 ];
    systemd.services."llm-netbird-relay-swap" = lib.mkIf withSwap {
      description = "Relay llama-swap /v1 to the NetBird mesh (for the etra LiteLLM gateway)";
      wantedBy = [ "multi-user.target" ];
      after = [ "llama-swap.service" ];
      wants = [ "llama-swap.service" ];
      serviceConfig = {
        ExecStart = "${pkgs.socat}/bin/socat -d TCP-LISTEN:39704,bind=0.0.0.0,fork,reuseaddr TCP:127.0.0.1:39700";
        Restart = "always";
        RestartSec = 3;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        DynamicUser = true;
      };
    };

    # The build-farm `agent-check` responder. HAProxy on `etra` cannot see llama-swap (39700 is
    # loopback-only) or prometheus (its container is confined), so this host answers a one-line
    # verdict on a port the proxy can reach: `ready` when ample RAM is free, `drain` when a frontier
    # model is resident. `MemAvailable` is the honest signal — `llamaswap_memory_used_bytes` follows
    # host page cache and does not fall when a model unloads (measured 2026-10-30).
    #
    # A frontier residency costs about 14 GiB (measured), so `drain` starts well before the box is
    # starved.
    systemd.services."kdn-build-farm-agent" = lib.mkIf withSwap {
      description = "Answer HAProxy agent-check with the LLM RAM state";
      wantedBy = [ "multi-user.target" ];
      after = [ "prometheus.service" ];
      wants = [ "prometheus.service" ];
      path = [
        pkgs.curl
        pkgs.gawk # MemTotal from /proc/meminfo
        pkgs.gnugrep
        pkgs.coreutils
        pkgs.socat
      ];
      serviceConfig = {
        # `socat` runs one script per agent-check connection and prints its one-word answer. It binds
        # 0.0.0.0 and the firewall restricts it to the LAN and mesh, because HAProxy on `etra` must
        # reach it and the internal bridge address is not routable off-host.
        ExecStart = "${pkgs.socat}/bin/socat -d TCP-LISTEN:39701,fork,reuseaddr SYSTEM:${
          pkgs.writeShellApplication {
            name = "kdn-build-farm-agent";
            text = ''
              # The gauge is the second element of `data.result[0].value`.
              # Fail OPEN: a prometheus hiccup must not silently stop every build on the farm, so an
              # unreadable gauge answers `ready`. The hazard it guards (builds competing with a
              # resident model) only exists when the host is genuinely loaded, and then it is readable.
              set +o pipefail +o errexit
              raw=$(curl -sS --max-time 3 "http://10.233.90.2:9090/api/v1/query?query=node_memory_MemAvailable_bytes" 2>/dev/null || true)
              avail=$(printf '%s' "$raw" | sed -E 's/.*,"([0-9.e+]+)"\]\}\].*/\1/' | cut -d. -f1)
              case "$avail" in
                [0-9]*) ;;
                *) printf 'ready\n'; exit 0 ;;
              esac
              # Curve on ABSOLUTE free memory, not a percentage: what matters is whether a build
              # plus the resident model still fits, and a build peak is a few GiB whatever the box
              # size. At or above FULL_GIB free brys takes full capacity; at or below ONE_GIB free it
              # takes a single build; in between it scales linearly. Tunable per host if needed.
              full_gib=${toString buildProbe.fullFreeGiB}
              one_gib=${toString buildProbe.oneFreeGiB}
              max_slots=${toString buildProbe.maxSlots}
              free_gib=$((avail / 1024 / 1024 / 1024))
              if [ "$free_gib" -ge "$full_gib" ]; then
                slots=$max_slots
              elif [ "$free_gib" -le "$one_gib" ]; then
                slots=1
              else
                # Linear between the two anchors: (free - one) / (full - one).
                slots=$(( 1 + (max_slots - 1) * (free_gib - one_gib) / (full_gib - one_gib) ))
              fi
              # The pool uses `balance first`, and the HAProxy manual states `first` "ignores the
              # server weight", so only `maxconn` is reported: it moves the spill point, and since
              # the x86 pool holds brys alone a lower `maxconn` means fewer concurrent builds.
              #
              # `ready` is NOT optional. The manual is explicit: "only the agent may revert its own
              # actions, so if a server is set to DRAIN … the agent must implement the … actions to
              # bring the service into operations again." A bare `maxconn:12` never clears a DRAIN
              # the agent set earlier, so the server would stay drained forever after one busy
              # period. Emitting `ready` every time is the fix; `maxconn` then shapes the curve.
              printf 'ready maxconn:%s\n' "$slots"
            '';
          }
        }/bin/kdn-build-farm-agent";
        Restart = "always";
        RestartSec = 3;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RestrictAddressFamilies = [ "AF_INET" ];
        DynamicUser = true;
      };
    };

    systemd.services."llm-metrics-relay-node" = lib.mkIf withSwap {
      description = "Relay node-exporter metrics to the prometheus container bridge";
      wantedBy = [ "multi-user.target" ];
      after = [ "prometheus-node-exporter.service" ];
      wants = [ "prometheus-node-exporter.service" ];
      serviceConfig = {
        ExecStart = "${pkgs.socat}/bin/socat -d TCP-LISTEN:9100,bind=10.233.90.1,fork,reuseaddr TCP:127.0.0.1:9100";
        Restart = "always";
        RestartSec = 3;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        DynamicUser = true;
      };
    };

    # The nixpkgs container module exposes no `unitConfig`, so the ordering goes on the
    # generated unit directly. `container@prometheus` sorts before `nftables.service`,
    # so without this the guest boots before the firewall rule that lets it reach the
    # relays: the bridge address then answers from the host but not from inside the
    # guest. The interface rule below is the other half of the fix.
    systemd.services."container@prometheus" = lib.mkIf withSwap {
      after = [
        "nftables.service"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
    };

    # The guest must reach the two relays across the veth. The `nixos-fw` input chain
    # has `policy drop` and trusts only `lo`, `virbr*` and NetBird; a veth is none of
    # them. Open exactly the two relay ports, on that interface only.
    networking.firewall.interfaces."ve-prometheus".allowedTCPPorts = lib.mkIf withSwap [
      9100
      39700
    ];

    services.prometheus.exporters.node = lib.mkIf withSwap {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9100;
      # `textfile` picks up /var/lib/llm-stats/llamaswap.prom; the rest of the
      # default collector set is dropped so the exporter stays small.
      enabledCollectors = [
        "textfile"
      ];
      extraFlags = [ "--collector.textfile.directory=/var/lib/llm-stats" ];
    };

    # Shared /run/configs/llms secrets: HF token and llama-server API keys.
    # Decrypted to their full sops key paths under /run/configs/llms/. Shared
    # with the oams host (same mount point).
    kdn.security.secrets.sops.files."llms" = {
      sopsFile = "${kdnConfig.self}/llms.nonsensitive.sops.yaml";
      basePath = "/run/configs/llms";
      sops.mode = "0444";
    };

    # Raw-decrypt the brys LLM leaf PRIVATE key from hosts-den/brys/certs/llm.key.sops
    # into /run/secrets (root-only tmpfs) before Caddy starts. The pub cert
    # is referenced directly from the store (no decryption). Caddy loads the key
    # via LoadCredential (see the llm slot's caddy wiring).
    #
    # `sops decrypt` looks for an identity at `$HOME/.ssh/id_*` and brys' root home has none, so
    # this unit needs one passed explicitly. `SOPS_AGE_SSH_PRIVATE_KEY_FILE` is silently ignored by
    # sops 3.13.3 (measured: still "failed to get the data key"); `SOPS_AGE_KEY_CMD` works. It gets
    # a wrapper script rather than an inline command because systemd splits `Environment=` values
    # on spaces, which truncates `ssh-to-age -i … -private-key` to the binary path alone.
    systemd.services.kdn-llm-leaf-key = {
      description = "Decrypt brys LLM leaf private key into /run/secrets";
      wantedBy = [ "caddy.service" ];
      before = [ "caddy.service" ];
      path = [
        pkgs.sops
        pkgs.coreutils
      ];
      environment.SOPS_AGE_KEY_CMD = pkgs.writeShellScript "brys-sops-age-identity" ''
        exec ${pkgs.ssh-to-age}/bin/ssh-to-age -i /etc/ssh/ssh_host_ed25519_key -private-key
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        Group = "root";
      };
      script = ''
        set -euo pipefail
        mkdir -p /run/secrets/kdn/brys
        ${pkgs.sops}/bin/sops decrypt --output-type binary \
          ${kdnConfig.self}/hosts-den/brys/certs/llm.key.sops \
          > /run/secrets/kdn/brys/llm.key
        chmod 0400 /run/secrets/kdn/brys/llm.key
      '';
    };

    # The LLM tuning both consumers share: the ZFS ARC cap (without it the ARC
    # evicts the mmap'd weights and every request re-reads them from disk),
    # `transparent_hugepage=madvise` and `numa_balancing=disable`. See
    # ./llm-tuning-shared.nix for the measured numbers and for why the core
    # reservation stayed out of it.
    imports = [ ./llm-tuning-shared.nix ];
  };
}
