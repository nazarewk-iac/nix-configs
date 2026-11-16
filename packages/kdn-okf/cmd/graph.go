package cmd

import (
	"fmt"
	"strings"

	"github.com/spf13/cobra"
)

func newGraphCmd(app *App) *cobra.Command {
	var format string
	cmd := &cobra.Command{
		Use:   "graph",
		Short: "Export the link graph as JSON or Graphviz DOT",
		RunE: func(cmd *cobra.Command, args []string) error {
			if app.JSON && format == "dot" {
				return &ExitError{Code: 2, Err: fmt.Errorf("--json and --format dot are mutually exclusive")}
			}
			result, err := app.load()
			if err != nil {
				return err
			}
			nodes := make([]map[string]any, 0, len(result.Bundle.Concepts))
			for _, concept := range result.Bundle.Concepts {
				nodes = append(nodes, map[string]any{
					"id":    concept.ID,
					"type":  concept.Type,
					"title": concept.Title,
				})
			}
			type edge struct {
				Source string `json:"source"`
				Target string `json:"target"`
			}
			edges := []edge{}
			for _, concept := range result.Bundle.Concepts {
				for _, link := range concept.Links {
					if link.Resolved != "" {
						edges = append(edges, edge{Source: concept.ID, Target: link.Resolved})
					}
				}
			}
			if format == "dot" {
				var b strings.Builder
				b.WriteString("digraph okf {\n")
				b.WriteString("  rankdir=LR;\n")
				for _, node := range nodes {
					fmt.Fprintf(&b, "  %q;\n", node["id"])
				}
				for _, edge := range edges {
					fmt.Fprintf(&b, "  %q -> %q;\n", edge.Source, edge.Target)
				}
				b.WriteString("}\n")
				fmt.Fprint(app.Out, b.String())
				return nil
			}
			if app.JSONL {
				return app.writeJSONL([]any{map[string]any{"nodes": nodes, "edges": edges}})
			}
			return app.writeJSON("graph", map[string]any{"nodes": nodes, "edges": edges}, result.Issues)
		},
	}
	cmd.Flags().StringVar(&format, "format", "json", "json or dot")
	return cmd
}

func newIndexCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "index",
		Short: "Build or refresh the index",
		RunE: func(cmd *cobra.Command, args []string) error {
			result, err := app.load()
			if err != nil {
				return err
			}
			if app.JSONL {
				return app.writeJSONL([]any{map[string]any{
					"index":    result.Cache,
					"concepts": len(result.Bundle.Concepts),
					"reserved": len(result.Bundle.Reserved),
				}})
			}
			if app.JSON {
				return app.writeJSON("index", map[string]any{
					"index":    result.Cache,
					"concepts": len(result.Bundle.Concepts),
					"reserved": len(result.Bundle.Reserved),
				}, result.Issues)
			}
			state := "cold"
			if result.Cache.Warm {
				state = "warm"
			}
			fmt.Fprintf(app.Out, "bundle    %s\n", result.Bundle.Root)
			fmt.Fprintf(app.Out, "concepts  %d\n", len(result.Bundle.Concepts))
			fmt.Fprintf(app.Out, "reserved  %d\n", len(result.Bundle.Reserved))
			fmt.Fprintf(app.Out, "cache     %s (%s)\n", result.Cache.Path, state)
			return nil
		},
	}
}
