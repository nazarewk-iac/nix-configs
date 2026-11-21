# The account that runs the local LLM stack on brys.
#
# Why a dedicated account: Strata refuses files that another user owns ("not allowed to open one of
# its own files"), so it must run as the owner of its data tree. It also must not run as a human
# account: the engine pins tens of GB and holds the GPU.
#
# `max-multi` is the primary and resting profile, by decision of 2026-11-21: a swarm of five 512k
# slots on the best pack (UD-IQ4_XS). It overrides the earlier decision of the same day ("`max`, one
# 1M session, is the primary"), because an agent fleet asks for several short sessions far more
# often than for one million-token one; 1M is now an explicit request (`max-long`). Measured
# 2026-11-21: 5 slots x 512k, 23.9 GiB of pinned K/V, 12.0 GiB of MemAvailable, 31.9 t/s aggregate.
# Five rather than six, because this host also builds: a six-slot load holds 6.6 GiB on a quiet host
# and fell to 2.9 GiB with two builds running, while five decodes no slower (31.9 against 30.7 t/s
# saturated) because the expert cache shrinks as the slot sessions grow.
#
# The siblings exist because the card cannot be everything at once:
#
#   max-multi    UD-IQ4_XS, 512k x 5  12.0 GiB free  31.9 t/s  the resting profile
#   max-swarm    UD-IQ4_XS, 256k x 8  18.4 GiB free  36.2 t/s  the same slots with RAM to spare
#   max-long     UD-IQ4_XS,   1M x 2  10.5 GiB free  29.7 t/s  one or two long sessions
#   max-single   UD-IQ4_XS,   1M x 1   9.6 GiB K/V   86.6 t/s  one big job, no concurrency
#   fast-swarm   IQ2_XS,    384k x 8  31.4 GiB free  61.0 t/s  concurrency over pack quality
#
# **This file is the only place a profile's context window, slot count, VRAM reserve and resident
# K/V are written** (`.agents/rules/config-single-source.md`). The generated `config.json` is built
# from the `profiles` table below, the manager reads that file, and `strata-serve.sh` reads the same
# file with `jq`. Neither carries a table or a fallback. The reason is a real drift: before
# 2026-11-21 the slot count lived here, in `strata-serve.sh` (`parallel=6`) and in the Go adapter
# (`Parallel: 6`) at the same time, and the omni profiles were served with 8 slots by the manager
# while this file said 1 and 2.
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

  # The window Qwen3.8-Flash-Next was trained on. A profile above it needs yarn scaling, and the
  # factor is exactly the served window over this number, so no profile writes a rope value of its
  # own and the two can never disagree.
  nativeContext = 262144;

  # One operating point. Every knob a profile has is written here and nowhere else: the deployment
  # file carries the result, the manager and `strata-serve.sh` read it, and the `status` table shows
  # it. `ropeScale` is derived from the window, not a second knob.
  #
  # `conversationCacheMiB = null` keeps the base config's own value, which is the engine's default.
  # That is what the two colo profiles were measured with, and it is spelled out rather than left
  # to a consumer's fallback: a missing key is an error in both consumers.
  frontierProfile =
    {
      base,
      parallel,
      maxContext,
      reserveMiB,
      kvResident,
      conversationCacheMiB,
      pleIO,
    }:
    {
      inherit
        base
        parallel
        maxContext
        reserveMiB
        kvResident
        conversationCacheMiB
        pleIO
        ;
      ropeScale = maxContext / (nativeContext * 1.0);
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

  # The llm-swap entry point: materialises a profile and serves it in the foreground. It needs `jq`
  # on PATH because the deployment file is the only source of a profile's knobs; a missing key stops
  # the entry instead of falling back to a literal.
  strataServe = pkgs.writeShellScriptBin "strata-serve" ''
    export PATH=${
      pkgs.lib.makeBinPath [
        pkgs.python3
        pkgs.jq
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
  # alias or the cache-drop hook is a Nix value here and never a rebuild of the binary. It is
  # deliberately a complete copy rather than a delta: the binary carries **no** profile table for
  # this deployment, so the `profiles` block below is the only definition of a profile's window,
  # slot count, VRAM reserve and resident K/V.
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
      # because clients name it; the explicit spelling is `qfn-max-long`, and the one-slot shape is
      # `qfn-max-single`.
      qfn-max = "max-long";
      qfn-max-multi = "max-multi";
      qfn-max-swarm = "max-swarm";
      qfn-max-long = "max-long";
      qfn-max-single = "max-single";
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
      "qfn-max-single"
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
      "max-single"
      "fast-swarm"
      "omni-max"
      "omni-fast"
    ];
    # The operating points. `strata serve --parallel N` becomes the engine's `--batch N`, one session
    # per slot, and each session carves its own K/V for the whole `--max-context` at start-up:
    # 9.56 KiB per cell with k8v4, so 2.39 GiB for a 256k slot, 3.59 GiB for a 384k slot,
    # 4.78 GiB for a 512k slot and 9.56 GiB for a 1M slot. The wall is host RAM, not the card:
    #
    #   profile      slots x ctx   K/V total  MemAvailable  measured
    #   max-multi      5 x 512k     23.9 GiB     12.0 GiB   31.9 t/s aggregate, load 58 s
    #   max-swarm      8 x 256k     19.1 GiB     18.4 GiB   36.2 t/s aggregate, load 54 s
    #   max-long       2 x 1M       19.1 GiB     10.5 GiB   29.7 t/s aggregate, load 58 s
    #   max-single     1 x 1M        9.6 GiB     20+ GiB    86.6 t/s single stream, load 58 s
    #   fast-swarm     8 x 384k     28.7 GiB     31.4 GiB   61.0 t/s aggregate, load 44 s
    #
    # Eight is the engine's own cap (SLOTS_MAX; `vram_fit` prices min(slots, 8)), so no profile asks
    # for more. 1M stops at two slots: a third would fit arithmetically, but this host has hard-reset
    # twice under a long prefill and the window keeps a slot of headroom for it. `max-single` is the
    # one-slot shape of the same window — the fastest single stream this host serves (86.6 t/s), for
    # one big job with no concurrency; the manager still rests on `max-multi`.
    #
    # 512k stops at five, because this host builds as well as serves. Five leaves 12.0 GiB and
    # decodes no faster than six (31.9 against 30.7 t/s saturated): the expert cache shrinks as the
    # slot sessions grow, so the aggregate is flat from five callers to seven at this window and the
    # slot count buys concurrency, not throughput. Six holds 6.6 GiB on a quiet host but fell to
    # 2.9 GiB with two builds running — under the 4 GiB of headroom a build needs — and seven
    # measured 2.0 GiB and a 130 s load as the page cache thrashed against the pinned K/V.
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
    #
    # This table is the single source. Every consumer reads the generated `config.json`: the manager
    # through the Go adapter, `strata-serve.sh` through `jq`. No consumer may carry a number of its
    # own, and `checks/inference-helpers/profiles.nix` fails when one does.
    profiles = {
      max-multi = frontierProfile {
        base = "unsloth-ud-iq4_xs";
        parallel = 5;
        maxContext = 524288;
        reserveMiB = 1024;
        kvResident = 32768;
        conversationCacheMiB = 2048;
        pleIO = "mmap";
      };
      max-swarm = frontierProfile {
        base = "unsloth-ud-iq4_xs";
        parallel = 8;
        maxContext = 262144;
        reserveMiB = 1024;
        kvResident = 32768;
        conversationCacheMiB = 2048;
        pleIO = "mmap";
      };
      max-long = frontierProfile {
        base = "unsloth-ud-iq4_xs";
        parallel = 2;
        maxContext = 1048576;
        reserveMiB = 1024;
        kvResident = 32768;
        conversationCacheMiB = 1024;
        pleIO = "mmap";
      };
      max-single = frontierProfile {
        base = "unsloth-ud-iq4_xs";
        parallel = 1;
        maxContext = 1048576;
        reserveMiB = 1024;
        kvResident = 32768;
        conversationCacheMiB = 1024;
        pleIO = "mmap";
      };
      fast-swarm = frontierProfile {
        base = "iq2_xs";
        parallel = 8;
        maxContext = 393216;
        reserveMiB = 1024;
        kvResident = 32768;
        conversationCacheMiB = 2048;
        pleIO = "mmap";
      };
      # The colo pair keeps the engine's own park pool (`null`) and the n-gram table locked in RAM,
      # which is what their 21.5 GiB reserve was measured with. The 1M window is spelled out rather
      # than inherited from the base config: the deployment file is the only source.
      omni-max = frontierProfile {
        base = "unsloth-ud-iq4_xs";
        parallel = 1;
        maxContext = 1048576;
        reserveMiB = 21500;
        kvResident = 32768;
        conversationCacheMiB = null;
        pleIO = "ram";
      };
      omni-fast = frontierProfile {
        base = "iq2_xs";
        parallel = 2;
        maxContext = 1048576;
        reserveMiB = 21500;
        kvResident = 32768;
        conversationCacheMiB = null;
        pleIO = "ram";
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
