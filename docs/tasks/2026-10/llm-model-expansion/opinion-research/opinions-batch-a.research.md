---
type: Research
description: What real users and reviewers say about eight new local models (batch A) from Reddit r/LocalLLaMA, r/LocalLLM, Hacker News, blog reviews, and model cards; strengths, weaknesses, comparisons, and runtime gotchas, with a source for each claim.
task: ../definition.md
authored_by: agent
timestamp: 2026-10-20T21:15:00+02:00
---

# Opinion research, batch A: what users and reviewers say

This file collects public opinion on eight models from the popularity sweep
([sweep.research.md](../popularity-sweep/sweep.research.md)). It is a desk study.
No model was run. The goal is to help a non-expert choose which models to keep.

**Evidence marks.** Each claim carries a source. `[HN]` means Hacker News,
`[R]` means a Reddit thread, `[blog]` means a review or news blog, `[card]`
means the model card. Where coverage is thin, this file says so. Vendor claims
are marked as self-reported; independent numbers are marked as independent.

**A warning on dates.** These are 2026 models. Most opinion is days to weeks old
at the time of writing. Treat every benchmark as a snapshot.

## 1. Qwen3.8-27B (Qwen, 27B dense, vision, 2026-08)

The best-covered model in this batch. One Reddit megathread alone scanned about
2,000 posts across r/LocalLLaMA and r/LocalLLM `[blog/prismix]`.

**Good at**

- Agentic coding and tool calling. The megathread calls tool-calling
  reliability "the strongest claim with controlled evidence behind it", with a
  plain-Python tool loop reporting zero failed calls where Gemma 4 A4B and
  Qwen3.6 A3B failed often. One user drove 80 tool calls to scrape a university
  site with no intervention `[blog/prismix]`.
- One-shot creative and game generation. Users built playable clones and, in one
  case, an online multiplayer MOBA overnight `[blog/prismix]`.
- Vision. It reads images natively, with OCR-style reading at about 1,000 image
  tokens `[blog/prismix]`.
- Thinking-level control. Low and medium effort score close to xhigh on
  Artificial Analysis (about 43/44) while cutting reasoning tokens several-fold
  `[blog/prismix]`.

**Weak at**

- Knowledge recall regressed against Qwen3.6. This is widely reported and reads
  as a deliberate agent-first tradeoff: the model is trained to search instead
  of recall. "Trivia nerds: keep Gemma around" `[blog/prismix]`.
- Long analytical or document work. One user calls it "a step backwards" against
  3.6 at default settings `[blog/prismix]`.
- Overthinking. xhigh is the shipped default and "is why your context window
  evaporates". One reviewer calls xhigh "for leaderboard screenshots" and low
  "the rational preset" `[blog/prismix]`.

**Compared to**

- Neck-and-neck with DeepSeek V4 and GPT-5.6 Luna Max on the Artificial Analysis
  headline, but "heavily caveated" `[blog/prismix]`.
- A community table has it well ahead of Ornith-1.5-35B on Terminal-Bench 2.1
  (73.0 vs 67.8), SWE-bench Pro (61.7 vs 59.6), and DeepSWE (42.2 vs 22.0)
  `[HN]`.
- Faster than a dense 27B should be on fast hardware, but one user got only
  about 4 tok/s on an M1 Pro with MTP `[HN]`.

**Runtime notes**

- The official Jinja chat template shipped with real bugs: thinking toggle
  crashes, blank think tags poisoning multi-turn history, and JSON-string tool
  arguments crashing. The community fix is `froggeric/Qwen-Fixed-Chat-Templates`
  `[blog/prismix]`.
- Q4_K_M is the community sweet spot. "Never run reasoning off"; two reports
  say it costs 8 to 12 points `[blog/prismix]`.
- llama.cpp must register the `qwen35` architecture. Older builds refuse the
  file `[blog/locallyuncensored]`.
- `--mmproj` is a separate 0.9 GB file. Without it images are silently ignored
  `[blog/locallyuncensored]`.
- One report: decode degrades from 122 to 69 tok/s within a single generation on
  a 5090 (bug filed) `[blog/prismix]`.

Sources: prismix.dev miror of the r/LocalLLaMA megathread (Aug 2026);
locallyuncensored.com run guide (Aug 2026); explainx.ai; HN Ornith-1.5 thread.

## 2. Ornith-1.5-9B and Ornith-1.5-35B-A3B (ornith-ai)

Ornith is a small research startup (traced by HN to Jiwei Li, tied to
DeepReinforce). The family extends "self-scaffolding" into a self-improvement
loop. The 9B and 35B are post-trained derivatives, not new base models
`[blog/explainx]`.

**Good at**

- Agentic coding at a size that fits consumer hardware. Vendor tables put
  Ornith-1.5-35B ahead of Qwen3.6-35B-A3B and Gemma-4-31B on Terminal-Bench 2.1
  (self-reported) `[blog/explainx]`.
- Speed per size. One HN user ran the 35B-A3B for web scraping "on par with
  Qwen3.8 27B at a much higher speed and at a higher quant (q4 vs q8)"
  `[HN]`.
- The 9B is a strong small model, with a quantized Mobile build for phones
  `[blog/explainx]`.

**Weak at**

- Coding versus Qwen3.8-27B. The one independent run available disagrees with
  the vendor: Ornith-1.5-35B trailed Qwen3.8-27B on Terminal-Bench 2.1, SWE-bench
  Pro, and DeepSWE, and the DeepSWE gap was large (22.0 vs 42.2) `[HN]`;
  `[blog/explainx]`.
- Coding versus Qwen3.6. One HN user: "it does not seem to be better than Qwen
  3.6 35B at coding. A bit worse" `[HN]`.
- Identity confusion. Across five probes it "reliably claims to be Claude"
  `[HN]`; `[blog/explainx]`. This is a training-data artifact, not copied
  weights.

**Compared to**

- Ornith's own claim: 35B-A3B beats Gemma-4-31B and Qwen3.6-35B-A3B on agentic
  coding while activating only 3B per token `[blog/explainx]`.
- The 397B flagship is reported to match Claude Opus 4.8 on self-reported
  Terminal-Bench 2.1 (86.1 vs 85.0), not independently reproduced `[blog/explainx]`.
- The 397B is reported to be derived from Qwen3.5-397B-A17B via post-training;
  community reverse-engineering, not vendor-confirmed `[HN]`.

**Runtime notes**

- MIT license, BF16 / FP8 / NVFP4 / GGUF / MLX builds on day one `[card]`.
- No official MLX version seen by at least one HN user `[HN]`.
- The 397B needs multi-Spark or 4x 3090 class hardware; the 35B-A3B runs on a
  single consumer GPU or an M1 64GB MacBook `[HN]`.

Sources: explainx.ai Ornith-1.5 review (Aug 2026); howdoaiagentswork.com;
HN thread "Ornith-1.5: From Self-Scaffolding to Self-Improvement" (76 comments);
ornith-ai HF model card.

## 3. Muse-Glimmer-30B (Meta Superintelligence Lab)

An open, 30B dense agentic model with a perception encoder, distilled from the
closed Muse Spark. A large HN launch thread (about 1,209 points, 638 comments)
`[HN]`. Independent reviews exist `[blog/awesomeagents]`.

**Good at**

- Tool use. Independent LM Studio BionicBench: 83.3% task completion versus
  77.7% for both Gemma 4 31B and Qwen3.6-27B. The widest benchmark margin is on
  MCP Atlas (75.5 vs 54.2 / 62.5) `[blog/awesomeagents]`.
- Bounded, schema-driven agent tasks with a clear success condition
  `[blog/awesomeagents]`.
- Fits a 24 GB or 32 GB card at 4-bit "with minimum to no degradation on
  agentic tasks" `[card]`.

**Weak at**

- Long agent sessions. It trails Qwen3.6-27B on Terminal-Bench 2.1 (51.7 vs
  60.7) and OSWorld-Verified (65.9 vs 75.6), the two tests that best simulate a
  multi-step session `[blog/awesomeagents]`.
- Prompt-injection safety. Siren AgentDojo attack success rate 28.4%, worse than
  Gemma 4's 25.6% `[blog/awesomeagents]`.
- Memory leakage. CI Memories violation rate 26.4%, more than double Gemma 4's
  12.1% `[blog/awesomeagents]`.
- Fine-tuning still needs data-center hardware (1 to 8 H100s) `[blog/awesomeagents]`.

**Compared to**

- One HN user reported it "performing great, roughly on par with 3.6 27B" on a
  single 3090 for agentic coding `[blog/latent.space]`.
- HN feedback is split between technical praise and skepticism of Meta's
  motives; the top comment called the release "reputation management"
  `[blog/awesomeagents]`.

**Runtime notes**

- Apache 2.0, day-one GGUF and ExecuTorch builds, broad runtime support
  `[blog/awesomeagents]`.
- Optional vision projector adds about 1.4 GB; the DFlash drafter adds about
  1.63 GB `[blog/awesomeagents]`.
- Dense architecture, so it activates every parameter per token and pays no MoE
  tax on a single GPU `[blog/awesomeagents]`.
- New architecture (`muse_glimmer`); the sweep flags it as needing a llama.cpp
  check `[sweep]`.

Sources: awesomeagents.ai review (Aug 2026); meta-models HF card; Semaphore
analysis; HN launch thread; popularity sweep.

## 4. Inkling-Small (Thinking Machines Lab)

Note: the sweep lists `inkling_mm_model` as the architecture but the maker is
Thinking Machines Lab, not a generic arch. It is a 276B-A12B MoE, fifteen days
after the 975B flagship. Coverage is real but quieter than the flagship
(HN about 33 points) `[blog/eesel]`; `[HN]`.

**Good at**

- Coding and agentic tool use, beating its own larger parent. SWE-bench
  Verified 80.2% versus 77.6%; Toolathlon Verified 54.4% versus 45.5%
  `[blog/eesel]`.
- Instruction following (IFBench) and long context (1M tokens on the card)
  `[blog/eesel]`.
- Self-hosting on a workstation: an 89 GB 2-bit quant fits a 128 GB
  unified-memory box `[blog/eesel]`; `[blog/runaihome]`.
- Native audio and image input, still uncommon at this size `[blog/eesel]`.

**Weak at**

- Factual recall, sharply. SimpleQA Verified falls to 20.6% from the parent's
  43.9%, and AA Omniscience is -9.0, meaning it states more wrong things
  confidently than right things `[blog/eesel]`.
- Long agentic sessions and factual categories where raw size still buys
  something `[blog/runaihome]`.
- Multilingual and some workflows (Tau 3 Banking drops to 15.5% from 23.7%)
  `[blog/eesel]`.
- One HN user: got "stuck in a token puke loop and couldn't do tool calls"; a
  separate user said the models "have serious issues with coherence"
  `[HN]`.

**Compared to**

- Independent Artificial Analysis: 40 on the Intelligence Index versus 41 for
  the full Inkling, one point apart at a quarter of the size `[blog/eesel]`.
- Against DeepSeek-V4-Flash-0731: DeepSeek scores 50 on AA versus Inkling-Small's
  40, "significantly better", but DeepSeek is text-only while Inkling takes
  images `[blog/uwekorn]`.
- One HN comment: "better than haiku 4.5, smaller than nemotron 3 ultra"
  `[blog/eesel]`.

**Runtime notes**

- Apache 2.0. Self-host floor is about 89 GB at a 2-bit quant; BF16 is 543 GB
  `[blog/eesel]`.
- llama.cpp needs PR #25731 merged `[blog/eesel]`. Stale runtimes give an
  "unknown model architecture" error `[blog/runaihome]`.
- The 1M context is a weights capability; a single 96 GB card leaves only about
  8 GB for KV cache, so plan 8 to 16K context locally `[blog/runaihome]`.
- Reasoning effort is a 0 to 0.99 dial set through the chat template, not the
  standard OpenAI `reasoning_effort` field `[blog/uwekorn]`.
- One local reviewer, on a 128GB MacBook: 15 to 22 tok/s decode, and it
  over-thinks far less than Laguna-S-2.1 `[blog/uwekorn]`.

Sources: eesel.ai review (Aug 2026); runaihome.com hardware guide (Jul 2026);
uwekorn.com local test (Aug 2026); thinkingmachines.ai; HN.

## 5. Hy-Memory-30B-A3B (Tencent)

A narrow specialist, not a chat model. It writes the write-path of an agent
memory framework (Mem0, MemOS, Hy-Memory). It released quietly with no launch
post `[blog/orcarouter]`. Coverage is small but coherent.

**Good at**

- One job: deciding what to retain in a long-term memory bank, how to phrase it,
  and how new evidence updates it `[card]`.
- Tencent's cross-harness benchmark: macro average 55.49, ahead of Claude Opus 5
  (54.62) and DeepSeek V4.1 Flash (53.64), and it transfers to a held-out
  framework (EverMemOS) `[card]`; `[blog/mindstudio]`.

**Weak at**

- Everything outside memory writing. "Hy-Memory-30B-A3B is not a chat model"
  `[blog/mindstudio]`. Do not expect general assistant quality.
- Independent proof. All four tests were designed and run by Tencent with no
  independent replication `[blog/techtimes]`.

**Compared to**

- Beat Claude Opus 5 by 0.87 points on average, and by only 0.01 on one harness
  `[blog/ibl]`. One reviewer's read: "the news is governance, not capability"
  `[blog/ibl]`.
- The Reddit thread's top comment is dismissive: "cool i guess" `[R]`.
- One analysis frames it as a validated engineering judgment: "memory writing is
  a narrow, deep task where a small specialist beats a general-purpose giant on
  cost and latency" `[blog/aimodeling]`.

**Runtime notes**

- Apache 2.0; 30B total / about 3B active MoE, 262K context `[card]`; `[blog/duckets]`.
- One 60 GB BF16 checkpoint; community MLX-4bit and FP8 builds exist `[blog/orcarouter]`;
  `[HF]`.
- Tencent publishes no first-party hosted endpoint or token price `[blog/benchlm]`.

Sources: tencent HF card and arXiv 2610.22196; orcarouter.ai; mindstudio.ai;
techtimes.com (Oct 2026); ibl.ai; aimodeling.com; r/LocalLLaMA thread.

## 6. Mellum2.1-12B-A2.5B-Thinking (JetBrains)

A coding-focused 12B-A2.5B MoE, trained from scratch, Apache 2.0. The 2.1 release
is the same architecture as Mellum2 but RL-trained in real coding environments
`[blog/byteiota]`.

**Good at**

- Fast inference. About 40 tok/s on an 8GB notebook; the whole point is
  throughput under concurrent load and cheap sub-agents `[R]`; `[blog/byteiota]`.
- Function-level code generation (HumanEval+ / MBPP+). Mellum2 thinking scored
  78.4% on EvalPlus, ahead of Qwen3.5-9B at 71.8% `[blog/thenewstack]`.
- Not overthinking. Local users say it "doesn't overthink" and returns reviews
  faster than larger models `[R]`; `[blog/uwekorn]`.

**Weak at**

- Agentic coding is still mid-tier despite the jump. Hugging Face card shows
  LiveCodeBench v6 82.0, but SWE-bench Verified only 47.0 and Terminal-Bench 2.1
  only 17.4 `[card]`.
- Tool calling is unreliable in practice. One local user: "it can't do tool calls
  right, it repeatedly called Pi's agent-browser wrongly". In an OpenCode test it
  got "stuck and claim it had no tool access, rendering it effectively useless"
  `[R]`.
- One user: "it runs surprisingly fast ... Pro: ... Contra: it doesn't always
  write working code, and even if, it's often not what you asked it for" `[R]`.

**Compared to**

- JetBrains' own matched eval: SWE-bench Verified rose from 2.0 (Mellum2) to
  47.0 (2.1), but Qwen3.5-9B still scored 50.0, with a wider Qwen lead on
  SWE-bench Pro `[blog/pirouter]`.
- Against Qwen 3.5 4B: "worse in everything else" than the reasoning model, per
  a launch thread `[R]`.
- Reddit consensus: it is a fast router / sub-agent / orchestration model, not a
  primary coder `[R]`.

**Runtime notes**

- Apache 2.0, 128K to 131K context. GGUF and (from JetBrains) a Q6 MLX variant
  were promised `[R]`.
- One user found it needed very precise instructions to function as an agent
  `[R]`.

Sources: JetBrains blog (Jun and Oct 2026); HF card; MarkTechPost; thenewstack.io;
r/LocalLLaMA "Mellum2.1 - a JetBrains Collection" and "Mellum2 local
deployments"; r/LocalLLM.

## 7. LFM2.5-24B-A2B and LFM2.5-2.6B (LiquidAI)

A family of on-device models. The 24B-A2B reasoning model and the 2.6B dense
sibling. Good HN coverage (about 288 points, 81 comments on the 24B; 169 on the
2.6B) `[HN]`.

**Good at**

- Tool calling, not coding. Liquid's own guidance: "not recommended for agentic
  coding and knowledge-heavy tasks"; strength is "tool use, data extraction, RAG,
  and long-context workflows" `[HN]`.
- Speed. Users report 200 to 320 tok/s on a 5070 Ti with 131K context and no
  tuning; 184 tok/s on an M5 Max is the vendor number `[HN]`.
- Terminal operation: "stronger for terminal use, like chaining bash calls,
  monitoring background tasks ... rather than for straight up coding/SWE work"
  `[HN]`.

**Weak at**

- Coding. One user asked it to implement the simplest todo in the ghostty
  codebase "and it failed badly - kept going in circles fixing one compile error
  and introducing another"; Qwen3.8 was slower (40 vs 75 tok/s) but finished
  `[HN]`.
- Knowledge. "Performs much, much worse than Qwen 35B A3B for general knowledge"
  and "it put out some old knowledge as well" `[HN]`.
- Speed without judgment. "It is very fast on a 4090, but also very stupid ...
  it will delete prod, and it will do so at 250t/s" `[HN]`.
- The 2.6B: "These LiquidAI models have never worked well for me"; tool calls
  came out as "bare tool calls in the response" (likely a template issue) `[HN]`.

**Compared to**

- Claims parity with Qwen3.6-35B-A3B on agentic tasks, but a commenter noted it
  scores much worse on SWE-bench Verified and only clearly wins on
  AutomationBench, ToolSandbox, and LiveClaw `[HN]`.
- Sits below a plain Qwen3.8-27B for coding, as a 24B-A2B MoE should `[HN]`.
- The 2.6B is "not even competitive with 2x sized Qwen 4B" per one comment
  `[HN]`.

**Runtime notes**

- LFM Open license, with a non-commercial clause above a revenue threshold
  (free under $10M) `[HN]`.
- Ollama may not cache the prompt correctly ("forcing full prompt re-processing
  due to lack of cache data"), which breaks agent loops. Use another runtime
  `[HN]`.
- Reasoning is forced on, so time-to-answer mixes speed with over-reasoning
  `[HN]`.
- The 2.6B runs at 25 to 30 tok/s under llama.cpp on a 2013 Mac Pro `[HN]`.

Sources: HN threads "LFM2.5-24B-A2B" (288 pts) and "LFM2.5 2.6B" (169 pts);
LiquidAI HF cards; liquid.ai blog.

## 8. Nemotron-3-Nano-30B-A3B (NVIDIA)

A hybrid Mamba-Transformer MoE, 30B total / 3.5B active, 1M context, open
weights plus open data and recipes `[card]`. Coverage is mixed: real Reddit
praise, but also real criticism and a general "nobody uses Nemotron" sentiment
`[R]`.

**Good at**

- Reasoning quality for size and token efficiency. "The reasoning quality is
  insane for its size" `[R]`. One user: "the first local LLM I can run on my
  budget AI rig that seems actually capable of filling in the gaps" `[R]`.
- Long context and speed. Fits 256K in a modest VRAM budget and runs 46.8 tok/s
  at short context; a 3090 user reported "1M+ token CTX on one 3090" `[R]`.
- Deterministic, robotic answers suit research and analysis `[R]`.

**Weak at**

- Agentic coding and tool use past mid-context. One agentic-coding user: "about
  50k tokens in, then it kind of goes off the rails, enters infinite retry loops,
  or starts doing things ... 'silly'" `[R]`.
- Coding versus Qwen. "Qwen3Next runs circles around nemotron for any and all
  coding tasks - the reasoning is actively harmful for data extraction ...
  (10,000!!!! Tokens to convert 5 lines of csv to SQL inserts)" `[R]`.
- General visibility and trust. "Nemotron gets almost no mentions ... they are
  good, but they are not exactly on par with the best open weight models" `[R]`.

**Compared to**

- Beats GLM-4.7-Flash on some benchmarks and underperforms it on others `[HN]`.
- Vendor table: ahead of Qwen3-30B-A3B-Thinking-2507 on SWE-Bench (38.8 vs 22.0)
  and AIME25 with tools, level on GPQA, behind on MMLU-Pro and multilingual
  MMLU-ProX `[card]`.
- The related Cascade 2 30B-A3B: "strong on single shot math/code but falls off
  on multi-step agentic benchmarks is pretty classic for models trained heavily
  on rl with narrow reward signals" `[R]`.

**Runtime notes**

- NVIDIA Open Model License (not Apache) `[card]`.
- ` thinking` and `</think>` are separate tokens; use `--special` if needed
  `[card]`.
- llama.cpp support arrived via PR #18058; older builds fail `[R]`.
- Reasoning is configurable through the chat template, and can be turned off at
  a small accuracy cost on hard prompts `[card]`.

Sources: nvidia HF card; arXiv 2512.20848; r/LocalLLaMA threads (Dec 2025 to Mar
2026); r/LocalLLM "does anyone actually use it" thread; HN.

## See also

- [sweep.research.md](../popularity-sweep/sweep.research.md) — the popularity
  sweep that named these models.
- [definition.md](../definition.md) — this task.
