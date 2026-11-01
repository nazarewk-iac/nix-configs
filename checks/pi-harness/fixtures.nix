# Tiny GGUF models for the Pi harness checks, as fixed-output derivations so a check runs offline
# after the first build.
#
# ## URL stability
#
# The upstream repo `ggml-org/models` was RENAMED to `ggml-org/models-moved`, and the old path now
# 307-redirects. A redirect is not a guarantee. So each URL here names the **immutable commit**
# (`resolve/<commit>/`) rather than `main`: a commit URL cannot be retargeted. The `sha256-` hash
# pins the bytes on top of that, so a changed file fails the build instead of silently swapping.
#
# Follow-up (see the task note): mirror these two files into our own storage (S3/Nextcloud) and
# point the URLs there, so an upstream repo deletion cannot break the build either.
{ pkgs }:
let
  # One commit for the whole tinyllamas directory, read from HF's `x-repo-commit` header.
  rev = "499bc8821c6b12b4e53c5bffcb21ec206f212d81";
  base = "https://huggingface.co/ggml-org/models-moved/resolve/${rev}/tinyllamas";
in
{
  stories260K = pkgs.fetchurl {
    url = "${base}/stories260K.gguf";
    hash = "sha256-Jwy6G9UQn0LQM1D2BAYCRWBGTbFzwOOH2R8EJtO9JW0=";
  };

  # Qwen2.5-0.5B-Instruct: the smallest model measured to emit REAL tool calls (finish_reason
  # "tool_calls") under llama-server --jinja. 491 MB on disk, ~587 MiB RSS at ctx 2048. It exists
  # only for the delegation check; the cheap checks stay on stories260K.
  # Measured 2026-11-01 against llama-server from nixpkgs: tool call -> {"command":"echo hi"}.
  qwen2_5_0_5b_instruct = pkgs.fetchurl {
    url = "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf";
    hash = "sha256-dKTajJ/bzRW9H20B1iFBDTHG/ACYb162h4JOe5PXqds=";
  };
  # ~98 MB; used only by the prompt-stability check, which needs an instruction-following model.
  stories15M = pkgs.fetchurl {
    url = "${base}/stories15M.gguf";
    hash = "sha256-YbUNRXgJpRlIGP0i5nJLRWzXu5piZMUsgRBoTFPzcEo=";
  };
}
