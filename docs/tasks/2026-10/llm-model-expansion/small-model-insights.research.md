---
type: Research
description: Practical, sourced insights from Hacker News, r/LocalLLaMA and blogs about choosing and using small, local, dense and MoE models on a small CPU-first fleet.
task: definition.md
authored_by: agent
timestamp: 2026-10-21T17:34:10+02:00
---

# Small-model insights for a local fleet

This file collects practical guidance for a small local fleet. The target box is a
128 GB CPU-first machine with one 8 GB GPU. Models range from 0.5B to 180B, dense
and MoE. The file answers ten questions. Each answer gives short, actionable
points and a source.

Most sources are primary discussions with real user reports: Hacker News (HN)
threads, r/LocalLLaMA threads, and blog posts. Vendor claims are marked. Where
the community disagrees, or where the evidence is thin, the point says so.

Evidence labels:

- `[HN]` Hacker News thread or comment.
- `[R]` Reddit thread.
- `[B]` Blog or forum post.
- `[thin]` Few sources, or practitioner consensus only.
- `[disagree]` The community does not agree.

## 1. Prompting smaller models

- **Give explicit, tight instructions.** A 1-4B model needs one clear task, the
  exact output shape, and no open choices. Remove ambiguity. A 27-30B model
  tolerates more, but still less than a frontier model. `[B]`
  [alexellis.io](https://blog.alexellis.io/local-ai-is-not-opus/),
  `[HN]` [48580209](https://news.ycombinator.com/item?id=48580209)
- **Scope the task. Do not give an open-ended goal.** A local 27B model read
  every file on a machine and then hallucinated file names and tool calls. The
  same model produced a good report when the user narrowed the task. `[B]`
  [alexellis.io](https://blog.alexellis.io/local-ai-is-not-opus/)
- **The prompting technique differs by model family.** One user compares the
  model to an instrument: Claude accepts under-specification, GPT needs
  precision. A local model needs the most precision. `[HN]`
  [48580209](https://news.ycombinator.com/item?id=48580209)
- **Put standing rules in a system prompt or `AGENTS.md`.** With detailed
  `AGENTS.md` instructions, a local model added new CLIs faster than human
  contributors and tested its own work. `[B]`
  [alexellis.io](https://blog.alexellis.io/local-ai-is-not-opus/)
- **Expect confident wrong output on open tasks.** A small model does the wrong
  thing with high confidence when the task has no tight bound. `[HN]`
  [48580209](https://news.ycombinator.com/item?id=48580209), `[R]`
  [Prompt Engineering for 7b LLMs](https://www.reddit.com/r/LocalLLaMA/comments/18e929k/prompt_engineering_for_7b_llms/)

## 2. Context hygiene

- **Performance falls as the input grows, even for simple tasks.** The Chroma
  "Context Rot" report tests 18 models of all sizes, including Qwen3, and
  isolates input length as the only variable. `[B]`
  [research.trychroma.com/context-rot](https://research.trychroma.com/context-rot),
  `[HN]` [44564248](https://news.ycombinator.com/item?id=44564248)
- **Distractors hurt more than unrelated text.** A distractor is topically
  related but wrong. One distractor lowers accuracy. Four distractors lower it
  more. The effect grows with input length. `[B]`
  [research.trychroma.com/context-rot](https://research.trychroma.com/context-rot)
- **Keep context focused and compact.** A focused input (about 300 tokens) beats
  the full input (about 113k tokens) across all model families. The full input
  forces the model to retrieve and to reason at the same time. `[B]`
  [research.trychroma.com/context-rot](https://research.trychroma.com/context-rot)
- **Summarize first, then retrieve.** Users report better results when the model
  summarizes documents first, then reads full text only on request. Clearing the
  context and re-reading the relevant files beats a compacted history. `[HN]`
  [44564248](https://news.ycombinator.com/item?id=44564248)
- **Check the runtime context default.** Ollama defaults to a 4K context below
  24 GB of VRAM. A small context makes a thinking model forget the question in
  the middle of the answer. `[HN]`
  [49402232](https://news.ycombinator.com/item?id=49402232)
- **A counterintuitive result.** A shuffled haystack performs better than a
  coherent one. Structural coherence lowers performance. Treat this as an open
  finding. `[B]`
  [research.trychroma.com/context-rot](https://research.trychroma.com/context-rot)
- `[disagree]` Chroma sells a vector database, so its report has a commercial
  interest in retrieval. The direction of the effect is not in dispute. The size
  is model-dependent.

## 3. MoE versus dense in practice

- **MoE decodes fast because few parameters are active.** Memory holds all
  experts. Speed follows the active parameters. A 35B-A3B model reads about 3B
  parameters per token. `[HN]`
  [49142301](https://news.ycombinator.com/item?id=49142301), `[B]`
  [Running a 35B LLM at 128K on used hardware](https://medium.com/ai-advances/running-a-35b-llm-at-128k-context-full-speed-on-870-of-used-hardware-no-cloud-required-c4f7629810b8)
- **MoE speed does not guarantee quality.** One operator prefers a dense 27B for
  quality. The 35-A3B is popular because it "looks faster on MacBooks" with only
  3B active parameters. He trades speed for quality. `[B]`
  [alexellis.io](https://blog.alexellis.io/local-ai-is-not-opus/)
- **MoE may be more sensitive to aggressive quantization.** A low quant makes
  the router logits noisy. The router then picks the wrong experts. Standard
  perplexity tests do not show this "routing drift". `[HN]`
  [49408266](https://news.ycombinator.com/item?id=49408266) `[thin]` this is one
  commenter's claim. The same thread's author reports the opposite from his own
  tests: MoEs held up better than dense models under quant.
- **MoE helps long context in practice.** Users report that MoE models stay
  usable past 128K context where a dense model degrades earlier. `[HN]`
  [49402232](https://news.ycombinator.com/item?id=49402232)
- `[disagree]` Reports differ on whether a MoE beats a dense model of the same
  size on quality. The result depends on the task and the quant.

## 4. Quantization

- **Q4_K_M is the common default.** Use Q5 or Q6 when memory allows. Use Q8 for
  near-lossless quality. Use IQ quants when memory is very tight. `[R]`
  [What Quantization level do you use?](https://www.reddit.com/r/LocalLLaMA/comments/18q5uej/what_quantization_level_do_you_use/),
  `[R]`
  [Overview of GGUF quantization methods](https://www.reddit.com/r/LocalLLaMA/comments/1ba55rj/overview_of_gguf_quantization_methods/)
- **The quality cliff is below Q4.** Above Q4, most quants are statistically
  indistinguishable in head-to-head tests. Below Q4, quality drops. `[HN]`
  [49408266](https://news.ycombinator.com/item?id=49408266), `[B]`
  [which-quant-beats-how-many-bits](https://rakuensoftware.com/blog/which-quant-beats-how-many-bits)
- **Q8 is close to no loss.** One report gives the BF16-to-Q8_0 loss as about
  0.1-0.3 percent, near zero. `[HN]`
  [47863217](https://news.ycombinator.com/item?id=47863217)
- **Weight quant is safer than KV-cache quant.** A weight quant at Q4 or Q8
  often holds. An int4 KV cache caused a reproducible tool-call failure in a
  long-context test; int8 KV recovered. `[B]`
  [level1techs](https://forum.level1techs.com/t/why-your-local-llm-feels-dumber-than-it-is/253917)
- **A lower quant is fine for chat, harmful for exact work.** Chat tolerates a
  low quant. Tool calls, exact literals, code, and long context do not. `[B]`
  [level1techs quant guide](https://forum.level1techs.com/t/qwen-3-8-quant-selection-guide-for-rtx-5090/254095),
  `[B]` [alexellis.io](https://blog.alexellis.io/local-ai-is-not-opus/)
- **MoE and draft models can be more quant-sensitive.** A low-quant draft model
  caps the speculative-decoding acceptance rate. `[HN]`
  [49408266](https://news.ycombinator.com/item?id=49408266)
- **The quant name is not enough.** Two files with the same label (for example
  NVFP4) can come from different recipes and give different quality. Test the
  exact file. `[B]`
  [level1techs quant guide](https://forum.level1techs.com/t/qwen-3-8-quant-selection-guide-for-rtx-5090/254095)

## 5. Reasoning versus non-reasoning models

- **Use a thinking model for hard, multi-step tasks.** Use a fast non-thinking
  model for extraction, classification, and simple transforms. `[HN]`
  [44112326](https://news.ycombinator.com/item?id=44112326)
- **Reasoning costs tokens and time.** AutoThink classifies a query by
  complexity and gives simple queries 20-40 percent of the tokens and complex
  queries 70-90 percent. It uses fewer tokens on average. `[HN]`
  [44112326](https://news.ycombinator.com/item?id=44112326)
- **Reasoning can hurt extraction.** Extra reasoning tokens add latency and
  noise to a task that needs one short, exact answer. Many models recommend
  thinking off for structured output. `[thin]` practitioner consensus; few
  controlled tests.
- **A very low temperature makes a thinking model loop.** The model cannot leave
  its think output. Use the temperature from the model card. `[B]`
  [level1techs](https://forum.level1techs.com/t/why-your-local-llm-feels-dumber-than-it-is/253917)
- **Thinking mode helps long context.** In the Chroma tests, thinking mode
  raised scores on both focused and full inputs for models that support it. `[B]`
  [research.trychroma.com/context-rot](https://research.trychroma.com/context-rot)

## 6. Tool calling and agent use

- **Tool calling needs a capable model.** Small models fail in a common way:
  they write a bare tool call as plain text instead of a real tool call. `[HN]`
  [48192383](https://news.ycombinator.com/item?id=48192383)
- **A guardrail layer fixes most failures.** Forge takes an 8B model from about
  53 percent to about 99 percent on multi-step agentic tasks without changing
  the model. It injects a message such as "you must call a tool" and the model
  retries. `[HN]` [48192383](https://news.ycombinator.com/item?id=48192383)
- **Tool calling is retrieval and assembly, not reasoning.** A 26M distilled
  model can do tool calls well for a narrow tool set. Large models are overkill
  for this step. `[HN]`
  [48111896](https://news.ycombinator.com/item?id=48111896)
- **A wrong chat template breaks tool calls silently.** Some GGUF files omit the
  chat template. The runtime falls back to a default template. The model still
  talks, but it gets "noticeably dumber". Check the template tokens before you
  blame the model. `[HN]`
  [49402232](https://news.ycombinator.com/item?id=49402232)
- **Add schema validation and execution-side checks.** For tool calls that can
  change infrastructure, validate the JSON and check on the execution side. `[B]`
  [level1techs quant guide](https://forum.level1techs.com/t/qwen-3-8-quant-selection-guide-for-rtx-5090/254095)
- **Small models need retries and step limits.** Some models get stuck. Set a
  maximum iteration count and decide what to do when it is reached. `[HN]`
  [48192383](https://news.ycombinator.com/item?id=48192383)

## 7. Speculative decoding and draft models

- **It helps most when decode is memory-bandwidth bound.** On a CPU-first box,
  or a low-VRAM GPU, speculative decoding gives a clear gain. One user says it
  "made low memory bandwidth model usage so much nicer". `[HN]`
  [49366792](https://news.ycombinator.com/item?id=49366792)
- **It is lossless when implemented correctly.** The output must match the
  target model distribution. A regression against the target model is a bug.
  `[HN]` [49366792](https://news.ycombinator.com/item?id=49366792)
- **MTP gives a large real gain.** One operator reports a 93 percent acceptance
  rate with an MTP draft model and a speed increase from 67 to 130-200 tokens
  per second. `[B]`
  [alexellis.io](https://blog.alexellis.io/local-ai-is-not-opus/)
- **The draft model must be much cheaper than the target.** On the CPU the draft
  also costs compute. A low-quant draft is fast but caps the acceptance rate. `[HN]`
  [49408266](https://news.ycombinator.com/item?id=49408266)
- **It needs spare compute.** If you already batch many users, the gain drops.
  Batching already amortizes the weight load. `[HN]`
  [49596054](https://news.ycombinator.com/item?id=49596054)

## 8. Temperature and sampling

- **Follow the model card.** The card gives the sampling settings and the chat
  template. UIs ship their own defaults. Benchmarks often run greedy. Wrong
  settings make the model look worse. `[HN]`
  [49402232](https://news.ycombinator.com/item?id=49402232), `[B]`
  [level1techs](https://forum.level1techs.com/t/why-your-local-llm-feels-dumber-than-it-is/253917)
- **A too-low temperature causes looping.** This is common with thinking
  models. `[B]`
  [level1techs](https://forum.level1techs.com/t/why-your-local-llm-feels-dumber-than-it-is/253917)
- **Example settings.** For Qwen3.6-27B the operator uses temp 0.6, top-p 0.95,
  top-k 20, min-p 0.0, presence-penalty 1.1. `[B]`
  [alexellis.io](https://blog.alexellis.io/local-ai-is-not-opus/)
- **Fine-tunes can need different settings.** One fine-tune works best with
  thinking off and a hot temperature of 0.85-1.0. `[B]`
  [alexellis.io](https://blog.alexellis.io/local-ai-is-not-opus/)
- `[thin]` There is no single rule. Test the settings on your own workload.

## 9. Batching and concurrency

- **Parallel slots divide the context.** `--parallel 2` halves the context for
  each slot. To keep the full context, run two server instances instead. `[B]`
  [alexellis.io](https://blog.alexellis.io/local-ai-is-not-opus/)
- **Unrelated concurrent requests destroy the prefix cache.** Two agents on one
  server with different contexts invalidate each other's cached prefix. The
  server then re-processes the full prompt each time. `[B]`
  [alexellis.io](https://blog.alexellis.io/local-ai-is-not-opus/)
- **Batching amortizes the weight load.** This is why batching helps speculative
  decoding verification. `[HN]`
  [49596054](https://news.ycombinator.com/item?id=49596054)
- **Check vendor throughput claims.** One large number came from 200 users
  sending the same prompt. That case gives maximum expert parallelism and is not
  a normal single-user rate. `[HN]`
  [49596054](https://news.ycombinator.com/item?id=49596054)
- **On a CPU-first box, aggregate throughput rises but latency rises too.**
  Concurrency shares one memory bandwidth budget.

## 10. When to reach for a bigger model

- **Use the local model for bounded, repetitive, private work.** Use the big
  model for long-horizon, open, or high-stakes work. `[HN]`
  [48580209](https://news.ycombinator.com/item?id=48580209), `[B]`
  [alexellis.io](https://blog.alexellis.io/local-ai-is-not-opus/)
- **A small model on a hard task is unreliable.** One user can ask the same
  question ten times and get one good answer. The big model is slower but
  reliable. `[HN]`
  [39019532](https://news.ycombinator.com/item?id=39019532)
- **Route by confidence.** Cactus Hybrid gives each answer a confidence score
  and routes only 15-35 percent of queries to a cloud model. The small model
  then matches the cloud model on most benchmarks. `[HN]`
  [49010782](https://news.ycombinator.com/item?id=49010782)
- **A local model can read and explain code even when it cannot write it.** This
  is a strong use case. `[B]`
  [alexellis.io](https://blog.alexellis.io/local-ai-is-not-opus/)
- **Do not hand long, unsupervised agentic work to a local model.** That is
  where it loops and goes off course. `[B]`
  [alexellis.io](https://blog.alexellis.io/local-ai-is-not-opus/)
- **Match the model to the task.** A model is tuned for certain tasks. Ask
  "good for what?" before you compare two models. `[HN]`
  [48296794](https://news.ycombinator.com/item?id=48296794)

## Source index

Hacker News threads and comments:

- [48580209](https://news.ycombinator.com/item?id=48580209) Local Qwen is not a
  worse Opus, it is a different tool.
- [49402232](https://news.ycombinator.com/item?id=49402232) Why your local LLM
  feels dumber than it is.
- [44564248](https://news.ycombinator.com/item?id=44564248) Context Rot.
- [44112326](https://news.ycombinator.com/item?id=44112326) AutoThink adaptive
  reasoning.
- [48192383](https://news.ycombinator.com/item?id=48192383) Forge guardrails for
  tool calling.
- [48111896](https://news.ycombinator.com/item?id=48111896) Needle distilled tool
  calling.
- [49010782](https://news.ycombinator.com/item?id=49010782) Cactus Hybrid
  confidence routing.
- [49596054](https://news.ycombinator.com/item?id=49596054) Speculative decoding
  on AMD GPUs.
- [49366792](https://news.ycombinator.com/item?id=49366792) DFlash 2 parallel
  drafting.
- [49408266](https://news.ycombinator.com/item?id=49408266) Do LLM quants impact
  as much as we think?
- [47863217](https://news.ycombinator.com/item?id=47863217) Qwen3.6-27B dense
  model.
- [49142301](https://news.ycombinator.com/item?id=49142301) 35B LLM at 128K on
  used hardware.
- [39019532](https://news.ycombinator.com/item?id=39019532) Stable Code 3B.
- [48296794](https://news.ycombinator.com/item?id=48296794) Model tuning and
  task fit.

Reddit (r/LocalLLaMA):

- [Prompt Engineering for 7b LLMs](https://www.reddit.com/r/LocalLLaMA/comments/18e929k/prompt_engineering_for_7b_llms/)
- [What Quantization level do you use?](https://www.reddit.com/r/LocalLLaMA/comments/18q5uej/what_quantization_level_do_you_use/)
- [Overview of GGUF quantization methods](https://www.reddit.com/r/LocalLLaMA/comments/1ba55rj/overview_of_gguf_quantization_methods/)
- [Quantization: How Much Quality is Lost?](https://www.reddit.com/r/LocalLLaMA/comments/153lfc2/quantization_how_much_quality_is_lost/)
- [Small and fast function calling models](https://www.reddit.com/r/LocalLLaMA/comments/1d5k0a7/small_and_fast_function_calling_models/)
- [What can we achieve with small models](https://www.reddit.com/r/LocalLLaMA/comments/15ayz6l/what_can_we_achieve_with_small_models/)
- [What are the capabilities of LLMs smaller than 7B](https://www.reddit.com/r/LocalLLaMA/comments/1dbg6uy/what_are_the_capabilities_of_llms_smaller_than_7b/)
- [PSA: use llama.cpp/transformers/vLLM/SGLang to test new models](https://www.reddit.com/r/LocalLLaMA/comments/1rjb7yk/)

Blogs and forum posts:

- [alexellis.io — Local Qwen is not a worse Opus](https://blog.alexellis.io/local-ai-is-not-opus/)
- [Chroma — Context Rot](https://research.trychroma.com/context-rot)
- [Level1Techs — Why your local LLM feels dumber than it is](https://forum.level1techs.com/t/why-your-local-llm-feels-dumber-than-it-is/253917)
- [Level1Techs — Qwen 3.8 quant selection guide](https://forum.level1techs.com/t/qwen-3-8-quant-selection-guide-for-rtx-5090/254095)
- [Rakuen Software — Which quant beats how many bits](https://rakuensoftware.com/blog/which-quant-beats-how-many-bits)
- [Sleeping Robots — Friends do not let friends use Ollama](https://sleepingrobots.com/dreams/stop-using-ollama/)

## Notes on evidence quality

- The Reddit threads are cited by title and URL. Reddit blocked direct reads from
  the build network. The points from Reddit are titles and community consensus,
  not quoted text.
- The Chroma report is a controlled study. It has a commercial interest. Use its
  direction, not its exact numbers.
- The Level1Techs series is a strong primary measurement, but on NVIDIA GPUs.
  The CPU-first box will see the same hazards (KV quant, chat template,
  sampling) with different numbers.
- The reasoning-hurts-extraction point is practitioner consensus only. No strong
  controlled source was found.

## See also

- [definition.md](definition.md) — this task.
- [mid-band-survey.research.md](mid-band-survey.research.md) — the model survey
  for the same fleet.
- [model-selection-guide.md](model-selection-guide.md) — the selection guide.
