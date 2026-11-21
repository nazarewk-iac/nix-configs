# The account that runs the local LLM stack on brys.
#
# Why a dedicated account: Strata refuses files that another user owns ("not allowed to open one of
# its own files"), so it must run as the owner of its data tree. It also must not run as a human
# account: the engine pins tens of GB and holds the GPU.
#
# `omni-fast` is the resting profile, measured 2026-11-19 on this host: the frontier reads
# 88.3 t/s (short context) and 71.6 t/s at 1M with the IQ2_XS pack, the companion answers at
# 98.8 t/s beside it, and the box keeps **23-27 GiB** of RAM free. Every alternative costs
# something worse: `max` (UD-IQ4_XS, whole card) is 94.8-100.4 t/s but leaves 2-3 GiB free and a
# media request then runs the companion at 6.1 t/s on the CPU; `omni-max` keeps the better pack but
# drops the frontier to 59-62 t/s and still leaves 3-5 GiB. Flip to `max` deliberately for a
# quality-critical session, with a TTL so the box returns here.
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

  # The profile the service starts with, and the profile a timed loan returns to. Change this one
  # value, or run `hack/brys-frontier.sh up --profile <name> --ttl <duration>` for a one-off.
  defaultProfile = "omni-fast";

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
      qfn-max = "max";
      qfn-max-colo = "omni-max";
      qfn-fast-colo = "omni-fast";
    };
    frontierIDs = [
      "qfn"
      "qfn-max"
      "qfn-max-colo"
      "qfn-fast-colo"
    ];
    # The profiles that serve chat. `qfn` (alias `auto`) keeps only one of these: an image profile
    # is never "kept" for a chat request, because a diffusion server answers no chat. Anything
    # outside this list is a batch profile, and asking for `auto` while one is loaded is refused
    # with an error that names the way back.
    # `max` first: the whole-card profile is the primary and the resting one, by decision. Every
    # fallback — `auto` with nothing loaded, a companion unload, a refusal that names the way back —
    # lands here unless the caller asks for something else.
    #
    # Consequence to keep in mind: on `max` there is about 1 GiB left, so a companion or a small
    # model cannot load beside it. That is intended, and the refusal must be a readable 409 offering
    # `kdn_switch_to: omni-fast`, never a 500.
    textProfiles = [
      "max"
      "omni-max"
      "omni-fast"
    ];
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
