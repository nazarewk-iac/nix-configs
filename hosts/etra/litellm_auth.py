"""DB-less custom auth for the LiteLLM gateway.

Configured as `general_settings.custom_auth: "auth.user_api_key_auth"`. LiteLLM
calls this for every request BEFORE its own master-key check, so this hook also
handles the master key (full access) explicitly.

Model:
  - master key (`LITELLM_MASTER_KEY`) -> admin, ALL models (incl. requesty/*).
  - a client key from the keys file  -> only the `models` allow-list for it,
    so a "local-only" key can never reach `requesty/*` (paid) or any other group.

Keys file (JSON, mounted from sops):
    { "<token>": { "name": "pi", "models": ["chat-fast", "chat-deep-slow", ...] }, ... }

Never raises anything other than a 401 for an unknown key.
"""

import json
import os

from fastapi import HTTPException, Request

from litellm.proxy._types import LitellmUserRoles, UserAPIKeyAuth

KEYS_FILE = os.environ.get("KDN_LITELLM_KEYS_FILE", "/etc/litellm-keys/clients")


def _strip_bearer(api_key: str | None) -> str:
    key = api_key or ""
    if key[:7].lower() == "bearer ":
        return key[7:]
    return key


def _load_keys() -> dict:
    try:
        with open(KEYS_FILE, encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


async def user_api_key_auth(request: Request, api_key: str) -> UserAPIKeyAuth:
    token = _strip_bearer(api_key)

    master = os.environ.get("LITELLM_MASTER_KEY")
    if master and token == master:
        return UserAPIKeyAuth(
            api_key=token,
            user_id="master",
            user_role=LitellmUserRoles.PROXY_ADMIN,
        )

    entry = _load_keys().get(token)
    if not entry:
        raise HTTPException(status_code=401, detail="Invalid API key")

    # `models` must be OMITTED (not None) for "all models": UserAPIKeyAuth's field
    # is typed as a list and rejects None. A list restricts to exactly those model
    # group names, so requesty/* is reachable only if it is listed or omitted.
    kwargs = {"api_key": token, "user_id": entry.get("name", "client")}
    models = entry.get("models")
    # "all models": `UserAPIKeyAuth.models` defaults to [] (rejects None), so mark
    # full access explicitly with the conventional ALL_MODELS sentinel.
    kwargs["models"] = models if models is not None else ["all-team-models"]
    return UserAPIKeyAuth(**kwargs)
