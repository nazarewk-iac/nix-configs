package cmd

import (
	"fmt"
	"sort"

	"github.com/spf13/cobra"

	"kdn-certs/internal/decl"
	"kdn-certs/internal/smallstep"
)

// newDoctorCmd builds `kdn-certs doctor`.
func newDoctorCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "doctor",
		Short: "Discover zombie step-ca processes and stale PID files",
		RunE: func(cmd *cobra.Command, args []string) error {
			targets, err := app.loadTargets()
			if err != nil {
				return err
			}
			app.reportFailures(targets.Failures)

			// Scan the directory of every declared CA. A tree that declares no CA keeps the
			// historical default, so `doctor` still works on a bare checkout.
			dirs := caDirectories(targets.Targets)
			if len(dirs) == 0 {
				dirs = []string{"data/ca"}
			}

			for _, dir := range dirs {
				zombies, err := smallstep.FindZombies(dir)
				if err != nil {
					return err
				}
				if len(zombies) == 0 {
					fmt.Fprintf(app.Out, "%s\tno zombies found\n", dir)
					continue
				}
				for _, zombie := range zombies {
					fmt.Fprintf(app.Out, "%s\t%s\t%s\n", dir, zombie.Kind, zombie.Detail)
				}
				if app.Options.Force {
					if err := smallstep.RemoveZombies(zombies); err != nil {
						return err
					}
				}
			}
			return failuresError(targets.Failures)
		},
	}
}

// caDirectories returns the sorted, unique CA directories of the readable targets.
func caDirectories(targets []decl.Target) []string {
	seen := map[string]bool{}
	for _, target := range targets {
		for _, ca := range target.CAs {
			if ca.Directory != "" {
				seen[ca.Directory] = true
			}
		}
	}
	dirs := make([]string, 0, len(seen))
	for dir := range seen {
		dirs = append(dirs, dir)
	}
	sort.Strings(dirs)
	return dirs
}
