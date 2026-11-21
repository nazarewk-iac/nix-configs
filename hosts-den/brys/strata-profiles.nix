# The account that runs the local LLM stack on brys.
#
# Why a dedicated account: Strata refuses files that another user owns ("not allowed to open one of
# its own files"), so it must run as the owner of its data tree. It also must not run as a human
# account: the engine pins tens of GB and holds the GPU.
#
# `max-multi` is the primary and resting profile, by decision of 2026-11-21: a swarm of six 512k
# slots on the best pack (UD-IQ4_XS). It overrides the earlier decision of the same day ("`max`, one
# 1M session, is the primary"), because an agent fleet asks for several short sessions far more
# often than for one million-token one; 1M is now an explicit request (`max-long`). Measured
# 2026-11-21: 6 slots x 512k, 28.7 GiB of pinned K/V, 6.6 GiB of MemAvailable, 30.7 t/s aggregate.
#
# The three siblings exist because the card cannot be everything at once:
#
#   max-multi    UD-IQ4_XS, 512k x 6   6.6 GiB free  30.7 t/s  the resting profile
#   max-swarm    UD-IQ4_XS, 256k x 8  18.4 GiB free  36.2 t/s  the same slots with RAM to spare
#   max-long     UD-IQ4_XS,   1M x 2  10.5 GiB free  29.7 t/s  one or two long sessions
#   fast-swarm   IQ2_XS,    384k x 8  31.4 GiB free  61.0 t/s  concurrency over pack quality
#
# `omni-fast` is the colo profile: the IQ2_XS pack with a 21.5 GiB reserve, 71.6 t/s at 1M, and the
# companion answers at 98.8 t/s beside it. `omni-max` keeps the better pack and drops the frontier to
# 59-62 t/s. Flip to a colo profile deliberately, for a session that needs a companion.
{ lib, pkgs, ... }:
let
  # The KFD shim: ROCm 7.2 aborts `hsa_init` because the RX 550 (gfx803) reports a deprecated
  # doorbell type. The shim hides that node from the topology reads the runtime makes. Built from
  # the repo source so it never drifts from hack/rocm-skip-legacy-gpu.c.
  rocmShim = pkgs.stdenv.mkDerivation {
    pname = "rocm-skip-legacy-gpu";
    version = "1";
    src = ../../hack/rocm-skip-legacy-gpu.c;
    dontUnpack = true;
    buildPhase = ''
      $CC -shared -fPIC -O2 -o rocm-skip.so "$src" -ldl
    '';
    installPhase = ''
      mkdir -p $out/lib
      cp rocm-skip.so $out/lib/
    '';
  };

  # The profile the manual fallback unit starts, and the profile a timed loan returns to. Change this
  # one value, or run `hack/brys-frontier.sh up --profile <name> --ttl <duration>` for a one-off. It
  # matches `textProfiles` below: the manager rests on `max-multi`.
  defaultProfile = "max-multi";

  # One parent for everything the LLM stack owns, so a second machine can share it by mounting the
  # same datasets. `models` and `engines` live on usr/data, `sessions` on usr/cache, `home` on
  # usr/data. The engine tree keeps its path: the Terminal's venv hardcodes it.
  llmsRoot = "/var/lib/kdn/llms";
  engines = "${llmsRoot}/models/.bench";
  dataHome = "${engines}/xdg";

  # The llm-swap entry point: materialises a profile and serves it in the foreground.
  strataServe = pkgs.writeShellScriptBin "strata-serve" ''
    export PATH=${
      pkgs.lib.makeBinPath [
        pkgs.python3
        pkgs.coreutils
      ]
    }:$PATH
    exec ${pkgs.bash}/bin/bash ${./strata-serve.sh} "$@"
  '';

  # The runtime is one Go binary (`packages/kdn-inference-helpers`). The three wrappers below keep
  # the historical names, so the units, the sudoers line and `data/llm.nix` are untouched:
  #
  #   strata-manager  the control plane on :8181
  #   strata-select   the llama-swap entry: select the profile, then serve the proxy in-process
  #   strata-proxy    a bare proxy, kept for a hand run and for the fallback unit
  #
  # The Python implementations stay in the tree for one release as the rollback path; deleting them
  # is the last step of docs/tasks/2026-11/kdn-inference-helpers.
  # The image and video editors are profiles of the same manager: their argv, their readiness path
  # and the `sd-server` binary come from one file, and the card stays one card.
  imageModels = import ./image-models.nix { inherit pkgs lib; };

  # The placement policy: the behaviour tree and the measured facts it decides over. The manager
  # answers `/decide` from it; nothing acts on it until `admit` is wired into the entries.
  placement = import ./policy.nix { inherit lib; };

  inferenceHelpers = pkgs.kdn.kdn-inference-helpers;
  strataManager = pkgs.writeShellScriptBin "strata-manager" ''
    exec ${inferenceHelpers}/bin/kdn-inference-helpers manager "$@"
  '';
  strataProxy = pkgs.writeShellScriptBin "strata-proxy" ''
    exec ${inferenceHelpers}/bin/kdn-inference-helpers proxy "$@"
  '';
  strataSelect = pkgs.writeShellScriptBin "strata-select" ''
    exec ${inferenceHelpers}/bin/kdn-inference-helpers select "$@"
  '';
in
{
  # ---------------------------------------------------------------- the service account
  # A high, fixed pair out of every dynamic-assignment pool, so the UID/GID mean the same thing on
  # every machine that shares the LLM tree. `isSystemUser` stays on so the account gets no login
  # shell and no aging; it does **not** cap the uid — only `isNormalUser` would assert uid >= 1000,
  # and that is the flag this account must not carry.
  users.groups.llm-server = {
    gid = 67890;
  };
  users.users.llm-server = {
    isSystemUser = true;
    group = "llm-server";
    uid = 67890;
    home = "${llmsRoot}/home";
    createHome = true;
    description = "Generic LLMs runner account";
  };

  # The runtime's deployment file. The Go CLI and both daemons read this one path, so a port, an
  # alias or the cache-drop hook is a Nix value here and never a rebuild of the binary. The built-in
  # defaults describe brys, so this file is deliberately a complete copy rather than a delta: it is
  # the place a person edits.
  environment.etc."kdn-inference-helpers/config.json".text = builtins.toJSON {
    engine = "strata";
    dataDir = dataHome;
    enginePort = 8080;
    managerPort = 8181;
    swapURL = "http://127.0.0.1:39700";
    engineBin = "${engines}/bin/strata";
    aliases = {
      qfn = "auto";
      # `qfn-max` is the old name of the 1M whole-card profile and keeps that meaning: it resolves
      # to `max-long`, the same window on the same pack, now with two slots instead of one. It stays
      # because clients name it; the explicit spelling is `qfn-max-long`.
      qfn-max = "max-long";
      qfn-max-multi = "max-multi";
      qfn-max-swarm = "max-swarm";
      qfn-max-long = "max-long";
      qfn-fast-swarm = "fast-swarm";
      qfn-max-colo = "omni-max";
      qfn-fast-colo = "omni-fast";
    };
    frontierIDs = [
      "qfn"
      "qfn-max"
      "qfn-max-multi"
      "qfn-max-swarm"
      "qfn-max-long"
      "qfn-fast-swarm"
      "qfn-max-colo"
      "qfn-fast-colo"
    ];
    # The profiles that serve chat. `qfn` (alias `auto`) keeps only one of these: an image profile
    # is never "kept" for a chat request, because a diffusion server answers no chat. Anything
    # outside this list is a batch profile, and asking for `auto` while one is loaded is refused
    # with an error that names the way back.
    #
    # `max-multi` first: the swarm is the primary and the resting one, by decision of 2026-11-21.
    # Every fallback — `auto` with nothing loaded, a companion unload, a refusal that names the way
    # back — lands here unless the caller asks for something else. It overrides the earlier decision
    # of the same day, which rested on `max` (one 1M slot): an agent fleet asks for several short
    # sessions far more often than for one million-token one, and 1M is now an explicit request.
    #
    # Consequence to keep in mind: every whole-card profile leaves under 20 GiB of RAM and about
    # 1 GiB of VRAM, so a companion or a small model cannot load beside any of them. That is
    # intended, and the refusal must be a readable 409 offering `kdn_switch_to: omni-fast`, never a
    # 500.
    textProfiles = [
      "max-multi"
      "max-swarm"
      "max-long"
      "fast-swarm"
      "omni-max"
      "omni-fast"
    ];
    # Concurrent engine slots per frontier profile. `strata serve --parallel N` becomes the engine's
    # `--batch N`, one session per slot, and each session carves its own K/V for the whole
    # `--max-context` at start-up: 9.56 KiB per cell with k8v4, so 2.39 GiB for a 256k slot,
    # 3.59 GiB for a 384k slot, 4.78 GiB for a 512k slot and 9.56 GiB for a 1M slot. The wall is
    # host RAM, not the card:
    #
    #   profile      slots x ctx   K/V total  MemAvailable  measured
    #   max-multi      6 x 512k     28.7 GiB      6.6 GiB   30.7 t/s aggregate, load 62 s
    #   max-swarm      8 x 256k     19.1 GiB     18.4 GiB   36.2 t/s aggregate, load 54 s
    #   max-long       2 x 1M       19.1 GiB     10.5 GiB   29.7 t/s aggregate, load 58 s
    #   fast-swarm     8 x 384k     28.7 GiB     31.4 GiB   61.0 t/s aggregate, load 44 s
    #
    # Eight is the engine's own cap (SLOTS_MAX; `vram_fit` prices min(slots, 8)), so no profile asks
    # for more. 1M stops at two slots: a third would fit arithmetically, but this host has hard-reset
    # twice under a long prefill and the window keeps a slot of headroom for it.
    #
    # 512k stops at six: seven measured 2.0 GiB of `MemAvailable` and a 130 s load (the page cache
    # thrashes as the pinned K/V grows), and five would leave 12.0 GiB and decode no faster (31.9
    # against 30.7 t/s saturated) because the expert cache shrinks as the slot sessions grow.
    #
    # Two settings carry the fit, both measured 2026-11-21:
    #
    #   * `--ple-io mmap`, not `ram`. Locking the ~30 GiB n-gram table in RAM is what made a second
    #     1M slot OOM (engine RSS 109.6 GiB, 2026-11-21) and what pushed a 384k load to 126 s. In
    #     the page cache the same load takes 56 s, frees 22-25 GiB and decodes no slower.
    #   * `--conversation-cache-mib 2048`, not the engine's 8 GiB default. The park pool buys parked
    #     conversations; a swarm spends that RAM on live slots instead.
    #
    # `--batch` turns MTP drafting off unless `--batch-mtp` is added. Measured: with it, drafting
    # does survive (140 of 174 proposals accepted, 80.5%) but the eight-slot aggregate falls 12%
    # (61.0 -> 54.0 t/s) and it costs about 3 GiB of RAM, so it stays off.
    profiles = {
      max-multi = {
        parallel = 6;
      };
      max-swarm = {
        parallel = 8;
      };
      max-long = {
        parallel = 2;
      };
      fast-swarm = {
        parallel = 8;
      };
      omni-max = {
        parallel = 1;
      };
      omni-fast = {
        parallel = 2;
      };
    };
    # The editors. Each is an `sd-server` on the engine port, so selecting one stops the frontier
    # first (drain, then stop, then load) and selecting a text profile stops the editor.
    commands = imageModels.profiles;
    policyPath = "/etc/kdn-inference-helpers/policy.json";
    # The policy the gate applies to qwen3-omni: only a profile that keeps the reserve satisfies it,
    # and only a colo tier may be named in `kdn_switch_to`.
    # The reviewer shares the companion's policy: it only fits beside the frontier when the engine
    # holds a reserve, so the same two colo profiles satisfy it and the same field asks for the
    # switch.
    gates."qwen2.5-vl-7b" = {
      requireProfiles = [
        "omni-max"
        "omni-fast"
      ];
      allow = [
        "omni-max"
        "omni-fast"
      ];
      confirmField = "kdn_switch_to";
    };
    gates.qwen3-omni = {
      requireProfiles = [
        "omni-max"
        "omni-fast"
      ];
      allow = [
        "omni-max"
        "omni-fast"
      ];
      confirmField = "kdn_switch_to";
    };
    cacheDropCommand = [
      "/run/wrappers/bin/sudo"
      "-n"
      "/run/current-system/sw/bin/systemctl"
      "start"
      "strata-drop-cache.service"
    ];
    engineLog = "${dataHome}/strata/engine.log";
  };

  # The placement policy lives beside the runtime's deployment file, so a decision is one file to
  # read and one diff to review.
  environment.etc."kdn-inference-helpers/policy.json".text = builtins.toJSON placement;

  # nix-ld runs the Terminal's bundled CPython in place; the FHS wrapper cannot be used because a
  # systemd sandbox forbids the user namespace bubblewrap needs.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      libxcrypt
    ];
  };

  environment.systemPackages = [
    # The runtime is named by `data/llm.nix` entries as an absolute path, so it must be on PATH.
    inferenceHelpers
    # The editors' server binary. It is named absolutely in the config, so this is for a hand run.
    imageModels.sd
    pkgs.kdn.strata
    strataServe
    strataSelect
    strataProxy
    strataManager
  ];

  # ---------------------------------------------------------------- the profile manager
  #
  # One engine, one owner, and a selection that is a no-op when the profile is already current.
  # The llama-swap entries call `strata-select`, which asks this service and then proxies their
  # port to the engine, so a switch between two entries that resolve to the same profile costs a
  # TCP proxy instead of a 55 GiB reload.
  systemd.services.strata-manager = {
    description = "Strata profile manager (/select, /status on :8181)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "simple";
      User = "llm-server";
      Group = "llm-server";
      Restart = "always";
      RestartSec = "5s";
      LimitMEMLOCK = "infinity";
      MemoryMax = "118G";
      Environment = [
        "HOME=${llmsRoot}/home"
        "XDG_DATA_HOME=${dataHome}"
        "STRATA_DATA_HOME=${dataHome}"
        "LD_PRELOAD=${rocmShim}/lib/rocm-skip.so"
      ];
      ExecStart = "${strataManager}/bin/strata-manager";
    };
  };

  # ---------------------------------------------------------------- cache drop before a load
  #
  # A Strata load is one ~95 GiB allocation burst on a 125 GiB host with no swap. With 40-48 GiB of
  # the pack still sitting in the page cache, reclaim cannot keep up and the kernel OOM-kills the
  # engine mid-load (measured 2026-11-19: every failing load ended at 88-98 GiB RSS with `free` at
  # zero). The cache is the cheap side of that trade: the pool reads the pack back at 7.7 GB/s
  # (`dd iflag=direct`), so dropping it costs seconds and returns tens of GiB.
  #
  # Writing `/proc/sys/vm/drop_caches` needs root, and the manager runs as `llm-server`, so it asks
  # for this one unit. The sudoers rule names the exact command and nothing else.
  systemd.services.strata-drop-cache = {
    description = "Drop the page cache before a Strata model load";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      # `sync` first: `drop_caches` only discards clean pages.
      ExecStart = "${pkgs.runtimeShell} -c 'sync; echo 3 > /proc/sys/vm/drop_caches'";
    };
  };

  security.sudo.extraRules = [
    {
      users = [ "llm-server" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/systemctl start strata-drop-cache.service";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # ---------------------------------------------------------------- Strata as a service
  systemd.services.strata-frontier = {
    description = "Strata frontier (Qwen3.8-Flash-Next) on :8080";
    # llama-swap owns the profiles now (it starts the requested one and evicts the previous), so
    # this unit must NOT start at boot: two engines would fight for the card and port 8080. It
    # stays as a manual fallback: `systemctl start strata-frontier`.
    wantedBy = lib.mkForce [ ];
    after = [ "network.target" ];
    # The engine holds a pinned arena of tens of GB and the GPU.
    serviceConfig = {
      Type = "simple";
      User = "llm-server";
      Group = "llm-server";
      LimitMEMLOCK = "infinity";
      Restart = "on-failure";
      RestartSec = "10s";
      # 55 GiB of experts plus the conversation cache; leave the desktop a margin.
      MemoryMax = "112G";
      Environment = [
        "HOME=${llmsRoot}/home"
        "XDG_DATA_HOME=${dataHome}"
        "LD_PRELOAD=${rocmShim}/lib/rocm-skip.so"
        "STRATA_DATA_HOME=${dataHome}"
      ];
      ExecStart = "${strataServe}/bin/strata-serve ${defaultProfile} --port 8080";
    };
  };

  # ---------------------------------------------------------------- llama-swap shares the account
  systemd.services.llama-swap.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = lib.mkForce "llm-server";
    Group = lib.mkForce "llm-server";
    ReadWritePaths = [
      "/var/lib/kdn/llms/models"
      # Strata keeps its per-user state in `$HOME/.local/state/strata` and checks that the folder
      # is its own, mode 0700. `ProtectSystem=strict` makes /var read-only, so the home needs an
      # explicit exception too.
      "/var/lib/kdn/llms/home"
    ];
  };

  # The wrapper defaults the shim to the dataset copy; the sandbox hides /home, so name it here.
  systemd.services.llama-swap.environment.ROCM_SHIM = "${engines}/rocm-skip.so";

  # A deploy that changes the helper leaves an entry running the *old* build: measured 2026-11-20,
  # a `select` process from the previous store path kept answering after the switch. Restarting
  # llama-swap fixes that but cuts every running request, so the entry does it itself instead: the
  # proxy compares its own store path with `/run/current-system/sw/bin/kdn-inference-helpers` and
  # leaves once it holds no request. The next request spawns the new build.

  # The data tree belongs to the engine user, and everyone may read the models.
  systemd.tmpfiles.rules = [
    "d ${engines} 0755 llm-server llm-server -"
    "d ${dataHome} 0755 llm-server llm-server -"
    "d ${llmsRoot}/home 0755 llm-server llm-server -"
    # A stable copy of the shim for hand-run servers; the service uses the store path directly.
    "C+ ${engines}/rocm-skip.so 0644 llm-server llm-server - ${rocmShim}/lib/rocm-skip.so"
  ];
}
