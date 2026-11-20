// Package engine is the engine-neutral half of the runtime: one process owns one inference engine,
// and the parts that need to know *which* engine are behind this small interface.
//
// The boundary is deliberate and narrow. Everything expensive and risky — the lease registry, the
// drain, the proxy, the journal, the HTTP API — lives outside and never learns the engine's name.
// An adapter answers three questions and nothing else.
package engine

import "context"

// Command is a fully prepared child process: the adapter has already materialised whatever config
// the engine needs and decided the argument list.
type Command struct {
	Path string
	Args []string
	Env  []string
	// Port is the port this profile listens on; zero means the supervisor's EnginePort. A
	// deployment that serves two kinds of server gives each its own: a stopped server leaves
	// TIME_WAIT sockets on its port, and the next engine's plain bind() sees them as "already in
	// use" for a minute. Two servers that never share a socket never collide.
	Port int
	// PortFlag is the flag the engine takes its listen port on. The supervisor appends
	// `PortFlag <port>`; an engine that reads the port from its own config leaves this empty and
	// the supervisor appends nothing. Guessing was the bug: `--port` is llama-server's and
	// strata's flag, and `sd-server` calls it `--listen-port`.
	PortFlag string
}

// Adapter is what an inference engine has to provide. There are deliberately no lifecycle hooks
// beyond these: a health URL, a command to start a profile, and a command to stop whatever is left.
type Adapter interface {
	// Name is the value `--engine` accepts and the value the manager reports.
	Name() string
	// Profiles lists the operating points this adapter can prepare, in a stable order.
	Profiles() []string
	// Prepare materialises the profile and returns the command that serves it. It is called for a
	// real start and for a dry run; it must be cheap and side-effect free apart from writing the
	// engine's own config file.
	Prepare(profile string) (Command, error)
	// Stop terminates an engine this runtime did not spawn. The supervisor already kills its own
	// child with a process-group signal; this is the fallback for a leftover from another manager
	// instance or a manual unit.
	Stop(ctx context.Context) error
	// ReadyPath is the HTTP path that answers 200 once the profile serves. It takes the profile
	// because a deployment can serve two kinds of server: the frontier answers `/v1/models`, a
	// diffusion server answers its own API root.
	ReadyPath(profile string) string
}
