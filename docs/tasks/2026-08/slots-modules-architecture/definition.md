---
type: Task
description: Update the modules architecture docs for slots considerations — call out what applies to modules/universal but not to modules/slots.
status: in-progress
authored_by: agent
timestamp: 2026-08-29T00:00:00+02:00
---

# Update modules architecture for slots considerations

Some module architecture concepts only make sense for `modules/universal/`,
not for `modules/slots/`. Call these out so agents do not apply the wrong
patterns to slots.

## Done so far

- Created `modules/slots/README.md` — the main slots architecture reference
  (targets, plain-attrset vs target-function emission, the two-level trap,
  the standalone rule).
- Created `.agents/rules/slots-standalone.md` — the hard standalone rule
  (no `modules/universal/`/`modules/meta/` option reference or assignment
  inside slot target configs; cross-wiring only in consuming host configs).
- Linked both from `AGENTS.md`.

## Remaining

- Review `docs/module-architecture.md` and `module-architecture.md`
  (`.agents/rules/`) for statements that apply only to `modules/universal/`
  and add explicit "not applicable to slots" call-outs where a reader could
  misapply them to a slot module.
- The `TASKS.md` legacy entry should be removed once this task is fully
  resolved (its content now lives here).

## Next directions

Do the audit of `module-architecture.md` for universal-only claims once the
LLM standalone slot work is complete and verified.
