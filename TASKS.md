# Tasks

## Backlog

### Improve mcp-gateway tool prompts

**Context:** After watching live JSON-RPC traffic through mcpsnoop, the current gateway prompts
are bare — essentially "Invoke Tool → json blob" with no natural-language context about what
each tool does or when to use it.

**Goal:** Rewrite the gateway's tool descriptions and/or system prompt so the LLM gets
meaningful guidance: what each backend is for, when to prefer it over another, and how to
interpret results.

**Reference:** https://assistant.kagi.com/share/f456cad0-8678-4199-bf33-87d9a9d60d52
— session capturing observations on prompt quality and ideas for improvement.

**Starting point:** `.devenv/mcp-gateway.yaml` backend `description` fields and any
gateway-level system prompt configuration in `modules/slots/mcp/default.nix`.
