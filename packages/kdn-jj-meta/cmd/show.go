package cmd

import (
	"context"
	"fmt"

	"github.com/spf13/cobra"

	"kdn-jj-meta/internal/trailer"
)

type showData struct {
	ChangeID    string            `json:"change_id"`
	CommitID    string            `json:"commit_id"`
	Mutable     bool              `json:"mutable"`
	Body        string            `json:"body"`
	Description string            `json:"description"`
	Trailers    []trailer.Trailer `json:"trailers"`
}

func newShowCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "show [<change-id>]",
		Short: "Print the description, the trailers and the mutability of a change",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			rev := "@"
			if len(args) == 1 {
				rev = args[0]
			}
			return app.show(rev)
		},
	}
}

func (a *App) show(rev string) error {
	changes, err := a.Runner.Changes(context.Background(), rev)
	if err != nil {
		return err
	}
	if len(changes) == 0 {
		return &ExitError{Code: 1, Err: fmt.Errorf("no change matches %q", rev)}
	}
	if len(changes) > 1 {
		return &ExitError{Code: 1, Err: fmt.Errorf("show expects one change, %d match %q; pass a single change ID", len(changes), rev)}
	}
	change := changes[0]
	doc := trailer.Parse(change.Description)
	data := showData{
		ChangeID:    change.ChangeID,
		CommitID:    change.CommitID,
		Mutable:     !change.Immutable,
		Body:        doc.Body(),
		Description: change.Description,
		Trailers:    doc.Trailers,
	}
	if data.Trailers == nil {
		data.Trailers = []trailer.Trailer{}
	}
	if a.JSONL {
		return a.writeJSONL([]any{data})
	}
	if a.JSON {
		return a.writeJSON("show", data, nil)
	}
	state := "mutable"
	if change.Immutable {
		state = "immutable"
	}
	fmt.Fprintf(a.Out, "%s %s %s\n", shortID(change.ChangeID), change.CommitID, state)
	if data.Body != "" {
		fmt.Fprintln(a.Out)
		fmt.Fprintln(a.Out, data.Body)
	}
	if len(data.Trailers) > 0 {
		fmt.Fprintln(a.Out)
		for _, t := range data.Trailers {
			fmt.Fprintln(a.Out, t.String())
		}
	}
	return nil
}
