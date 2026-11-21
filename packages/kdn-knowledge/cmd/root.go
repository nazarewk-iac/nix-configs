// Package cmd holds the command tree of kdn-knowledge.
//
// The tree uses only the standard flag package: the tool must build with no third-party module.
package cmd

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"kdn-knowledge/internal/llm"
	"kdn-knowledge/internal/state"
	"kdn-knowledge/internal/store"
)

// Defaults of the design. The models are base ids, not purpose aliases: several aliases point at
// models that were pruned from the catalogue and answer `no router for requested model`.
const (
	DefaultEndpoint     = "https://llama-swap.brys.priv.nb.net.int.kdn.im/v1"
	DefaultKeyFile      = "/run/configs/llms/llama-server/api-keys/default"
	DefaultExtractModel = "qfn"
	DefaultMergeModel   = "qfn"
	// DefaultManager is empty on purpose: the placement manager answers on the fleet host only.
	// A laptop run must not spend its timeout on an unreachable address. On brys, pass
	// --manager http://127.0.0.1:8181.
	DefaultManager = ""
	DefaultTimeout = 300 * time.Second
)

// ExitError carries an explicit process exit code.
type ExitError struct {
	Code int
	Err  error
}

func (e *ExitError) Error() string {
	if e.Err != nil {
		return e.Err.Error()
	}
	return fmt.Sprintf("exit %d", e.Code)
}

// App is the shared state of one CLI run.
type App struct {
	Version string
	Now     func() time.Time

	JSON       bool
	Quiet      bool
	DataDir    string
	Endpoint   string
	KeyFile    string
	Model      string
	MergeModel string
	Manager    string
	Bundle     string
	AllowHosts stringList
	Timeout    time.Duration

	out    io.Writer
	errOut io.Writer
	log    *os.File
	logDir string
}

// config is the resolved run configuration.
type config struct {
	Store      *store.Store
	Ledger     *state.State
	DataDir    string
	DB         string
	Endpoint   string
	KeyFile    string
	APIKey     string
	KeyError   error
	Model      string
	MergeModel string
	Manager    string
	Bundle     string
	Timeout    time.Duration
}

// Main dispatches one command.
func Main(args []string, version string, stdout, stderr io.Writer) error {
	app := &App{Version: version, Now: time.Now, out: stdout, errOut: stderr}
	if len(args) == 0 {
		printUsage(stderr)
		return &ExitError{Code: 2, Err: errors.New("a command is required")}
	}
	command, rest := args[0], args[1:]
	switch command {
	case "harvest":
		return app.runHarvest(rest)
	case "extract":
		return app.runExtract(rest)
	case "dream":
		return app.runDream(rest)
	case "apply":
		return app.runApply(rest)
	case "run":
		return app.runAll(rest)
	case "status":
		return app.runStatus(rest)
	case "completion":
		return app.runCompletion(rest)
	case "version", "--version", "-v":
		fmt.Fprintf(stdout, "kdn-knowledge %s\n", version)
		return nil
	case "help", "-h", "--help":
		printUsage(stdout)
		return nil
	default:
		printUsage(stderr)
		return &ExitError{Code: 2, Err: fmt.Errorf("unknown command %q", command)}
	}
}

// commonFlags registers the flags that every command accepts.
func (a *App) commonFlags(fs *flag.FlagSet) {
	fs.BoolVar(&a.JSON, "json", false, "print the summary on stdout as one JSON object")
	fs.BoolVar(&a.Quiet, "quiet", false, "suppress progress lines on stderr")
	fs.StringVar(&a.DataDir, "data-dir", "", "data directory (default: ${XDG_CACHE_HOME:-~/.cache}/kdn/knowledge)")
	fs.StringVar(&a.Endpoint, "endpoint", "", "OpenAI-compatible base URL of the local fleet")
	fs.StringVar(&a.KeyFile, "key-file", "", "one-line bearer key file (default: "+DefaultKeyFile+")")
	fs.Var(&a.AllowHosts, "allow-host", "extra allowed endpoint host (repeatable)")
	fs.StringVar(&a.Manager, "manager", "", "placement manager; empty skips the check (on brys: http://127.0.0.1:8181)")
	fs.StringVar(&a.Bundle, "bundle", "", "memory bundle root (default: ./.agents/knowledge)")
	fs.DurationVar(&a.Timeout, "timeout", 0, "per-call timeout (default: 300s)")
}

// modelFlags registers the model selection of the commands that call a model.
func (a *App) modelFlags(fs *flag.FlagSet) {
	fs.StringVar(&a.Model, "model", "", "extraction model id (default: "+DefaultExtractModel+")")
	fs.StringVar(&a.MergeModel, "merge-model", "", "merge model id (default: "+DefaultMergeModel+")")
}

// prepare resolves the configuration and opens the store and the ledger.
func (a *App) prepare() (*config, error) {
	cfg := &config{}
	dataDir, err := resolveDataDir(a.DataDir)
	if err != nil {
		return nil, err
	}
	st, err := store.Open(dataDir)
	if err != nil {
		return nil, err
	}
	ledger, err := state.Load(st.StatePath())
	if err != nil {
		return nil, err
	}
	ledger.SetNow(a.Now)
	cfg.Store = st
	cfg.Ledger = ledger
	cfg.DataDir = dataDir
	cfg.Endpoint = firstNonEmpty(a.Endpoint, os.Getenv("KDN_KNOWLEDGE_ENDPOINT"), DefaultEndpoint)
	cfg.KeyFile = firstNonEmpty(a.KeyFile, os.Getenv("KDN_KNOWLEDGE_KEY_FILE"), DefaultKeyFile)
	cfg.APIKey, cfg.KeyError = llm.ReadKey(cfg.KeyFile)
	cfg.Model = firstNonEmpty(a.Model, os.Getenv("KDN_KNOWLEDGE_MODEL"), DefaultExtractModel)
	cfg.MergeModel = firstNonEmpty(a.MergeModel, os.Getenv("KDN_KNOWLEDGE_MERGE_MODEL"), DefaultMergeModel)
	cfg.Manager = firstNonEmpty(a.Manager, os.Getenv("KDN_KNOWLEDGE_MANAGER"), DefaultManager)
	cfg.Timeout = a.Timeout
	if cfg.Timeout <= 0 {
		cfg.Timeout = DefaultTimeout
	}
	cfg.DB = firstNonEmpty(os.Getenv("KDN_KNOWLEDGE_DB"), defaultDB())
	cfg.Bundle = a.Bundle
	if cfg.Bundle == "" {
		cwd, err := os.Getwd()
		if err != nil {
			return nil, err
		}
		cfg.Bundle = filepath.Join(cwd, ".agents", "knowledge")
	}
	return cfg, nil
}

// startLog opens runs/<UTC timestamp>.log and returns a closer. Progress goes to stderr and to
// this file, so a failed unattended run can be read afterwards.
func (a *App) startLog(st *store.Store) error {
	name := a.Now().UTC().Format("20060102T150405Z") + ".log"
	path := filepath.Join(st.RunsDir(), name)
	file, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return err
	}
	a.log = file
	a.logDir = st.RunsDir()
	return nil
}

// stopLog closes the run log.
func (a *App) stopLog() {
	if a.log != nil {
		_ = a.log.Close()
		a.log = nil
	}
}

// requireKey turns a missing or empty key file into one clear error before the first request.
func (a *App) requireKey(cfg *config) error {
	if cfg.APIKey != "" {
		return nil
	}
	if cfg.KeyError != nil {
		return &ExitError{Code: 1, Err: cfg.KeyError}
	}
	return &ExitError{Code: 1, Err: errors.New("no model API key; pass --key-file")}
}

// progressf writes one progress line to stderr and to the run log.
func (a *App) progressf(format string, args ...any) {
	line := fmt.Sprintf(format, args...)
	if !a.Quiet {
		fmt.Fprintln(a.errOut, line)
	}
	if a.log != nil {
		fmt.Fprintf(a.log, "%s %s\n", a.Now().UTC().Format(time.RFC3339), line)
	}
}

// emit prints the one-line summary, or the JSON envelope with --json.
func (a *App) emit(command, oneLine string, data any) error {
	if a.log != nil {
		fmt.Fprintf(a.log, "%s %s\n", a.Now().UTC().Format(time.RFC3339), oneLine)
	}
	if a.JSON {
		envelope := struct {
			Command     string `json:"command"`
			GeneratedAt string `json:"generated_at"`
			Data        any    `json:"data"`
		}{
			Command:     command,
			GeneratedAt: a.Now().UTC().Format(time.RFC3339),
			Data:        data,
		}
		encoder := json.NewEncoder(a.out)
		encoder.SetIndent("", "  ")
		return encoder.Encode(envelope)
	}
	fmt.Fprintln(a.out, oneLine)
	return nil
}

func (a *App) parse(fs *flag.FlagSet, args []string) error {
	if err := fs.Parse(args); err != nil {
		return &ExitError{Code: 2, Err: err}
	}
	if fs.NArg() > 0 {
		return &ExitError{Code: 2, Err: fmt.Errorf("unexpected argument %q", fs.Arg(0))}
	}
	return nil
}

// stringList collects a repeatable string flag.
type stringList []string

func (l *stringList) String() string { return strings.Join(*l, ",") }

func (l *stringList) Set(value string) error {
	*l = append(*l, value)
	return nil
}

func resolveDataDir(flagValue string) (string, error) {
	if flagValue != "" {
		return flagValue, nil
	}
	if value := os.Getenv("KDN_KNOWLEDGE_DATA"); value != "" {
		return value, nil
	}
	base := os.Getenv("XDG_CACHE_HOME")
	if base == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		base = filepath.Join(home, ".cache")
	}
	return filepath.Join(base, "kdn", "knowledge"), nil
}

func defaultDB() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".local", "share", "opencode", "opencode.db")
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func parseSince(raw string) (time.Time, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return time.Time{}, nil
	}
	for _, layout := range []string{"2006-01-02", time.RFC3339, "2006-01-02 15:04"} {
		if parsed, err := time.Parse(layout, raw); err == nil {
			return parsed.UTC(), nil
		}
	}
	return time.Time{}, fmt.Errorf("--since %q is not a date; use YYYY-MM-DD or RFC 3339", raw)
}

// printUsage writes the command surface.
func printUsage(w io.Writer) {
	fmt.Fprint(w, `kdn-knowledge turns finished agent sessions into knowledge and skill proposals.
It reads the OpenCode SQLite database through sqlite3 and calls local models only.

usage:
  kdn-knowledge harvest [--db PATH] [--source all|opencode|pi] [--pi-root DIR] [--since DATE]
                        [--project DIR] [--limit N] [--include-live]
  kdn-knowledge extract [--model ID] [--limit N] [--force] [--dry-run] [--chunk-chars N]
  kdn-knowledge dream   [--threshold F] [--min-sessions N] [--merge-model ID]
  kdn-knowledge apply   [--proposal DIR] [--yes]
  kdn-knowledge run     [--limit N] [--extract-limit N] [--model ID] [--source all|opencode|pi]
  kdn-knowledge status
  kdn-knowledge completion bash|fish|zsh
  kdn-knowledge version

common flags:
  --data-dir DIR    data directory (default: ${XDG_CACHE_HOME:-~/.cache}/kdn/knowledge)
  --endpoint URL    OpenAI-compatible base URL (default: `+DefaultEndpoint+`)
  --key-file PATH   one-line bearer key (default: `+DefaultKeyFile+`)
  --allow-host HOST extra allowed endpoint host (repeatable)
  --manager URL     placement manager; empty skips the check (on brys: http://127.0.0.1:8181)
  --bundle DIR      memory bundle (default: ./.agents/knowledge)
  --timeout DUR     per-call timeout (default: 300s)
  --json            print the summary on stdout as one JSON object
  --quiet           suppress progress
`)
}
