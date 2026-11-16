package cmd

import (
	"fmt"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"

	"kdn-okf/internal/okf"
)

func newOutlineCmd(app *App) *cobra.Command {
	var depth int
	cmd := &cobra.Command{
		Use:   "outline [<bundle|concept>]",
		Short: "Print the heading tree with line ranges",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			result, err := app.load()
			if err != nil {
				return err
			}
			var outline okf.Outline
			if len(args) == 0 || args[0] == "." || args[0] == result.Bundle.Root || args[0] == filepath.Base(result.Bundle.Root) {
				outline = bundleOutline(result.Bundle, depth)
			} else {
				concept, err := app.resolve(result.Bundle, args[0])
				if err != nil {
					return err
				}
				if app.PrintPath {
					fmt.Fprintln(app.Out, concept.Path)
					return nil
				}
				outline = okf.OutlineOf(concept, depth)
			}
			if app.JSONL {
				return app.writeJSONL([]any{outline})
			}
			if app.JSON {
				return app.writeJSON("outline", map[string]any{"outline": outline}, result.Issues)
			}
			printOutline(app, outline.Headings, 0)
			return nil
		},
	}
	cmd.Flags().IntVar(&depth, "depth", 0, "maximum heading depth (0 = unlimited)")
	return cmd
}

func bundleOutline(bundle *okf.Bundle, depth int) okf.Outline {
	root := okf.Heading{Level: 0, Text: bundle.Name}
	for _, concept := range bundle.Concepts {
		root.Children = append(root.Children, okf.Heading{
			Level:    1,
			Text:     concept.Title,
			Children: okf.CapDepth(concept.Headings, depth),
		})
	}
	return okf.Outline{Kind: "bundle", Title: bundle.Name, Headings: []okf.Heading{root}}
}

func printOutline(a *App, headings []okf.Heading, indent int) {
	for _, heading := range headings {
		if heading.Level > 0 {
			fmt.Fprintf(a.Out, "%s%s  [%d-%d]\n", strings.Repeat("  ", indent), heading.Text, heading.StartLine, heading.EndLine)
		} else {
			fmt.Fprintf(a.Out, "%s\n", heading.Text)
		}
		printOutline(a, heading.Children, indent+1)
	}
}

func newSectionCmd(app *App) *cobra.Command {
	var maxLines int
	cmd := &cobra.Command{
		Use:   "section <concept> <heading>",
		Short: "Print exactly one heading range",
		Args:  cobra.ExactArgs(2),
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
			section, ok := okf.Section(concept, args[1], maxLines)
			if !ok {
				return &ExitError{Code: 2, Err: fmt.Errorf("heading %q not found in %s", args[1], concept.ID)}
			}
			if app.JSONL {
				return app.writeJSONL([]any{section})
			}
			if app.JSON {
				return app.writeJSON("section", map[string]any{"section": section}, result.Issues)
			}
			fmt.Fprintln(app.Out, section.Markdown)
			if section.Truncated {
				fmt.Fprintf(app.Out, "\n… truncated at %d lines (range %d-%d)\n", maxLines, section.StartLine, section.EndLine)
			}
			return nil
		},
	}
	cmd.Flags().IntVar(&maxLines, "max-lines", 0, "truncate the section after this many lines")
	return cmd
}

func newContextCmd(app *App) *cobra.Command {
	var budget int
	cmd := &cobra.Command{
		Use:   "context <concept>",
		Short: "Print a budgeted summary of one concept",
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
			ctx := okf.ContextOf(concept, budget)
			if app.JSONL {
				return app.writeJSONL([]any{ctx})
			}
			if app.JSON {
				return app.writeJSON("context", map[string]any{"context": ctx}, result.Issues)
			}
			fmt.Fprintf(app.Out, "# %s\n\n", ctx.Title)
			fmt.Fprintln(app.Out, ctx.Preview)
			return nil
		},
	}
	cmd.Flags().IntVar(&budget, "budget", 80, "maximum lines of preview")
	return cmd
}
