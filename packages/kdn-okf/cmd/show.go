package cmd

import (
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"

	"kdn-okf/internal/okf"
)

type conceptFull struct {
	conceptSummary
	Resource  string        `json:"resource,omitempty"`
	Generated *okf.Event    `json:"generated,omitempty"`
	Verified  []okf.Event   `json:"verified"`
	Sources   []okf.Source  `json:"sources"`
	Headings  []okf.Heading `json:"headings"`
	Links     []okf.Link    `json:"links"`
	Backlinks []okf.Link    `json:"backlinks"`
	Issues    []okf.Issue   `json:"issues"`
	Body      string        `json:"body,omitempty"`
}

func fullConcept(concept *okf.Concept, includeBody bool) conceptFull {
	out := conceptFull{
		conceptSummary: summarize(concept),
		Resource:       concept.Resource,
		Generated:      concept.Generated,
		Verified:       nonNilEvents(concept.Verified),
		Sources:        nonNilSources(concept.Sources),
		Headings:       nonNilHeadings(concept.Headings),
		Links:          nonNilLinks(concept.Links),
		Backlinks:      nonNilLinks(concept.Backlinks),
		Issues:         nonNilIssues(concept.Issues),
	}
	if includeBody {
		out.Body = string(concept.Body)
	}
	return out
}

func newShowCmd(app *App) *cobra.Command {
	var (
		raw         bool
		render      bool
		includeBody bool
	)
	cmd := &cobra.Command{
		Use:   "show <concept>",
		Short: "Show one concept with its frontmatter, body, links and trust",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return app.show(args[0], raw, render, includeBody)
		},
	}
	cmd.Flags().BoolVar(&raw, "raw", false, "print the file bytes unchanged")
	cmd.Flags().BoolVar(&render, "render", false, "render the Markdown with glamour")
	cmd.Flags().BoolVar(&includeBody, "include-body", false, "include the body in --json")
	return cmd
}

func (a *App) show(selector string, raw, render, includeBody bool) error {
	if raw && render {
		return &ExitError{Code: 2, Err: errors.New("--raw and --render are mutually exclusive")}
	}
	if raw && (a.JSON || a.JSONL) {
		return &ExitError{Code: 2, Err: errors.New("--raw cannot be combined with --json or --jsonl")}
	}
	result, err := a.load()
	if err != nil {
		return err
	}
	concept, err := a.resolve(result.Bundle, selector)
	if err != nil {
		return err
	}
	if a.PrintPath {
		fmt.Fprintln(a.Out, concept.Path)
		return nil
	}
	if raw {
		data, err := os.ReadFile(concept.Path)
		if err != nil {
			return err
		}
		_, err = a.Out.Write(data)
		return err
	}
	if a.JSONL {
		return a.writeJSONL([]any{fullConcept(concept, includeBody)})
	}
	if a.JSON {
		return a.writeJSON("show", map[string]any{"concept": fullConcept(concept, includeBody)}, result.Issues)
	}
	fmt.Fprintf(a.Out, "concept    %s\n", concept.ID)
	fmt.Fprintf(a.Out, "title      %s\n", concept.Title)
	fmt.Fprintf(a.Out, "type       %s\n", concept.Type)
	fmt.Fprintf(a.Out, "status     %s\n", concept.Status)
	fmt.Fprintf(a.Out, "trust      %s\n", concept.Trust.String())
	if concept.Stale {
		fmt.Fprintf(a.Out, "stale      yes (%s)\n", concept.StaleAfter)
	}
	if len(concept.Tags) > 0 {
		fmt.Fprintf(a.Out, "tags       %s\n", strings.Join(concept.Tags, ", "))
	}
	if len(concept.Links) > 0 {
		fmt.Fprintf(a.Out, "links      %d (%d missing)\n", len(concept.Links), missingLinks(concept))
	}
	if len(concept.Backlinks) > 0 {
		fmt.Fprintf(a.Out, "backlinks  %d\n", len(concept.Backlinks))
	}
	body := string(concept.Body)
	if render {
		body = renderMarkdown(body, a.Width)
	}
	fmt.Fprintln(a.Out)
	fmt.Fprintln(a.Out, body)
	return nil
}

func missingLinks(concept *okf.Concept) int {
	count := 0
	for _, link := range concept.Links {
		if link.Missing {
			count++
		}
	}
	return count
}

func nonNilEvents(values []okf.Event) []okf.Event {
	if values == nil {
		return []okf.Event{}
	}
	return values
}

func nonNilSources(values []okf.Source) []okf.Source {
	if values == nil {
		return []okf.Source{}
	}
	return values
}

func nonNilHeadings(values []okf.Heading) []okf.Heading {
	if values == nil {
		return []okf.Heading{}
	}
	return values
}

func nonNilLinks(values []okf.Link) []okf.Link {
	if values == nil {
		return []okf.Link{}
	}
	return values
}

func nonNilIssues(values []okf.Issue) []okf.Issue {
	if values == nil {
		return []okf.Issue{}
	}
	return values
}
