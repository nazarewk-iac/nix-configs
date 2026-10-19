# `ik_llama.cpp` — a llama.cpp fork with optimized CPU kernels, by ikawrakow.
#
# This build is a CPU-only runner for the A/B comparison against the in-repo
# `llama-cpp-*` builds. It is pinned by `fetchFromGitHub`; there is no
# `builtins.fetchGit` of a moving branch.
#
# The fork diverges from ggml-org llama.cpp, so several flags of
# `packages/llama-cpp/default.nix` do not exist here and are omitted:
#
#   * `GGML_CPU_ALL_VARIANTS` and `GGML_BACKEND_DL` are absent. The fork
#     compiles for one ISA baseline. With `GGML_NATIVE=OFF` the build enables
#     AVX/AVX2/FMA/F16C by default (`ggml/CMakeLists.txt`: `INS_ENB`), so the
#     binary runs on the AVX2 target (brys, a Zen3 Ryzen 5950X) and never emits
#     `-march=native`.
#   * There is no `LLAMA_BUILD_UI` / `LLAMA_USE_PREBUILT_UI` switch. The server
#     always embeds prebuilt `.gz` assets from the source tree, so no npm tree
#     and no `npmDepsHash` are needed.
#   * There is no `GGML_BLAS` option. The IQK quantized GEMM kernels are the
#     fork's fast CPU path and are on by default (`GGML_IQK_MUL_MAT`).
#
# `LLAMA_BUILD_EXAMPLES=ON` builds `llama-bench`, the benchmark tool, beside
# `llama-server`. `LLAMA_BUILD_TESTS=OFF` skips the upstream test suite.
{
  pkgs,
  lib,
  ...
}:
let
  inherit (lib)
    cmakeBool
    ;

  # The fork publishes no release tags, so the version is date-based.
  version = "0.0.0-unstable-2026-10-19";
  buildCommit = "35e72560";
  # `git rev-list --count HEAD` on the pinned rev.
  buildNumber = "2761";
in
pkgs.stdenv.mkDerivation {
  pname = "ik-llama-cpp";
  inherit version;

  src = pkgs.fetchFromGitHub {
    owner = "ikawrakow";
    repo = "ik_llama.cpp";
    rev = "35e72560fac6eb4e0bedc99976d3a12040749230";
    hash = "sha256-FGBbmLThxMK8PFr3VaoXa4k2yPMCBne+QtR0fUrGw9w=";
  };

  __structuredAttrs = true;
  strictDeps = true;

  outputs = [
    "out"
    "dev"
  ];

  nativeBuildInputs = with pkgs; [
    cmake
    ninja
    pkg-config
  ];

  buildInputs = with pkgs; [
    openssl
  ];

  cmakeFlags = [
    # -march=native would make the build non-deterministic. The fork then
    # enables AVX2/FMA/F16C by default, which is the brys baseline.
    (cmakeBool "GGML_NATIVE" false)
    (cmakeBool "LLAMA_BUILD_EXAMPLES" true)
    (cmakeBool "LLAMA_BUILD_SERVER" true)
    (cmakeBool "LLAMA_BUILD_TESTS" false)
    (cmakeBool "BUILD_SHARED_LIBS" true)
    (cmakeBool "LLAMA_CURL" false)
    # CPU-only. brys serves these models on the CPU alone.
    (cmakeBool "GGML_CUDA" false)
    (cmakeBool "GGML_HIPBLAS" false)
    (cmakeBool "GGML_METAL" false)
    (cmakeBool "GGML_RPC" false)
    (cmakeBool "GGML_VULKAN" false)
  ];

  # The fork derives the build number and commit from `git` in the source
  # tree, which `fetchFromGitHub` does not keep. The `LLAMA_BUILD_NUMBER` /
  # `LLAMA_BUILD_COMMIT` cache variables do not reach it: `build-info.cmake`
  # sets both from git and `CMakeLists.txt` reads them back. Force the pinned
  # values, so `--version` reports the pinned revision.
  postPatch = ''
    substituteInPlace cmake/build-info.cmake \
      --replace-fail 'set(BUILD_NUMBER 0)' 'set(BUILD_NUMBER ${buildNumber})' \
      --replace-fail 'set(BUILD_COMMIT "unknown")' 'set(BUILD_COMMIT "${buildCommit}")'
  '';

  doCheck = false;

  meta = {
    description = "llama.cpp fork with optimized CPU kernels (ik_llama.cpp), CPU-only";
    homepage = "https://github.com/ikawrakow/ik_llama.cpp";
    license = lib.licenses.mit;
    mainProgram = "llama-server";
    platforms = lib.platforms.unix;
  };
}
