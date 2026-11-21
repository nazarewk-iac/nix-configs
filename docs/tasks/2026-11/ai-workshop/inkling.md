---
type: Research
description: Out-of-band measurement of Inkling 2 Mini IQ4_NL on brys - download, load time, VRAM cost, decode and prefill speed, and whether it can sit beside a colo profile.
task: definition.md
authored_by: agent
timestamp: 2026-11-21T13:20:00+01:00
---

# Inkling 2 Mini IQ4_NL on brys

Measured on 2026-11-21. The model was not registered in `data/llm.nix` or `hosts-den/brys/policy.nix`.
A built `llama-server` ran directly, on a private port, outside llama-swap.

## Result at a glance

| fact                   | value                                                                         |
| ---------------------- | ----------------------------------------------------------------------------- |
| file                   | `Inkling-2-Mini-IQ4_NL.gguf`, 17 627 940 768 B (16.42 GiB)                    |
| SHA256                 | `cbdf3fa9dc50a4124977980f37da4f1fa764b0cfe800d275cd43d26ce2a81af4`            |
| architecture           | `inkling2_loop`, 26.07 B params, 48 layers, 128 experts (8 used), 704 tensors |
| context trained        | 1 048 576 tokens                                                              |
| download               | 4 min 11 s, 66.8 MB/s average                                                 |
| load to listening      | **37.2 s**                                                                    |
| VRAM at 16 384 context | **18 935 MiB (18.49 GiB)**                                                    |
| decode                 | **16.8 t/s**                                                                  |
| prefill                | **17.0 t/s** (34.7 t/s on a cached prefix)                                    |
| host RSS during load   | 153 MiB (mmap; weights stay in page cache)                                    |
| card peak during test  | 31.84 GiB of 31.86 GiB                                                        |
| side effect            | the kernel OOM killer killed `strata-host`                                    |

## Build

The fleet fork `nazarewk-iac/llama.cpp` at `727cb0f63` (upstream b12608 plus the session patches).
The store path is:

```
/nix/store/sk57ra87fhpr1mqlb5a1yil5an7d9yax-llama-cpp-sessions-vulkan-noblas-1.0.0-unstable-2026-11-21
```

`llama-server --version` reports `1.0.0 (build 12609, commit 727cb0f63)`. The build recognises
`inkling2` and `inkling2_loop` in `libllama.so`.

## Download

The file is larger than the brief said. It is 17.63 GB, not about 14 GB. The Hugging Face
`x-linked-size` header and the final `stat` agree to the byte. `sha256sum` equals the LFS etag, so
the file is complete. No `.part` file was left.

```bash
sudo install -d -o llm-server -g llm-server -m 0755 /var/lib/kdn/llms/models/inkling-2-mini
sudo -u llm-server bash -c "cd /var/lib/kdn/llms/models/inkling-2-mini && \
  curl -fL -C - --retry 5 --retry-delay 5 \
  -o Inkling-2-Mini-IQ4_NL.gguf \
  https://huggingface.co/ggml-org/Inkling-2-Mini-GGUF/resolve/main/Inkling-2-Mini-IQ4_NL.gguf"
```

The log is at `/tmp/inkling-download.log` on brys. The exit code is 0.

The repository also holds `mmproj-Inkling-2-Mini-Q8_0.gguf` and `mmproj-Inkling-2-Mini-BF16.gguf`.
Neither was downloaded, because this run measured text only.

## Device order

`vulkaninfo --summary` lists the RX 550 first and the R9700 second:

```
Vulkan0 = AMD Radeon RX 550 / 550 Series (RADV POLARIS12)
Vulkan1 = AMD Radeon AI PRO R9700 (RADV GFX1201)
Vulkan2 = llvmpipe
```

The server must pin `--device Vulkan1`. A default run would take the RX 550 and fail. Do not set
`GGML_VK_VISIBLE_DEVICES=1` at the same time, because that renumbers the R9700 to `Vulkan0` and
`--device Vulkan1` then does not resolve.

## Exact command line

Run as `llm-server`, outside llama-swap, on port 8099:

```bash
sudo -u llm-server setsid nohup \
  /nix/store/sk57ra87fhpr1mqlb5a1yil5an7d9yax-llama-cpp-sessions-vulkan-noblas-1.0.0-unstable-2026-11-21/bin/llama-server \
  --model /var/lib/kdn/llms/models/inkling-2-mini/Inkling-2-Mini-IQ4_NL.gguf \
  --device Vulkan1 \
  --n-gpu-layers 99 \
  --ctx-size 16384 \
  --host 127.0.0.1 --port 8099 \
  --threads 16 \
  --flash-attn on \
  --load-mode mmap \
  --parallel 1 \
  --verbose \
  > /tmp/inkling-server-16384.log 2>&1 &
```

`--load-mode mmap` was enough. `--no-mmap` was not needed. The server reported
`listening on http://127.0.0.1:8099` at 37.2 s.

## VRAM

The server's own accounting, from the log, is the authoritative figure:

| buffer                              | MiB           |
| ----------------------------------- | ------------- |
| Vulkan1 model buffer                | 16 330.58     |
| Vulkan1 KV buffer (512.00 + 240.00) | 752.00        |
| Vulkan1 recurrent-state buffer      | 3.66          |
| Vulkan1 compute buffer              | 1 849.68      |
| **Vulkan1 total**                   | **18 935.92** |
| CPU-mapped model buffer             | 469.31        |
| Vulkan_Host compute buffer          | 111.03        |

The fit check agreed and left the parameters unchanged:

```
common_params_fit_impl: projected to use 18935 MiB of device memory vs. 21592 MiB of free device memory
common_params_fit_impl: will leave 2656 >= 1024 MiB of free device memory, no changes needed
```

All 48 layers went to the GPU (`offloading 47 repeating layers to GPU` plus the output layer). No
layer fell back to the CPU. The 469 MiB `CPU_Mapped` buffer is the mmap'd host copy, not compute.

The context did fit at 16 384, so the 4 096 fallback was not needed.

`mem_info_vram_used` for `card1` read 31.84 GiB at the peak. That figure covers both processes,
because the strata frontier was reloading at the same moment. Treat 18.49 GiB as the cost of
Inkling and read the sysfs peak as the sum of both residents.

## Speed

One chat completion, a coding question, `max_tokens` 400, `temperature` 0.2, not streamed:

| run    | prompt tokens | prefill  | output tokens | decode       |
| ------ | ------------- | -------- | ------------- | ------------ |
| first  | 43            | 17.0 t/s | 50            | 16.6 t/s     |
| second | 4 (39 cached) | 34.7 t/s | 359           | **16.8 t/s** |

The first run returned `finish_reason: length` with empty `content`, because the model is a
reasoning model and spent all 50 tokens in `reasoning_content`. The chat template prints
`Thinking effort level: 0.9` and reports `thinking = 1`. Give it at least a few hundred tokens or
the answer never starts.

The second run produced correct code: an iterative list reversal with a node class, a docstring and
a one-line explanation.

16.8 t/s decode is slow for a model with 3.4 B active parameters. Vulkan is the weak path for a
128-expert mixture of experts, and the looped transformer repeats its core, so each token costs
more compute than the active count suggests. The fleet serves Qwen through the HIP strata engine
instead. A HIP build of this fork was not available here, so a fair comparison of the same model
across backends is still open.

## Collateral damage: the frontier was killed

This is the most important result. Loading 16.4 GiB beside the live `omni-fast` frontier caused a
**host RAM** out-of-memory event, not a VRAM one:

```
Nov 21 12:09:58 brys kernel: oom-kill:constraint=CONSTRAINT_NONE,...,global_oom,task_memcg=/system.slice/strata-manager.service,task=strata-host
Nov 21 12:09:58 brys kernel: Out of memory: Killed process 3677318 (strata-host)
  total-vm:644869240kB, anon-rss:58417972kB, file-rss:28126776kB, shmem-rss:12194352kB
Nov 21 12:10:01 brys systemd[1]: strata-manager.service: Failed with result 'oom-kill'.
```

`strata-host` held 55.7 GiB of anonymous memory and 26.8 GiB of file-backed memory. The mmap of
the new 16.4 GB file pushed a 125 GiB machine into global OOM, and the largest resident process
died. `strata-manager` restarted itself and restored `omni-fast` in 102 s.

Everything came back on its own: the manager, the engine and llama-swap all answer HTTP 200, and
`mem_info_vram_used` returned to 13.96 GiB. The download is intact.

The lesson is that brys has a RAM budget problem before it has a VRAM budget problem. Any large
`llama-server` companion needs `--no-mmap` or `--cache-ram 0` and an explicit RAM check, and it
must not be loaded while the frontier holds tens of GiB of anonymous memory.

## Verdict

Inkling 2 Mini IQ4_NL does not fit comfortably beside `qfn-fast-colo`, and it is too slow to earn
the space. The arithmetic is marginal but not impossible: 18.49 GiB of VRAM plus the 10.7 GiB that
`qfn-fast-colo` holds is 29.19 GiB of the card's 31.86 GiB, which leaves only 2.67 GiB spare, under
the 1024 MiB that `llama.cpp` wants plus any growth from the prompt cache and checkpoints. The real
obstacle is elsewhere: measured beside the live frontier the load triggered a global host-RAM OOM
that killed `strata-host`, because the frontier already holds about 56 GiB anonymous and the 16.4 GB
mmap added more pressure to a 125 GiB machine. Even if it loaded cleanly, 16.8 t/s decode and
17 t/s prefill make a 2 000-token prompt cost about two minutes before the first token, which is
wrong for a colo companion that answers coding questions interactively. Keep the IQ3/IQ2 frontier
packs on the HIP engine. Revisit Inkling only if three things change together: a HIP build of the
`inkling2_loop` architecture, a smaller quant that lands near 10 GiB, and a measured RAM budget that
`--no-mmap` plus `--cache-ram 0` keeps under control.
