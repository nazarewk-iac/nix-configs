package cmd

import (
	"encoding/json"
	"fmt"

	"github.com/spf13/cobra"

	"kdn-certs/internal/decl"
	"kdn-certs/internal/dedup"
	"kdn-certs/internal/walk"
)

// statusEntry is one line of the status output.
type statusEntry struct {
	Name   string `json:"name"`
	CA     string `json:"ca"`
	Type   string `json:"type"`
	State  string `json:"state"`
	Reason string `json:"reason"`
}

// statusResponse is the `status --json` payload. It carries the per-certificate state and the
// per-target failures, so a machine reader sees both.
type statusResponse struct {
	Entries  []statusEntry  `json:"entries"`
	Failures []walk.Failure `json:"failures"`
}

// newStatusCmd builds `kdn-certs status`.
func newStatusCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "status",
		Short: "Report each certificate as valid, expiring or mismatched",
		RunE: func(cmd *cobra.Command, args []string) error {
			targets, err := app.loadTargets()
			if err != nil {
				return err
			}
			cas, err := walk.MergeCAs(targets.Targets)
			if err != nil {
				return err
			}
			result := dedup.Merge(targets.Targets)

			entries, err := statusEntries(app, result, cas)
			if err != nil {
				return err
			}

			if app.Options.JSON {
				encoder := json.NewEncoder(app.Out)
				encoder.SetIndent("", "  ")
				if err := encoder.Encode(statusResponse{Entries: entries, Failures: targets.Failures}); err != nil {
					return err
				}
				return failuresError(targets.Failures)
			}

			app.reportFailures(targets.Failures)
			for _, entry := range entries {
				fmt.Fprintf(app.Out, "%s\t%s\t%s\n", entry.Name, entry.Type, entry.State)
			}
			return failuresError(targets.Failures)
		},
	}
}

// statusEntries reads the committed certificate of every deduplicated leaf and reports its state.
// A valid certificate reports `valid`; a missing or mismatched one reports its reason.
func statusEntries(app *App, result dedup.Result, cas decl.CAs) ([]statusEntry, error) {
	entries := make([]statusEntry, 0, len(result.Certs))
	for _, cert := range result.Sorted() {
		ca, ok := cas[cert.CA]
		if !ok {
			return nil, fmt.Errorf("certificate %q names CA %q, which is not declared", cert.Name, cert.CA)
		}
		reason, err := app.decide(cert, ca.CommonName, false)
		if err != nil {
			return nil, err
		}
		state := "valid"
		if reason != "" {
			state = string(reason)
		}
		entries = append(entries, statusEntry{
			Name:   cert.Name,
			CA:     cert.CA,
			Type:   cert.Type,
			State:  state,
			Reason: string(reason),
		})
	}
	return entries, nil
}
