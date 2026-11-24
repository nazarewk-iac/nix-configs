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
     its verdict, reason and failing check, the tree's `alternatives`, and the entry to select (the
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
# How long ONE lease attempt may wait for a shared engine slot. A generation holds a slot for
# tens of seconds to minutes, and a cold load is ~50-70 s, so a queue that gives up after 18 s
# would 429 a request that was about to run. Pi's provider idle timeout is 300 s
# (`httpIdleTimeoutMs`), which bounds what is safe to hold.
LEASE_WAIT_SECONDS = 60
# A full pool is a retryable condition, not a failure. Pi retries a 429 by itself (settings
# `retry.enabled` = true, `retry.maxRetries` = 3, `retry.baseDelayMs` = 2000), so the gateway's job
# is to absorb the short burst and then say "retry" — never to hang and never to fall through to
# an unbounded queue at the engine.
LEASE_ATTEMPTS = 2
LEASE_BACKOFF_SECONDS = (2.0,)
LEASE_RETRY_AFTER_SECONDS = 30
# A lease whose release hook never fires would block a slot until the manager's 30-minute TTL. The
# gateway sweeps its own registry after this long and releases what it still holds. It must exceed
# the gateway's own `request_timeout` (3600 s in `litellm.nix`), or the sweep would free a slot that
# a live stream still owns; the streaming hook renews the deadline on every chunk, so this is the
# ceiling for a request that has gone completely silent.
LEASE_MAX_HOLD_SECONDS = 3600
# A lease wait blocks a thread for up to LEASE_WAIT_SECONDS. Running it on the default executor
# would starve every other `to_thread` in the process once enough requests queue (the ladder's
# `/decide` and `/models` reads included), so the waits get their own small pool. When even that
# pool is saturated the answer is a retryable 429, not an unbounded queue.
LEASE_EXECUTOR = ThreadPoolExecutor(max_workers=16, thread_name_prefix="kdn-lease")
LEASE_INFLIGHT = asyncio.Semaphore(16)
# A release that cannot reach the manager is retried by the sweep, not dropped with the entry.
LEASE_RELEASE_RETRY_SECONDS = 60
# An untagged client is `normal`: it must not outrank the human's own turn, and it must not starve
# behind every delegated sub-agent either.
LEASE_DEFAULT_PRIORITY = os.environ.get("KDN_LEASE_DEFAULT_PRIORITY", "normal")


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


def _post_json(url: str, body: dict, timeout: float = TIMEOUT_SECONDS) -> dict | None:
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
        with opener.open(request, timeout=timeout) as response:
            return json.load(response)
    except Exception:
        return None


class ResidentFirst(CustomLogger):
    def __init__(self, **_ignored) -> None:
        super().__init__()
        self._facts: dict | None = None
        self._loaded: set[str] = set()
        self._fetched_at = 0.0
        # request key -> (lease id, deadline). Process-local, because one worker handles both the
        # pre-call and the post-call of a request.
        self._leases: dict[str, tuple[str, float]] = {}

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
        # The gateway NEVER switches, so it must not advertise the tree's `kdn_switch_to` as a
        # request field: a caller that sent it would get the same refusal back, with the field
        # silently passed to the model. Name the llama-swap entry to call instead.
        if named:
            body["select"] = {
                "entries": named,
                "effect": "reloads the engine once on brys (~60 s), then repeat this request",
            }
        return body

    # -------- the shared slot pool --------
    #
    # The manager's `/lease` is the pool: capacity is the resident profile's `parallel`, admission
    # is strict priority (primary > high > normal > low) and FIFO within a class. A lease lives for
    # exactly one model call, never for a session, and it is released on success, failure and
    # stream end. Nothing here may fail a request: a pool that cannot be reached, or a full pool
    # that outlasts the wait, runs the request unleased exactly as before.

    def _priority(self, data: dict) -> str:
        headers = (data.get("proxy_server_request") or {}).get("headers") or {}
        value = str(
            headers.get("x-kdn-priority")
            or headers.get("X-Kdn-Priority")
            or (data.get("metadata") or {}).get("kdn_priority")
            or ""
        ).strip().lower()
        return value if value in ("primary", "high", "normal", "low") else LEASE_DEFAULT_PRIORITY

    def _release_cancelled(self, task) -> None:
        try:
            lease, _ = task.result()
        except Exception:
            return
        if lease is not None:
            self._release_slot(lease)

    def _lease_key(self, data: dict) -> str:
        for field in ("litellm_call_id", "litellm_trace_id"):
            value = data.get(field)
            if isinstance(value, str) and value:
                return value
        return f"local-{id(data)}"

    def _remember_lease(self, key: str, lease: str) -> None:
        now = time.monotonic()
        self._sweep_leases(now)
        # A second pre_call for one key (a retry, a fallback) must not orphan the first lease.
        previous = self._leases.get(key)
        if previous:
            self._release_slot(previous[0])
        self._leases[key] = (lease, now + LEASE_MAX_HOLD_SECONDS)

    def _touch_lease(self, key: str | None) -> None:
        """Renew the deadline of a live streamed request, so the sweep never frees a busy slot."""
        if not key:
            return
        entry = self._leases.get(key)
        if entry:
            self._leases[key] = (entry[0], time.monotonic() + LEASE_MAX_HOLD_SECONDS)

    def _release_key(self, key: str | None) -> None:
        if not key:
            return
        entry = self._leases.pop(key, None)
        if not entry:
            return
        if not self._release_slot(entry[0]):
            # Keep the entry so the sweep retries: dropping it here would orphan the slot for the
            # manager's full TTL with nothing left that remembers it.
            self._leases[key] = (
                entry[0],
                time.monotonic() + LEASE_RELEASE_RETRY_SECONDS,
            )

    def _sweep_leases(self, now: float) -> None:
        for key, (lease, deadline) in list(self._leases.items()):
            if deadline <= now:
                self._leases.pop(key, None)
                self._release_slot(lease)

    def _lease_once(self, priority: str):
        """One lease attempt: (lease, reply).

        `lease` is set when a slot was granted. A non-None `reply` without a lease means the pool
        answered "no free slot", which is retryable and carries the capacity/position for the 429.
        `(None, None)` means the manager could not be reached: a fail-open case, and the request
        proceeds unleased exactly as before.
        """
        base = self._decide_url()
        if not base:
            return None, None
        reply = _post_json(
            f"{base}/lease",
            {"slot": True, "priority": priority, "wait_seconds": LEASE_WAIT_SECONDS},
            timeout=LEASE_WAIT_SECONDS + 2,
        )
        if not reply:
            return None, None
        lease = reply.get("lease")
        if isinstance(lease, str) and lease:
            return lease, reply
        return None, reply

    def _release_slot(self, lease) -> bool:
        base = self._decide_url()
        if not base or not isinstance(lease, str) or not lease:
            return True
        return _post_json(f"{base}/release", {"lease": lease}) is not None

    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        if "embedding" in str(call_type) or "rerank" in str(call_type):
            return data
        priority = self._priority(data)
        last: dict | None = None
        for attempt in range(LEASE_ATTEMPTS):
            if LEASE_INFLIGHT.locked():
                raise HTTPException(
                    status_code=429,
                    detail={
                        "error": "too many requests are already waiting for an engine slot",
                        "priority": priority,
                        "retry_after_seconds": LEASE_RETRY_AFTER_SECONDS,
                    },
                    headers={"Retry-After": str(LEASE_RETRY_AFTER_SECONDS)},
                )
            loop = asyncio.get_running_loop()
            async with LEASE_INFLIGHT:
                pending = asyncio.ensure_future(
                    loop.run_in_executor(LEASE_EXECUTOR, self._lease_once, priority)
                )
                try:
                    lease, reply = await asyncio.shield(pending)
                except asyncio.CancelledError:
                    # The worker thread may still obtain a slot after the client is gone. Release
                    # it when it lands instead of leaving it to the sweep.
                    pending.add_done_callback(self._release_cancelled)
                    raise
            if lease is not None:
                key = self._lease_key(data)
                self._remember_lease(key, lease)
                metadata = data.get("metadata")
                if not isinstance(metadata, dict):
                    metadata = {}
                    data["metadata"] = metadata
                metadata["kdn_lease"] = lease
                metadata["kdn_lease_key"] = key
                return data
            if reply is None:
                # The pool is unreachable: fail open, never fail a request.
                return data
            last = reply
            if attempt < LEASE_ATTEMPTS - 1:
                await asyncio.sleep(LEASE_BACKOFF_SECONDS[attempt])
        capacity = (last or {}).get("capacity")
        position = (last or {}).get("position")
        raise HTTPException(
            status_code=429,
            detail={
                "error": (
                    f"no free engine slot for priority {priority!r} after "
                    f"{LEASE_ATTEMPTS} attempts; retry is safe"
                ),
                "priority": priority,
                "capacity": capacity,
                "position": position,
                "retry_after_seconds": LEASE_RETRY_AFTER_SECONDS,
            },
            headers={"Retry-After": str(LEASE_RETRY_AFTER_SECONDS)},
        )

    async def async_post_call_success_hook(self, data, user_api_key_dict, response):
        self._release_lease_for(data)
        return response

    def _release_lease_for(self, data: dict) -> None:
        """Release by the request key, falling back to the lease id carried in metadata.

        The key is authoritative: it survives a hook that receives a copy of the data, and the
        registry sweep still frees the slot if no hook runs at all.
        """
        key = (data.get("metadata") or {}).get("kdn_lease_key") or self._lease_key(data)
        self._release_key(key)

    async def async_post_call_streaming_iterator_hook(
        self, user_api_key_dict, response, request_data
    ):
        key = (request_data.get("metadata") or {}).get("kdn_lease_key")
        try:
            async for item in response:
                self._touch_lease(key)
                yield item
        finally:
            self._release_lease_for(request_data)

    async def async_post_call_failure_hook(
        self, request_data, original_exception, user_api_key_dict, traceback_str=None
    ):
        self._release_lease_for(request_data)
        return None

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
