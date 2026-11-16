package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/spf13/cobra"

	"kdn-okf/internal/okf"
)

func newLinksCmd(app *App) *cobra.Command {
	var (
		recursive   bool
		maxDistance int
	)
	cmd := &cobra.Command{
		Use:   "links <concept>",
		Short: "List outgoing links",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			result, err := app.load()
			if err != nil {
				return err
			}
			concept, err := app.resolve(result.Bundle, args[0])
			if err != nil {
				return err
			}
			if app.PrintPath {
				fmt.Fprintln(app.Out, concept.Path)
				return nil
			}
			links := concept.Links
			if recursive {
				links = recursiveLinks(result.Bundle, concept, maxDistance)
			}
			if app.JSONL {
				items := make([]any, 0, len(links))
				for _, link := range links {
					items = append(items, link)
				}
				return app.writeJSONL(items)
			}
			if app.JSON {
				return app.writeJSON("links", map[string]any{
					"concept": concept.ID,
					"links":   nonNilLinks(links),
				}, result.Issues)
			}
			printLinks(app, links)
			return nil
		},
	}
	cmd.Flags().BoolVar(&recursive, "recursive", false, "follow resolved links breadth-first")
	cmd.Flags().IntVar(&maxDistance, "max-distance", 0, "stop after this many hops (0 = unlimited)")
	return cmd
}

func recursiveLinks(bundle *okf.Bundle, concept *okf.Concept, maxDistance int) []okf.Link {
	seen := map[string]bool{concept.ID: true}
	var out []okf.Link
	queue := []*okf.Concept{concept}
	distance := 0
	for len(queue) > 0 && (maxDistance <= 0 || distance < maxDistance) {
		var next []*okf.Concept
		for _, current := range queue {
			for _, link := range current.Links {
				if link.Resolved == "" {
					continue
				}
				out = append(out, link)
				if seen[link.Resolved] {
					continue
				}
				seen[link.Resolved] = true
				if target := bundle.Find(link.Resolved); target != nil {
					next = append(next, target)
				}
			}
		}
		queue = next
		distance++
	}
	return out
}

func newBacklinksCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "backlinks <concept>",
		Short: "List incoming links",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			result, err := app.load()
			if err != nil {
				return err
			}
			concept, err := app.resolve(result.Bundle, args[0])
			if err != nil {
				return err
			}
			if app.PrintPath {
				fmt.Fprintln(app.Out, concept.Path)
				return nil
			}
			if app.JSONL {
				items := make([]any, 0, len(concept.Backlinks))
				for _, link := range concept.Backlinks {
					items = append(items, link)
				}
				return app.writeJSONL(items)
			}
			if app.JSON {
				return app.writeJSON("backlinks", map[string]any{
					"concept":   concept.ID,
					"backlinks": nonNilLinks(concept.Backlinks),
				}, result.Issues)
			}
			printLinks(app, concept.Backlinks)
			return nil
		},
	}
}

func printLinks(app *App, links []okf.Link) {
	if len(links) == 0 {
		fmt.Fprintln(app.Out, "no links")
		return
	}
	for _, link := range links {
		state := "ok"
		if link.Missing {
			state = "missing"
		}
		target := link.Target
		if link.Resolved != "" {
			target = link.Resolved
		}
		fmt.Fprintf(app.Out, "%s\t%s\t%s\t%s\n", link.Source, target, link.Kind, state)
	}
}

func newOpenCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "open <concept>",
		Short: "Open a concept in $EDITOR, or print its path",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			result, err := app.load()
			if err != nil {
				return err
			}
			concept, err := app.resolve(result.Bundle, args[0])
			if err != nil {
				return err
			}
			editor := strings.TrimSpace(os.Getenv("EDITOR"))
			if app.PrintPath || editor == "" {
				fmt.Fprintln(app.Out, concept.Path)
				return nil
			}
			// #nosec G204 -- the editor comes from $EDITOR and the path from the bundle.
			command := exec.Command("sh", "-c", editor+" \"$1\"", "sh", concept.Path)
			command.Stdin, command.Stdout, command.Stderr = os.Stdin, os.Stdout, os.Stderr
			return command.Run()
		},
	}
}
