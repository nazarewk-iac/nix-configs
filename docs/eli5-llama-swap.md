# llama-swap explained in plain words

This page explains how **llama-swap** works.
It is written for a person who has never run a local LLM before.
I use short sentences and plain words.
When I must use a technical word, I explain it in the Glossary at the end.

Your machine runs NixOS.
It has a Ryzen 3950X CPU and 128 GB of RAM.
It has no usable GPU.
Everything runs on the CPU and in RAM.

On this machine, `kdn.llm.local.*` sets up llama-swap.
llama-swap serves three local models. Each model is a GGUF file on disk.
These are the three models, with their approximate sizes:

- deepseek-v4-flash, about 103 GB
- qwen3-next-80b, about 48 GB
- qwen3-30b-a3b, about 18 GB

The files live in `/var/lib/kdn/llms/models`.
llama-swap listens on your machine at `localhost:8080`.
It gives one single OpenAI-compatible API. This API is the same shape as the API offered by OpenAI's online service, but it runs on your own machine.

Below you find the answers to seven common questions.

---

## 1. What is llama-swap, in one sentence?

llama-swap is a small program that lets you hold several different LLMs on one machine and switch between them on demand, using one single API address.

The problem it solves is simple. Running an LLM on CPU uses a lot of RAM. You cannot keep three big models in RAM at the same time. llama-swap loads one model when you ask for it, and loads the next one only when you ask for it. You never manage the models yourself. You just talk to one API.

## 2. Do all the models run at the same time, or one at a time?

In the basic setup on this machine, **one model runs at a time**.

Remember the sizes. DeepSeek is about 103 GB. qwen3-next is about 48 GB. The small model is about 18 GB. Your machine has 128 GB of RAM. It cannot hold all three models plus the operating system at once. So llama-swap keeps only the model you asked for in RAM. The other models stay on the disk, idle.

llama-swap can run several models at once if it is set up that way, but this machine does not use that option. Here, one model is loaded at a time.

## 3. When I send a request, what happens step by step?

This is the normal flow, step by step:

1. Your client (the app you use to chat) sends a request to `localhost:8080`.
2. The request body has a field called `model`. It holds the name of the model you want.
3. llama-swap reads that name and finds the matching model in its configuration.
4. If that model is not loaded yet, llama-swap starts an underlying program called `llama-server` and points it at the right GGUF file.
5. `llama-server` reads the GGUF file from the disk into RAM. This is the "load" step.
6. Once the model is in RAM, `llama-server` is ready.
7. llama-swap sends your request to `llama-server`.
8. `llama-server` answers your request, in tokens.
9. llama-swap passes the answer back to your client at the same address.

From your point of view, the address never changes. You always talk to `localhost:8080`. Only the `model` field in the request changes. llama-swap does all the work behind the scenes.

## 4. When I switch models, what happens to the old one?

The old model is **unloaded**.

The unload step frees the old model's memory so the new one can use it. One model must leave RAM before another takes its place. That is why your machine can handle models bigger than half of its RAM, one at a time.

The order of events in a switch is:

1. You send a request for a new model.
2. llama-swap sees the new model name differs from the one currently running.
3. llama-swap stops the current `llama-server` for the old model.
4. The old model's memory is freed back to the system.
5. llama-swap starts a new `llama-server` for the new model.
6. The new model loads from disk into RAM.
7. Your request is then answered.

The load of the old model is not lost in a permanent way. Its GGUF file stays on the disk, untouched. You can load the old model again later by asking for it. Loading it again takes time, because the file must be read from disk again. The GGUF file is like a saved document on your desk. It stays on the shelf. Removing it from the desk frees the desk, but the document is not gone.

## 5. How long does a switch take?

The switch takes as long as the new model takes to load. The load time depends mostly on three things:

- the size of the model file
- the speed of your disk, which must read the file
- the memory bandwidth of your RAM, which must receive the file

Your Ryzen 3950X uses DDR4 memory. DDR4 is slower than newer DDR5. Reading a big file into RAM is limited by how fast the disk can read it and how fast the RAM can accept it. The model also does some extra work during load, such as parsing the file. So the real time is a bit longer than the file size alone would suggest.

Here are honest, realistic ranges for this machine:

| Model | File size | Rough load time |
|---|---|---|
| deepseek-v4-flash | ~103 GB | several minutes, possibly up to 10+ minutes on slower disk |
| qwen3-next-80b | ~48 GB | a few minutes |
| qwen3-30b-a3b | ~18 GB | well under a minute |

These numbers are estimates. They are not exact. The exact time depends on your disk speed and your exact memory speed.

The switch itself (stopping the old model and starting the new one) is fast, a few seconds. The loading of the new model is the slow part. So a switch to the small model feels quick. A switch to the big DeepSeek model feels slow.

## 6. What do I need to do to switch models?

Almost nothing. You do not manage models. You never load or unload them by hand.

You just choose which model you talk to. You do this by changing the `model` field in your request. llama-swap reads that field and does the load and unload for you.

A client that follows the OpenAI API is a program that sends HTTP requests to an address. You can test this by hand with a small command. Here are two example calls. Only the `model` field differs. The base address `localhost:8080` is the same.

First call: ask the big DeepSeek model.

```
POST /v1/chat/completions HTTP/1.1
Host: localhost:8080
Content-Type: application/json

{
  "model": "deepseek-v4-flash",
  "messages": [{"role": "user", "content": "Hello, who are you?"}]
}
```

Second call: shortly after, ask the small model instead.

```
POST /v1/chat/completions HTTP/1.1
Host: localhost:8080
Content-Type: application/json

{
  "model": "qwen3-30b-a3b",
  "messages": [{"role": "user", "content": "Hello again, who are you now?"}]
}
```

The first call makes llama-swap load DeepSeek. That load can take minutes. The second call makes llama-swap unload DeepSeek and load the small model. That switch is much faster.

In a normal chat app you do not write these calls by hand. The app has a setting where you choose the model name. You pick `deepseek-v4-flash` or `qwen3-30b-a3b`, and the app sends the right request. You never think about load or unload. llama-swap handles it.

## 7. Glossary

- **GGUF** — A file format that stores the model. It is one single file with the model's knowledge and settings. The file name ends in `.gguf`. You download a GGUF file once, and the server reads it each time it loads the model.
- **llama-server** — The program from llama.cpp that actually runs the model. llama-swap starts a new llama-server for each model. llama-swap itself is only the dispatcher; llama-server does the real work.
- **llama.cpp** — The software project that provides llama-server and the code to run LLMs on normal computers, including CPU-only machines like yours.
- **OpenAI-compatible API** — A standard way for programs to talk to an LLM. The same request shape that OpenAI's online service uses. Because this standard is common, many chat apps can talk to a local server without special changes. You only change the address from the public cloud to `localhost:8080`.
- **Context window** — The amount of text, in tokens, that the model can "see" at one time when answering. It is the working memory of a single conversation.
- **Tokens** — Small pieces of text. A token is often a part of a word or a short word. The model reads your input as tokens and writes its answer as tokens. Roughly 100 tokens are about 75 English words. More precise "tokenizer" rules decide exactly how the text is cut into tokens.
- **Load** — The action of reading a model file from disk into RAM so it can run. Loading is slow, because the file is big and disk and RAM have speed limits.
- **Unload** — The action of stopping a model and freeing its RAM. Unloading is fast. The model file stays on disk and can be loaded again later.
- **Model swapping / hot-swap** — The automatic process of unloading the current model and loading the one you asked for. This is the core job of llama-swap.
