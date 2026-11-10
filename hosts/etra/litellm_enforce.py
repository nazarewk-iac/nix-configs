"""Model-scope enforcement for the LiteLLM gateway (DB-less).

The custom-auth hook (`auth.user_api_key_auth`) authenticates a client key and
attaches its `models` allow-list to the UserAPIKeyAuth. LiteLLM does NOT enforce
that list for custom-auth tokens unless `litellm.enable_post_custom_auth_checks`
is on (a getattr-only global), so this `pre_call` hook does the check explicitly:

  - admin / master (role PROXY_ADMIN) or `models is None`  -> allow all.
  - a key with a `models` list (optionally containing "all-team-models")
    -> only those model group names; anything else is a 403, raised BEFORE the
       call reaches the upstream. This is what stops a "local-only" key from
       spending on `requesty/*`.

Never allow a bug here to silently widen access: an unexpected error while
enforcing re-raises (fails closed) rather than passing the request through.
"""

from fastapi import HTTPException

from litellm.integrations.custom_logger import CustomLogger


def _is_admin(role) -> bool:
    text = str(role or "")
    return text.endswith("PROXY_ADMIN") or text == "proxy_admin"


class ModelScope(CustomLogger):
    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        try:
            if _is_admin(getattr(user_api_key_dict, "user_role", None)):
                return data
            allowed = getattr(user_api_key_dict, "models", None)
            # None or the ALL_MODELS sentinel => unrestricted. An empty list is
            # NOT unrestricted (fail-closed): a key scoped to nothing can call nothing.
            if allowed is None or "all-team-models" in allowed:
                return data
            model = (data or {}).get("model")
            if model is not None and model not in allowed:
                raise HTTPException(
                    status_code=403,
                    detail=f"API key is not allowed to call model group {model!r}",
                )
            return data
        except HTTPException:
            raise
        except Exception as exc:  # fail closed
            raise HTTPException(
                status_code=500, detail=f"model-scope check failed: {exc}"
            ) from exc


# Module-level instance, so the config can name `enforce.scope`.
scope = ModelScope()
