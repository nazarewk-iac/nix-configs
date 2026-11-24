"""The `dyn-*` residency ladder, driven with fake deployments.

`litellm_resident.py` imports `CustomLogger` from LiteLLM. The stub below satisfies that import
before the file is loaded, so the check needs no LiteLLM dependency tree; `fastapi` stays real, so
the refusal is the same `HTTPException` LiteLLM maps to the client's error body.
"""

import asyncio
import os
import time
import sys
import types

litellm = types.ModuleType("litellm")


class CustomLogger: ...


litellm.CustomLogger = CustomLogger
sys.modules["litellm"] = litellm
sys.modules["litellm.integrations"] = types.ModuleType("litellm.integrations")
sys.modules["litellm.integrations.custom_logger"] = types.ModuleType(
    "litellm.integrations.custom_logger"
)
sys.modules["litellm.integrations.custom_logger"].CustomLogger = CustomLogger

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import pytest  # noqa: E402
from fastapi import HTTPException  # noqa: E402

import litellm_resident  # noqa: E402

IMAGE_MODELS = ["qwen3-vl-30b-a3b", "ornith-1.5-35b-a3b", "qwen2.5-vl-7b"]

IMAGE_POLICY = {
    "groups": {"dyn-image": {"kind": "image", "models": IMAGE_MODELS}},
    "textProfiles": ["qfn-fast-colo", "qfn-max-colo"],
    "profiles": {
        "qfn-fast-colo": ["qfn-fast-colo"],
        "qfn-max-colo": ["qfn-max-colo"],
    },
}

TEXT_POLICY = {
    "groups": {"dyn-fast": {"kind": "text", "models": ["qfn"]}},
    "textProfiles": ["qfn-fast-colo", "qfn-max-colo"],
    "profiles": {
        "qfn-fast-colo": ["qfn-fast-colo"],
        "qfn-max-colo": ["qfn-max-colo"],
    },
}

REFUSAL = {
    "verdict": "refuse",
    "refusal": {"reason": "no fit", "alternatives": ["qfn-fast-colo", "qfn-max-colo"]},
    # The action node comes last and has no verb: the refusal must still name `fits-beside`.
    "why": [
        {"verb": "fits-beside", "result": "failure"},
        {"node": "root.5.2", "result": "failure"},
    ],
}


def deployment(base):
    """The shape `_upstream_model` reads: a LiteLLM deployment is a dict."""
    return {
        "litellm_params": {"model": f"openai/{base}"},
        "model_info": {"id": f"brys-dyn-image-{base}"},
    }


def build(policy, *, loaded=None, decide=None, profile="omni-max"):
    resident = litellm_resident.ResidentFirst()
    resident._policy = lambda: policy
    resident._fetch_loaded = lambda: set(loaded or ())
    resident._decide = decide or (lambda model: {"verdict": "refuse"})
    resident._current_profile = lambda: profile
    return resident


def run(resident, model, deployments):
    return asyncio.run(resident.async_filter_deployments(model, deployments))


def test_resident_candidate_wins_without_asking_the_tree():
    calls = []

    def decide(model):
        calls.append(model)
        return {"verdict": "admit"}

    resident = build(IMAGE_POLICY, loaded={IMAGE_MODELS[1]}, decide=decide)
    deployments = [deployment(base) for base in IMAGE_MODELS]

    assert run(resident, "dyn-image", deployments) == [deployments[1]]
    assert calls == []


def test_first_admitted_candidate_wins_in_order():
    calls = []
    verdicts = {
        IMAGE_MODELS[0]: {"verdict": "refuse"},
        IMAGE_MODELS[1]: {"verdict": "refuse"},
        IMAGE_MODELS[2]: {"verdict": "admit"},
    }

    def decide(model):
        calls.append(model)
        return verdicts[model]

    resident = build(IMAGE_POLICY, decide=decide)
    deployments = [deployment(base) for base in IMAGE_MODELS]

    assert run(resident, "dyn-image", deployments) == [deployments[2]]
    assert calls == IMAGE_MODELS


def test_refusal_is_a_409_built_from_the_tree():
    resident = build(IMAGE_POLICY, decide=lambda model: REFUSAL)
    deployments = [deployment(base) for base in IMAGE_MODELS]

    with pytest.raises(HTTPException) as caught:
        run(resident, "dyn-image", deployments)

    assert caught.value.status_code == 409
    detail = caught.value.detail
    assert detail["current_profile"] == "omni-max"
    assert [candidate["model"] for candidate in detail["candidates"]] == IMAGE_MODELS
    for candidate in detail["candidates"]:
        assert candidate["verdict"] == "refuse"
        assert candidate["reason"] == "no fit"
        assert candidate["check"] == "fits-beside"
        assert not candidate["check"].startswith("root")
    assert detail["alternatives"] == ["qfn-fast-colo", "qfn-max-colo"]
    assert detail["remedy"] == [
        "qfn-fast-colo (profile qfn-fast-colo)",
        "qfn-max-colo (profile qfn-max-colo)",
    ]
    assert detail["select"]["entries"] == detail["remedy"]
    assert "reloads the engine" in detail["select"]["effect"]
    assert "confirm" not in detail


def test_text_preset_names_the_image_profile_that_refuses_auto():
    resident = build(
        TEXT_POLICY,
        decide=lambda model: {
            "verdict": "refuse",
            "refusal": {"reason": "unknown model"},
        },
        profile="omni-max",
    )

    with pytest.raises(HTTPException) as caught:
        run(resident, "dyn-fast", [deployment("qfn")])

    candidate = caught.value.detail["candidates"][0]
    assert "omni-max" in candidate["reason"]
    assert candidate["check"] == "profile-met"


def test_unreachable_manager_is_named_as_such():
    resident = build(IMAGE_POLICY, decide=lambda model: None)
    deployments = [deployment(base) for base in IMAGE_MODELS]

    with pytest.raises(HTTPException) as caught:
        run(resident, "dyn-image", deployments)

    for candidate in caught.value.detail["candidates"]:
        assert candidate["reason"] == "the placement manager did not answer"
        assert candidate["check"] == "unreachable"


def test_pre_call_fails_open_when_the_pool_is_unreachable():
    """No manager, no lease, no failure: a pool that cannot be reached must never fail a request."""
    resident = litellm_resident.ResidentFirst()
    resident._decide_url = lambda: ""
    data = {"model": "qfn", "messages": []}
    returned = asyncio.run(resident.async_pre_call_hook(None, None, data, "acompletion"))
    assert returned is data
    assert "kdn_lease" not in (data.get("metadata") or {})


def test_pre_call_retries_a_full_pool_and_then_returns_429(monkeypatch):
    """A full pool is retryable, not fatal: three attempts, then a 429 the harness can retry."""
    resident = litellm_resident.ResidentFirst()
    resident._decide_url = lambda: "http://pool"
    calls = {"n": 0}

    def always_full(priority):
        calls["n"] += 1
        return None, {"wait": True, "capacity": 5, "position": 7, "priority": priority}

    resident._lease_once = always_full
    monkeypatch.setattr(litellm_resident, "LEASE_BACKOFF_SECONDS", (0.0,))

    with pytest.raises(HTTPException) as raised:
        asyncio.run(
            resident.async_pre_call_hook(None, None, {"model": "qfn"}, "acompletion")
        )

    assert calls["n"] == 2  # literal: the budget is two attempts, not whatever the constant says
    assert raised.value.status_code == 429
    assert raised.value.detail["capacity"] == 5
    assert raised.value.detail["retry_after_seconds"] == litellm_resident.LEASE_RETRY_AFTER_SECONDS
    assert raised.value.headers["Retry-After"] == str(litellm_resident.LEASE_RETRY_AFTER_SECONDS)


def test_pre_call_takes_a_slot_and_records_the_lease(monkeypatch):
    resident = litellm_resident.ResidentFirst()
    resident._decide_url = lambda: "http://pool"
    resident._lease_once = lambda priority: (42, {"lease": 42, "priority": priority})

    data = {"model": "qfn", "messages": [], "metadata": {"trace": "x"}}
    asyncio.run(resident.async_pre_call_hook(None, None, data, "acompletion"))
    assert data["metadata"]["kdn_lease"] == 42
    assert data["metadata"]["trace"] == "x"


def test_success_hook_releases_by_request_key():
    resident = litellm_resident.ResidentFirst()
    released = []
    resident._release_slot = lambda lease: released.append(lease) or True
    resident._leases["call-1"] = (11, time.monotonic() + 60)

    asyncio.run(
        resident.async_post_call_success_hook(
            {"metadata": {"kdn_lease_key": "call-1"}}, None, object()
        )
    )
    assert released == [11]
    assert "call-1" not in resident._leases


def test_streaming_hook_releases_when_the_client_stops_early():
    resident = litellm_resident.ResidentFirst()
    released = []
    resident._release_slot = lambda lease: released.append(lease) or True
    resident._leases["call-2"] = (12, time.monotonic() + 60)

    async def stream():
        yield "a"
        yield "b"

    async def consume_one():
        generator = resident.async_post_call_streaming_iterator_hook(
            None, stream(), {"metadata": {"kdn_lease_key": "call-2"}}
        )
        await generator.__anext__()
        await generator.aclose()  # what a client disconnect does

    asyncio.run(consume_one())
    assert released == [12]


def test_sweep_releases_a_lease_whose_hook_never_ran():
    resident = litellm_resident.ResidentFirst()
    released = []
    resident._release_slot = lambda lease: released.append(lease) or True
    resident._leases["lost"] = (13, time.monotonic() - 1)

    resident._sweep_leases(time.monotonic())
    assert released == [13]
    assert resident._leases == {}


def test_a_second_lease_for_one_key_releases_the_first(monkeypatch):
    """A retry or a fallback for the same request must not orphan its earlier slot."""
    resident = litellm_resident.ResidentFirst()
    released = []
    resident._release_slot = lambda lease: released.append(lease) or True or True
    resident._remember_lease("call-3", 21)
    resident._remember_lease("call-3", 22)
    assert released == [21]
    assert resident._leases["call-3"][0] == 22


def test_a_failed_release_is_kept_and_retried(monkeypatch):
    """Dropping the entry after a failed /release would orphan the slot for the manager's TTL."""
    resident = litellm_resident.ResidentFirst()
    resident._release_slot = lambda lease: False
    resident._leases["call-4"] = (31, time.monotonic() + 60)

    resident._release_key("call-4")
    assert "call-4" in resident._leases, "the failed release lost its retry record"

    released = []
    resident._release_slot = lambda lease: released.append(lease) or True or True
    resident._sweep_leases(time.monotonic() + litellm_resident.LEASE_RELEASE_RETRY_SECONDS + 1)
    assert released == [31]
    assert resident._leases == {}
