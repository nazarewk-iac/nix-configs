# The image and video editors, as profiles of the same manager that runs the frontier.
#
# This file is data plus one package, not a module: `strata-profiles.nix` imports it and puts
# `profiles` into the runtime's deployment config, so an editor is a *profile* — it obeys the same
# drain, the same leases and the same gate as `qfn`, and the card can never be double-booked.
#
# Why a second engine at all: llama.cpp cannot run a diffusion model. `stable-diffusion.cpp` can,
# with no torch and no ROCm, and on this card it reaches the GPU through Vulkan exactly as
# llama.cpp does. The measured numbers live in
# docs/tasks/2026-11/image-video-editing-models/measurements.md.
{ pkgs, lib }:
let
  models = "/var/lib/kdn/llms/models";

  # nixpkgs pins master-1043, which predates LongCat support. Pin the upstream revision the survey
  # measured, so the runtime and the numbers describe the same binary.
  sd = (pkgs.stable-diffusion-cpp.override { vulkanSupport = true; }).overrideAttrs (_: {
    version = "master-532d2c1";
    src = pkgs.fetchFromGitHub {
      owner = "leejet";
      repo = "stable-diffusion.cpp";
      rev = "532d2c15c430a785a712b2d94281f04e733008a4";
      hash = "sha256-D5fGSMPrGXLaMU1ZItnPnRPiDkIbR8n0sdi89eA5kQs=";
      fetchSubmodules = true;
    };
  });

  # The card enumerates two Vulkan devices: the 4 GB RX 550 is `vulkan0`, the R9700 is `vulkan1`.
  # Pinning the device is not an optimisation — the first survey run silently used the RX 550 and
  # ran at 147 s/it.
  backend = "diffusion=vulkan1,te=vulkan1,vae=vulkan1";

  # Both image editors share the Qwen2.5-VL encoder and its vision projector.
  qwenEncoder = "${models}/qwen-image-edit/Qwen2.5-VL-7B-Instruct-Q8_0.gguf";
  qwenVision = "${models}/qwen-image-edit/mmproj-F16.gguf";

  server =
    {
      model,
      extra,
    }:
    [
      "${sd}/bin/sd-server"
      "--listen-ip"
      "127.0.0.1"
      "--diffusion-model"
      model
      "--backend"
      backend
    ]
    ++ extra;

  # Every profile: an `sd-server` argv, the A1111 path that answers once it serves, and the port
  # flag the supervisor appends (`sd-server` spells it `--listen-port`).
  #
  # Each editor gets its own port, off the frontier's 8080 and off 8082 (zellij's). A stopped server leaves TIME_WAIT
  # sockets on the port it listened on, and the next engine's plain bind() sees them as "already in
  # use" for a minute: measured on brys, the strata engine refused to start two seconds after an
  # editor stopped. Two servers that never share a socket never collide, and the manager tells the
  # proxy which port the selected profile is on.
  readyPath = "/sdapi/v1/options";
  portFlag = "--listen-port";
  profile = port: argv: {
    inherit
      argv
      readyPath
      portFlag
      port
      ;
  };
in
{
  inherit sd;

  profiles = {
    # 20B DiT at Q4_K_M plus the 4-step Lightning LoRA: 41-44 s per 1024x1024 edit, 26 GiB peak.
    # `qwen_image_zero_cond_t=true` is mandatory for the 2511 checkpoint; without it the edit
    # quality degrades noticeably.
    image-qwen = profile 8091 (server {
      model = "${models}/qwen-image-edit/qwen-image-edit-2511-Q4_K_M.gguf";
      extra = [
        "--vae"
        "${models}/qwen-image-edit/qwen_image_vae.safetensors"
        "--llm"
        qwenEncoder
        "--llm_vision"
        qwenVision
        "--model-args"
        "qwen_image_zero_cond_t=true"
        "--lora-model-dir"
        "${models}/qwen-image-edit"
        "--sampling-method"
        "euler"
        "--cfg-scale"
        "1"
        "--steps"
        "4"
        "--flow-shift"
        "3"
      ];
    });

    # 6B distilled, 29-30 s per edit, 23 GiB peak. The official Comfy-Org bf16 file: the GGUF
    # conversion of this model that circulates renders noise.
    image-longcat = profile 8092 (server {
      model = "${models}/longcat-image-edit/longcat_image_edit_turbo_bf16.safetensors";
      extra = [
        "--vae"
        "${models}/longcat-image-edit/flux-vae-bf16.safetensors"
        "--llm"
        qwenEncoder
        "--llm_vision"
        qwenVision
        "--sampling-method"
        "euler"
        "--cfg-scale"
        "1"
        "--steps"
        "8"
        "--flow-shift"
        "3"
      ];
    });

    # Wan2.1 VACE 14B at Q4_K_M: 940-1039 s for 2 s of 832x480 at 20 steps, 28.6 GiB peak. A batch
    # job by any measure, which is why it is a profile and not a chat alias.
    image-vace = profile 8093 (server {
      model = "${models}/wan-vace-14b/Wan2.1_14B_VACE-Q4_K_M.gguf";
      extra = [
        "--vae"
        "${models}/wan-vace-14b/wan_2.1_vae.safetensors"
        "--t5xxl"
        "${models}/wan-vace-14b/umt5-xxl-encoder-Q8_0.gguf"
        "--sampling-method"
        "euler"
        "--cfg-scale"
        "6"
        "--steps"
        "20"
      ];
    });
  };
}
