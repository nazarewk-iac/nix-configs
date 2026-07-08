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

### Improve the fork validation logic

1. verify every commit in the list of changes independently in pre-push
2. make the pre-commit (and therefore the `prek run`) verify that commits on top of upstream, but without a fork do not contain fork-specific changes

### Fix modules/slots/ usage & implementation for devenv

I can see that modules/slots don't actually set `config.devenv` options and instantiate that, but instead import directly which is plain wrong.

1. move over all `config =` into `config.devenv =` within modules/slots
2. register it properly as flake's devenvModules.default

call out any issues you encounter.

### Update the modules architecture for slots/ considerations

Some module architecture only makes sense for modules/universal, but not module/slots/, let's call those out
