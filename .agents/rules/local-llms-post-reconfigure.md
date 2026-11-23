---
type: Rule
title: Local LLMs after a reconfiguration
description: Confirm the local LLM stack after any switch — compare store paths instead of trusting the exit code, restart the manager that caches its policy, read both gateway model endpoints, match the client projection, and make one real call per name, including the refusals.
timestamp: 2026-11-23T22:25:00+01:00
---

# Local LLMs after a reconfiguration

A successful switch does not prove a working stack. The manager caches its policy at start, the
gateway caches its config at start, and the client caches its projection. Each step below catches a
failure the step before it cannot see. Run them in this order.

Hosts: `brys` runs the engine, the placement manager and llama-swap. `etra` runs the LiteLLM
gateway (a container). `oams` is the client.

## 1. Activation: compare store paths, not exit codes

```sh
nix eval --raw .#nixosConfigurations.<host>.config.system.build.toplevel
ssh <host> readlink /run/current-system
```

Both must print the same path. `nixos-rebuild switch` exits 4 on every host because
`kdn-atuin-login-root.service` fails. An exit 4 with an unchanged store path is the only failure
signal; an exit 4 with the new path means the activation worked. Record the path.

```sh
ssh <host> 'systemctl is-system-running; systemctl --failed --no-legend --plain'
ssh etra 'systemctl is-active container@litellm'
```

A container host has one extra trap: a switch can kill `systemd-machined.socket` and report exit 4
while the containers still run. See [Post-change checks](post-change-checks.md) §4.

## 2. Manager: restart it after any policy or config change

`strata-manager` reads `config.json` and `policy.json` **once, at start**. A switch that rewrites
either file leaves the old policy in memory, and every later refusal quotes stale numbers.

```sh
ssh brys 'sudo systemctl restart strata-manager'
ssh brys 'curl -s http://127.0.0.1:8181/status | jq -c "{profile, in_flight, draining}"'
```

The manager restores its profile on start and the engine needs 60–90 s. Wait for a `profile` and
`in_flight: 0` before you call the engine.

## 3. Gateway: read both model endpoints

The client key is root-only.

```sh
K=$(sudo -n cat /run/configs/llms/litellm/client-key)
curl -s -H "Authorization: Bearer $K" https://litellm.etra.priv.nb.net.int.kdn.im/v1/models \
  | jq -r '.data[].id' | sort
curl -s -H "Authorization: Bearer $K" https://litellm.etra.priv.nb.net.int.kdn.im/model/info \
  | jq -r '(.data // .)[] | "\(.model_name)\t\(.model_info.max_input_tokens)\t\(.model_info.max_output_tokens)\t\(.model_info.id)"'
```

- The gateway publishes the window as **`max_input_tokens`**, not the OpenAI field name
  `context_length`. A `null` there means the deployment advertises no window.
- A model **group** prints once, with its default route's numbers. `/model/info` prints one row per
  deployment, so it is the only place that shows the group's candidates.
- 401 = no key. 403 = the key's allow-list does not cover the name. 502 right after a switch = the
  gateway is still starting; check `container@litellm` and look for
  `Started LiteLLM OpenAI-compatible gateway` in its journal.

## 4. Client: the projection must match the gateway

```sh
pi --list-models | grep -E '<the names you changed>'
```

Compare the name, window, max-out and the flags per name with step 3. The `litellm` provider is
curated and carries the thinking and image flags; `litellm-dynamic` is discovery only and shows no
flags. A name that appears in `litellm-dynamic` but not in `litellm` is unprojected.

`dyn-*` names exist **only** on the gateway. `curl https://llama-swap.brys.priv.nb.net.int.kdn.im/v1/models`
must not list them, and a `dyn-*` call to brys or oams must answer `no router for requested model`.
That answer is the design, not a fault.

## 5. Real calls: a listing is not an answer

A listing proves the config parsed. Only a completion proves the engine answers.

```sh
curl -s -H "Authorization: Bearer $K" -H 'Content-Type: application/json' \
  -d '{"model":"dyn-fast","messages":[{"role":"user","content":"Say ok"}],"max_tokens":1}' \
  https://litellm.etra.priv.nb.net.int.kdn.im/v1/chat/completions | jq -c '{usage, msg: .choices[0].message}'
```

- `dyn-fast` returns no `reasoning_content`. `dyn-max` returns one. Both answer on the same prompt.
- A client `max_tokens: 1` must lose to the preset cap: `completion_tokens` greater than 1 proves
  the `extra_body` cap wins.
- A refusal must be readable. `dyn-image` and `dyn-audio` on a full card answer 409 with one
  candidate entry per model, each `check` a **verb** (`fits-beside`, `profile-met`, `unreachable`),
  plus `alternatives`, `remedy`, `select`, and no `confirm`. A `check` that starts with `root` is a
  node id that leaked into the message.
- The engine profile gates the text presets. On an image profile they answer 409 `profile-met` and
  name the profile; they must not time out.
- Switch the profile back after the test, or the next session pays a reload.

## 6. Relays: test from the peer that uses them

The manager binds `127.0.0.1:8181` and the firewall does not open it. A remote caller uses the relay
`etra:8446 → brys:8182 → 127.0.0.1:8181`, which carries `/decide` and `/status` only.

```sh
ssh brys 'curl -s http://127.0.0.1:8182/status | jq -c .profile'
```

llama-swap is relayed the same way. A new mesh port must answer **from the peer**, not from the host
that owns it: a loopback test passes while the firewall still blocks the caller.

## 7. Run the checks for the area

```sh
nix build --no-eval-cache -L \
  .#checks.x86_64-linux.dyn-aliases-config \
  .#checks.x86_64-linux.dyn-aliases-ladder \
  .#checks.x86_64-linux.dyn-aliases-e2e
```

Never run a bare `nix flake check`. See [Checks](checks.md) and [checks/README.md](../../checks/README.md).

## Failure signatures

| symptom                                             | cause                                          | action                                                |
| --------------------------------------------------- | ---------------------------------------------- | ----------------------------------------------------- |
| exit 4, store path unchanged                        | `kdn-atuin-login-root.service`                 | none — the switch worked                              |
| exit 4 on a container host                          | `systemd-machined.socket` is dead              | restart it (post-change-checks §4)                    |
| old policy after a switch                           | the manager cached `config.json`/`policy.json` | restart `strata-manager`                              |
| `max_input_tokens: null`                            | the deployment sets no window                  | fix the derivation, redeploy                          |
| a name in `litellm-dynamic`, absent from `litellm`  | the Pi projection is stale                     | update `mkPiModelsJson` / `data.dyn`                  |
| 403 on a name                                       | the client key allow-list                      | scope the key, do not widen it blindly                |
| 409 with `check: root.5.2`                          | a node id reached the message                  | fix the trace reader, not the policy                  |
| `dyn-*` answers `no router` on brys                 | correct — the names are gateway-only           | call the gateway                                      |
| a 502 immediately after activation                  | the gateway is still starting                  | wait, then repeat the call                            |
| the firmware boots a different entry after a switch | `nixos-rebuild` adds a NixOS boot entry        | check `efibootmgr` when the host must boot unattended |
