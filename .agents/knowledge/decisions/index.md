# Decisions
* [Never push](no-push.md) - The user reviews and pushes every change.
* [Path-scoped jj commands](path-scoped-jj.md) - Every path-taking jj command lists the files the session owns.
* [One writer per bundle](one-writer-per-bundle.md) - okf-agent-memory writes .agents/knowledge; kdn-okf only reads it.
* [Cache outside the bundle](cache-outside-bundle.md) - kdn-okf caches in the XDG cache, never inside the bundle.
* [Agent trailer profiles](trailer-profiles.md) - Agent commits carry Assisted-by, Generated-by, Session-Id, Harness and Model.
