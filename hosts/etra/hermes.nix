# Hermes Agent on etra: one nix-snapshotter container, its state in a declared directory.
#
# Task: docs/tasks/2026-11/ai-workshop/. Package: packages/hermes-agent/.
#
# ## What it is
#
# `hermes` is a Python CLI (a coding/ops agent with a tool shell) plus a messaging
# gateway that keeps persistent memory in its home directory. Both run from one
# container: the gateway is the long-lived process, and `nerdctl exec -it hermes
# hermes` attaches to it (the CLI multiplexes through the running gateway's control
# socket and starts one on demand when none runs).
#
# ## Network shape
#
# etra has no CNI configuration, so the container cannot join a nerdctl bridge (the
# proof container in ./containers.nix uses `--net=none` for the same reason). It runs
# on the host network namespace instead, and the ONE endpoint it needs is a loopback
# relay this file declares:
#
#   hermes container -- 127.0.0.1:9530 --> litellm guest 10.233.100.2:4000
#
# `hosts/etra/litellm.nix` gives the gateway a private veth (10.233.100.1/2) and no
# host TCP listener at all (Caddy reaches it over a unix socket). The relay is bound
# to 127.0.0.1, so nothing off-host reaches the gateway through it, and the model
# URL in `config.yaml` names the relay, not the veth address: a litellm re-address
# is then one line here, not an edit inside the agent's state.
#
# ## State
#
# `/var/lib/kdn/hermes` is the container's `stateDir`: `kdn.containers` mounts it
# inside the container at the same path and exports it as `KDN_STATE_DIR`, and
# `HERMES_HOME` points there, so the agent's home IS the state root. The directory is
# declared in `kdn.disks.persist."sys/state"`, i.e. it is a directory in the ZFS
# dataset `etra-main/etra/impermanence/sys/state`, bind-mounted over the tmpfs root.
# It holds everything that must survive a reboot:
#
#   config.yaml   model/provider selection (seeded once, then owned by the operator)
#   .env          platform tokens written by `hermes gateway setup` (never touched here)
#   litellm.env   `CUSTOM_API_KEY`, derived from the sops client key (managed here)
#   sessions/ state.db memories/ skills/ ...   the agent's own memory and history
#
# To make it its own dataset later, set `stateDataset = { name = "…/sys/state/hermes"; }`
# on the container AND drop the `kdn.disks.persist` entry below: the module then
# creates the dataset with `mountpoint=/var/lib/kdn/hermes` and mounts it before the
# container starts. Keeping both would mount the dataset over the preserved directory
# and hide it.
{
  pkgs,
  ...
}:
let
  hermes = pkgs.callPackage ../../packages/hermes-agent { };

  stateDir = "/var/lib/kdn/hermes";
  # The app's own home. It is the container's `stateDir` (the module mounts that host
  # directory at the same absolute path and exports `KDN_STATE_DIR`), so the whole
  # agent — config, sessions, SQLite state, memories, skills — is one directory.
  containerHome = stateDir;

  # litellm runs as the nspawn container `container@litellm` on a private veth. Its
  # guest address is the only TCP listener the gateway has; see ./litellm.nix.
  litellmGuest = "10.233.100.2";
  litellmPort = 4000;
  # The loopback port the agent talks to. 9530 is the fleet's usual
  # OpenAI-compatible proxy port, so the number is recognisable in a config.
  relayPort = 9530;

  # The fleet frontier: `qfn` is profile-neutral (it asks the engine manager for
  # `auto`, so it never forces a reload), 1M context. `chat-fast` is the two-model
  # fast pool; `chat-std-mid` is the 262k middle. Switch with `hermes config set
  # model.default <name>` or `hermes -m <name>`.
  defaultModel = "qfn";

  # The agent's config. Seeded into the state directory once (see the entrypoint);
  # after that the operator owns it.
  configFile = pkgs.writeText "hermes-config.yaml" ''
    # Written by hosts/etra/hermes.nix when the state directory had no config.yaml.
    # This file is the operator's after that: `hermes config set <key> <value>` or a
    # plain edit both survive a rebuild.
    model:
      # A plain OpenAI-compatible endpoint: `custom` plus a base_url.
      provider: custom
      default: ${defaultModel}
      base_url: http://127.0.0.1:${toString relayPort}/v1
  '';

  # Everything the container's `/bin` holds: the agent, the entrypoint, and the tools
  # its shell tool and this script call. A nix-snapshotter image starts with an empty
  # filesystem, so a command that is not linked here does not exist inside the
  # container — the first failure was `install: command not found`.
  #
  # `buildEnv` merges every `bin/` into one `/bin`, and `env.PATH = "/bin"` makes that
  # the whole PATH. Extend this list when a task needs another tool; keep it a list of
  # packages, not a hand-written script.
  runtimeTools = [
    pkgs.bash
    pkgs.coreutils
    pkgs.findutils
    pkgs.gawk
    pkgs.gnugrep
    pkgs.gnused
    pkgs.gnutar
    pkgs.gzip
    pkgs.jq
    pkgs.less
    pkgs.procps
    pkgs.which
    pkgs.xz
    # The agent's own tools: search, version control, remote workspaces, HTTP.
    pkgs.git
    pkgs.openssh
    pkgs.ripgrep
    pkgs.curl
    # The same interpreter family the venv uses, so `python3 -c ...` in the agent's
    # shell sees the same stdlib version.
    pkgs.python3
  ];

  # Runs inside the container as PID 1. Two jobs: seed a missing config, then decide
  # between the gateway and an idle container.
  #
  # The idle branch exists because `hermes gateway run` with no platform configured
  # is a supported but pointless state (it polls nothing and only keeps the cron
  # scheduler alive). Sleeping keeps the container's memory at a few MB until someone
  # runs `hermes gateway setup` and adds a token.
  entrypoint = pkgs.writeShellScriptBin "hermes-entrypoint" ''
    set -eu
    # Belt and braces: `env.PATH` already points at the image's /bin, but a manual
    # `nerdctl run` without it must still find `install` and `sleep`.
    export PATH="/bin''${PATH:+:$PATH}"

    home="''${HERMES_HOME:-${containerHome}}"
    install -d -m 0700 "$home"

    if [ ! -e "$home/config.yaml" ]; then
      install -m 0600 /etc/hermes/config.yaml "$home/config.yaml"
      echo "hermes: seeded $home/config.yaml"
    fi

    # A token is configured when one of the gateway's platform variables is set, in
    # the process environment or in the profile's .env (which is where
    # `hermes gateway setup` saves it).
    configured() {
      for name in TELEGRAM_BOT_TOKEN DISCORD_BOT_TOKEN SLACK_BOT_TOKEN; do
        if [ -n "''${!name:-}" ]; then return 0; fi
        if [ -f "$home/.env" ] && grep -qE "^''${name}=.+" "$home/.env"; then return 0; fi
      done
      return 1
    }

    if configured; then
      echo "hermes: platform token found, starting the gateway"
      exec ${hermes}/bin/hermes gateway run
    fi

    cat <<'EOF'
    hermes: no messaging platform token configured, so the gateway stays down.
      Set one up with:  nerdctl exec -it hermes hermes gateway setup
      Then restart:     systemctl restart container-hermes
      Use the CLI any time with:  nerdctl exec -it hermes hermes
    EOF
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';

  image = pkgs.nix-snapshotter.buildImage {
    name = "hermes";
    tag = "latest";
    resolvedByNix = true;
    config.Cmd = [ "/bin/hermes-entrypoint" ];
    copyToRoot = pkgs.buildEnv {
      name = "hermes-root";
      pathsToLink = [ "/bin" ];
      paths = [
        entrypoint
        hermes
      ]
      ++ runtimeTools;
    };
  };
in
{
  # The state directory. `sys/state` is the boot-persistent bucket (./litellm.nix uses
  # the same one for its own state); the mode keeps the agent's memory and .env private.
  kdn.disks.persist."sys/state".directories = [
    {
      directory = stateDir;
      mode = "0700";
    }
  ];

  kdn.containers.containers.hermes = {
    inherit image;
    cmd = [ "/bin/hermes-entrypoint" ];
    # The state root, spelled out rather than left to the module's `/var/lib/kdn/<name>`
    # default: this path is the backup contract and must not move when a container is
    # renamed. The module mounts it inside the container at the same path and exports
    # it as `KDN_STATE_DIR`.
    inherit stateDir;
    env = {
      HERMES_HOME = containerHome;
      # The gateway binds its control socket and writes logs under HERMES_HOME; the
      # rest of the container filesystem is throwaway.
      HOME = "/root";
      # One merged `/bin` holds every tool (see `runtimeTools`); nothing else exists.
      PATH = "/bin";
    };
    extraArgs = [
      # No CNI on this host (see the module header): share the host's network
      # namespace. The only endpoint the agent needs is the loopback relay below.
      "--net=host"
      # `CUSTOM_API_KEY`, written at boot from the sops client key. An env FILE, not
      # `env`, because a value in `env` would be rendered into the systemd unit and
      # therefore into the Nix store.
      "--env-file"
      "${stateDir}/litellm.env"
      # The default config, read-only from the store; the entrypoint copies it into
      # the state directory when that has none.
      "-v"
      "${configFile}:/etc/hermes/config.yaml:ro"
    ];
  };

  # --- model access -----------------------------------------------------------
  #
  # A loopback relay to the LiteLLM guest. Bound to 127.0.0.1: only local processes
  # (the agent container on the host network) reach it.
  systemd.services.hermes-litellm-relay = {
    description = "Relay the Hermes Agent container to the LiteLLM guest";
    wantedBy = [ "multi-user.target" ];
    after = [ "container@litellm.service" ];
    wants = [ "container@litellm.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat -d TCP-LISTEN:${toString relayPort},bind=127.0.0.1,fork,reuseaddr,connect-timeout=5 TCP:${litellmGuest}:${toString litellmPort}";
      Restart = "always";
      RestartSec = 3;
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
    };
  };

  # --- the API key ------------------------------------------------------------
  #
  # The gateway authenticates with the sops-managed client key
  # (`/run/configs/llms/litellm/client-key`, mounted into the LiteLLM container as
  # `/etc/litellm-master-key`'s sibling). Hermes reads `CUSTOM_API_KEY` from the
  # process environment, so this unit renders it into an env file in the state
  # directory — never into the store, never into the repository.
  #
  # It writes `litellm.env` only: `.env` belongs to `hermes gateway setup` (platform
  # tokens), and rewriting that file would delete them.
  systemd.services.hermes-env = {
    description = "Render the Hermes Agent CUSTOM_API_KEY from the sops LiteLLM client key";
    wantedBy = [ "multi-user.target" ];
    before = [ "container-hermes.service" ];
    requiredBy = [ "container-hermes.service" ];
    after = [ "sops-install-secrets.service" ];
    wants = [ "sops-install-secrets.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # A key rotation is a `systemctl restart hermes-env` plus a container restart;
      # the oneshot must stay cheap and idempotent.
      StartLimitIntervalSec = 0;
      StartLimitBurst = 0;
    };
    script = ''
      set -eu
      install -d -m 0700 ${stateDir}
      keyFile=/run/configs/llms/litellm/client-key
      target=${stateDir}/litellm.env
      tmp="$target.tmp"

      if [ -s "$keyFile" ]; then
        printf 'CUSTOM_API_KEY=%s\n' "$(cat "$keyFile")" > "$tmp"
      else
        # A comment-only env file still parses, so the container starts and fails
        # with a 401 instead of refusing to run.
        printf '# %s was absent; no CUSTOM_API_KEY\n' "$keyFile" > "$tmp"
      fi
      chmod 0600 "$tmp"
      mv "$tmp" "$target"
    '';
  };

  # The container mounts the state directory, so it must not start before the sops
  # file (and therefore the env file) exists.
  systemd.services."container-hermes" = {
    after = [ "sops-install-secrets.service" ];
    wants = [ "sops-install-secrets.service" ];
  };
}
