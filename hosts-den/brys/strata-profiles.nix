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
# The siblings exist because the card cannot be everything at once. Their numbers — pack, window,
# slots, free RAM, throughput, load time — are in `data/llm.nix` beside each entry, where they are
# measured and where every consumer reads them:
#
#   max-multi    the resting profile, five 512k slots on the best pack
#   max-swarm    the same pack with the slots at 256k, and RAM to spare
#   max-long     one or two long (1M) sessions
#   max-single   the one-slot 1M shape: one big job, no concurrency
#   fast-swarm   concurrency over pack quality (IQ2_XS, 384k x 8)
#
# **The knobs of a profile are not in this file.** The pack, the window, the slot count, the VRAM
# reserve, the resident K/V, the park pool and the n-gram backing store of every operating point are
# written on the model itself in `data/llm.nix` (`hosts.brys.serving`), together with the measured
# facts the placement policy quotes. This file maps that one projection (`lib/llm.nix` `strata`) into
# the generated `config.json`, which is what the manager and `strata-serve.sh` read. A profile table
# here, a context literal in the script and a built-in table in the Go adapter were three copies of
# the same number; before 2026-11-21 they had already drifted, and the omni profiles were served with
# 8 slots while the deployment said 1 and 2.
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

  # The window Qwen3.8-Flash-Next was trained on, and the yarn factor derived from it, live in
  # `data/llm.nix` (`servers.brys.frontier.nativeContext`): a profile above the native window needs
  # scaling, and the factor is exactly the served window over it, so no profile writes a rope value
  # of its own.

  # The profile the manual fallback unit starts, and the profile a timed loan returns to: the first
  # entry of `textProfiles`, which `data/llm.nix` marks with `rank = 0`. Change the rank there, or
  # run `hack/brys-frontier.sh up --profile <name> --ttl <duration>` for a one-off.
  defaultProfile = lib.head strata.textProfiles;

  # One parent for everything the LLM stack owns, so a second machine can share it by mounting the
  # same datasets. `models` and `engines` live on usr/data, `sessions` on usr/cache, `home` on
  # usr/data. The engine tree keeps its path: the Terminal's venv hardcodes it.
  llmsRoot = "/var/lib/kdn/llms";
  engines = "${llmsRoot}/models/.bench";
  dataHome = "${engines}/xdg";

  # The llm-swap entry point: materialises a profile and serves it in the foreground. It needs `jq`
  # on PATH because the deployment file is the only source of a profile's knobs; a missing key stops
  # the entry instead of falling back to a literal. Python is no longer needed: the argv patch is one
  # `jq` filter.
  strataServe = pkgs.writeShellScriptBin "strata-serve" ''
    export PATH=${
      pkgs.lib.makeBinPath [
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
  # The image and video editors are profiles of the same manager: their argv, their readiness path
  # and the `sd-server` binary come from one file, and the card stays one card.
  imageModels = import ./image-models.nix { inherit pkgs lib; };

  # The placement policy: the behaviour tree and the measured facts it decides over. The manager
  # answers `/decide` from it; nothing acts on it until `admit` is wired into the entries.
  placement = import ./policy.nix { inherit lib; };

  # The frontier serving data: ONE source (`data/llm.nix`) and one projection of it. The deployment
  # file below maps `strata.profiles`, `strata.textProfiles`, `strata.aliases` and
  # `strata.frontierIDs` straight into `config.json`; the manager, `strata-serve.sh` and the policy
  # read the result. No knob is written twice, so nothing has to check that two copies agree.
  data = import ../../data/llm.nix;
  llm = import ../../lib/llm.nix { inherit lib; };
  strata = llm.strata data "brys";

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
  # this deployment, so `profiles` below is the only definition of a profile's window, slot count,
  # VRAM reserve and resident K/V — and it is mapped straight from `data/llm.nix`, never typed here.
  environment.etc."kdn-inference-helpers/config.json".text = builtins.toJSON {
    engine = "strata";
    dataDir = dataHome;
    enginePort = 8080;
    managerPort = 8181;
    swapURL = "http://127.0.0.1:39700";
    engineBin = "${engines}/bin/strata";
    # Every name llama-swap answers to, mapped to the operating point it forces, derived from the
    # models' own `hosts.brys.serving` blocks. `qfn` resolves to `auto` (keep the current point), so
    # naming it never reloads the engine; `qfn-max` is the older name of the two-slot 1M point and
    # therefore resolves to `max-long`; the one-slot shape of that window is `qfn-max-single`.
    aliases = strata.aliases;
    # The ids that survive a switch. Anything loaded and *not* here is a companion, which the
    # manager may unload; a frontier entry proxies to the engine and has nothing to free.
    frontierIDs = strata.frontierIDs;
    # The operating points that serve chat, in `rank` order — the first one rests. `qfn` (alias
    # `auto`) keeps only one of these: an image profile is never "kept" for a chat request, because
    # a diffusion server answers no chat. Anything outside this list is a batch profile, and asking
    # for `auto` while one is loaded is refused with an error that names the way back.
    #
    # `max-multi` first: the swarm is the primary and the resting one, by decision of 2026-11-21 —
    # an agent fleet asks for several short sessions far more often than for one million-token one.
    # Every fallback (`auto` with nothing loaded, a companion unload, a refusal that names the way
    # back) lands there unless the caller asks for something else.
    #
    # Consequence to keep in mind: every whole-card point leaves under 20 GiB of RAM and about 1 GiB
    # of VRAM, so a companion or a small model cannot load beside any of them. That is intended, and
    # the refusal must be a readable 409 offering `kdn_switch_to: omni-fast`, never a 500.
    textProfiles = strata.textProfiles;
    # The operating points themselves. `strata serve --parallel N` becomes the engine's `--batch N`,
    # one session per slot, and each session carves its own K/V for the whole `--max-context` at
    # start-up: 9.56 KiB per cell with k8v4, so 2.39 GiB for a 256k slot, 3.59 GiB for a 384k slot,
    # 4.78 GiB for a 512k slot and 9.56 GiB for a 1M slot. The wall is host RAM, not the card; the
    # measured numbers and the reasoning behind each point are in `data/llm.nix`.
    #
    # `--batch` turns MTP drafting off unless `--batch-mtp` is added. Measured: with it, drafting
    # does survive (140 of 174 proposals accepted, 80.5%) but the eight-slot aggregate falls 12%
    # (61.0 -> 54.0 t/s) and it costs about 3 GiB of RAM, so it stays off.
    profiles = strata.profiles;
    # The editors. Each is an `sd-server` on the engine port, so selecting one stops the frontier
    # first (drain, then stop, then load) and selecting a text profile stops the editor.
    commands = imageModels.profiles;
    policyPath = "/etc/kdn-inference-helpers/policy.json";
    # The policy the gate applies to the companions: only a point that keeps the reserve satisfies
    # it, and only a colo point may be named in `kdn_switch_to`. The list is derived from the models
    # that declare `colo = true` in `data/llm.nix`, so a new colo point is gated the moment it is
    # declared, and a point that stops keeping a reserve stops being offered.
    gates = lib.genAttrs [ "qwen2.5-vl-7b" "qwen3-omni" ] (_: {
      requireProfiles = strata.coloProfiles;
      allow = strata.coloProfiles;
      confirmField = "kdn_switch_to";
    });
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
