package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"time"

	"kdn-inference-helpers/internal/config"
	"kdn-inference-helpers/internal/engine/strata"
	"kdn-inference-helpers/internal/policy"
	"kdn-inference-helpers/internal/status"
)

// runStatus answers "what can this host serve, and what is serving right now" in one screen.
//
// It is the one subcommand that must work when everything else does not: a manager that does not
// answer and a policy file that is missing are lines of output, never errors. Whoever runs this is
// usually looking at a host that has already gone wrong, and a command that refuses to say anything
// until the control plane is healthy is a command they cannot use.
func runStatus(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("status", flag.ExitOnError)
	configPath := fs.String("config", config.DefaultPath(), "deployment config (JSON)")
	policyPath := fs.String("policy", "", "placement policy (default: the deployment config's policyPath)")
	long := fs.Bool("long", false, "the live detail as well, even when nothing is loaded")
	asJSON := fs.Bool("json", false, "the same data as one JSON object")
	host := fs.String("host", "", "name in the header (default: the kernel hostname)")
	if err := fs.Parse(args); err != nil {
		return err
	}
	cfg, _, err := loadConfig(*configPath)
	if err != nil {
		return err
	}
	snap := status.Snapshot{Host: *host, Now: time.Now()}
	if snap.Host == "" {
		snap.Host, _ = os.Hostname()
	}
	// The policy is the only source of measured facts, and it is optional: a deployment that has
	// not adopted it still gets the table, with the reason it has no numbers on it.
	snap.Policy.Path = cfg.PolicyPath
	if *policyPath != "" {
		snap.Policy.Path = *policyPath
	}
	var pol *policy.Policy
	if snap.Policy.Path == "" {
		snap.Policy.Error = "no policy configured"
	} else if loaded, err := policy.Load(snap.Policy.Path); err != nil {
		snap.Policy.Error = err.Error()
	} else {
		pol = loaded
		snap.Policy.Models = len(loaded.Models)
	}
	snap.Profiles = status.FromDeployment(deploymentPlan(cfg, pol), engineRows(cfg), pol)
	snap.Manager = status.ManagerView(ctx, fmt.Sprintf("http://127.0.0.1:%d", cfg.ManagerPort))
	snap.Swap = status.SwapView(ctx, cfg.SwapURL)
	if free, total, ok := status.VRAM("/sys/class/drm"); ok {
		snap.Free.VRAMMiB, snap.Free.VRAMTotalMiB = free, total
	}
	if free, total, ok := status.Memory("/proc/meminfo"); ok {
		snap.Free.RAMMiB, snap.Free.RAMTotalMiB = free, total
	}
	if rate, at, ok := status.Rate(cfg.EngineLog); ok {
		snap.EngineRateTps, snap.EngineRateAt = &rate, &at
	}

	if *asJSON {
		raw, err := status.JSON(snap)
		if err != nil {
			return err
		}
		_, err = fmt.Fprintln(os.Stdout, string(raw))
		return err
	}
	return status.Render(os.Stdout, snap, *long)
}

// deploymentPlan is the configured half: the profiles this deployment can serve, and the names and
// reserves that reach them.
func deploymentPlan(cfg *config.Config, pol *policy.Policy) status.Plan {
	plan := status.Plan{
		TextProfiles: cfg.TextProfiles,
		Aliases:      cfg.Aliases,
		Resting:      cfg.DefaultTextProfile(),
		Commands:     make([]string, 0, len(cfg.Commands)),
	}
	for name := range cfg.Commands {
		plan.Commands = append(plan.Commands, name)
	}
	if pol != nil {
		plan.Colo = pol.ColoProfiles
	}
	return plan
}

// engineRows asks the engine adapter for the pack, the window and the slot count. It builds the
// adapter itself rather than reading the manager's: the manager serves through a router, which is
// the right shape for switching and hides the engine's own table.
func engineRows(cfg *config.Config) func(string) status.EngineRow {
	if cfg.Engine != "strata" {
		return func(string) status.EngineRow { return status.EngineRow{} }
	}
	profiles := strata.New(cfg.EngineBin, cfg.DataDir, cfg.Profiles)
	return func(name string) status.EngineRow {
		p, ok := profiles.Profile(name)
		if !ok {
			return status.EngineRow{}
		}
		return status.EngineRow{Pack: status.PackName(p.Base), Context: p.MaxContext, Slots: p.Parallel}
	}
}
