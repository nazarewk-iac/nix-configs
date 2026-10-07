# See README.md in this directory for how to update these builds.
#
# Two CPU-only llama.cpp builds from source, for the Qwen3.8-Flash-Next
# (`qwen4exp`) work on brys.
#
# The pinned nixpkgs `llama-cpp` is 0.4.0 (build 10809). That build does not
# contain the merged `qwen4exp` MTP graph, so the server cannot use the model
# MTP head for speculative decode. The two derivations below provide:
#
#   * `llama-cpp-v0_6_0` — the ggml-org v0.6.0 release. It merges MTP for
#     `qwen4exp` (PR #29761) and the mask/indexer performance fixes.
#   * `llama-cpp-unsloth-mtp` — the Unsloth fork branch `qwen4exp/mtp`, the
#     build the Unsloth docs name. It has an older base, so it is only for a
#     comparison benchmark.
#
# Both derivations drop the embedded web UI. The server API, the MTP graph and
# `--help` do not need the UI. Dropping it removes the npm dependency tree and
# its `npmDepsHash`, and it shortens the build. Upstream CMake builds no UI when
# `LLAMA_BUILD_UI` and `LLAMA_USE_PREBUILT_UI` are both OFF; it then prints
# "no assets available - building without an embedded UI".
{
  pkgs,
  lib,
  ...
}:
let
  inherit (lib)
    cmakeBool
    cmakeFeature
    optionalString
    ;

  mkLlamaCpp =
    {
      pname,
      version,
      src,
      buildNumber,
      buildCommit,
    }:
    pkgs.stdenv.mkDerivation {
      inherit pname version src;

      __structuredAttrs = true;
      strictDeps = true;

      outputs = [
        "out"
        "dev"
      ];

      nativeBuildInputs = with pkgs; [
        cmake
        installShellFiles
        ninja
        pkg-config
      ];

      buildInputs = with pkgs; [
        blas
        openssl
      ];

      cmakeFlags = [
        # -march=native would make the build non-deterministic.
        (cmakeBool "GGML_NATIVE" false)
        (cmakeBool "LLAMA_BUILD_EXAMPLES" false)
        (cmakeBool "LLAMA_BUILD_SERVER" true)
        (cmakeBool "LLAMA_BUILD_TESTS" false)
        (cmakeBool "LLAMA_BUILD_IS_DEV" false)
        (cmakeBool "LLAMA_OPENSSL" true)
        (cmakeBool "BUILD_SHARED_LIBS" true)
        (cmakeBool "GGML_BLAS" true)
        # brys serves these models on the CPU alone.
        (cmakeBool "GGML_CLBLAST" false)
        (cmakeBool "GGML_CUDA" false)
        (cmakeBool "GGML_HIP" false)
        (cmakeBool "GGML_METAL" false)
        (cmakeBool "GGML_RPC" false)
        (cmakeBool "GGML_VULKAN" false)
        # Build every CPU variant and select one at runtime. This prevents an
        # illegal instruction on an older CPU and gives the best speed on a
        # newer one.
        (cmakeBool "GGML_CPU_ALL_VARIANTS" true)
        (cmakeBool "GGML_BACKEND_DL" true)
        # No embedded web UI. See the file header.
        (cmakeBool "LLAMA_BUILD_UI" false)
        (cmakeBool "LLAMA_USE_PREBUILT_UI" false)
        (cmakeFeature "LLAMA_BUILD_NUMBER" buildNumber)
        (cmakeFeature "LLAMA_BUILD_COMMIT" buildCommit)
      ];

      postInstall = optionalString (pkgs.stdenv.buildPlatform.canExecute pkgs.stdenv.hostPlatform) ''
        installShellCompletion --cmd llama-server --bash <($out/bin/llama-server --completion-bash)
      '';

      # The upstream tests fail as of 2025-08 (nixpkgs carries the same note).
      doCheck = false;

      meta = {
        description = "Inference of LLaMA and other models in C/C++ (CPU-only, no web UI)";
        homepage = "https://github.com/ggml-org/llama.cpp";
        license = lib.licenses.mit;
        mainProgram = "llama-server";
        platforms = lib.platforms.unix;
      };
    };
in
{
  # ggml-org v0.6.0 (build 11429, commit d812350). The version string cannot be
  # an attribute name (a dot is not valid in a Nix identifier), so the
  # attribute uses underscores.
  llama-cpp-v0_6_0 = mkLlamaCpp {
    pname = "llama-cpp";
    version = "0.6.0";
    buildNumber = "11429";
    buildCommit = "d812350";
    src = pkgs.fetchFromGitHub {
      owner = "ggml-org";
      repo = "llama.cpp";
      rev = "d81235049384534c167caea52b85a694f6103d14";
      hash = "sha256-l6l6JIlIVTaVC6xh5M4fRHFtXsweQuugtkNTWHcZZF4=";
    };
  };

  # Unsloth fork, branch `qwen4exp/mtp`, head 6fcaa16 (2026-09-21), base
  # version 0.4.1, build 11098.
  llama-cpp-unsloth-mtp = mkLlamaCpp {
    pname = "llama-cpp-unsloth-mtp";
    version = "0.4.1-unstable-2026-09-21";
    buildNumber = "11098";
    buildCommit = "6fcaa16";
    src = pkgs.fetchFromGitHub {
      owner = "danielhanchen";
      repo = "llama.cpp";
      rev = "6fcaa16f4b360649933a54d1f91ad40ed35c0e11";
      hash = "sha256-YgIkYHiV1LNA1OvTcB8SSdOeqr37+cEFAOQjEBfXcK4=";
    };
  };
}
