---
type: Research
description: Practical, sourced insights about serving and operating a small local LLM fleet (llama.cpp / llama-server, GGUF, a CPU-first box with one small GPU): the flags that matter, the real cost of context, KV-cache quant, CPU throughput, model-choice heuristics, prefix caching, notable Hacker News threads, and failure modes.
task: definition.md
authored_by: agent
timestamp: 2026-10-21T17:50:00+02:00
---

# Serving and operating a small local LLM fleet

This file is a companion to
[small-model-insights.research.md](small-model-insights.research.md). That file
covers prompting, context hygiene, MoE versus dense, quantization levels,
reasoning, tool calling, speculative decoding, sampling, batching, and when to
use a bigger model. This file does not repeat those topics. It covers the
serving and operations layer: the llama.cpp flags that matter, the cost of a
large context, KV-cache quant, CPU throughput, model-choice heuristics, prefix
caching, notable Hacker News threads, and failure modes.

The target box is a 128 GB CPU-first machine with one small GPU. Models range
from 0.5B to 180B, dense and MoE.

Most sources are primary discussions with real user reports: Hacker News (HN)
threads and comments, r/LocalLLaMA threads, blogs, and the llama.cpp docs. Where
the community disagrees, or where the evidence is thin, the point says so.

Evidence labels:

- `[docs]` llama.cpp server documentation or issue.
- `[HN]` Hacker News thread or comment.
- `[R]` Reddit thread.
- `[B]` Blog or forum post.
- `[thin]` Few sources, or practitioner consensus only.
- `[disagree]` The community does not agree.

## 1. llama.cpp serving flags that matter in practice

- **Start from the new defaults, then tune.** Recent llama.cpp made `-ngl` and
  `-fa` default to automatic. For most models `--model`, `--ctx-size`, and
  `--jinja` are enough to start. Practitioners then tune the rest for the local
  hardware. `[docs]`
  [server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md),
  `[HN]` [45609463](https://news.ycombinator.com/item?id=45609463)
- **`--n-cpu-moe N` is the key flag on a small GPU.** It keeps the MoE expert
  weights of the first N layers on the CPU and the rest on the GPU. One operator
  reports a 50 percent boost on `gpt-oss-120b` from this flag alone. Another runs
  `gpt-oss-120b` (5.1B active) on a single 4080 at about 20 tokens per second.
  `[HN]` [45609463](https://news.ycombinator.com/item?id=45609463),
  `[HN]` [45345641](https://news.ycombinator.com/item?id=45345641),
  `[docs]` [server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- **`-ngl` and `--n-cpu-moe` are different tools.** Use `-ngl` to move whole
  layers to the GPU. Use `--n-cpu-moe` to keep only the expert weights on the
  CPU while attention and KV stay on the GPU. For a dense model the MoE flag does
  nothing; use `--n-cpu-ffn` instead. `[HN]`
  [45792491](https://news.ycombinator.com/item?id=45792491), `[docs]`
  [server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- **`-ot` gives per-tensor control.** `--override-tensor` places named tensors in
  a chosen buffer. It is finer than `--n-cpu-moe` and useful when one tensor
  type causes an out-of-memory (OOM) error. `[docs]`
  [server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- **Tune `-b` and `-ub`, and watch memory.** `-b` is the logical batch (default
  2048); `-ub` is the physical micro-batch (default 512). A 24 GB GPU operator
  runs `-b 2048 -ub 1024`. A higher `-ub` raises peak memory. `[HN]`
  [48544986](https://news.ycombinator.com/item?id=48544986), `[docs]`
  [server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- **`--no-mmap` and `--mlock` trade load time and RAM for stable speed.**
  Memory-mapping is the default. `--no-mmap` reads the model fully into RAM.
  `--mlock` pins it there so the kernel does not page it out. Operators on
  dedicated boxes use both. Trap: `--mlock` needs enough free RAM, or the kernel
  kills the process. `[HN]`
  [50129914](https://news.ycombinator.com/item?id=50129914), `[HN]`
  [48544986](https://news.ycombinator.com/item?id=48544986), `[docs]`
  [server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- **`--no-context-shift` turns silent truncation into an error.** By default
  llama.cpp does not shift the context. Some front-ends slide the window. Use
  `--no-context-shift` so an overflow returns an error instead of silently
  dropping old tokens. `[HN]`
  [48544986](https://news.ycombinator.com/item?id=48544986), `[docs]`
  [server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- **Two traps with `-fit` and `--parallel`.** `--fit on` is the default and
  adjusts unset arguments to fit device memory; it can lower your context size
  without a clear message. `--fit-ctx` sets the minimum. `--parallel N` divides
  the context among N slots. `[docs]`
  [server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)

## 2. Context size versus quality and cost

- **KV memory grows linearly with context length.** A 260k context on a dense
  Qwen model needs about 16 GB of RAM for the KV cache alone, before any
  quantization. The memory cost is a first-class reason to keep `-c` small.
  `[HN]` [48428077](https://news.ycombinator.com/item?id=48428077)
- **A larger `-c` does not by itself lower quality, but it slows the model.**
  Token-generation speed falls as the context fills. One operator sees 30
  tokens per second drop to 2 tokens per second at very long context. Another
  reports that throughput and latency degrade noticeably past 100k tokens.
  `[HN]` [48147087](https://news.ycombinator.com/item?id=48147087), `[B]`
  [deploy.live](https://deploy.live/blog/running-local-llms-offline-on-a-ten-hour-flight/)
- **The effective context is smaller than the trained context.** A model trained
  for 128K may hold far less in practice. One operator reports a 128K-trained
  model at an effective context near 16K, a limitation he observed directly. `[B]`
  [nullprogram](https://nullprogram.com/blog/2024/11/10/)
- **Reserve memory for the whole runtime, not only the weights.** The KV cache,
  the compute buffers, and the desktop session all share memory. On a GPU box
  that also drives the display, leave headroom or the desktop OOMs. `[HN]`
  [48544986](https://news.ycombinator.com/item?id=48544986)
- **Quantizing the KV cache buys context at a quality price.** A K8V4 cache
  (8-bit keys, 4-bit values) cuts KV memory by about 59 percent for about a
  0.86 percent perplexity loss. This lets the same memory hold a longer context.
  See topic 3 for the caveats. `[HN]`
  [44009321](https://news.ycombinator.com/item?id=44009321)

## 3. KV-cache quantization

- **The default is f16, and the flag is `--cache-type-k` / `--cache-type-v`.**
  Allowed values are f32, f16, bf16, q8_0, q4_0, q4_1, iq4_nl, q5_0, and q5_1.
  KV quant is applied at runtime and is independent of the weight quant. `[docs]`
  [server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- **Keys are more sensitive than values.** The attention pattern comes from the
  keys. A key error redirects attention to the wrong tokens. A value error only
  adds noise after the pattern is set. K8V4 gave a 7x lower perplexity loss than
  K4V8 at the same memory. `[HN]`
  [44009321](https://news.ycombinator.com/item?id=44009321), `[thin]` the effect
  direction is well supported; the exact numbers come from one disputed project.
- **q8_0 is the safe floor for most work.** Operators report that q8_0 KV is the
  lowest that still keeps tool calling reliable. Below q8, quality problems
  appear on exact tasks. `[HN]`
  [48544986](https://news.ycombinator.com/item?id=48544986), `[HN]`
  [49305335](https://news.ycombinator.com/item?id=49305335)
- **Quantize the weights before you quantize the KV cache.** Weight quant is
  baked into the file and is cheaper to reason about. KV quant acts at runtime
  and its errors grow with context length. Use the smallest weight quant you can
  afford, then lower the KV type only if you still need memory. `[B]`
  [level1techs](https://forum.level1techs.com/t/why-your-local-llm-feels-dumber-than-it-is/253917),
  `[HN]` [44009321](https://news.ycombinator.com/item?id=44009321)
- **Flash attention and KV quant work together.** A common belief that flash
  attention must be off for quantized KV is wrong for the built-in
  `--cache-type-k/-v` flags. Commenters corrected a project that made this claim.
  `[HN]` [44012200](https://news.ycombinator.com/item?id=44012200)
- **`[disagree]`** Some operators report no quality loss from K8V4 on long-context
  retrieval. One operator reports that any KV quant failed a hard reasoning
  benchmark. The impact depends on the task and the model. `[HN]`
  [49912522](https://news.ycombinator.com/item?id=49912522), `[HN]`
  [49305335](https://news.ycombinator.com/item?id=49305335)

## 4. Throughput versus latency on CPU

- **Prefill is compute-bound; token generation is memory-bandwidth-bound.**
  Prompt processing runs large matrix multiplications (GEMM). Token generation
  reads all weights for each token (GEMV) and is limited by memory bandwidth.
  This split explains most local performance numbers. `[HN]`
  [42313615](https://news.ycombinator.com/item?id=42313615), `[HN]`
  [48138610](https://news.ycombinator.com/item?id=48138610), `[HN]`
  [48928290](https://news.ycombinator.com/item?id=48928290)
- **On CPU, token generation follows memory bandwidth.** More channels and
  faster DDR raise token generation in proportion. One operator estimates 8
  channels of DDR4-2400 give about 6 tokens per second, and 12 channels of
  DDR5-4800 give about 3x. More CPU cores raise prefill speed, not token speed.
  `[HN]` [48640337](https://news.ycombinator.com/item?id=48640337)
- **Prefill dominates for long prompts.** One operator reports that a 1000-token
  prefill took about 54 seconds (18.5 tokens per second) with experts on the CPU,
  while generation ran at about 14 tokens per second. On a GPU with experts on
  the CPU, prompt processing was 3039 tokens per second against 42.85 for
  generation. `[HN]` [47928961](https://news.ycombinator.com/item?id=47928961),
  `[HN]` [45224772](https://news.ycombinator.com/item?id=45224772)
- **A full-GPU run shows the same split at a higher scale.** One RTX 5090 report
  gives 4818 tokens per second prompt processing against 221 tokens per second
  generation for a 4-bit 30B model. `[HN]`
  [45224772](https://news.ycombinator.com/item?id=45224772)
- **Unified-memory boxes improve both phases.** Apple Silicon and AMD Strix Halo
  have high memory bandwidth to system RAM, so they beat a plain CPU on both
  prefill and generation. An average iGPU or low-end GPU does not. `[HN]`
  [44854259](https://news.ycombinator.com/item?id=44854259)
- **Concurrency raises aggregate throughput but not single-request latency.**
  One operator gets about 4x aggregate throughput from 8 parallel requests. All
  slots share one memory-bandwidth budget, so latency per request rises. `[HN]`
  [48147087](https://news.ycombinator.com/item?id=48147087)
- **On a generic desktop, CPU inference is comfortable up to about 10B
  parameters.** One practitioner writes that CPU inference works reasonably to
  about 10B and that GPU inference is not worth it below 8 GB of VRAM. `[B]`
  [nullprogram](https://nullprogram.com/blog/2024/11/10/) `[disagree]` brys
  runs 27-36B models on CPU: the MoE models (few active parameters) reach 20-23
  tokens per second and the dense models about 2-3. The 10B figure is an
  interactive-comfort rule for a plain desktop, not a hard limit for a 16-core,
  128 GB box.

## 5. Model-choice heuristics practitioners use

- **Match the model to the task; there is no single best model.** One operator
  maps tasks to models: a fast small model for extraction and classification,
  Gemma for summarization, `gpt-oss` for transcript lookup, and a large Qwen for
  hard reasoning and code reading. `[HN]`
  [49410310](https://news.ycombinator.com/item?id=49410310)
- **On a generic desktop, 7-8B is the general-purpose floor and about 20B the
  usual practical ceiling.** One guide states that 7-8B models are good for
  generic work and programming, and that most users stay below 20B without
  special hardware. `[B]`
  [steelph0enix](https://steelph0enix.github.io/posts/llama-cpp-guide/)
  `[disagree]` brys serves and uses 27-36B models. The 20B ceiling is a
  consumer-desktop rule; a 128 GB box reaches larger models, fast when MoE and
  slow when dense.
- **Choose dense for quality, MoE for speed, at the same size.** On one 4090 the
  recommendation is a dense 27B for best quality and a 35B-A3B MoE for best
  speed. This matches the companion file's MoE-versus-dense findings. `[HN]`
  [47843466](https://news.ycombinator.com/item?id=47843466)
- **A larger MoE can beat a smaller dense model on a small GPU.** With
  `--n-cpu-moe`, a 120B MoE (5.1B active) runs on a single 4080. The active
  parameter count, not the total, sets the speed. `[HN]`
  [45345641](https://news.ycombinator.com/item?id=45345641)
- **A MoE on CPU can be as fast as a much smaller dense model.** One author
  reports a 16B MoE (2B active) running as fast as a 2B dense model while
  scoring like a much larger model. `[B]`
  [nullprogram](https://nullprogram.com/blog/2024/11/10/)

## 6. Prompt and prefix caching

- **Prompt caching is on by default and reuses the unchanged prefix.** The
  server compares a new prompt to the previous one and evaluates only the unseen
  suffix. This makes a stable system prompt cheap to reuse. `[docs]`
  [server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- **An unstable system prompt breaks the cache.** In an agent loop the same
  system prompt and tool schemas are resent every turn. If any part changes, the
  whole prefix is re-processed. One commenter states that resending the prefix,
  not decode speed, is the real cost for agents. `[HN]`
  [49918132](https://news.ycombinator.com/item?id=49918132)
- **`--cache-reuse N` reuses a prefix in chunks via KV shifting.** The chunk size
  is N tokens. One operator runs `--cache-reuse 256`. This needs prompt caching
  enabled. `[HN]`
  [48544986](https://news.ycombinator.com/item?id=48544986), `[docs]`
  [server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- **The client must send the cache flag.** The server defaults to caching, but
  some clients must set `cache_prompt` in the request. One author writes that
  prompt caching is nearly always better enabled yet is off by default in some
  clients. `[B]` [nullprogram](https://nullprogram.com/blog/2024/11/10/)
- **Slots change cache behavior.** With multiple slots each request may match a
  different slot. `--kv-unified` shares one KV buffer across slots, and
  `-sps`/`--slot-prompt-similarity` controls how close a prompt must be to reuse
  a slot. `[docs]`
  [server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)

## 7. Notable Hacker News threads with durable lessons

- **"The local LLM ecosystem doesn't need Ollama"** `[HN]`
  [47788385](https://news.ycombinator.com/item?id=47788385). Core takeaway: the
  runtime, not only the model, decides quality. Lessons: (1) a runtime with
  botched chat templates makes a good model look bad, and users blame the model;
  (2) llama.cpp now serves an OpenAI-compatible API with router support, so the
  old convenience gap has narrowed.
- **"Experimenting with Local LLMs on macOS"** `[HN]`
  [45168953](https://news.ycombinator.com/item?id=45168953). Core takeaway:
  local models still hallucinate on open tasks. Lessons: (1) a cleanup task with
  "do not add anything" still added content; (2) most NPUs are too weak for
  useful local inference; GPU compute wins.
- **"Everything I've learned so far about running local LLMs"** `[HN]`
  [42100560](https://news.ycombinator.com/item?id=42100560) (blog
  [nullprogram](https://nullprogram.com/blog/2024/11/10/)). Core takeaway: a
  practical snapshot of CPU and small-GPU serving. Lessons: (1) use
  `llama-server` and enable prompt caching; (2) fill-in-the-middle models often
  do not know when to stop, so expect to cut generation.
- **"Ask HN: Has anyone replaced Claude/GPT with a local model for daily
  coding?"** `[HN]` [48542100](https://news.ycombinator.com/item?id=48542100).
  Core takeaway: a full local coding setup is now viable on a good GPU. Lessons:
  (1) one operator publishes a complete flag set, including `-np 1`,
  `--no-context-shift`, `--cache-reuse`, and q8_0 KV; (2) the harness matters as
  much as the model.
- **"Running local LLMs offline on a ten-hour flight"** `[HN]`
  [47921064](https://news.ycombinator.com/item?id=47921064) (blog
  [deploy.live](https://deploy.live/blog/running-local-llms-offline-on-a-ten-hour-flight/)).
  Core takeaway: tight-scope work runs well locally; long-context work does not.
  Lessons: (1) throughput and latency degrade past 100k tokens; (2) prompts can
  send the model into an infinite loop.
- **"Show HN: Llmspeed"** `[HN]`
  [50127979](https://news.ycombinator.com/item?id=50127979). Core takeaway: a
  shared thread of real serving configurations. Lessons: (1) a commenter
  publishes a full `config.ini` with `--n-cpu-moe`, `--no-mmap`, `--mlock`, and
  KV quant; (2) another reports 131k context with minimal quality loss on a
  bandwidth-limited box.
- **"Llama.cpp 30B runs with only 6GB of RAM now"** `[HN]`
  [35393284](https://news.ycombinator.com/item?id=35393284). Core takeaway: the
  memory-mapping and offload work is the reason huge models run on small
  machines. Lesson: mmap made larger-than-RAM models practical and shaped later
  flags such as `--no-mmap`.
- **"Llama.cpp guide - Running LLMs locally on any hardware, from scratch"**
  `[HN]` [42274489](https://news.ycombinator.com/item?id=42274489) (blog
  [steelph0enix](https://steelph0enix.github.io/posts/llama-cpp-guide/)). Core
  takeaway: a full build-and-quantize walkthrough. Lessons: (1) speed depends on
  matrix throughput, memory bandwidth, and model size; (2) pick the largest quant
  that fits in memory.

## 8. Failure modes of self-hosted small models

- **Silent truncation and context overflow.** By default llama.cpp does not
  shift the context. A front-end that slides the window can silently drop old
  tokens. Use `--no-context-shift` to get an error instead. `[HN]`
  [48544986](https://news.ycombinator.com/item?id=48544986), `[docs]`
  [server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- **Chat template mismatch.** A GGUF with no chat template, or a template the
  runtime cannot convert, makes the model talk but "dumber". Many runtimes use a
  Go template syntax that cannot losslessly convert a Jinja template. Check the
  template before blaming the model. `[HN]`
  [47788385](https://news.ycombinator.com/item?id=47788385), `[HN]`
  [49402232](https://news.ycombinator.com/item?id=49402232)
- **Out-of-memory on long context.** KV memory grows with context. A model that
  fits at 8k can OOM at 128k. `--fit on` may reduce the context silently instead
  of failing. Reserve memory and set `-c` explicitly. `[HN]`
  [44842494](https://news.ycombinator.com/item?id=44842494), `[docs]`
  [server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- **Loops and no stop condition.** Local models can loop and not stop, both in
  chat and in fill-in-the-middle code. Set a step limit and be ready to cut
  generation. `[B]`
  [deploy.live](https://deploy.live/blog/running-local-llms-offline-on-a-ten-hour-flight/),
  `[B]` [nullprogram](https://nullprogram.com/blog/2024/11/10/)
- **GPU hang and device loss.** A GPU draft head can wedge the device. On this
  fleet the W6600 hit an amdgpu ring timeout under the MTP draft workload; the
  Vulkan context was lost for the life of the process and every later decode
  failed. This matches open llama.cpp reports
  ([27306](https://github.com/ggml-org/llama.cpp/issues/27306),
  [27076](https://github.com/ggml-org/llama.cpp/issues/27076),
  [30010](https://github.com/ggml-org/llama.cpp/issues/30010)). See
  [w6600-amdgpu-hang](../w6600-amdgpu-hang/research.md). `[docs]`
- **`[thin]`** Online reports of GPU hangs under llama.cpp are sparse and often
  hardware-specific. Treat this as an open risk on a small GPU, not a solved
  one.

## Source index

Hacker News threads and comments:

- [45609463](https://news.ycombinator.com/item?id=45609463) `--n-cpu-moe` and
  default flags.
- [45345641](https://news.ycombinator.com/item?id=45345641) 120B MoE on one 4080.
- [48544986](https://news.ycombinator.com/item?id=48544986) full serving flag set
  for local coding.
- [50129914](https://news.ycombinator.com/item?id=50129914) `config.ini` with
  `--n-cpu-moe`, `--no-mmap`, `--mlock`.
- [48428077](https://news.ycombinator.com/item?id=48428077) 260k context needs
  about 16 GB of KV.
- [48147087](https://news.ycombinator.com/item?id=48147087) generation speed drop
  and parallel throughput.
- [44009321](https://news.ycombinator.com/item?id=44009321) KVSplit, K8V4 versus
  K4V8.
- [44012200](https://news.ycombinator.com/item?id=44012200) correction: built-in
  `-ctk`/`-ctv` already existed.
- [42313615](https://news.ycombinator.com/item?id=42313615),
  [48138610](https://news.ycombinator.com/item?id=48138610),
  [48928290](https://news.ycombinator.com/item?id=48928290) prefill is
  compute-bound, generation is bandwidth-bound.
- [48640337](https://news.ycombinator.com/item?id=48640337) token generation
  follows memory channels.
- [47928961](https://news.ycombinator.com/item?id=47928961),
  [45224772](https://news.ycombinator.com/item?id=45224772) measured prefill and
  generation rates.
- [44854259](https://news.ycombinator.com/item?id=44854259) unified memory helps
  both phases.
- [49410310](https://news.ycombinator.com/item?id=49410310) task-to-model mapping.
- [47843466](https://news.ycombinator.com/item?id=47843466) dense for quality,
  MoE for speed.
- [49918132](https://news.ycombinator.com/item?id=49918132) resending the prefix
  is the real agent cost.
- [47788385](https://news.ycombinator.com/item?id=47788385) the Ollama thread.
- [45168953](https://news.ycombinator.com/item?id=45168953) local LLMs on macOS.
- [42100560](https://news.ycombinator.com/item?id=42100560) everything learned
  about local LLMs.
- [48542100](https://news.ycombinator.com/item?id=48542100) local model for daily
  coding.
- [47921064](https://news.ycombinator.com/item?id=47921064) ten-hour flight.
- [50127979](https://news.ycombinator.com/item?id=50127979) Llmspeed thread.
- [35393284](https://news.ycombinator.com/item?id=35393284) 30B on 6 GB of RAM.
- [42274489](https://news.ycombinator.com/item?id=42274489) llama.cpp guide.
- [44842494](https://news.ycombinator.com/item?id=44842494) larger contexts eat
  memory.
- [45792491](https://news.ycombinator.com/item?id=45792491),
  [46232011](https://news.ycombinator.com/item?id=46232011) `--n-cpu-moe` for
  MoE offload.
- [49305335](https://news.ycombinator.com/item?id=49305335),
  [49912522](https://news.ycombinator.com/item?id=49912522) KV quant quality
  reports.

Blogs and documentation:

- [llama.cpp server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- [nullprogram - Everything I've learned so far about running local LLMs](https://nullprogram.com/blog/2024/11/10/)
- [steelph0enix - llama.cpp guide](https://steelph0enix.github.io/posts/llama-cpp-guide/)
- [deploy.live - Running local LLMs offline on a ten-hour flight](https://deploy.live/blog/running-local-llms-offline-on-a-ten-hour-flight/)
- [jadidbourbaki - 42x faster prompt lookup drafting in llama.cpp](https://jadidbourbaki.github.io/blog/prompt-lookup-llama-cpp/)
- [Level1Techs - Why your local LLM feels dumber than it is](https://forum.level1techs.com/t/why-your-local-llm-feels-dumber-than-it-is/253917)

llama.cpp issues:

- [27306](https://github.com/ggml-org/llama.cpp/issues/27306),
  [27076](https://github.com/ggml-org/llama.cpp/issues/27076),
  [30010](https://github.com/ggml-org/llama.cpp/issues/30010) GPU hang and
  device loss under the draft head.

## Notes on evidence quality

- The llama.cpp README is the authority for flag names and defaults. Verify the
  defaults against the version on the box; they changed recently (`-fa` and
  `-ngl` now default to automatic).
- The KVSplit project that produced the K8V4 numbers is disputed. Commenters
  found the "new" flags already existed as `--cache-type-k` and
  `--cache-type-v`. Use the direction of the effect (keys matter more than
  values), not the exact project.
- Reddit blocked direct reads from the build network. Reddit points are titles
  and community consensus, not quoted text.
- GPU-hang reports online are thin and hardware-specific. The fleet's own
  [w6600-amdgpu-hang](../w6600-amdgpu-hang/research.md) task is the strongest
  local evidence.

## See also

- [definition.md](definition.md) - this task.
- [small-model-insights.research.md](small-model-insights.research.md) - the
  companion file (prompting, context hygiene, MoE, quantization levels,
  reasoning, tool calling, speculative decoding, sampling, batching).
- [model-selection-guide.md](model-selection-guide.md) - the selection guide.
- [w6600-amdgpu-hang/research.md](../w6600-amdgpu-hang/research.md) - the GPU
  hang on this fleet.
