package cmd

import (
	"context"
	"fmt"
	"strings"
	"text/tabwriter"

	"github.com/spf13/cobra"

	"kdn-journal/internal/atuin"
)

func newAtuinCmd(app *App) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "atuin",
		Short: "Read Atuin Threads through the atuin CLI",
		Long: "Read the captured agent threads Atuin stores. The journal never opens Atuin's\n" +
			"database: every command shells out to `atuin threads ... --style json`.",
	}
	cmd.AddCommand(
		newAtuinListCmd(app),
		newAtuinShowCmd(app),
		newAtuinSearchCmd(app),
	)
	return cmd
}

func newAtuinListCmd(app *App) *cobra.Command {
	var harness string
	cmd := &cobra.Command{
		Use:   "list",
		Short: "List captured Atuin threads",
		RunE: func(cmd *cobra.Command, args []string) error {
			threads, err := app.listThreads(harness)
			if err != nil {
				return err
			}
			if app.JSONL {
				items := make([]any, 0, len(threads))
				for _, thread := range threads {
					items = append(items, thread)
				}
				return app.writeJSONL(items)
			}
			if app.JSON {
				return app.writeJSON("atuin list", map[string]any{"threads": threads}, nil)
			}
			return printThreads(app, threads)
		},
	}
	cmd.Flags().StringVar(&harness, "harness", "", "only this harness")
	return cmd
}

func newAtuinShowCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "show <thread-id>",
		Short: "Show one captured Atuin thread",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			if !app.Atuin.Available() {
				return fmt.Errorf("atuin is not on PATH")
			}
			thread, err := app.Atuin.Show(context.Background(), strings.TrimSpace(args[0]))
			if err != nil {
				return err
			}
			if app.JSONL {
				return app.writeJSONL([]any{thread})
			}
			if app.JSON {
				return app.writeJSON("atuin show", map[string]any{"thread": thread}, nil)
			}
			fmt.Fprintf(app.Out, "thread  %s\n", thread.AtuinID)
			fmt.Fprintf(app.Out, "harness %s\n", thread.Harness)
			if thread.SessionID != "" {
				fmt.Fprintf(app.Out, "session %s\n", thread.SessionID)
			}
			if thread.Model != "" {
				fmt.Fprintf(app.Out, "model   %s\n", thread.Model)
			}
			if thread.Cwd != "" {
				fmt.Fprintf(app.Out, "cwd     %s\n", thread.Cwd)
			}
			if thread.StartedAt != "" {
				fmt.Fprintf(app.Out, "started %s\n", thread.StartedAt)
			}
			if thread.UpdatedAt != "" {
				fmt.Fprintf(app.Out, "updated %s\n", thread.UpdatedAt)
			}
			fmt.Fprintf(app.Out, "messages %d\n", thread.MessageCount)
			if thread.Title != "" {
				fmt.Fprintf(app.Out, "title   %s\n", thread.Title)
			}
			return nil
		},
	}
}

func newAtuinSearchCmd(app *App) *cobra.Command {
	var (
		harness string
		limit   int
	)
	cmd := &cobra.Command{
		Use:   "search <query...>",
		Short: "Search captured Atuin threads",
		Args:  cobra.MinimumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			if !app.Atuin.Available() {
				return fmt.Errorf("atuin is not on PATH")
			}
			query := strings.Join(args, " ")
			threads, err := app.Atuin.Search(context.Background(), query, harness, limit)
			if err != nil {
				return err
			}
			if app.JSONL {
				items := make([]any, 0, len(threads))
				for _, thread := range threads {
					items = append(items, thread)
				}
				return app.writeJSONL(items)
			}
			if app.JSON {
				return app.writeJSON("atuin search", map[string]any{"query": query, "threads": threads}, nil)
			}
			return printThreads(app, threads)
		},
	}
	cmd.Flags().StringVar(&harness, "harness", "", "only this harness")
	cmd.Flags().IntVar(&limit, "limit", 10, "maximum threads to return")
	return cmd
}

func (a *App) listThreads(harness string) ([]atuin.Thread, error) {
	if !a.Atuin.Available() {
		return nil, fmt.Errorf("atuin is not on PATH")
	}
	threads, err := a.Atuin.List(context.Background())
	if err != nil {
		return nil, err
	}
	if harness == "" {
		return threads, nil
	}
	want := strings.ToLower(strings.TrimSpace(harness))
	filtered := make([]atuin.Thread, 0, len(threads))
	for _, thread := range threads {
		if strings.ToLower(thread.Harness) == want {
			filtered = append(filtered, thread)
		}
	}
	return filtered, nil
}

func printThreads(app *App, threads []atuin.Thread) error {
	w := tabwriter.NewWriter(app.Out, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, "THREAD\tHARNESS\tSTARTED\tMESSAGES\tTITLE")
	for _, thread := range threads {
		fmt.Fprintf(w, "%s\t%s\t%s\t%d\t%s\n",
			thread.AtuinID, thread.Harness, thread.StartedAt, thread.MessageCount, truncateTitle(thread.Title))
	}
	return w.Flush()
}

func truncateTitle(title string) string {
	const width = 70
	title = strings.TrimSpace(strings.ReplaceAll(title, "\n", " "))
	if len(title) <= width {
		return title
	}
	return title[:width-1] + "…"
}
