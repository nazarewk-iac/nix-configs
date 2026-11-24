// kdn-inference-helpers is the inference serving runtime: one engine per card, a profile manager,
// a per-entry proxy that never cuts a request a switch would interrupt, and a CLI.
//
// Subcommands:
//
//	manager  the control plane: /select, /status, /stats, /events, /lease, /release, /unload
//	proxy    the per-entry listener llama-swap spawns (lease per request, health during a drain)
//	select   ask the manager for a profile, then serve the proxy in this process
//	serve    materialise a profile and exec the engine (the unit fallback)
//	ctl      human CLI: up, down, status, stats, unload
//	status   what this host can serve, and what is serving right now
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"kdn-inference-helpers/internal/companion"
	"kdn-inference-helpers/internal/config"
	"kdn-inference-helpers/internal/control"
	"kdn-inference-helpers/internal/ctl"
	"kdn-inference-helpers/internal/engine"
	enginecmd "kdn-inference-helpers/internal/engine/command"
	"kdn-inference-helpers/internal/engine/router"
	"kdn-inference-helpers/internal/engine/strata"
	"kdn-inference-helpers/internal/journal"
	"kdn-inference-helpers/internal/policy"
	"kdn-inference-helpers/internal/proxy"
	"kdn-inference-helpers/internal/runtime"
	"kdn-inference-helpers/internal/swap"
)

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	var err error
	switch os.Args[1] {
	case "manager":
		err = runManager(ctx, os.Args[2:])
	case "proxy":
		err = runProxy(ctx, os.Args[2:])
	case "select":
		err = runSelect(ctx, os.Args[2:])
	case "serve":
		err = runServe(ctx, os.Args[2:])
	case "gate":
		err = runGate(ctx, os.Args[2:])
	case "admit":
		err = runAdmit(ctx, os.Args[2:])
	case "ctl":
		err = runCtl(ctx, os.Args[2:])
	case "status":
		err = runStatus(ctx, os.Args[2:])
	case "version":
		fmt.Println("kdn-inference-helpers 0.1.0")
	case "-h", "--help", "help":
		usage()
	default:
		fmt.Fprintf(os.Stderr, "unknown command %q\n", os.Args[1])
		usage()
	}
	if err != nil && err != context.Canceled {
		log.Fatalf("kdn-inference-helpers: %v", err)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, `usage: kdn-inference-helpers <manager|proxy|select|serve|status|ctl|version> [flags]

  manager  the profile manager and its HTTP API
  proxy    forward one llama-swap entry port to the engine
  select   select a profile, then serve the proxy
  serve    materialise a profile and exec the engine
  gate     guard a model behind a profile requirement (the collocated companion)
  admit    ask the placement policy, then exec the model server
  status   what this host can serve, and what is serving right now
  ctl      up, down, status, stats, unload`)
	os.Exit(2)
}

// loadConfig reads the deployment file (optional) and builds the engine adapter it names.
func loadConfig(path string) (*config.Config, engine.Adapter, error) {
	cfg, err := config.Load(path)
	if err != nil {
		return nil, nil, err
	}
	switch cfg.Engine {
	case "strata":
		text := strata.New(cfg.EngineBin, cfg.DataDir, cfg.Profiles)
		// A deployment that also serves batch models names them in `commands`; each one is a
		// profile of the same manager, so an image job and the frontier cannot both hold the card.
		return cfg, router.New(text, enginecmd.New(cfg.Commands)), nil
	case "command":
		// Every profile is a command from the deployment config. It exists so the runtime can be
		// tested with a 1 MB model and no GPU, and so a second engine needs no code.
		return cfg, enginecmd.New(cfg.Commands), nil
	default:
		return nil, nil, fmt.Errorf("unknown engine %q (known: strata, command)", cfg.Engine)
	}
}

func runManager(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("manager", flag.ExitOnError)
	configPath := fs.String("config", config.DefaultPath(), "deployment config (JSON); the built-in brys defaults apply when empty")
	listen := fs.String("listen", "", "override the control-plane listen address")
	if err := fs.Parse(args); err != nil {
		return err
	}
	cfg, adapter, err := loadConfig(*configPath)
	if err != nil {
		return err
	}
	addr := *listen
	if addr == "" {
		addr = fmt.Sprintf("127.0.0.1:%d", cfg.ManagerPort)
	}

	sup := &engine.Supervisor{
		Adapter: adapter, EnginePort: cfg.EnginePort, LogPath: cfg.EngineLog,
		Env: os.Environ(),
	}
	client := swap.New(cfg.SwapURL)
	backend := &runtime.Backend{Supervisor: sup, Swap: client, Cfg: cfg}
	leases := control.NewLeases(time.Duration(cfg.LeaseTTLSeconds) * time.Second)
	j := journal.New(cfg.EventsPath())
	mgr := control.NewManager(cfg, j, leases, backend, client)
	// The placement policy is optional: a deployment that has not adopted it answers 501.
	if path := cfg.PolicyPath; path != "" {
		if p, err := policy.Load(path); err != nil {
			log.Printf("placement policy not loaded: %v", err)
		} else {
			mgr.Policy = p
			log.Printf("placement policy loaded from %s (%d models)", path, len(p.Models))
		}
	}

	// Restore the profile the last run left selected, and watch the companions llama-swap owns.
	go mgr.Restore(ctx)
	go mgr.WatchCompanions(ctx, 3*time.Second)

	srv := &http.Server{Addr: addr, Handler: mgr.Handler(), ReadHeaderTimeout: 10 * time.Second}
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdownCtx)
	}()
	log.Printf("kdn-inference-helpers manager on %s (engine %s, data %s)", addr, cfg.Engine, cfg.DataDir)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		return err
	}
	return nil
}

// remoteLeaser talks to the manager's /lease and /release, so a `select` process participates in the
// drain without sharing memory with it.
type remoteLeaser struct {
	base string
	http *http.Client
}

func newRemoteLeaser(base string) *remoteLeaser {
	return &remoteLeaser{base: base, http: &http.Client{Timeout: 15 * time.Second}}
}

func (r *remoteLeaser) Acquire(ctx context.Context) (string, bool) {
	var reply struct {
		Lease string `json:"lease"`
		Wait  bool   `json:"wait"`
	}
	if err := r.post(ctx, "/lease", nil, &reply); err != nil {
		return "", false
	}
	if reply.Wait || reply.Lease == "" {
		return "", false
	}
	return reply.Lease, true
}

func (r *remoteLeaser) Release(id string) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = r.post(ctx, "/release", map[string]any{"lease": id}, nil)
}

func (r *remoteLeaser) post(ctx context.Context, path string, body any, out any) error {
	payload, err := jsonBody(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, r.base+path, payload)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := r.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if out == nil {
		return nil
	}
	return decode(resp.Body, out)
}

func runProxy(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("proxy", flag.ExitOnError)
	port := fs.Int("port", 0, "listen port (llama-swap's ${PORT})")
	target := fs.String("target", "", "engine base URL (default http://127.0.0.1:<enginePort>)")
	manager := fs.String("manager", "", "manager base URL (default http://127.0.0.1:<managerPort>)")
	configPath := fs.String("config", "", "deployment config")
	if err := fs.Parse(args); err != nil {
		return err
	}
	cfg, _, err := loadConfig(*configPath)
	if err != nil {
		return err
	}
	if *port == 0 {
		return fmt.Errorf("proxy needs --port")
	}
	targetURL := *target
	if targetURL == "" {
		targetURL = fmt.Sprintf("http://127.0.0.1:%d", cfg.EnginePort)
	}
	managerURL := *manager
	if managerURL == "" {
		managerURL = fmt.Sprintf("http://127.0.0.1:%d", cfg.ManagerPort)
	}
	return serveProxy(ctx, cfg, *port, targetURL, managerURL, "", "", "")
}

// serveProxy forwards one llama-swap entry port to the engine and holds a lease per request.
//
// `watch` is the profile this listener was selected for. When it is set, the proxy leaves as soon
// as the manager moves to a different profile: it is the listener for a server that no longer
// exists, and a stale listener is worse than none — it would forward a chat request to whatever
// engine happens to hold the port next. `auto` (the profile-neutral frontier name) passes an empty
// `watch`, because staying alive across a switch is exactly what that name promises.
func serveProxy(ctx context.Context, cfg *config.Config, port int, targetURL, managerURL, watch, alias, profile string) error {
	target, err := url.Parse(targetURL)
	if err != nil {
		return err
	}
	leaser := newRemoteLeaser(managerURL)
	draining := func() bool {
		var status struct {
			Draining bool `json:"draining"`
		}
		if err := getJSON(ctx, managerURL+"/status", &status); err != nil {
			return false
		}
		return status.Draining
	}
	handler := proxy.New(target, leaser, draining)
	// The client learns what answered, not what it asked for. A harness records this next to the
	// commit: `qfn` is a name, `max` is the pack and the reserve that actually served it.
	handler.Identity = map[string]string{"X-KDN-Alias": alias}
	if profile != "" {
		// Ask per request: `auto` outlives a switch on purpose, so a startup snapshot would report
		// the profile that was current when llama-swap spawned this listener, not the one answering.
		handler.Profile = func(ctx context.Context) string {
			var status struct {
				Profile string `json:"profile"`
			}
			if err := getJSON(ctx, managerURL+"/status", &status); err != nil {
				return profile
			}
			if status.Profile == "" {
				return profile
			}
			return status.Profile
		}
	}

	// Dual stack on purpose: llama-swap resolves localhost to ::1 first, and a 127.0.0.1-only bind
	// fails its health check.
	runCtx, stop := context.WithCancel(ctx)
	defer stop()
	srv := &http.Server{Addr: fmt.Sprintf(":%d", port), Handler: handler, ReadHeaderTimeout: 10 * time.Second}
	go func() {
		<-runCtx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdownCtx)
	}()
	if watch != "" {
		// Leave when the profile moves on, but never mid-response: a 1039 s edit is not a lease
		// the listener may drop because the manager moved on. A stale binary (a deploy) is the
		// same rule: leave once nothing is in flight, so the next request spawns the new build.
		go watchProfile(runCtx, stop, managerURL, watch, handler.InFlight, staleBinary())
	}
	log.Printf("kdn-inference-helpers proxy :%d -> %s", port, targetURL)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		return err
	}
	return nil
}

// watchProfile stops the proxy when the manager is no longer serving `want`.
//
// llama-swap's unload path runs the entry's `cmdStop` and then waits for the entry process to exit;
// a proxy that never exits makes that wait last until llama-swap's 15-minute kill timeout, and the
// next model never starts. Leaving on our own is also the correct behaviour: the listener belongs
// to a profile, and the profile is gone.
func watchProfile(ctx context.Context, stop context.CancelFunc, managerURL, want string, inFlight func() int64, stale func() bool) {
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()
	// A listener that has been asked to leave keeps waiting for its own request, bounded: a wedged
	// request must not pin a stale listener for ever.
	deadline := time.Time{}
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
		var status struct {
			Profile string `json:"profile"`
		}
		if err := getJSON(ctx, managerURL+"/status", &status); err != nil {
			continue
		}
		leave := (status.Profile != "" && status.Profile != want) || stale()
		if !leave {
			continue
		}
		if deadline.IsZero() {
			deadline = time.Now().Add(20 * time.Minute)
		}
		if inFlight() > 0 && time.Now().Before(deadline) {
			continue // let the response finish; a switch is not a reason to cut a 15-minute edit
		}
		log.Printf("profile is %q, this listener served %q: leaving", status.Profile, want)
		stop()
		return
	}
}

// staleBinary reports whether this process runs a build the system no longer points at. A deploy
// replaces the helper; the listener exits once idle and llama-swap spawns the new one, which is
// safer than restarting llama-swap (that would cut every running request).
func staleBinary() func() bool {
	self, err := os.Executable()
	if err != nil {
		return func() bool { return false }
	}
	self, _ = filepath.EvalSymlinks(self)
	const current = "/run/current-system/sw/bin/kdn-inference-helpers"
	return func() bool {
		want, err := filepath.EvalSymlinks(current)
		if err != nil || want == "" {
			return false
		}
		return self != want
	}
}

func runSelect(ctx context.Context, args []string) error {
	// llama-swap passes `<profile> --port N`, and Go's `flag` stops at the first positional, so the
	// order cannot be delegated to the flag package: this scans both shapes.
	profile, flags, err := parsePositionalThenFlags(args, map[string]bool{
		"--port": true, "--manager": true, "--config": true, "--alias": true,
	})
	if err != nil {
		return err
	}
	if profile == "" {
		return fmt.Errorf("select needs a profile")
	}
	portValue := flags["--port"]
	if portValue == "" {
		return fmt.Errorf("select needs --port")
	}
	port, err := strconv.Atoi(portValue)
	if err != nil {
		return fmt.Errorf("--port %q is not a number", portValue)
	}
	cfg, _, err := loadConfig(flags["--config"])
	if err != nil {
		return err
	}
	managerURL := flags["--manager"]
	if managerURL == "" {
		managerURL = fmt.Sprintf("http://127.0.0.1:%d", cfg.ManagerPort)
	}
	var reply map[string]any
	if err := postJSON(ctx, managerURL+"/select", map[string]any{"profile": profile}, &reply); err != nil {
		return fmt.Errorf("the manager is not answering on %s: %w", managerURL, err)
	}
	if e, ok := reply["error"]; ok {
		return fmt.Errorf("select %s: %v", profile, e)
	}
	log.Printf("select %s -> %v", profile, reply)
	// `auto` keeps whatever profile is current, so this listener must survive a switch. Any other
	// name is a promise about one profile, and the listener leaves when the manager breaks it.
	//
	// `--alias` is the model name the caller used (`qfn`), which llama-swap does not pass on: the
	// entry command carries the profile it forces. Without it the header would say `auto`, which is
	// the manager's word, not the caller's.
	aliasName := flags["--alias"]
	if aliasName == "" {
		aliasName = profile
	}
	// The profile is reported either way: it is the one thing a caller cannot know for itself, and
	// `qfn` resolving to `max` is exactly the fact a commit needs to record.
	resolved, _ := reply["profile"].(string)
	watch := resolved
	if cfg.Normalise(profile) == "auto" {
		watch = ""
	}
	// The manager names the port the profile listens on: a diffusion server has its own, so the
	// frontier's port is never left in TIME_WAIT by a server that just stopped.
	target := cfg.EnginePort
	if p, ok := reply["port"].(float64); ok && int(p) > 0 {
		target = int(p)
	}
	return serveProxy(ctx, cfg, port, fmt.Sprintf("http://127.0.0.1:%d", target), managerURL, watch, aliasName, resolved)
}

func runServe(ctx context.Context, args []string) error {
	profile, flags, err := parsePositionalThenFlags(args, map[string]bool{"--port": true, "--config": true})
	if err != nil {
		return err
	}
	if profile == "" {
		return fmt.Errorf("serve needs a profile")
	}
	cfg, adapter, err := loadConfig(flags["--config"])
	if err != nil {
		return err
	}
	command, err := adapter.Prepare(profile)
	if err != nil {
		return err
	}
	argv := append([]string(nil), command.Args...)
	port := cfg.EnginePort
	if raw := flags["--port"]; raw != "" {
		if port, err = strconv.Atoi(raw); err != nil {
			return fmt.Errorf("--port %q is not a number", raw)
		}
	}
	argv = append(argv, "--port", fmt.Sprint(port))
	return execReplace(command.Path, argv, os.Environ())
}

// parsePositionalThenFlags accepts `<name> --flag value …` and `--flag value … <name>`, because
// llama-swap's contract puts the profile first and the flag package cannot see past it.
func parsePositionalThenFlags(args []string, known map[string]bool) (string, map[string]string, error) {
	positional := ""
	flags := map[string]string{}
	for i := 0; i < len(args); i++ {
		arg := args[i]
		if strings.HasPrefix(arg, "--") {
			if !known[arg] {
				return "", nil, fmt.Errorf("unknown flag %q", arg)
			}
			if i+1 >= len(args) {
				return "", nil, fmt.Errorf("%s needs a value", arg)
			}
			flags[arg] = args[i+1]
			i++
			continue
		}
		if positional != "" {
			return "", nil, fmt.Errorf("unexpected argument %q", arg)
		}
		positional = arg
	}
	return positional, flags, nil
}

// runGate guards one model behind a profile requirement: it owns the model server (started lazily,
// after the check) and answers the 409 that turns a silently slow companion into an actionable error.
//
// The policy is the deployment's: `--name` selects a gate spec from the config, which says which
// profiles satisfy the model, which targets a caller may ask for, and which body field carries the
// request. Nothing about a particular model is compiled in.
// runAdmit is the door every llama-swap entry goes through: it asks the manager's placement tree,
// prints the refusal verbatim when the answer is no, and execs the model server when it is yes.
//
// It replaces llama-swap's own eviction matrix as the decision point. A refusal must be readable in
// llama-swap's log, which is why the body is printed rather than turned into an exit code alone.
func runAdmit(ctx context.Context, args []string) error {
	configPath, rest := extractConfigFlag(args)
	// Stop at `--`: the server argv after it has its own `--model` (the GGUF path), and reading that
	// as the entry name asks the policy about a file path.
	model := ""
	for i := 0; i < len(rest); i++ {
		if rest[i] == "--" {
			break
		}
		if rest[i] == "--model" && i+1 < len(rest) {
			model = rest[i+1]
			i++
		}
	}
	if model == "" {
		return fmt.Errorf("admit needs --model <name>")
	}
	argv := companion.ResolveArgv(rest)
	if len(argv) == 0 {
		return fmt.Errorf("admit needs `-- <model server argv>`")
	}
	cfg, _, err := loadConfig(configPath)
	if err != nil {
		return err
	}
	managerURL := fmt.Sprintf("http://127.0.0.1:%d", cfg.ManagerPort)
	var reply map[string]any
	if err := postJSON(ctx, managerURL+"/admit", map[string]any{"model": model}, &reply); err != nil {
		// The manager's refusal carries the reason and the way out; print it so llama-swap's log
		// shows why the entry did not start.
		fmt.Fprintf(os.Stderr, "admit %s: %v\n", model, err)
		return err
	}
	if e, ok := reply["error"]; ok {
		return fmt.Errorf("admit %s: %v", model, e)
	}
	log.Printf("admit %s -> %v", model, reply)
	// exec, not spawn: the server replaces this process, so llama-swap's stop signal reaches it.
	return syscall.Exec(argv[0], argv, os.Environ())
}

func runGate(ctx context.Context, args []string) error {
	configPath, rest := extractConfigFlag(args)
	name := ""
	for i := 0; i < len(rest); i++ {
		if rest[i] == "--name" && i+1 < len(rest) {
			name = rest[i+1]
			i++
		}
	}
	argv := companion.ResolveArgv(rest)
	if len(argv) == 0 {
		return fmt.Errorf("gate needs `-- <model server argv>`; llama-swap supplies it")
	}
	cfg, _, err := loadConfig(configPath)
	if err != nil {
		return err
	}
	spec, ok := cfg.Gates[name]
	if !ok {
		return fmt.Errorf("no gate named %q in the deployment config", name)
	}
	port, err := companion.PublicPort(argv)
	if err != nil {
		return err
	}
	supervisor := &companion.Supervisor{
		Argv:    argv,
		LogPath: filepath.Join(cfg.DataDir, "strata", "companion.log"),
		Port:    port,
	}
	gate := &companion.Gate{
		Cfg:      cfg,
		Name:     name,
		Spec:     spec,
		Manager:  fmt.Sprintf("http://127.0.0.1:%d", cfg.ManagerPort),
		Upstream: supervisor.Upstream,
	}
	srv := &http.Server{Addr: fmt.Sprintf(":%d", port), Handler: gate, ReadHeaderTimeout: 10 * time.Second}
	go func() {
		<-ctx.Done()
		supervisor.Stop()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdownCtx)
	}()
	log.Printf("kdn-inference-helpers gate %q :%d (model starts on the first allowed request)", name, port)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		return err
	}
	return nil
}

func runCtl(ctx context.Context, args []string) error {
	// The CLI reads the same deployment file as the daemons: a different port or manager host is a
	// config change, never a rebuild.
	configPath, rest := extractConfigFlag(args)
	cfg, _, err := loadConfig(configPath)
	if err != nil {
		return err
	}
	base := fmt.Sprintf("http://127.0.0.1:%d", cfg.ManagerPort)
	return ctl.Run(ctx, base, rest, os.Stdout)
}

// extractConfigFlag pulls `--config PATH` out of the argument list before the ctl dispatcher sees it.
func extractConfigFlag(args []string) (string, []string) {
	path := config.DefaultPath()
	rest := make([]string, 0, len(args))
	for i := 0; i < len(args); i++ {
		if args[i] == "--config" && i+1 < len(args) {
			path = args[i+1]
			i++
			continue
		}
		rest = append(rest, args[i])
	}
	return path, rest
}

func execReplace(path string, argv, env []string) error {
	// syscall.Exec passes argv untouched, so argv[0] must be the program: without it the launcher
	// sees its own subcommand as the program name and parses `--profile <path>` as the command
	// (measured: "invalid choice: .../strata-omni-max.json"). `exec.Command` prepends it for us;
	// `Exec` does not.
	full := append([]string{path}, argv...)
	return syscallExec(path, full, env)
}

var syscallExec = func(path string, argv, env []string) error {
	return syscall.Exec(path, argv, env)
}
