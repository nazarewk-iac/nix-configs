---
name: current-date
description: Use when you need the current date or time. The system prompt does not inject the date, so run `date` to obtain it.
---

The system prompt deliberately omits the current date. This keeps its prefix
byte-stable, so a local model can reuse its KV cache across midnight instead of
re-prefilling the whole conversation.

When you need the current date or time, run one of:

```sh
date -Iseconds      # 2026-10-12T07:10:00+02:00
date +%Y-%m-%d      # 2026-10-12
date                # Sun Oct 12 07:10:00 CEST 2026
```
