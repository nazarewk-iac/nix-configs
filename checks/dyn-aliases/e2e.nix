# The `dyn-*` contract end to end: the real LiteLLM gateway, the real residency callback, and a fake
# brys on loopback.
#
# The two cheaper checks beside this one assert the values (`config.nix`) and the ladder's logic
# against fake deployments (`ladder.nix`). Neither proves that LiteLLM actually sends what the
# preset declares, that the client sees what the upstream returns, or that a callback refusal
# reaches the client as a 409 with its structure intact. That needs the whole chain in one process
# tree, so this check runs it.
#
# Three processes in the VM:
#
#   * `fake-brys` — `e2e_fake_brys.py`: llama-swap's `GET /v1/models`, the placement tree's
#     `POST /decide` and `/status`, and `POST /v1/chat/completions`. It records every upstream body
#     and adds `reasoning_content` only when the body carried `enable_thinking: true`, so it is the
#     proof of the preset enforcement.
#   * `litellm` — `pkgs.litellm`, the same package the etra container runs, with
#     `hosts/etra/litellm_resident.py` on `PYTHONPATH` as `resident.py`.
#   * `e2e_driver.py` — the client: it sets the fake's state, calls the gateway, asserts.
#
# The container on etra is only a carrier: nspawn, bind mounts and a private veth with socat relays.
# The package itself runs directly, so this check needs no image, no GPU, no brys and no network
# beyond the VM.
#
# The config is built here rather than imported from `hosts/etra/litellm.nix`: that module needs
# `config`, `kdnConfig` and sops-decrypted key files, and it renders a container. The five groups
# below are the host's five, from the same `lib/llm.nix` values; only `api_base`/`api_key` differ.
{
  pkgs,
  lib,
  ...
}:
let
  llm = import ../../lib/llm.nix { inherit lib; };
  data = import ../../data/llm.nix;
  strata = llm.strata data "brys";

  fakePort = 18080;
  gatewayPort = 4000;
  masterKey = "sk-dyn-e2e";
  stateDir = "/var/lib/dyn-e2e";
  apiBase = "http://127.0.0.1:${toString fakePort}/v1";

  # The host's `dynTextDeployments`: one deployment per preset, with the request shape fixed in
  # `extra_body`. `extra_body.max_tokens` wins over the client's value; `chat_template_kwargs` is
  # advertised rather than enforced (a client that sends its own replaces it wholesale), which is
  # exactly what assertion 1 and 2 measure.
  textDeployments = map (preset: {
    model_name = preset.name;
    litellm_params = {
      model = "openai/${preset.base}";
      api_base = apiBase;
      api_key = "fake-brys-key";
      extra_body = {
        chat_template_kwargs = preset.kwargs;
        max_tokens = preset.maxTokens;
      };
    };
    model_info = {
      id = "brys-${preset.name}";
      max_input_tokens = preset.context;
      max_output_tokens = lib.min preset.maxTokens preset.context;
    };
  }) llm.dynTextPresets;

  # The host's `dynModalityDeployments`: one model group per modality, one deployment per candidate
  # in preference order. The callback returns exactly one of them, so the routing strategy never
  # decides anything here.
  modalityDeployments = lib.concatMap (
    group:
    map (baseId: {
      model_name = group.name;
      litellm_params = {
        model = "openai/${baseId}";
        api_base = apiBase;
        api_key = "fake-brys-key";
      };
      model_info = {
        id = "brys-${group.name}-${baseId}";
        max_input_tokens = group.context;
        max_output_tokens = group.maxTokens;
      };
    }) group.models
  ) llm.dynModalityGroups;

  gatewayConfig = (pkgs.formats.json { }).generate "dyn-e2e-litellm-config.json" {
    model_list = textDeployments ++ modalityDeployments;
    litellm_settings = {
      callbacks = [ "resident.resident_fit" ];
      drop_params = true;
    };
    general_settings = {
      master_key = "os.environ/LITELLM_MASTER_KEY";
    };
    router_settings = {
      # The refusal is not retried, so the recorded candidate walk is exactly one pass. The etra
      # config retries once, which repeats the same walk with the same verdicts.
      num_retries = 0;
    };
  };

  # The facts `resident.resident_fit` reads, rendered exactly as `hosts/etra/litellm.nix` renders
  # them: names only, because every fit question goes to the tree.
  residentPolicy = (pkgs.formats.json { }).generate "dyn-e2e-resident-policy.json" {
    groups =
      lib.listToAttrs (
        map (
          preset:
          lib.nameValuePair preset.name {
            kind = "text";
            models = [ preset.base ];
          }
        ) llm.dynTextPresets
      )
      // lib.listToAttrs (
        map (
          group:
          lib.nameValuePair group.name {
            inherit (group) kind models;
          }
        ) llm.dynModalityGroups
      );
    inherit (strata) textProfiles;
    profiles = lib.genAttrs strata.textProfiles (
      profile:
      lib.concatMap (name: [ name ] ++ (data.models.${name}.aliases or [ ])) (
        lib.filter (
          name: ((data.models.${name}.hosts or { }).brys.serving or { }).profile or "" == profile
        ) (builtins.attrNames data.models)
      )
    );
  };
in
pkgs.testers.runNixOSTest {
  name = "dyn-aliases-e2e";

  nodes.machine = {
    # LiteLLM is a Python proxy with an OpenAI client and a router; one CPU starves its startup.
    virtualisation = {
      memorySize = 2048;
      cores = 2;
    };

    # The two facts files, the callback module (mounted as `resident.py`, the name the host uses)
    # and the fake. `/etc/dyn-e2e` is the callback's PYTHONPATH.
    environment.etc = {
      "dyn-e2e/config.yaml".source = gatewayConfig;
      "dyn-e2e/resident-policy.json".source = residentPolicy;
      "dyn-e2e/resident.py".source = ../../hosts/etra/litellm_resident.py;
      "dyn-e2e/fake-brys.py".source = ./e2e_fake_brys.py;
    };

    systemd.tmpfiles.rules = [ "d ${stateDir} 0755 root root -" ];

    systemd.services.fake-brys = {
      description = "Fake brys: llama-swap /v1/models and the placement tree /decide";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      environment = {
        DYN_E2E_STATE = stateDir;
        DYN_E2E_POLICY = "/etc/dyn-e2e/resident-policy.json";
        DYN_E2E_PORT = toString fakePort;
      };
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 /etc/dyn-e2e/fake-brys.py";
        Restart = "always";
        RestartSec = 1;
      };
    };

    systemd.services.litellm = {
      description = "LiteLLM gateway (dyn-* end-to-end check)";
      wantedBy = [ "multi-user.target" ];
      after = [ "fake-brys.service" ];
      wants = [ "fake-brys.service" ];
      # The same environment the etra unit sets, with every endpoint on loopback: `BRYS_API_BASE`
      # is both the completion upstream and the residency source, and `KDN_DECIDE_URL` is the tree.
      environment = {
        PYTHONPATH = "/etc/dyn-e2e";
        KDN_RESIDENT_POLICY = "/etc/dyn-e2e/resident-policy.json";
        KDN_DECIDE_URL = "http://127.0.0.1:${toString fakePort}";
        BRYS_API_BASE = apiBase;
        BRYS_API_KEY = "fake-brys-key";
        LITELLM_MASTER_KEY = masterKey;
        # Start from the cost map bundled in the package: the VM has no egress, and the default
        # path spends 18 s retrying the GitHub fetch before it falls back to the same file.
        LITELLM_LOCAL_MODEL_COST_MAP = "True";
        HOME = stateDir;
      };
      serviceConfig = {
        ExecStart = "${pkgs.litellm}/bin/litellm --config /etc/dyn-e2e/config.yaml --host 127.0.0.1 --port ${toString gatewayPort}";
        Restart = "always";
        RestartSec = 2;
      };
    };
  };

  # The driver polls `/health/liveliness` itself: a uvicorn boot is slower than the unit's start,
  # and a poll that fails prints the gateway journal instead of only a status code. Its output is
  # printed on the host side, so a passing run keeps the assertion summary in the build log.
  testScript = ''
    machine.start()
    machine.wait_for_unit("fake-brys.service")
    machine.wait_for_unit("litellm.service")
    status, output = machine.execute("${pkgs.python3}/bin/python3 ${./e2e_driver.py}")
    print(output)
    assert status == 0, "the dyn-* driver failed"
  '';
}
