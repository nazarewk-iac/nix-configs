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
{ lib }:
let
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
  defaultDeadlineSeconds = 120;
  # Below this, a model beside the frontier is not worth serving: the measured companion beside the
  # whole-card profile ran at 6.1 t/s.
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

  models = {
    # ---------------------------------------------------------------- engines
    # `qfn` is profile-neutral: it is served by whatever text profile is current, so the policy
    # refuses it on an image profile instead of letting a chat request reach a diffusion server.
    qfn = {
      kind = "engine";
      tier = "frontier";
      persistent = true;
      requiresProfile = [
        "max"
        "omni-max"
        "omni-fast"
      ];
      vramMiB = 10957;
      ramMiB = 60000;
      measured = "2026-11-20";
      source = "docs/tasks/2026-11/policy-behaviour-tree/definition.md";
    };
    "qfn-max" = {
      kind = "engine";
      tier = "frontier";
      profile = "max";
      persistent = true;
      vramMiB = 31539;
      ramMiB = 62000;
      switchSeconds = 72;
      measured = "2026-11-20";
    };
    "qfn-fast-colo" = {
      kind = "engine";
      tier = "frontier";
      profile = "omni-fast";
      persistent = true;
      vramMiB = 10957;
      ramMiB = 60000;
      switchSeconds = 55;
      measured = "2026-11-20";
    };
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
      vramMiB = 20685;
      ramMiB = 21000;
      minResidencySeconds = 60;
      # Measured: 98.8 t/s beside omni-fast, 6.1 t/s beside max. The floor is what stops the second.
      decodeWithFrontier = {
        omni-fast = 98.8;
        max = 6.1;
      };
      measured = "2026-11-20";
    };
    "qwen2.5-vl-7b" = {
      kind = "companion";
      tier = "companion";
      requiresProfile = [
        "omni-max"
        "omni-fast"
      ];
      vramMiB = 12595;
      ramMiB = 11000;
      minResidencySeconds = 60;
      decodeWithFrontier = {
        omni-fast = 40.0;
      };
      measured = "2026-11-20";
    };
  };
}
