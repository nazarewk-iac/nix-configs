# Local LLM serving on oams — a second llama-swap host beside brys.
#
# oams is a laptop with a 12 GB Radeon RX 6800M (NAVI22), measured 6-9x faster at
# prefill than brys' 8 GB W6600 on the same small models (docs/local-llms.md). The
# small GPU models live here; brys keeps the big CPU/offload models.
#
# This file is deliberately leaner than hosts/brys/llm.nix:
#   - no TLS / Caddy LAN gate and no leaf-key decrypt: the gateway (LiteLLM on
#     etra, task docs/tasks/2026-11/litellm-gateway/) is the single entrypoint and
#     talks to the loopback router;
#   - no Prometheus container on the host: metrics are centralised on etra;
#   - no TPM age identity: oams has no need to decrypt LLM secrets at boot.
#
# What it does own: the slot projection from data/llm.nix, the GPU runtime config
# for the 6800M, the model/session directories (raw disko datasets, not the
# kdn.disks.persist buckets that brys uses), and the serving toggle.
{
  lib,
  pkgs,
  kdnConfig,
  # Which profile of `servers.oams` in data/llm.nix to serve. Only `desktop` exists
  # for now; the argument exists so a future dedicated boot entry can differ.
  profile ? "desktop",
}:
let
  data = import ../../data/llm.nix;
  llm = import ../../lib/llm.nix { inherit lib; };
  srv = data.servers.oams;
in
{
  # The `kdn.llm.local` slot assignments, merged into the host's mkSlots call.
  slot = {
    kdn.llm.local = {
      package = pkgs.kdn.${srv.package};
      defaultThreads = srv.defaultThreads;
      modelsDir = srv.modelsDir;
      download = srv.download;
      apiKeyDir = srv.apiKeyDir;
      sessionStore = srv.sessionStore;
      routers = srv.routers;
      swap = srv.swap;
      models = llm.mkServerModels data "oams" profile;
    };
  };

  # Runtime graphics/ICD config: expose the Mesa RADV ICD and pin llama-cpp to the
  # RX 6800M (1002:73df) so the RENOIR iGPU is never selected. brys pins 1002:73e3
  # (the W6600) — a different device, so do not copy that value.
  gpu = {
    hardware.graphics.enable = true;
    hardware.graphics.extraPackages = [ pkgs.mesa ];
    systemd.services.llama-cpp.environment.MESA_VK_DEVICE_SELECT = "1002:73df!";
  };

  nixos = {
    # Model and session directories are created by the disko datasets (see
    # hosts/oams/disko.nix). disko cannot express ownership/mode, so tmpfiles
    # fixes them up at boot: models world-readable so any user can read them, the
    # session cache 0770 so the llama-cpp DynamicUser can write without world
    # access to plaintext prompt tokens and KV.
    systemd.tmpfiles.rules = [
      "d /var/lib/kdn/llms/models 0755 root root -"
      "d /var/lib/kdn/llms/sessions 0770 root llama-cpp-sessions -"
      "d /var/lib/llm-stats 0755 llm-stats llm-stats -"
    ];

    users.groups.llm-stats = { };
    users.users.llm-stats = {
      isSystemUser = true;
      group = "llm-stats";
      description = "llama-swap statistics collector";
    };

    # Per-request stats, durable. The collector only issues GETs to llama-swap, so
    # it can never load or evict a model.
    systemd.services.llm-stats = {
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

    # The shared fleet secrets file (`llms.nonsensitive.sops.yaml`) is mounted at
    # the same path as on brys; it carries the llama-server API keys. No LLM TLS
    # key on this host — the gateway terminates the client connection.
    kdn.security.secrets.sops.files."llms" = {
      sopsFile = "${kdnConfig.self}/llms.nonsensitive.sops.yaml";
      basePath = "/run/configs/llms";
      sops.mode = "0444";
    };

    # --- GPU serving toggle ----------------------------------------------------
    #
    # oams is a laptop: the GPU must be free for gaming and the battery must be
    # spared. There is no rebuild in any of these paths. The switch has three
    # states, written to /var/lib/kdn/llm/serve-mode and re-read every 30 s and on
    # every `oams-llm` call:
    #
    #   on    serve regardless of battery/gaming (manual override)
    #   off   never serve (manual override)
    #   auto  serve only on AC power AND no gaming scope running
    #
    # `off`/`auto`-tripped stops llama-swap and MASKS it, so nothing can spawn a
    # model. The mask is a runtime symlink to /dev/null, recreated at boot by the
    # oneshot below — it is state, so `serve-mode` and the mask both live under
    # /var/lib (a persistent dataset) and the mode file survives a reboot.
    #
    # Gaming detection reuses the build-farm signal: an `app-steam_app_*` scope on
    # the user bus. Battery detection reads the AC line from sysfs.
    #
    # Why stop rather than just unload the model: with llama-swap running under an
    # active `auto`-off condition, a stray request would load a model and fight the
    # game for VRAM. Stopping the unit removes that.
    systemd.services.kdn-llm-serve = {
      description = "Apply the oams LLM serving on|off|auto state";
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.systemd
      ];
      serviceConfig = {
        Type = "oneshot";
        # Restarted by the `oams-llm` CLI and by the timer; a restart limit would
        # eventually refuse a legitimate run. This is an idempotent writer.
        StartLimitIntervalSec = 0;
        StartLimitBurst = 0;
      };
      environment.GAMING_SCOPES = "app-steam_app_";
      script = ''
        set -eu
        dir=/var/lib/kdn/llm
        install -d -m 0755 "$dir"
        mode=$(cat "$dir/serve-mode" 2>/dev/null || echo auto)

        case "$mode" in
          on) eff=on ;;
          off) eff=off ;;
          *)
            # auto: serve only on AC and with no game running. A missing battery
            # or a failed probe leans to `on` (serve), because a stuck `off` would
            # silently take the whole host out of the fleet.
            eff=on
            # Any battery reporting `discharging` means we are on DC power.
            for bat in /sys/class/power_supply/BAT*; do
              [ -r "$bat/status" ] || continue
              if [ "$(cat "$bat/status")" = "Discharging" ]; then
                eff=off
              fi
            done
            if [ "$eff" = on ]; then
              for uid_dir in /run/user/*; do
                uid="$(basename "$uid_dir")"
                uname="$(id -nu "$uid" 2>/dev/null || true)"
                [ -n "$uname" ] || continue
                running="$(systemctl --machine="$uname@.host" --user --no-pager \
                  list-units --type=scope --state=running --plain 2>/dev/null || true)"
                for prefix in $GAMING_SCOPES; do
                  if printf '%s\n' "$running" | grep -qF -- "$prefix"; then
                    eff=off
                    break 2
                  fi
                done
              done
            fi
            ;;
        esac
        printf '%s\n' "$eff" > "$dir/serve-effective"

        mask=/etc/systemd/system/llama-swap.service
        if [ "$eff" = off ]; then
          systemctl stop llama-swap.service 2>/dev/null || true
          ln -sf /dev/null "$mask"
          systemctl daemon-reload
        else
          rm -f "$mask"
          systemctl daemon-reload
          systemctl start llama-swap.service 2>/dev/null || true
        fi
      '';
    };

    systemd.timers.kdn-llm-serve = {
      description = "Recheck the oams LLM serving auto state";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "30s";
      };
    };

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "oams-llm" ''
        set -eu
        [ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
        dir=/var/lib/kdn/llm
        install -d -m 0755 "$dir"
        show() {
          m=$(cat "$dir/serve-mode" 2>/dev/null || echo auto)
          e=$(cat "$dir/serve-effective" 2>/dev/null || echo unknown)
          if [ "$m" = auto ]; then printf '%s\n' "$e-auto"; else printf '%s\n' "$e"; fi
        }
        case "''${1:-status}" in
          on | off | auto)
            printf '%s\n' "''${1}" > "$dir/serve-mode"
            systemctl restart kdn-llm-serve.service
            ;;
          status)
            show
            exit 0
            ;;
          *)
            echo "usage: oams-llm on|off|auto|status" >&2
            exit 2
            ;;
        esac
      '')
    ];

    # The ZFS ARC cap is shared with brys' tuning file; without it the ARC evicts
    # the mmap'd weights. oams already sets its own ARC cap in default.nix, so do
    # not import the brys tuning file (which also carries brys-only kernel args).
  };
}
