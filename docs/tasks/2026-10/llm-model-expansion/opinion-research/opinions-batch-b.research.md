---
type: Research
description: What real users and reviewers say about the batch B local models (Qwen coder/VL/Omni, QwQ, North Mini Code, Tiel-Coder, the Qwen3.5/3.6 fleet, Gemma 4, GLM-4.7-Flash, Granite, Seed-OSS, OLMo, MiniCPM-V, Ternary Bonsai, Qwen3 embeddings) from Reddit r/LocalLLaMA, Hacker News, blogs, leaderboards, and model cards; strengths, weaknesses, comparisons, and runtime gotchas, with a source for each claim.
task: ../definition.md
authored_by: agent
timestamp: 2026-10-20T22:37:54+02:00
---

# Opinion research, batch B: what users and reviewers say

This file collects public opinion on the batch B models. It is a desk study. No
model was run. The goal is to help a non-expert choose which models to keep. It
follows [opinions-batch-a.research.md](opinions-batch-a.research.md).

**Evidence marks.** Each claim carries a source. `[HN]` means Hacker News,
`[R]` means a Reddit thread, `[blog]` means a review or news blog, `[card]`
means the model card or the Hugging Face file data. Where coverage is thin, this
file says so. Vendor claims are marked as self-reported; independent numbers are
marked as independent.

**A warning on dates.** These are 2025 and 2026 models. Most opinion is days to
weeks old at the time of writing. Treat every benchmark as a snapshot. Reddit
search returned no direct article text for these queries, so most Reddit
evidence here is second-hand (a thread title reproduced on Hacker News, or a
review that quotes the thread).

## 1. Qwen3-Coder-30B-A3B-Instruct (Qwen, 30B/3B MoE, code, 2025-07)

The pure-Qwen CPU-fit coder. Release thread on Hacker News (about 765 points on
the 480B launch; the 30B card thread drew only 10 comments) `[HN]`.

**Good at**

- Agentic coding and tool calling at a size that fits one 24 GB or 32 GB card, or
  the CPU at a low speed. The card claims strong "agentic coding, agentic
  browser-use, and foundational coding tasks" and gives a special function-call
  format for Qwen Code and Cline (self-reported) `[card]`.
- Long context: 256K native, 1M with YaRN, aimed at repository-scale work
  `[card]`.
- It became a local-default workhorse. One user runs it as the primary model on a
  single 3090 next to separate speech models `[HN]`. Another calls it "the best
  results" among local 30B-A3B models for a "write tests for this method" task
  `[HN]`.

**Weak at**

- Harness-dependent tool calling. In one test "Qwen Code just straight up fails
  to use it. Fails to use tools and crashes it"; Aider was "a huge waste of
  time", while OpenHands worked well with an occasional malformed parameter
  `[HN]`. So the model is good, but the wrapper must be tolerant.
- It is the prior generation. Qwen ships no 2026 refresh of the pure Coder line
  under this name; the survey file marks it as superseded by North-Mini-Code and
  Qwen3-Coder-Next for pure quality `[survey]`.
- Not a reasoner. The card states it supports only non-thinking mode and does
  not emit ` thinking` blocks `[card]`.

**Compared to**

- One local reviewer puts it first among small coders: "So far Qwen3-coder gives
  me the best results" over a 30B-A3B field that includes Nemotron 3 Nano `[HN]`.
- A Claude-Code-style client author found `qwen3-coder:30b` "the best-performing
  model so far" for local tool-calling in that flow `[HN]`.

**Runtime notes**

- Needs `transformers>=4.51.0`; older versions raise `KeyError: 'qwen3_moe'`
  `[card]`.
- Unsloth publishes full and quantized GGUFs (Q4_K_M 18.56 GB) and fixed tool
  calling for the 480B sibling `[HN]`; `[card]`.
- Sampling: `temperature=0.7`, `top_p=0.8`, `top_k=20`,
  `repetition_penalty=1.05` `[card]`.

Sources: Qwen HF card; HN "Qwen3-Coder-30B-A3B-Instruct" thread (Jul 2025); HN
Qwen3-Coder launch thread; [qwen-specialized-survey.research.md](../qwen-specialized-survey.research.md).

## 2. Qwen3-VL-30B-A3B-Instruct and Qwen3-VL-8B-Instruct (Qwen, vision, 2025-10)

The Qwen3-VL line. The 8B is the small GPU-or-CPU pick; the 30B-A3B is the
higher-quality CPU MoE. The launch thread drew about 434 points and 160 comments
`[HN]`; the "two-hour video" follow-up drew 265 points `[HN]`.

**Good at**

- OCR and reading real text. The card claims expanded OCR to 32 languages, robust
  in low light, blur, and tilt (self-reported) `[card]`. One independent user
  found Qwen3-VL-8B read a grocery receipt "accurate to the penny" where MiniCPM-V
  (same size) "fabricated" the whole receipt `[HN]`.
- Video and long context. Native 256K, expandable to 1M, with second-level video
  indexing `[card]`. A reviewer headline says it "can scan two-hour videos and
  pinpoint nearly every detail" `[HN]`.
- Local captioning and cataloguing. Users run Qwen3-VL-30B-A3B as a NAS
  image-captioner feeding a vector database, and call it one of their "favorite
  local LLMs" for translation, classification, and categorization `[HN]`.

**Weak at**

- It is a general VLM, not a coder. The same users explicitly separate it from
  "agentic coding assistants" `[HN]`. No independent SWE-bench-style number was
  found for the 8B or 30B.
- Coverage of the 30B-A3B specifically is thin. Most independent comment is
  "it works and I like it"; there is little head-to-head testing quoted in public
  threads.

**Compared to**

- Qwen3-VL-8B is the community answer to "read this image correctly". In the
  receipt duel it beat MiniCPM-V 8B on the same hardware `[HN]`.
- The 30B-A3B became the base for a browser-use model (`bu-30b-a3b-preview`),
  whose author calls the smaller sibling "much much faster than anything out
  there" for browser use (self-reported) `[HN]`.

**Runtime notes**

- llama.cpp implements `qwen3vl` and `qwen3vlmoe`; official GGUFs plus an
  `mmproj` projector exist for each size `[survey]`. The 8B `mmproj` is 1.16 GB
  and must be passed with `--mmproj`, or images are silently ignored `[survey]`;
  `[card]`.
- The 2B fits a Raspberry Pi under llama.cpp `[HN]`.
- Card recommends `flash_attention_2` for multi-image and video `[card]`.

Sources: Qwen3-VL-30B-A3B HF card; HN "Qwen3-VL" thread (Sep 2025); HN
"Qwen3-VL can scan two-hour videos" thread (Nov 2025); HN "Localmaxxing" comment;
HN receipt-fabrication post (Mar 2026); [qwen-specialized-survey.research.md](../qwen-specialized-survey.research.md).

## 3. Qwen3-Omni-30B-A3B-Instruct (Qwen, audio+vision+text, 2025-09)

The only open omni model in this set. The GitHub launch drew about 571 points and
142 comments `[HN]`.

**Good at**

- Native speech in and speech out, plus vision and text, in one model. The card
  claims SOTA on 22 of 36 audio/video benchmarks and open-source SOTA on 32
  (self-reported); ASR is close to Gemini 2.5 Pro `[card]`.
- Real local voice-assistant building. Users wire it (or the related Qwen3-30B)
  into Home Assistant with ESP32 voice satellites and call it "shockingly well"
  `[HN]`.
- Music and non-speech audio understanding is unusual. One HN user fed simple
  clips and it identified instrumentation `[HN]`.

**Weak at**

- Memory and tooling, on real hardware. The card's own minimum GPU memory for the
  Instruct model is 78.85 GB at BF16 with a 15 s video, rising to 144.81 GB at
  120 s `[card]`. That is far beyond a consumer GPU.
- Local speech-to-speech is not turnkey. A widely read "Ask HN" asks for a single
  reproducible local real-time voice loop and reports that none was found:
  "either (a) the tooling isn't there yet, or (b) I'm missing the secret sauce"
  `[HN]`. A vendor serving it on HPC echoed the caveat: "we've seen faster
  results chaining ASR/LLM/TTS compared to native S2S" `[HN]`.
- Modality handling is fiddly. Writing to `use_audio_in_video` must be consistent
  across turns or "unexpected results may occur" `[card]`.

**Compared to**

- Paper title (offered on HN): "first multimodal model with SoTA text, image,
  audio, and video perf" `[HN]`. Treat as a vendor claim until reproduced.
- The card's own tables put the 30B-A3B near a 235B-A22B on text and above
  GPT-4o on some audio rows (self-reported) `[card]`.

**Runtime notes**

- License is Qwen `other`, not Apache `[survey]`.
- llama.cpp does support it (`qwen3_omni_moe`); the official
  `ggml-org` GGUFs exist, Q4_K_M 18.56 GB plus a 1.33 GB `mmproj` `[survey]`.
  The 8 GB GPU is too small; it runs on the CPU.
- The Instruct checkpoint has both a thinker and a talker; `disable_talker()`
  saves about 10 GB but then audio output is off `[card]`.

Sources: Qwen3-Omni HF card; HN "Qwen3-Omni: Native Omni AI model" thread (Sep
2025); HN "Ask HN: best local speech-to-speech" (Jan 2026); HN Qwen3-Omni API
Show HN; [qwen-specialized-survey.research.md](../qwen-specialized-survey.research.md).

## 4. QwQ-32B (Qwen, 32B dense, reasoning, 2025-03)

An older dedicated reasoning model. The release thread drew about 480 points and
169 comments `[HN]`.

**Good at**

- Math and hard reasoning for its time. The card says it competes with DeepSeek-R1
  and o1-mini (self-reported) `[card]`. One API vendor reported "QwQ does well in
  math and coding" and ties o1 on some math and coding benchmarks `[HN]`.
- Local CPU/GPU reasoning on a single card at Q4 (~19.85 GB) `[survey]`.

**Weak at**

- It is superseded. Anyone with Qwen3.8-27B or Qwen3.6 has little reason to keep
  it; it is the "older" reasoning model in the brief.
- Language mixing and over-thinking. A vendor noted QwQ "at times flip flopped
  between English and Chinese" and that o1 "could understand the question better
  and employ more complex strategies" `[HN]`.
- Greedy decoding breaks it: it can enter "endless repetitions" `[card]`.

**Compared to**

- One vendor's read: `o1` was qualitatively better on harder prompts even where
  the scores tied `[HN]`.
- It was strong enough in 2025 that a math commentary called it "significantly
  better at competition problems than previous open models" `[HN]`.

**Runtime notes**

- It is a dedicated reasoning model with a thinking phase; the card requires the
  output to start with ` thinking\n` or quality degrades (an empty think block)
  `[card]`.
- For inputs over 8,192 tokens, enable YaRN, ideally only when long context is
  actually needed, because it hurts short-text performance `[card]`.
- Unsloth published a "how to run QwQ-32B effectively" guide `[HN]`.

Sources: QwQ-32B HF card; HN "QwQ-32B: Embracing the Power of RL" thread (Mar
2025); HN "How to Run QwQ-32B effectively"; [qwen-specialized-survey.research.md](../qwen-specialized-survey.research.md).

## 5. North-Mini-Code-1.0 (CohereLabs, 30B/3B MoE, code, 2026-06)

Cohere's first open coding model. Coverage is real but modest; the launch drew
small HN threads (3 to 10 points) `[HN]`.

**Good at**

- Benchmarked agentic coding at 30B-A3B. The HF leaderboard rows report SWE-bench
  Verified 67.6, SWE-bench Pro 40.2, and Terminal-Bench 2.0 36 `[card]`.
- Tool use was a design goal, with a two-stage SFT plus RLVR post-training aimed
  at agentic coding, and interleaved thinking that "works best when turned on"
  `[card]`.
- One experienced user ranks it high: "North Mini Code by Cohere ... has honestly
  been very competitive ... I'd position it below Moonshot AIs and Z.ai's recent
  releases, but above the varieties of Qwen, DeepSeek, MiMo" `[HN]`.

**Weak at**

- Tool-calling can fail badly. One user could not get it "to play nice on Pi ...
  It just couldn't grasp the tools", even though the model "seemed good
  otherwise" `[HN]`. This matches the class pattern: strong benchmarks, brittle
  harness integration.
- Thin independent testing. Most evidence is the vendor card and a handful of
  comments; no large Reddit megathread was found.

**Compared to**

- A commenter places it below the recent Moonshot and Z.ai (GLM) releases and
  above Qwen, DeepSeek, and MiMo on personal assessment `[HN]`.
- Cohere's card compares it against Gemma 4 and other 30B-class coders using
  publicly reported or Artificial Analysis scores `[card]`.

**Runtime notes**

- It is a new architecture (`cohere2_moe`). Running it locally is easiest through
  vLLM main plus Cohere's `melody` library; there is no guaranteed llama.cpp path
  in the card `[card]`. The presence of community GGUFs suggests a llama.cpp route
  exists but was not confirmed here `[card]`.
- OpenCode support needs the main branch and an interleaved-reasoning config
  `[card]`.
- Sampling: `temperature=1.0`, `top_p=0.95` `[card]`.

Sources: CohereLabs HF card; HN "North Mini Code" thread (Jun 2026); HN PI 1.0
comment (Oct 2026); HN "Inkling" comment (Jul 2026).

## 6. Tiel-Coder-35B-A3B (community fine-tune, code, 2026-08)

A community fine-tune, not a base lab release. It is a derivative of
`ornith-ai/Ornith-1.5-35B-A3B` (a `qwen35moe` model), MIT license, published as
GGUF with MTP. It has about 1.9M downloads on its main GGUF repo `[card]`. There
is no vendor card; opinion comes from local-runner comments.

**Good at**

- Practical local agentic coding on old hardware. One user runs a 4-bit quant on
  a 9-year-old laptop (GTX 1070 Max-Q 8 GB, 16 GB RAM) at 131K context, "around
  16-19 tk/s and 350-500 tk/s prefill", and calls it "amazing for writing scripts
  and doing medium coding tasks and summarizing text for me" `[HN]`.
- A sibling "Cyber" build is described as "the better uncensored version" `[HN]`.

**Weak at**

- Context and loop behavior on small setups. The same class of user hit a loop:
  asked an open-ended "what would you improve in this file" question, "the
  context window seems to be too small. It's running in circles" `[HN]`.
- It is a fine-tune, so quality tracks the base (Ornith-1.5-35B) plus the
  tuning; it is not a frontier coder. No SWE-bench number was found for it.

**Compared to**

- It inherits the Ornith-1.5-35B-A3B base, which independent testing placed behind
  Qwen3.8-27B on Terminal-Bench 2.1, SWE-bench Pro, and DeepSWE `[HN]` (see batch
  A). So expect a solid, fast local coder, not a leaderboard leader.

**Runtime notes**

- Needs the MTP/`qwen35moe` support in llama.cpp; users run forks such as
  `Turboquant` for the low-bit kernels `[HN]`.
- Long context is usable: a 131K-context config is reported, dropping from about
  16-19 to 9 t/s past 100K `[HN]`.

Sources: `peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF-MTP` HF file data (base model
`ornith-ai/Ornith-1.5-35B-A3B`); HN "Llmspeed" thread comments (Oct 2026);
[opinions-batch-a.research.md](opinions-batch-a.research.md) for the Ornith base.

## 7. Fleet Qwen mid-band: Qwen3.6-27B, Qwen3.6-35B-A3B, Qwen3.5-35B-A3B

Already in the fleet. The Qwen3.6-35B-A3B launch drew about 1,274 points and 532
comments `[HN]`; the Qwen3.6-27B launch about 993 points and 458 comments `[HN]`.
Coverage is very rich.

**Good at**

- Qwen3.6-35B-A3B: agentic coding at 3B active. Vendor says it "delivers
  outstanding agentic coding performance, surpassing its predecessor
  Qwen3.5-35B-A3B by a wide margin and rivaling much larger dense models such as
  Qwen3.5-27B" (self-reported) `[HN]`. Simon Willison's popular post "drew me a
  better pelican than Claude Opus 4.7" drew about 463 points `[HN]`.
- Qwen3.6-27B: flagship-class coding in a dense 27B. It is a common local daily
  driver; one user runs it against Sonnet 4.6 for coding and sees "not a huge
  difference in my end user results" `[HN]`.
- Both run on consumer hardware; Qwen3.6-27B reaches 60-70 t/s on an RTX 5090 at
  small context, dropping to about 40 t/s at large context `[HN]`.

**Weak at**

- Qwen3.6-27B is now behind Qwen3.8-27B. Multiple users call 3.8 "a huge step up";
  "[Qwen3.8-27B] was the first time I felt like local models are actually good
  enough to use as daily drivers" `[HN]`. So the 3.6 pair is redundant if 3.8
  fits.
- Qwen3.5-35B-A3B: the weaker prior MoE. Users state plainly "Qwen3.5-27B was
  much better than Qwen3.5-35B-A3B (dense vs MoE)", i.e. the older MoE was worse
  than the older dense `[HN]`.
- Small models still need oversight. One detailed user: at 16 GB it is "very much
  like a junior dev, so much oversight is needed ... A tight code-test-fix loop
  seems to be the way forward" `[HN]`.

**Compared to**

- Qwen3.6-27B and Qwen3.6-35B-A3B were close to each other (dense 27B vs 3B-active
  MoE): "shocking that a 3b active model would perform as well as a 27b dense"
  `[HN]`.
- Against cloud: a local user argues the 35B-A3B is "4-5x cheaper than Haiku" in
  some setups, while others counter that cloud Haiku is faster and better for the
  same money `[HN]`.

**Runtime notes**

- Qwen3.6 and Qwen3.8 share the same architecture, so 3.8 is "in theory ... a
  drop-in replacement" for 3.6 `[HN]`; a well-known tiny benchmark of 27B Q3-Q6
  quants shows near-linear quality `[HN]`.
- The "3.6" name is a continuation of 3.5, not a new architecture `[HN]`.
- Low-bit quants of the 27B run far under full memory: "1 bit ... on my M1 pro
  (16G) and got 13 tok/s with only 5G of ram usage" `[HN]`.

Sources: HN Qwen3.6-35B-A3B launch thread (Apr 2026); HN Qwen3.6-27B launch
thread (Apr 2026); HN "Simon Willison pelican" thread; HN "Llmspeed" and "Nvidia
central bank" comment threads (Oct and Sep 2026).

## 8. Fleet others: Gemma-4 (12B / 26B-A4B / 31B), GLM-4.7-Flash, Granite-4.2-30B, Seed-OSS-36B, OLMo-3.1-32B

**Gemma 4 family.** The Gemma 4 12B launch drew about 1,062 points and 401
comments `[HN]`. It is a unified, encoder-free multimodal model.

- Good at: running on a laptop. Press coverage: "designed to run on any laptop
  with 16GB of RAM"; one reviewer "  tested Gemma4 12B on my 8GB GPU, now I don't
  want to go back to smaller models" `[HN]`. In an independent structured-output
  benchmark, "Gemma-4-31B leads images" across text and audio too `[HN]`.
  An independent user index of "a year of video locally" with Gemma4-31B drew
  about 471 points `[HN]`.
- Weak at: the 16 GB claim is contested. On an 18 GB MacBook Pro, selecting
  Gemma-4-12B "requires more memory ... than is available"; users note the HF
  weights are BF16 and "the 'runs in 16GB' claim is on a totally different
  quantized version" `[HN]`. Encoder-free multimodal is a fast linear projection,
  and the community debated whether that is really "encoder-free" `[HN]`.
- Compared to: "about as solid as Qwen just with a more advanced architecture"
  `[HN]`. As the fastest Gemma-4 mid size, the 26B-A4B is "the fastest of the
  three on the CPU (MoE, about 9 t/s predicted)" `[survey]`.
- Runtime: llama.cpp initially did not implement `gemma4`/`gemma4_unified`; one
  user got looping on an unrelated Qwen-based model and others noted the new arch
  was "NYI" in LM Studio `[HN]`. Because there is no separate encoder, the
  `.mmproj` file is not needed `[HN]`.

**GLM-4.7-Flash (30B/3B MoE, MIT, 2026-01).** The launch drew about 378 points
and 135 comments `[HN]`.

- Good at: agentic coding in a harness. "GLM-4.7-Flash is currently the best one
  for using inside a harness, it's even capable enough to drive simple tasks in
  OpenCode" `[HN]`. It is measured at 16 t/s on the brys-class CPU `[survey]`.
  A tied comment: it "is optimized for agentic work and only needs 5GB of memory"
  (about the 30B model, which is really ~19 GB at Q4) `[HN]`.
- Weak at: early tool-calling was broken. The author of a local Claude-Code
  client "tested glm-4.7-flash ... but it struggles with reliably following
  tool-calling instructions, so it is not usable for this workflow yet" `[HN]`.
  Another early report: with OpenCode it "doesn't work properly ... It repeats
  itself very quickly" and makes spelling errors (`AGANTS.md`); llama.cpp shipped
  a looping fix and users were told to re-download `[HN]`.
- Compared to: card says SWE-bench Verified about 59.7; users compare it to
  "o3/GPT-5 mini" on that metric `[HN]`. One user pairs it against DeepSeek 3.2:
  "faster than DeepSeek 3.2 and about the same quality" `[HN]`.
- Runtime: it is a new architecture at first (`glm4_moe_lite`), and llama.cpp
  needed a PR; older builds do not load it `[HN]`. There is no real gpt-oss-20b
  comparison in size terms: gpt-oss-20b is 11 GB mxfp4 while GLM-4.7-Flash is
  about 19 GB `[HN]`.

**Granite-4.2-30B (IBM, dense 30B, Apache, 2026).** Coverage is thin: the HN
threads carry points in the single digits `[HN]`.

- Good at: enterprise agentic workflows. A commenter: "Granite 4.2 models which
  are just recently out, are optimized to handle agentic workflows ... only needs
  5GB of memory" `[HN]`. IBM's own framing: "native reasoning to enterprise
  agents" `[HN]`. The 8B sibling is tested and holds up on a daily web-research
  task alongside other models `[HN]`.
- Weak at: little independent evaluation. Press ("ride the wave of interest in
  local LLMs") exists but no Reddit-style user testing was found `[HN]`.
- Compared to: no strong head-to-head was found. Treat rank claims as unproven.

**Seed-OSS-36B (ByteDance, dense 36B, Apache, 2025-08).** Reddit opinion exists
("Seed-OSS-36B is ridiculously good", a thread title reproduced on HN) but the HN
discussion is very thin `[HN]`.

- Good at: reasoning with a controllable thinking budget and agentic tasks. The
  card lists strong math (AIME25 84.7), LiveCodeBench v6 67.4, TAU1-Retail 70.4,
  and 512K native context (self-reported) `[card]`.
- Weak at: long-context usability and English-centric speed. Mixed-language use
  and the huge context are card claims, not independent. One production user lists
  Seed-OSS among models used "in production" but gives no quality number `[HN]`.
- Runtime: it is `seed_oss`; vLLM 0.10.0+ is recommended, and a tool-call parser
  `seed_oss` is needed `[card]`. Sampling: `temperature=1.1`, `top_p=0.95` `[card]`.

**OLMo-3.1-32B (AI2, dense 32B, Apache, fully open data, 2026).** The Olmo 3
launch drew about 390 points and 125 comments `[HN]`; Olmo 3.1 is the follow-up.

- Good at: full openness and research. The whole point is open data and recipes;
  Simon Willison covered "Olmo 3 is a fully open LLM" `[HN]`. Ai2 calls 3 "a new
  SOTA open LLM (7B and 32B)" (self-reported) `[HN]`.
- Weak at: tool calling and general usefulness as an agent. The mid-band survey
  marks its tool-calling "weak"; it is "a research or reasoning model, not an
  agent model" `[survey]`.
- Compared to: no strong local user reviews were found. Use it for openness and
  research, not for agentic work.

Sources: HN "Gemma 4 12B" thread (Jun 2026); HN "Gemma4-31B via LLM" and
"structured output benchmark" threads; HN "GLM-4.7-Flash" thread (Jan 2026); HN
"Granite 4.2" and "Granite 4.2-8b" threads; HN "Seed-OSS-36B is ridiculously
good" title and Seed-OSS HN thread; HN "Olmo 3" thread (Nov 2025);
[card] Seed-OSS HF card; [mid-band-survey.research.md](../mid-band-survey.research.md).

## 9. MiniCPM-V-4.7 (OpenBMB, vision, 35B-A3B and 1B, 2026-10) and Ternary-Bonsai-2-27B (Prism ML, ternary, 2026-09)

**MiniCPM-V-4.7 35B-A3B.** A fresh vision MoE. The card is detailed; independent
local opinion is still thin.

- Good at: on-device multimodal. The card claims the "first open-source MoE model
  to run smoothly on-device without compromising performance", at 13+ tokens/s on
  3 GB of memory on an iPhone 17 Pro Max, and a better score in less time than
  Qwen3.6-35B-A3B in Instruct mode (self-reported) `[card]`. It keeps the family
  strengths: single image, multi-image, and video, with 4x/16x visual token
  compression `[card]`.
- Weak at: independent runs are scarce. The 8B MiniCPM-V family has a mixed
  reputation for honesty: in the receipt test an older MiniCPM-V 8B "fabricated"
  the whole document while Qwen3-VL-8B read it correctly `[HN]`. That is the
  earlier version, but it is the strongest independent signal found. On a
  Sanborn-map task, "I tried Qwen 3.5, Gemma 4, Minicpm-v4.5 but those did not
  perform well on this task" `[HN]`.
- Compared to: the card positions 4.7 directly against Qwen3.6-35B-A3B on the
  performance-efficiency frontier `[card]`.
- Runtime: GGUF, BNB, AWQ, GPTQ, and FP8 variants exist; llama.cpp is supported;
  a `downsample_mode` parameter must be passed to both the processor and
  `generate` `[card]`.

**Ternary-Bonsai-2-27B.** A very popular 2-bit (ternary) quantization of
Qwen3.8-27B. About 3.0M downloads `[card]`. The "Bonsai 2 27B" news drew a
sizable HN thread `[HN]`.

- Good at: shrinking a 27B to about 6 GB with little quality loss. The card
  claims 98.2% of FP16 intelligence retained at 5.95 GB, ~47 tok/s on an M5 Max,
  and ~130 tok/s on an RTX 5090 (self-reported) `[card]`.
- Weak at: the vendor benchmark is doubted, and the approach is fragile. One
  commenter: "What did they do with their benchmarks? I've never seen Qwen3.6 27B
  this close to Qwen3.8 27B in any aggregated summary ... Makes one questions the
  entire accuracy section" `[HN]`. Another reported "significant issues with the
  previous Bonsai 27 compared to the parent Qwen model" `[HN]`. The real weakness
  is runtime: it needs a fork.
- Compared to: at 5.95 GB it beats a conventional IQ2_XXS build by more than
  twelve points and comes within 0.4 points of UD-Q4_K_XL at a third of the size
  (self-reported) `[card]`.
- Runtime: this is the big gotcha. "Stock llama.cpp will not run these files. It
  rejects PQ2_0 and PTQ1_0 as unknown types, and it loads Q2_0 without any warning
  and produces garbage." A custom fork (`PrismML-Eng/llama.cpp`) with ternary
  hybrid-attention kernels is required `[card]`. `low` reasoning effort is not
  supported and behaves like `xhigh` `[card]`.

Sources: OpenBMB MiniCPM-V-4.7-35B-A3B HF card; HN receipt-fabrication post;
HN Sanborn-map Show HN comment; Prism ML Ternary-Bonsai-2-27B-gguf HF card; HN
"Bonsai 2 27B" thread (Sep 2026).

## 10. Qwen3-Embedding-4B and Qwen3-Reranker-4B (Qwen, retrieval, 2025-05/06)

The text retrieval pair. Coverage is practical, not benchmark-heavy; the release
threads are small `[HN]`.

**Good at**

- Real production RAG. The package-search MCP from Chroma "embeds the data with
  Qwen3-Embedding" across NPM, PyPI, Go, and Crates at distinct versions `[HN]`.
  A local agent project uses `qwen3-embedding:8b` at 4096 dimensions in an HNSW
  index `[HN]`. The 0.6B variant runs "locally on a MacBook" `[HN]`.
- Reranking quality. An experienced RAG engineer: "The big LLM-based rerankers
  (e.g. Qwen3-reranker) are what you always wanted your cross-encoder to be, and
  I highly recommend giving them a try. Unfortunately they're also quite
  computationally expensive" `[HN]`.
- The 0.6B pair is a common cheap search aid in small apps `[HN]`.

**Weak at**

- Cost and latency at the larger sizes. The 4B reranker is "quite computationally
  expensive" relative to classical cross-encoders `[HN]`.
- Little independent ranking data. Most comment is "it works", not measured
  scores. The MMTEB/MTEB leaderboard claims were not independently reproduced in
  the sources found.
- For a pure local endpoint, the fleet already has these; the survey calls the
  text pair "the best simple retrieval choice" and notes it is already in the
  prior survey `[survey]`.

**Compared to**

- One builder moved off `qwen3-embedding-8b` to a same-family but higher-throughput
  model "to stay within a similar budget while having higher throughput", so
  throughput can matter more than the last point of quality `[HN]`.
- Nothing found beats it decisively at this size on retrieval; it is the default
  open choice in the cited projects `[HN]`.

**Runtime notes**

- Text pair arch is `qwen3`; official GGUFs exist (Embedding-4B Q4_K_M 2.50 GB;
  Reranker-4B via community `Voodisss` GGUF) `[survey]`.
- The reranker has a scoring head; use the reranker GGUF, not the plain causal
  build `[survey]`.
- Vision variants (Qwen3-VL-Embedding/Reranker) also run under `qwen3vl` `[survey]`.

Sources: HN "Package Search MCP" Show HN; HN "LocalClaw graph memory" post; HN
"Production RAG: 5M+ documents" comment; HN "A Re-Ranker as a Decision Model"
comment; [qwen-specialized-survey.research.md](../qwen-specialized-survey.research.md).

## Coverage honesty

- **Rich opinion:** Qwen3.6-27B and Qwen3.6-35B-A3B, Gemma 4 12B, GLM-4.7-Flash,
  Ternary-Bonsai-2-27B, QwQ-32B, Qwen3-Coder-30B.
- **Moderate:** Qwen3-VL (8B and 30B), Qwen3-Omni, North-Mini-Code, Qwen3
  retrieval pair, MiniCPM-V (mostly the earlier 4.5/8B, not 4.7).
- **Thin:** Granite-4.2-30B, Seed-OSS-36B, OLMo-3.1-32B, Qwen3.5-35B-A3B (only
  as "worse than the dense sibling"), and Tiel-Coder (community fine-tune, no
  vendor card).
- Reddit article text was not reachable in this session, so Reddit views appear
  here only where an HN item reproduced the thread title or a review quoted it.

## See also

- [opinions-batch-a.research.md](opinions-batch-a.research.md) — the batch A
  opinion file.
- [qwen-specialized-survey.research.md](../qwen-specialized-survey.research.md) —
  the Qwen specialized desk survey.
- [mid-band-survey.research.md](../mid-band-survey.research.md) — the 10-40B desk
  survey.
- [definition.md](../definition.md) — this task.
