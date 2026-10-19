# llm-bench harness

`llm-bench.sh` measures one served model on the brys llama-swap server. It sends
requests, reads the server timings, the resident child memory and the GPU VRAM,
and it prints one row per (model, step, phase). It never changes server state.
It leaves no background process.

## Requirements

- Network access to the brys compat proxy.
- A bearer key. The harness reads `--key-file` (default `/tmp/opencode/brys.key`).
  When that file is absent, it reads the key on brys over ssh.
- `curl`, `jq`, `python3`.
- `ssh` access to brys for the `mem`, `faults` and `vram` steps.

## Usage

```
llm-bench.sh --model ID [flags]
```

| Flag | Meaning | Default |
|---|---|---|
| `--model ID` | The model id from `GET /v1/models`. Required. | — |
| `--base-url URL` | The OpenAI-compatible base. | the brys compat proxy |
| `--key-file PATH` | A file with the bearer key. | `/tmp/opencode/brys.key` |
| `--steps LIST` | A comma-separated step list, or `all`. | all steps |
| `--max-tokens N` | The decode cap. | 128 |
| `--prompt-tokens N` | The prefill target token count. | 2048 |
| `--ssh-host HOST` | The ssh host for `mem`, `faults` and `vram`. An empty value skips these steps. | `kdn-brys` |
| `--json` | Print one JSON object per row, not TSV. | TSV |
| `--timeout SECONDS` | The per-request curl timeout. | 600 |
| `--help` | Print the help. | — |

## Steps

| Step | Phase | Keys | Meaning |
|---|---|---|---|
| `cold-start` | cold | `ttft_s`, `ttft_ms` | Time to the first streamed token, model not resident. |
| `warm-start` | warm | `ttft_s`, `ttft_ms` | The same, after a warm-up request. |
| `decode` | run | `predicted_tok_s`, `predicted_n` | Decode speed. |
| `prefill` | run | `prompt_tok_s`, `prompt_n`, `cache_n` | Prefill speed. |
| `ttft` | stream, nonstream | `ttft_s`, `ttft_ms` | TTFT from a streaming and a non-streaming call. |
| `reuse` | first, second | `cache_n`, `prompt_tok_s` | Prompt-cache reuse across two calls. |
| `mem` | run | `pid`, `vmrss_kb`, `rssanon_kb`, `rssfile_kb` | The resident child memory, from `/proc/<pid>/status`. |
| `faults` | idle | `major_faults_s` | The child major-fault rate at idle. |
| `vram` | run | `vram_used_MiB`, `vram_total_MiB` | The W6600 GPU VRAM, from sysfs. |

The `mem`, `faults` and `vram` steps need ssh. The default step list drops them
when `--ssh-host` is empty.

## Output

TSV: one header, then one row per (model, step, phase):

```
ts  host  model  step  phase  key  value  box_note
```

JSON: one object per row, with the same fields. The `box_note` holds the host
load at the start of the run.

## Examples

```
llm-bench.sh --model tmax-2b --steps decode,prefill
llm-bench.sh --model tmax-2b --prompt-tokens 4096 --json
llm-bench.sh --model tmax-2b --steps vram
llm-bench.sh --model frontier --steps cold-start,decode,prefill
```

## Caveats

- The `vram` step reads the card-wide sysfs counters
  `/sys/class/drm/card1/device/mem_info_vram_used` and `..._total`. There is no
  `amd-smi` or `rocm-smi` on brys. The box serves one model at a time, so the
  counters report the serving child. A CPU-only model leaves them near zero.
- The `mem` and `faults` steps resolve the serving child through a probe
  request. The probe loads the model when it is not resident. The `vram` step
  reads sysfs directly and does not load a model.
- A cold-start number is only truly cold when the model was evicted first. The
  box holds one frontier model at a time.
- A row records the host load, so a reader can judge the run.
