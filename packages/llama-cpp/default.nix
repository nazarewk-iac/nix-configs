# See README.md in this directory for how to update these builds.
#
# llama.cpp builds from source, for the Qwen3.8-Flash-Next (`qwen4exp`) work on
# brys.
#
# The pinned nixpkgs `llama-cpp` is 0.4.0 (build 10809). That build does not
# contain the merged `qwen4exp` MTP graph, so the server cannot use the model
# MTP head for speculative decode. The derivations below provide:
#
#   * `llama-cpp-v0_6_0` — the ggml-org v0.6.0 release, CPU-only. It merges MTP
#     for `qwen4exp` (PR #29761) and the mask/indexer performance fixes.
#   * `llama-cpp-v0_6_0-vulkan` — the same source with the Vulkan backend, for
#     the Radeon Pro W6600 on brys. Experts and KV stay on the CPU; Vulkan
#     offloads the dense layers.
#   * `llama-cpp-unsloth-mtp` — the Unsloth fork branch `qwen4exp/mtp`, the
#     build the Unsloth docs name. It has an older base, so it is only for a
#     comparison benchmark.
#
# Every derivation drops the embedded web UI. The server API, the MTP graph and
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
      # Build the Vulkan backend (for the AMD Radeon Pro W6600 on brys). The
      # default is the CPU-only build: the CPU keeps the experts and the KV
      # cache, and Vulkan offloads the dense layers.
      vulkan ? false,
      # Build the BLAS backend and link OpenBLAS. The default is on, as the
      # pinned nixpkgs build. The BLAS backend dequantizes a quantized `src0`
      # to F32 and calls `cblas_sgemm`; on brys that stalls fresh prompt
      # processing, so the `-noblas` variant below turns it off. See README.md.
      blas ? true,
      # Optional source patches, applied on top of `src` (patchPhase). Used for
      # the `--no-mmap-prefetch` variant that carries an unmerged upstream PR.
      patches ? [ ],
    }:
    pkgs.stdenv.mkDerivation {
      inherit
        pname
        version
        src
        patches
        ;

      __structuredAttrs = true;
      strictDeps = true;

      outputs = [
        "out"
        "dev"
      ];

      nativeBuildInputs =
        with pkgs;
        [
          cmake
          installShellFiles
          ninja
          pkg-config
        ]
        ++ lib.optionals vulkan [ shaderc ];

      buildInputs =
        with pkgs;
        [
          openssl
        ]
        ++ lib.optionals blas [ blas ]
        ++ lib.optionals vulkan [
          vulkan-headers
          vulkan-loader
          spirv-headers
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
        (cmakeBool "GGML_BLAS" blas)
        # brys serves these models on the CPU alone.
        (cmakeBool "GGML_CLBLAST" false)
        (cmakeBool "GGML_CUDA" false)
        (cmakeBool "GGML_HIP" false)
        (cmakeBool "GGML_METAL" false)
        (cmakeBool "GGML_RPC" false)
        (cmakeBool "GGML_VULKAN" vulkan)
        # Build every CPU variant and select one at runtime. This prevents an
        # illegal instruction on an older CPU and gives the best speed on a
        # newer one. The experts and the KV cache stay on the CPU in the Vulkan
        # build too, so this stays true.
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
        description = "Inference of LLaMA and other models in C/C++ (${
          if vulkan then "CPU+Vulkan" else "CPU-only"
        }, no web UI)";
        homepage = "https://github.com/ggml-org/llama.cpp";
        license = lib.licenses.mit;
        mainProgram = "llama-server";
        platforms = lib.platforms.unix;
      };
    };
in
let
  # ggml-org v0.6.0 (build 11429, commit d812350). Shared by the CPU-only and
  # the Vulkan builds below, so the two cannot drift on the source or the build
  # number.
  v0_6_0 = {
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

  # ggml-org master, head 9c2e0e4 (2026-10-08). Ten commits after the last
  # tagged build b11480, so the build number is 11480 + 10. Master still
  # prefetches model weights with `MADV_WILLNEED` unconditionally
  # (`ml.init_mappings(true, ...)`), so the `-vulkan` build below has no
  # `--no-mmap-prefetch` flag; use `--load-mode none` to disable mmap (and
  # therefore the prefetch) instead. See `llama-cpp-master-noprefetch-vulkan`
  # for the same source with the open upstream PR #29250 applied.
  master = {
    version = "0.6.0-unstable-2026-10-08";
    buildNumber = "11490";
    buildCommit = "9c2e0e4";
    src = pkgs.fetchFromGitHub {
      owner = "ggml-org";
      repo = "llama.cpp";
      rev = "9c2e0e491a822adae1f0b1c831adb4160057d24f";
      hash = "sha256-6S2c/usl0ZbuGG/iZXKhSJyz6PK3Ab2uGtpO9tF7LKI=";
    };
  };
in
{
  # The version string cannot be an attribute name (a dot is not valid in a Nix
  # identifier), so the attribute uses underscores.
  llama-cpp-v0_6_0 = mkLlamaCpp (v0_6_0 // { pname = "llama-cpp"; });

  # The same v0.6.0 source with the Vulkan backend on, for the Radeon Pro
  # W6600 on brys. The CPU keeps every expert and the KV cache
  # (`GGML_CPU_ALL_VARIANTS` and `GGML_BACKEND_DL` stay true); Vulkan offloads
  # the dense layers only. See packages/llama-cpp/README.md.
  llama-cpp-v0_6_0-vulkan = mkLlamaCpp (
    v0_6_0
    // {
      pname = "llama-cpp-vulkan";
      vulkan = true;
    }
  );

  # The same v0.6.0 Vulkan build with the BLAS backend off (`GGML_BLAS=false`,
  # no OpenBLAS input). It drops `bin/libggml-blas.so`, so the CPU falls back
  # to the ggml CPU backend for the dense-layer matmuls. The A/B on brys
  # (docs/local-llms.md) tests whether this removes the fresh-prompt prefill
  # stall of the BLAS backend.
  llama-cpp-v0_6_0-vulkan-noblas = mkLlamaCpp (
    v0_6_0
    // {
      pname = "llama-cpp-vulkan-noblas";
      vulkan = true;
      blas = false;
    }
  );

  # ggml-org master, Vulkan backend, for the `--no-mmap-prefetch` experiment on
  # brys. Master carries the `--load-mode` rework (auto/none/mmap/mlock/
  # mmap+mlock/dio) and the `--lazy-mode` on-demand tensor reads, but no
  # `--no-mmap-prefetch`: the prefetch stays hardcoded to `true`.
  llama-cpp-master-vulkan = mkLlamaCpp (
    master
    // {
      pname = "llama-cpp-master-vulkan";
      vulkan = true;
    }
  );

  # The same master source with the open upstream PR #29250 applied. That PR
  # adds `llama_model_params.mmap_prefetch` and the `--no-mmap-prefetch` CLI
  # flag, so mmap stays on (unlike `--load-mode none`) while the blocking
  # `MADV_WILLNEED` prefetch of the whole ~94 GB file is skipped.
  llama-cpp-master-noprefetch-vulkan = mkLlamaCpp (
    master
    // {
      pname = "llama-cpp-master-noprefetch-vulkan";
      vulkan = true;
      patches = [ ./29250-no-mmap-prefetch.patch ];
    }
  );

  # The same master source with the open upstream PR #25294 applied. That PR
  # streams MoE routed-expert weights from disk on demand: `--moe-stream`,
  # `--moe-stream-cache <NG|Ns>`, `--moe-stream-io-threads N` and
  # `--moe-stream-direct` (O_DIRECT). Streaming auto-disables mmap. The PR head
  # predates the `qwen4exp` arch, so the patch is a manual port onto master
  # (the PR conflicts with the already-merged `--moe-cache-mib` MoE cache in
  # `build_moe_ffn`/`build_lora_mm_id`; both mechanisms are kept).
  llama-cpp-master-moe-stream-vulkan = mkLlamaCpp (
    master
    // {
      pname = "llama-cpp-master-moe-stream-vulkan";
      vulkan = true;
      patches = [ ./25294-moe-stream.patch ];
    }
  );

  # The same master source with the open upstream PR #26414 applied. That PR
  # adds `--pin-hot-experts N` (mlock the N hottest MoE experts per layer so
  # the page cache cannot evict them), `--pin-hot-experts-budget-mib N` and the
  # `--load-mode mmap+pin` mode. The patch is a manual port onto master.
  llama-cpp-master-pin-hot-experts-vulkan = mkLlamaCpp (
    master
    // {
      pname = "llama-cpp-master-pin-hot-experts-vulkan";
      vulkan = true;
      patches = [ ./26414-pin-hot-experts.patch ];
    }
  );

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
