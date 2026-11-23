"""The `dyn-*` residency ladder for the LiteLLM gateway.

Loaded by LiteLLM as a callback (`resident.resident_fit`) from beside config.yaml, and named in
`litellm_settings.callbacks`. It acts only on the groups listed in its facts file
(`KDN_RESIDENT_POLICY`, `/etc/litellm/resident-policy.json`), which hosts/etra/litellm.nix renders
from `data/llm.nix`. The facts are NAMES ONLY — the candidate order, the text profiles, and the
llama-swap entry that forces each profile. Every fit question goes to the placement tree
(`POST /decide`), so there is no second copy of the `vramMiB`/`kvReserveMiB` arithmetic here.

The ladder, per request, for one group:

  1. **Resident** — a modality candidate that brys' llama-swap already reports as loaded wins, in
     the group's preference order. (Text presets skip this rung: their candidate is `qfn`, the
     profile-neutral `auto` alias, and the question is the profile, not residency.)
  2. **Admit** — one `POST /decide {"model": candidate}` per remaining candidate, in order; the
     first `admit` (or `wait`, which means "join the load already in flight") wins and its
     deployment is returned, so the upstream loads it. Nothing is switched or unloaded.
  3. **Refuse** — nothing admits: a 409 built from the tree's own answer. `error` is the readable
     summary, and the body carries `current_profile` (from `/status`), one entry per candidate with
     its verdict, reason and failing check, the tree's `alternatives` and `confirm` field, and the
     llama-swap entry that forces each alternative.

A text preset on an image profile is the case that needs the third rung: the manager resolves
`qfn` to the profile-neutral engine, finds none, and the tree answers "unknown model". The callback
knows the candidate is real, so it says what that means — the engine rests on an image profile and
`auto` is refused there — and names the text profiles that would serve it.

`reload_seconds` is deliberately absent. The companion gate hardcodes 70; the manager exposes no
expected switch time (`/status` carries the LAST switch, not the next), so the field is dropped
rather than guessed.

The refusal is a FastAPI `HTTPException`, and LiteLLM maps it to the client's error body:
`async_callback_filter_deployments` re-raises whatever the callback raises (`litellm/router.py`),
`_handle_llm_api_exception` turns an `HTTPException` into `ProxyException(message=<error>,
code=<status>)` and keeps the rest of a dict detail as structured fields
(`litellm/proxy/common_request_processing.py`), and `openai_exception_handler` renders
`{"error": {...}}` (`litellm/proxy/proxy_server.py`). Verified in litellm 1.85.0.

Never raises anything but that refusal: an unreachable tree or a selector bug must not break
routing, so the group falls through to its deployments unchanged.
"""

import asyncio
import json
import os
from concurrent.futures import ThreadPoolExecutor
import time
import urllib.request

from fastapi import HTTPException
from litellm.integrations.custom_logger import CustomLogger

FACTS_PATH = "/etc/litellm/resident-policy.json"
# How long a `/v1/models` answer stays usable. Residency changes on a model load, not between two
# requests of one turn, so this only keeps a busy group from polling.
CACHE_SECONDS = 2.0
TIMEOUT_SECONDS = 2.0


def _upstream_model(deployment: dict) -> str:
    """The model id this deployment sends upstream (`openai/<id>` in the config)."""
    model = str((deployment.get("litellm_params") or {}).get("model") or "")
    prefix = "openai/"
    return model[len(prefix) :] if model.startswith(prefix) else model


def _get_json(url: str) -> dict | None:
    """A GET that degrades to None: the ladder must not fail because a relay is slow."""
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(url, timeout=TIMEOUT_SECONDS) as response:
            return json.load(response)
    except Exception:
        return None


def _post_json(url: str, body: dict) -> dict | None:
    """A POST that degrades to None, for the same reason."""
    request = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    # No proxy for an internal relay: the container's HTTP_PROXY is the SaaS egress.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(request, timeout=TIMEOUT_SECONDS) as response:
            return json.load(response)
    except Exception:
        return None


class ResidentFirst(CustomLogger):
    def __init__(self, **_ignored) -> None:
        super().__init__()
        self._facts: dict | None = None
        self._loaded: set[str] = set()
        self._fetched_at = 0.0

    def _policy(self) -> dict:
        if self._facts is None:
            with open(
                os.environ.get("KDN_RESIDENT_POLICY", FACTS_PATH), encoding="utf-8"
            ) as handle:
                self._facts = json.load(handle)
        return self._facts

    def _decide_url(self) -> str:
        return os.environ.get("KDN_DECIDE_URL", "").rstrip("/")

    def _fetch_loaded(self) -> set[str]:
        """The ids llama-swap reports as loaded, or the last answer on any failure."""
        now = time.monotonic()
        if self._fetched_at and now - self._fetched_at < CACHE_SECONDS:
            return self._loaded
        base = os.environ.get("BRYS_API_BASE", "").rstrip("/")
        if not base:
            return self._loaded
        request = urllib.request.Request(
            base + "/models",
            headers={"Authorization": "Bearer " + os.environ.get("BRYS_API_KEY", "")},
        )
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        try:
            with opener.open(request, timeout=TIMEOUT_SECONDS) as response:
                payload = json.load(response)
        except Exception:
            # A dead backend keeps the previous answer: the group still routes, and the request
            # fails upstream with llama-swap's own message.
            return self._loaded
        self._loaded = {
            str(entry.get("id"))
            for entry in payload.get("data") or []
            if isinstance(entry, dict)
            and str((entry.get("status") or {}).get("value") or "") == "loaded"
        }
        self._fetched_at = now
        return self._loaded

    def _decide(self, model: str) -> dict | None:
        """The placement tree's advisory answer for one candidate, or None when unreachable."""
        url = self._decide_url()
        if not url:
            return None
        return _post_json(url + "/decide", {"model": model})

    def _current_profile(self) -> str:
        url = self._decide_url()
        if not url:
            return "unknown"
        status = _get_json(url + "/status") or {}
        return str(status.get("profile") or "unknown")

    def _failing_check(self, result: dict) -> str:
        """The last CHECK the tree failed, so the refusal names a verb and not a node id.

        The trace also carries `action` nodes (`refuse`, `load`); those have no verb, and the
        first version returned the last failing node of any type, which surfaced `root.5.2` where
        the caller needs `fits-beside`. Prefer a step with a verb; fall back to the node id only
        when the tree failed without one.
        """
        fallback = ""
        for step in reversed(result.get("why") or []):
            if str(step.get("result") or "") != "failure":
                continue
            if step.get("verb"):
                return str(step["verb"])
            if not fallback:
                fallback = str(step.get("node") or "")
        return fallback

    def _refusal(
        self, model: str, kind: str, verdicts: list[tuple[str, dict | None]]
    ) -> dict:
        facts = self._policy()
        profile = self._current_profile()
        profiles = facts.get("profiles") or {}
        candidates = []
        alternatives: list[str] = []
        confirm_field = ""
        for base, decision in verdicts:
            result = decision or {}
            refusal = result.get("refusal") or {}
            reason = str(
                refusal.get("reason") or result.get("explain") or "no decision"
            )
            check = self._failing_check(result)
            if decision is None:
                reason = "the placement manager did not answer"
                check = "unreachable"
            elif kind == "text" and reason == "unknown model":
                # `qfn` is the `auto` alias: the manager resolves it to the profile-neutral engine
                # only while a text profile is current, and answers "unknown model" otherwise.
                reason = (
                    f"the engine rests on {profile!r}, which is not a text profile, so `auto` is "
                    "refused there"
                )
                check = "profile-met"
            if not alternatives and refusal.get("alternatives"):
                alternatives = [str(name) for name in refusal["alternatives"]]
                confirm_field = str(refusal.get("confirmField") or "")
            if kind == "text" and not alternatives:
                # A text preset is not gated: the caller selects a profile on llama-swap, so there
                # is no body field to confirm with.
                alternatives = [str(name) for name in facts.get("textProfiles") or []]
            candidates.append(
                {
                    "model": base,
                    "verdict": str(result.get("verdict") or "no verdict"),
                    "reason": reason,
                    "check": check,
                }
            )
        # Name the entry that forces each alternative, not only the manager's internal profile.
        named = [
            f"{' / '.join(profiles.get(name) or [name])} (profile {name})"
            for name in alternatives
        ]
        tried = "; ".join(
            f"{c['model']}: {c['verdict']}"
            + (f" at {c['check']}" if c["check"] else "")
            + f" ({c['reason']})"
            for c in candidates
        )
        body: dict = {
            "error": (
                f"no {model} ({kind}) candidate can answer without switching the engine: {tried}. "
                f"Current profile: {profile}. Nothing was unloaded and no profile was switched."
            ),
            "current_profile": profile,
            "candidates": candidates,
        }
        if named:
            body["alternatives"] = alternatives
            body["remedy"] = named
        if confirm_field:
            body["confirm"] = {
                "field": confirm_field,
                "value": "a profile name from alternatives",
            }
        return body

    async def async_filter_deployments(
        self,
        model: str,
        healthy_deployments: list,
        messages=None,
        request_kwargs=None,
        parent_otel_span=None,
    ) -> list:
        try:
            facts = self._policy()
            group = (facts.get("groups") or {}).get(model)
            if not group or not healthy_deployments:
                return healthy_deployments
            candidates = group.get("models") or []
            kind = str(group.get("kind") or "modality")
            by_model: dict[str, dict] = {}
            for deployment in healthy_deployments:
                by_model.setdefault(_upstream_model(deployment), deployment)

            # 1. Already resident: nothing to load, nothing to evict. Text presets skip this rung.
            if kind != "text":
                loaded = await asyncio.to_thread(self._fetch_loaded)
                for base in candidates:
                    if base in loaded and base in by_model:
                        return [by_model[base]]

            # 2. The tree decides. One advisory POST per candidate, in preference order.
            verdicts: list[tuple[str, dict | None]] = []
            for base in candidates:
                decision = await asyncio.to_thread(self._decide, base)
                verdicts.append((base, decision))
                if str((decision or {}).get("verdict") or "") in ("admit", "wait"):
                    if base in by_model:
                        return [by_model[base]]

            # 3. Refuse, with the tree's own reasoning.
            raise HTTPException(
                status_code=409,
                detail=await asyncio.to_thread(self._refusal, model, kind, verdicts),
            )
        except HTTPException:
            raise
        except Exception:
            return healthy_deployments


# Module-level instance, so the config can name `resident.resident_fit`.
resident_fit = ResidentFirst()
