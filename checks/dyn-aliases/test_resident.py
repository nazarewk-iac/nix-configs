"""The `dyn-*` residency ladder, driven with fake deployments.

`litellm_resident.py` imports `CustomLogger` from LiteLLM. The stub below satisfies that import
before the file is loaded, so the check needs no LiteLLM dependency tree; `fastapi` stays real, so
the refusal is the same `HTTPException` LiteLLM maps to the client's error body.
"""

import asyncio
import os
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
