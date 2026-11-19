---
type: Solution
description: Add DB-less model-scoped client API keys to the LiteLLM gateway and a working Requesty backend, and answer that Pi cannot auto-discover Requesty models through the gateway.
task: definition.md
authored_by: agent
timestamp: 2026-11-14T05:09:42+01:00
---

# LiteLLM client API keys and Requesty — done

## Solution

Non-master clients get their own API keys, each scoped to an allow-list of model groups, so a
"local-only" key can never reach paid providers. The master key keeps full access. Requesty is a
second backend behind the gateway.

| Where                                     | What                                                                                                                                                                                             |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `hosts/etra/litellm_auth.py`              | `custom_auth` (`user_api_key_auth`). Reads the sops-mounted `token -> {name, models}` map; handles the master key explicitly (PROXY_ADMIN, all models).                                          |
| `hosts/etra/litellm_enforce.py`           | `enforce.scope` — a `pre_call` hook that enforces the token's model-group list, which LiteLLM would otherwise skip (`litellm.enable_post_custom_auth_checks` is not a config key). Fails closed. |
| `hosts/etra/litellm-keys.sops.yaml`       | the keys, sops-encrypted (etra ssh-host key + recovery YubiKeys), wrapped as `keys: { clients: <json> }` for the `keyPrefix`.                                                                    |
| `hosts/etra/litellm_requesty_discover.py` | fetches Requesty's real `/v1/models` and emits explicit LiteLLM deployments (tested live: returns the 4 real ids, not the wildcard's fake price-map names).                                      |
| `hosts/etra/litellm.nix`                  | Requesty egress: a `tinyproxy` CONNECT on `:8888`, the container's `HTTPS_PROXY`, and explicit `api_base = https://router.requesty.ai/v1`.                                                       |

Decisions that held:

- **DB-less** custom auth + `pre_call` enforcement (no DB, no prisma engine).
- **Explicit `requesty/*` deployments, not the wildcard** — the wildcard lists LiteLLM's OpenAI
  price-map names, not Requesty's real catalog, and it 404s on call.
- **Requesty egress via a CONNECT proxy, not the socat relay** — the relay keeps the relay's
  `Host` header, so Requesty serves its default vhost and 404s; a raw TLS tunnel cannot rewrite
  `Host`, but a proxy preserves SNI/Host.

## Pi auto-discovery — the answer

No real auto-discovery. Through the gateway a client's model list is its own static catalog; the
gateway can list model groups but there is no catalog pass-through for Requesty. To surface real
Requesty models a client enumerates them explicitly (few, and Requesty's real set is small).

## Verification

Observed on etra (sessions of 2026-11-07 and 2026-11-13):

- Client `pi-fast` (`["chat-fast"]`) → `chat-fast` 200, `chat-deep-slow` 403, `requesty/...` 403;
  unknown key 401; master → any group 200.
- Requesty models serve through the gateway after the 2026-11-13 etra switch: `GET /v1/models`
  lists `requesty/alibaba/qwen3.8-flash`, `requesty/deepinfra/...`, `requesty/tensorx/qwen3.8-flash-next`;
  a `requesty/alibaba/qwen3.8-flash` completion returns 200.

Re-check:

```bash
# a scoped client key must 403 out-of-scope and 200 in scope
curl -sS -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: Bearer <pi-fast-key>" \
  -d '{"model":"chat-deep-slow","messages":[{"role":"user","content":"hi"}]}' \
  http://<etra>:4000/v1/chat/completions
```

## Follow-up notes

- **Runtime auto-discovery** (the `--base/--out` merge plus a `systemd` timer re-running
  `litellm_requesty_discover.py` and restarting litellm) is designed and the script is tested, but
  not wired. The current source of truth is the pinned `requestyModelIds` list; refresh it with the
  script when Requesty's catalog changes.
- **DB mode** for budgets / rotation / UI remains optional and unchosen.
- The "cheap sub-tasks default to `chat-fast`" policy is tracked under `litellm-auto-router`.
