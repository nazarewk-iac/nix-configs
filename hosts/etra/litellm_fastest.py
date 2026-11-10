"""Fastest-fit selector for the LiteLLM gateway.

Loaded by LiteLLM as a callback (`fastest.fastest_fit`) from beside config.yaml.

The fleet has a slow frontier (qwen3.8-flash-next) and several fast small models.
An intent alias maps to ONE model, so "use the fastest model that fits the task"
needs a model GROUP (`chat-fast`) whose deployments are the candidate models. This
callback turns the group into a real selector: it drops deployments that cannot
FIT the request (context window, vision) and keeps the single fastest one by
measured throughput.

Why measured throughput and not `latency-based-routing`: the measured
`tokens_per_second`/`prefill_tokens_per_second` (from `data/llm.nix`
`capabilities.rates`, surfaced in `model_info`) are stable, whereas routed
latency is noisy from cold starts/model load. Pick by the dominant phase:
a long prompt is prefill-bound, a short prompt is decode-bound.

Never raises: a selector bug must not break routing.
"""

import os

from litellm.integrations.custom_logger import CustomLogger

# Model groups this selector acts on. Anything else passes through untouched, so
# ordinary aliases keep their normal routing.
DEFAULT_GROUPS = "chat-fast"
# Prompt size (estimated tokens) above which we optimize prefill instead of decode.
DEFAULT_LARGE_PROMPT = "4000"


def _info(d: dict) -> dict:
    return d.get("model_info") or {}


def _prompt_tokens_est(messages) -> int:
    chars = 0
    for m in messages or []:
        content = m.get("content")
        if isinstance(content, str):
            chars += len(content)
        elif isinstance(content, list):
            for part in content:
                if isinstance(part, dict) and part.get("type") == "text":
                    chars += len(part.get("text") or "")
    # ~4 chars per token, deliberately cheap; used only to bucket fit.
    return chars // 4


def _has_image(messages) -> bool:
    for m in messages or []:
        content = m.get("content")
        if isinstance(content, list):
            for part in content:
                if isinstance(part, dict) and part.get("type") in (
                    "image_url",
                    "input_image",
                ):
                    return True
    return False


class FastestFit(CustomLogger):
    def __init__(
        self, groups: str | None = None, large_prompt: str | None = None, **_ignored
    ) -> None:
        super().__init__()
        self.groups = {
            g.strip()
            for g in (
                groups or os.environ.get("KDN_FASTEST_GROUPS", DEFAULT_GROUPS)
            ).split(",")
            if g.strip()
        }
        try:
            self.large_prompt = int(
                large_prompt
                or os.environ.get("KDN_FASTEST_LARGE_PROMPT", DEFAULT_LARGE_PROMPT)
            )
        except ValueError:
            self.large_prompt = int(DEFAULT_LARGE_PROMPT)

    def _fits(self, info: dict, est: int, wants_image: bool) -> bool:
        max_in = info.get("max_input_tokens")
        if isinstance(max_in, int) and max_in > 0 and est > max_in:
            return False
        if wants_image and not info.get("supports_vision"):
            return False
        return True

    def _score(self, info: dict, est: int) -> float:
        key = (
            "prefill_tokens_per_second"
            if est > self.large_prompt
            else "tokens_per_second"
        )
        value = info.get(key)
        if value is None:
            value = info.get("tokens_per_second")
        return float(value or 0.0)

    async def async_filter_deployments(
        self,
        model: str,
        healthy_deployments: list,
        messages=None,
        request_kwargs=None,
        parent_otel_span=None,
    ) -> list:
        try:
            if model not in self.groups or not healthy_deployments:
                return healthy_deployments
            est = _prompt_tokens_est(messages)
            wants_image = _has_image(messages)
            fitting = [
                d for d in healthy_deployments if self._fits(_info(d), est, wants_image)
            ]
            # If nothing fits, keep the group rather than starve it.
            candidates = fitting or healthy_deployments
            fastest = max(candidates, key=lambda d: self._score(_info(d), est))
            # Force the single fastest fitting deployment; health/cooldown filtering
            # has already happened upstream, so the next-fastest becomes available on
            # failover.
            return [fastest]
        except Exception:
            return healthy_deployments


# Module-level instance, so the config can name `fastest.fastest_fit`.
fastest_fit = FastestFit()
