# The placement policy: one behaviour tree plus the measured facts it decides over.
#
# The tree is data on purpose. The order of its branches *is* the policy, so it should be readable
# and diffable by a person, and the verbs it names are implemented and tested in
# packages/kdn-inference-helpers/internal/policy. An unknown verb refuses to load the policy, and a
# model without measured facts refuses too: a typo that silently admits is the worst failure this
# design can have.
#
# The tree is evaluated by `POST /decide` (advisory, no side effects) and, later, by `admit` on
# every llama-swap entry. It never touches the card itself.
#
# The numbers come from docs/tasks/2026-11/image-video-editing-models/measurements.md and the
# brys sweep; `measured` is the date they were taken, so a stale table is visible.
#
# The decode floor guards a future profile, not a retired name: `profile-met` already refuses a
# companion beside a whole-card profile, so `minDecodeTps` is kept for a profile that admits both,
# and the `max` key it was measured under is not kept "just in case".
{ lib }:
let
  # The one source of the frontier's serving data, and the projection that quotes it.
  data = import ../../data/llm.nix;
  llm = import ../../lib/llm.nix { inherit lib; };
  strata = llm.strata data "brys";

  # A check node.
  check = verb: {
    type = "check";
    inherit verb;
  };
  # An action node, optionally with arguments.
  action =
    verb: args:
    {
      type = "action";
      inherit verb;
    }
    // lib.optionalAttrs (args != { }) { inherit args; };
  seq = children: {
    type = "sequence";
    inherit children;
  };
  sel = children: {
    type = "selector";
    inherit children;
  };
  # The KV reserve. A model's VRAM is `vramMiB` plus `kvReserveMiB`: the footprint is what the
  # weights, the projector and the compute buffers took when the model was measured, and the reserve
  # is the KV cache it holds at the context it serves. `fits-beside` subtracts both, for the
  # newcomer and for every resident model, so a card whose VRAM is filled by caches never reads as
  # free. A model with no reserve set keeps its KV inside `vramMiB`, which is what a footprint
  # measured at the served context already contains.
  #
  # `ramMiB` is the NON-RECLAIMABLE resident set: anonymous RSS plus shmem, the pages the kernel
  # cannot drop under pressure. It is deliberately NOT `VmRSS`. A llama.cpp server with
  # `--load-mode mmap` maps its weights, so RSS counts tens of GiB of clean, file-backed pages that
  # the kernel reclaims for free; reading RSS made a 30B companion look like 21 GiB of RAM and made
  # the policy refuse it beside a profile that had room. Measured 2026-11-21: qwen3-omni held
  # 11.7 GiB of `RssFile` against 128 MiB of `RssAnon`.
  #
  # The frontier's measured facts are not written here. Each operating point declares them on the
  # model itself (`data/llm.nix`, `hosts.brys.serving`), next to the window, the slot count and the
  # reserve that produced them, and this projection turns them into policy rows. `profile` is the
  # point the entry forces; `qfn` forces none (`auto`), so it is gated on every point instead.
  #
  # `--kv-resident 32768` keeps 32768 cells of each QSA layer in VRAM (a per-layer streaming window,
  # not a per-slot allocation), and k8v4 costs ~10.5 KiB per token against int8's 13.7 KiB — 336 MiB.
  # The colo points were measured with a 4096-cell window, so that 336 MiB is a real addition for
  # them; it is carried on the model, in `kvReserveMiB`, beside the measurement it belongs to.
  frontierFacts = lib.mapAttrs (
    _: m:
    let
      s = m.hosts.brys.serving;
    in
    {
      kind = "engine";
      tier = "frontier";
    }
    // lib.optionalAttrs (s.profile != "auto") {
      inherit (s) profile;
    }
    // {
      persistent = true;
    }
    // lib.optionalAttrs (s.profile == "auto") {
      requiresProfile = strata.textProfiles;
    }
    // {
      inherit (s) vramMiB kvReserveMiB ramMiB;
    }
    // lib.optionalAttrs (s ? loadSeconds) {
      inherit (s) loadSeconds;
    }
    // lib.optionalAttrs (s ? switchSeconds) {
      inherit (s) switchSeconds;
    }
    // {
      inherit (s) measured source;
    }
  ) strata.frontier;
  # The companions, at the 16384-token context they are served at: llama.cpp reported
  # `Vulkan0 KV buffer size = 1536.00 MiB` (qwen3-omni) and `896.00 MiB` (qwen2.5-vl-7b) at
  # n_ctx = 16384 in `companion.log` on 2026-11-21. Both footprints were measured with the cache
  # allocated, so it is carried here instead of inside `vramMiB` — the sum is unchanged, which is
  # why the measured colo pair still fits.
in
{
  schemaVersion = 1;

  # The card and the host. VRAM is the measured usable budget of the R9700; the RAM burst is what a
  # Strata load takes before the page cache is released.
  budget = {
    vramMiB = 32620;
    ramMiB = 124000;
    loadBurstRAMMiB = 60000;
  };

  switchCooldownSeconds = 30;
  # A capacity refusal on a model with no profile requirement offers these: the operating points
  # that leave a reserve for a second model, in `rank` order — the ones that declare `colo = true`
  # on the model in `data/llm.nix`.
  coloProfiles = strata.coloProfiles;
  defaultDeadlineSeconds = 120;
  # Below this, a model beside the frontier is not worth serving: the companion measured 6.1 t/s
  # beside a whole-card profile that left it about 1 GiB of VRAM, against 98.8 t/s inside the
  # reserve. That pairing is refused by the profile gate, so no measurement keyed by a whole-card
  # profile name is carried (see the header).
  minDecodeTps = 20;

  tree = sel [
    # 1. unknown model
    (seq [
      (check "model-unknown")
      (action "refuse" {
        code = 400;
        reason = "unknown model";
      })
    ])
    # 2. known but disabled
    (seq [
      (check "model-disabled")
      (action "refuse" {
        code = 400;
        reason = "model is disabled";
      })
    ])
    # 3. already served by what is resident
    (seq [
      (check "already-satisfied")
      (action "serve" { })
    ])
    # 4. a load or a switch is already in progress: join it
    (seq [
      (check "join-in-flight")
      (action "wait" { })
    ])
    # 5. debounce: a switch just happened
    (seq [
      (check "cooldown-active")
      (action "refuse" {
        code = 429;
        reason = "a switch just happened; retry shortly";
      })
    ])
    # 6. the placement decision
    (sel [
      # 6a. the profile requirement is met and it fits beside what is resident
      (seq [
        (check "profile-met")
        (check "tier-free")
        (check "fits-beside")
        (action "load" { })
        (action "serve" { })
      ])
      # 6b. the profile requirement is met, and evicting one model makes room
      (seq [
        (check "profile-met")
        (check "victim-available")
        (check "victim-idle")
        (check "victim-settled")
        (check "victim-evictable")
        (action "evict" { })
        (action "load" { })
        (action "serve" { })
      ])
      # 6c. the caller named a colo profile: switch, then load
      (seq [
        (check "confirmed-profile")
        (check "switch-affordable")
        (action "switch-profile" { })
        (action "load" { })
        (action "serve" { })
      ])
      # 6d. nothing works: refuse, and name the way out
      (action "refuse" {
        code = 409;
        reason = "no room and no permitted profile";
      })
    ])
  ];

  models = frontierFacts // {
    # ---------------------------------------------------------------- image profiles
    "qwen-image-edit" = {
      kind = "engine";
      tier = "frontier";
      profile = "image-qwen";
      vramMiB = 26829;
      ramMiB = 24000;
      loadSeconds = 40;
      minResidencySeconds = 120;
      measured = "2026-11-20";
    };
    "longcat-image-edit" = {
      kind = "engine";
      tier = "frontier";
      profile = "image-longcat";
      vramMiB = 23450;
      ramMiB = 22000;
      loadSeconds = 40;
      minResidencySeconds = 120;
      measured = "2026-11-20";
    };
    "wan-vace-14b" = {
      kind = "engine";
      tier = "frontier";
      profile = "image-vace";
      vramMiB = 29286;
      ramMiB = 26000;
      loadSeconds = 40;
      minResidencySeconds = 120;
      measured = "2026-11-20";
    };

    # ---------------------------------------------------------------- companions
    "qwen3-omni" = {
      kind = "companion";
      tier = "companion";
      requiresProfile = [
        "omni-max"
        "omni-fast"
      ];
      # 20685 MiB measured, of which 1536 MiB is the KV cache at n_ctx 16384: the weights and the
      # projector are 18561 MiB and the rest is 588 MiB of compute buffers. The two are carried apart
      # so the policy can hold the cache back on the card without counting it twice.
      vramMiB = 19149;
      kvReserveMiB = 1536;
      # Non-reclaimable RAM: `RssAnon` 131,480 KiB plus `RssShmem` 0 in llama-server, beside
      # `omni-fast` at 2 slots, 2026-11-21. The 11.7 GiB of `RssFile` is the GGUF mmap (clean,
      # reclaimable), and the 15.9 GiB `VmHWM` is the load burst, which `budget.loadBurstRAMMiB`
      # already covers. Rounded up to the next MiB.
      ramMiB = 129;
      minResidencySeconds = 60;
      # Measured: 98.8 t/s beside omni-fast. Beside a whole-card profile the engine leaves it about
      # 1 GiB of VRAM and it runs at 6.1 t/s; `profile-met` refuses that pairing, so only the colo
      # points are keys here.
      decodeWithFrontier = {
        omni-fast = 98.8;
      };
      measured = "2026-11-21";
      source = "llama-server /proc/<pid>/status: RssAnon+RssShmem (the non-reclaimable part), sampled 10 s after readiness, n_ctx 16384 beside omni-fast, 2026-11-21; vramMiB from hack/measure-footprint.py 2026-11-20; KV from companion.log at n_ctx 16384";
    };
    "qwen2.5-vl-7b" = {
      kind = "companion";
      tier = "companion";
      requiresProfile = [
        "omni-max"
        "omni-fast"
      ];
      # 12595 MiB measured, of which 896 MiB is the KV cache at n_ctx 16384.
      vramMiB = 11699;
      kvReserveMiB = 896;
      # Non-reclaimable RAM: `RssAnon` 74,132 KiB plus `RssShmem` 0, same method as qwen3-omni
      # (2026-11-21). The 565 MiB of `RssFile` is the GGUF mmap, and `VmHWM` peaked at 7.8 GiB.
      ramMiB = 73;
      minResidencySeconds = 60;
      decodeWithFrontier = {
        omni-fast = 40.0;
      };
      measured = "2026-11-21";
      source = "llama-server /proc/<pid>/status: RssAnon+RssShmem (the non-reclaimable part), sampled 10 s after readiness, n_ctx 16384 beside omni-fast, 2026-11-21; vramMiB from hack/measure-footprint.py 2026-11-20; KV from companion.log at n_ctx 16384";
    };

    "gemma-4-e4b" = {
      kind = "small";
      tier = "small";
      # Measured beside `qfn-fast-colo` (omni-fast) on the R9700, 2026-11-21. `vramMiB` is the
      # model's own footprint: the frontier is resident in both samples, so it cancels out.
      vramMiB = 4162;
      # The resident set with the weights on the card. The load burst is `budget.loadBurstRAMMiB`,
      # not this number: a cold load reads the whole GGUF through the page cache first. This one is
      # high for its size (2.9 GiB, against 0.2-0.7 GiB for the dense models): it is a MatFormer
      # with a separate vision projector, and both are mapped.
      ramMiB = 2946;
      loadSeconds = 13;
      decodeWithFrontier.omni-fast = 81.3;
      measured = "2026-11-21";
      source = "hack/measure-footprint.py";
    };
    "granite-4.2-3b" = {
      kind = "small";
      tier = "small";
      # Measured beside `qfn-fast-colo` (omni-fast) on the R9700, 2026-11-21. `vramMiB` is the
      # model's own footprint: the frontier is resident in both samples, so it cancels out.
      vramMiB = 3382;
      # The resident set with the weights on the card. The load burst is `budget.loadBurstRAMMiB`,
      # not this number: a cold load reads the whole GGUF through the page cache first.
      ramMiB = 223;
      loadSeconds = 5;
      decodeWithFrontier.omni-fast = 114.3;
      measured = "2026-11-21";
      source = "hack/measure-footprint.py";
    };
    "granite-4.2-8b" = {
      kind = "small";
      tier = "small";
      # Measured beside `qfn-fast-colo` (omni-fast) on the R9700, 2026-11-21. `vramMiB` is the
      # model's own footprint: the frontier is resident in both samples, so it cancels out.
      vramMiB = 7581;
      # The resident set with the weights on the card. The load burst is `budget.loadBurstRAMMiB`,
      # not this number: a cold load reads the whole GGUF through the page cache first.
      ramMiB = 303;
      loadSeconds = 11;
      decodeWithFrontier.omni-fast = 72.9;
      measured = "2026-11-21";
      source = "hack/measure-footprint.py";
    };
    "lfm2.5-24b-a2b" = {
      kind = "small";
      tier = "small";
      vramMiB = 14879;
      ramMiB = 15391;
      # Estimated, not measured: GGUF size plus 1 GiB for KV and compute buffers. Replace with a
      # measurement from stage 0 before trusting a tight admission.
      measured = "2026-11-21";
      source = "gguf size + 1 GiB";
    };
    "mellum-2.1-12b-a2.5b-thinking" = {
      kind = "small";
      tier = "small";
      # Measured beside `qfn-fast-colo` (omni-fast) on the R9700, 2026-11-21. `vramMiB` is the
      # model's own footprint: the frontier is resident in both samples, so it cancels out.
      vramMiB = 8232;
      # The resident set with the weights on the card. The load burst is `budget.loadBurstRAMMiB`,
      # not this number: a cold load reads the whole GGUF through the page cache first.
      ramMiB = 220;
      loadSeconds = 16;
      decodeWithFrontier.omni-fast = 122.0;
      measured = "2026-11-21";
      source = "hack/measure-footprint.py";
    };
    "ministral-3-3b-reasoning" = {
      kind = "small";
      tier = "small";
      # Measured beside `qfn-fast-colo` (omni-fast) on the R9700, 2026-11-21. `vramMiB` is the
      # model's own footprint: the frontier is resident in both samples, so it cancels out.
      vramMiB = 3839;
      # The resident set with the weights on the card. The load burst is `budget.loadBurstRAMMiB`,
      # not this number: a cold load reads the whole GGUF through the page cache first.
      ramMiB = 421;
      loadSeconds = 5;
      decodeWithFrontier.omni-fast = 147.9;
      measured = "2026-11-21";
      source = "hack/measure-footprint.py";
    };
    "nemotron-3-nano-30b-a3b" = {
      kind = "small";
      tier = "small";
      vramMiB = 24463;
      ramMiB = 24975;
      # Estimated, not measured: GGUF size plus 1 GiB for KV and compute buffers. Replace with a
      # measurement from stage 0 before trusting a tight admission.
      measured = "2026-11-21";
      source = "gguf size + 1 GiB";
    };
    "ornith-1.5-35b-a3b" = {
      kind = "small";
      tier = "small";
      vramMiB = 21729;
      ramMiB = 22241;
      # Estimated, not measured: GGUF size plus 1 GiB for KV and compute buffers. Replace with a
      # measurement from stage 0 before trusting a tight admission.
      measured = "2026-11-21";
      source = "gguf size + 1 GiB";
    };
    "qwen3-embedding-4b" = {
      kind = "small";
      tier = "small";
      vramMiB = 3410;
      ramMiB = 3922;
      # Estimated, not measured: GGUF size plus 1 GiB for KV and compute buffers. Replace with a
      # measurement from stage 0 before trusting a tight admission.
      measured = "2026-11-21";
      source = "gguf size + 1 GiB";
    };
    "qwen3-reranker-4b" = {
      kind = "small";
      tier = "small";
      vramMiB = 3410;
      ramMiB = 3922;
      # Estimated, not measured: GGUF size plus 1 GiB for KV and compute buffers. Replace with a
      # measurement from stage 0 before trusting a tight admission.
      measured = "2026-11-21";
      source = "gguf size + 1 GiB";
    };
    "qwen3-vl-30b-a3b" = {
      kind = "small";
      tier = "small";
      vramMiB = 18719;
      ramMiB = 19231;
      # Estimated, not measured: GGUF size plus 1 GiB for KV and compute buffers. Replace with a
      # measurement from stage 0 before trusting a tight admission.
      measured = "2026-11-21";
      source = "gguf size + 1 GiB";
    };
    "qwen3.5-0.8b" = {
      kind = "small";
      tier = "small";
      # Measured beside `qfn-fast-colo` (omni-fast) on the R9700, 2026-11-21. `vramMiB` is the
      # model's own footprint: the frontier is resident in both samples, so it cancels out.
      vramMiB = 844;
      # The resident set with the weights on the card. The load burst is `budget.loadBurstRAMMiB`,
      # not this number: a cold load reads the whole GGUF through the page cache first.
      ramMiB = 374;
      loadSeconds = 2;
      decodeWithFrontier.omni-fast = 61.9;
      measured = "2026-11-21";
      source = "hack/measure-footprint.py";
    };
    "qwen3.5-2b" = {
      kind = "small";
      tier = "small";
      # Measured beside `qfn-fast-colo` (omni-fast) on the R9700, 2026-11-21. `vramMiB` is the
      # model's own footprint: the frontier is resident in both samples, so it cancels out.
      vramMiB = 1567;
      # The resident set with the weights on the card. The load burst is `budget.loadBurstRAMMiB`,
      # not this number: a cold load reads the whole GGUF through the page cache first.
      ramMiB = 568;
      loadSeconds = 4;
      decodeWithFrontier.omni-fast = 122.1;
      measured = "2026-11-21";
      source = "hack/measure-footprint.py";
    };
    "qwen3.5-35b-a3b" = {
      kind = "small";
      tier = "small";
      vramMiB = 22016;
      ramMiB = 22528;
      # Estimated, not measured: GGUF size plus 1 GiB for KV and compute buffers. Replace with a
      # measurement from stage 0 before trusting a tight admission.
      measured = "2026-11-21";
      source = "gguf size + 1 GiB";
    };
    "qwen3.5-4b" = {
      kind = "small";
      tier = "small";
      # Measured beside `qfn-fast-colo` (omni-fast) on the R9700, 2026-11-21. `vramMiB` is the
      # model's own footprint: the frontier is resident in both samples, so it cancels out.
      vramMiB = 3274;
      # The resident set with the weights on the card. The load burst is `budget.loadBurstRAMMiB`,
      # not this number: a cold load reads the whole GGUF through the page cache first.
      ramMiB = 699;
      loadSeconds = 6;
      decodeWithFrontier.omni-fast = 83.6;
      measured = "2026-11-21";
      source = "hack/measure-footprint.py";
    };
  };
}
