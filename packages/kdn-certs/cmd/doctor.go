package cmd

import (
	"fmt"

	"github.com/spf13/cobra"

	"kdn-certs/internal/smallstep"
)

// newDoctorCmd builds `kdn-certs doctor`.
func newDoctorCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "doctor",
		Short: "Discover zombie step-ca processes and stale PID files",
		RunE: func(cmd *cobra.Command, args []string) error {
			// The CA directory of the declared root. A CA that names no directory uses the default.
			caDir := "data/ca"
			zombies, err := smallstep.FindZombies(caDir)
			if err != nil {
				return err
			}
			if len(zombies) == 0 {
				fmt.Fprintln(app.Out, "no zombies found")
				return nil
			}
			for _, zombie := range zombies {
				fmt.Fprintf(app.Out, "%s\t%s\n", zombie.Kind, zombie.Detail)
			}
			if app.Options.Force {
				return smallstep.RemoveZombies(zombies)
			}
			return nil
		},
	}
}
