package cmd

import (
	"fmt"
	"sort"
	"strings"
	"text/tabwriter"

	"github.com/spf13/cobra"

	"kdn-okf/internal/okf"
)

type listOptions struct {
	command    string
	Type       string
	Tag        string
	Status     string
	Trust      string
	Stale      bool
	Orphan     bool
	Broken     bool
	Unverified bool
	Sort       string
	Limit      int
	All        bool
}

func (o *listOptions) filters() filterOptions {
	return filterOptions{
		Type:       o.Type,
		Tag:        o.Tag,
		Status:     o.Status,
		Trust:      o.Trust,
		Stale:      o.Stale,
		Orphan:     o.Orphan,
		Broken:     o.Broken,
		Unverified: o.Unverified,
	}
}

func addFilterFlags(cmd *cobra.Command, opts *listOptions) {
	flags := cmd.Flags()
	flags.StringVar(&opts.Type, "type", "", "only this type")
	flags.StringVar(&opts.Tag, "tag", "", "only concepts with this tag")
	flags.StringVar(&opts.Status, "status", "", "only this status: draft, stable, deprecated")
	flags.StringVar(&opts.Trust, "trust", "", "only this trust tier: unverified, machine-confirmed, human-reviewed")
	flags.BoolVar(&opts.Stale, "stale", false, "only stale concepts")
	flags.BoolVar(&opts.Orphan, "orphan", false, "only concepts with no backlinks")
	flags.BoolVar(&opts.Broken, "broken", false, "only concepts with a missing link")
	flags.BoolVar(&opts.Unverified, "unverified", false, "only unverified concepts")
	flags.StringVar(&opts.Sort, "sort", "path", "sort by path, title, modified, type, status, trust or stale")
	flags.IntVar(&opts.Limit, "limit", 50, "maximum concepts to print (0 = unlimited)")
	flags.BoolVar(&opts.All, "all", false, "print every concept")
}

func newListCmd(app *App) *cobra.Command {
	opts := &listOptions{command: "list"}
	cmd := &cobra.Command{
		Use:   "list",
		Short: "List concepts with the active filters and sort",
		RunE: func(cmd *cobra.Command, args []string) error {
			return app.list(opts)
		},
	}
	addFilterFlags(cmd, opts)
	return cmd
}

func (a *App) list(opts *listOptions) error {
	result, err := a.load()
	if err != nil {
		return err
	}
	concepts := applyFilters(result.Bundle.Concepts, opts.filters())
	sortConcepts(concepts, opts.Sort)
	total := len(concepts)
	concepts = limitConcepts(concepts, opts.Limit, opts.All)
	if a.JSONL {
		items := make([]any, 0, len(concepts))
		for _, concept := range concepts {
			items = append(items, summarize(concept))
		}
		return a.writeJSONL(items)
	}
	if a.JSON {
		return a.writeJSON(opts.command, map[string]any{
			"concepts": summarizeAll(concepts),
			"index":    result.Cache,
			"total":    total,
		}, result.Issues)
	}
	printConceptTable(a, concepts)
	return nil
}

func printConceptTable(a *App, concepts []*okf.Concept) {
	w := tabwriter.NewWriter(a.Out, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, "CONCEPT\tTYPE\tSTATUS\tTRUST\tSTALE\tTITLE")
	for _, concept := range concepts {
		stale := ""
		if concept.Stale {
			stale = "stale"
		}
		titleWidth := a.Width - 60
		if titleWidth < 20 {
			titleWidth = 20
		}
		fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\t%s\n",
			concept.ID,
			concept.Type,
			concept.Status,
			concept.Trust.String(),
			stale,
			a.truncate(concept.Title, titleWidth),
		)
	}
	_ = w.Flush()
}

func newOrphansCmd(app *App) *cobra.Command {
	opts := &listOptions{command: "orphans", Orphan: true}
	cmd := &cobra.Command{
		Use:   "orphans",
		Short: "List concepts with no backlinks",
		RunE:  func(cmd *cobra.Command, args []string) error { return app.list(opts) },
	}
	addFilterFlags(cmd, opts)
	return cmd
}

func newBrokenCmd(app *App) *cobra.Command {
	opts := &listOptions{command: "broken", Broken: true}
	cmd := &cobra.Command{
		Use:   "broken",
		Short: "List concepts with at least one missing link target",
		RunE:  func(cmd *cobra.Command, args []string) error { return app.list(opts) },
	}
	addFilterFlags(cmd, opts)
	return cmd
}

func newStaleCmd(app *App) *cobra.Command {
	opts := &listOptions{command: "stale", Stale: true, Sort: "stale"}
	cmd := &cobra.Command{
		Use:   "stale",
		Short: "List stale concepts",
		RunE:  func(cmd *cobra.Command, args []string) error { return app.list(opts) },
	}
	addFilterFlags(cmd, opts)
	return cmd
}

func newUnverifiedCmd(app *App) *cobra.Command {
	opts := &listOptions{command: "unverified", Unverified: true}
	cmd := &cobra.Command{
		Use:   "unverified",
		Short: "List concepts with no verification",
		RunE:  func(cmd *cobra.Command, args []string) error { return app.list(opts) },
	}
	addFilterFlags(cmd, opts)
	return cmd
}

func newTypesCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "types",
		Short: "Count concepts by type",
		RunE: func(cmd *cobra.Command, args []string) error {
			return app.facet("types", func(c *okf.Concept) []string { return []string{c.Type} })
		},
	}
}

func newTagsCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "tags",
		Short: "Count concepts by tag",
		RunE: func(cmd *cobra.Command, args []string) error {
			return app.facet("tags", func(c *okf.Concept) []string { return c.Tags })
		},
	}
}

func newStatusesCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "statuses",
		Short: "Count concepts by status",
		RunE: func(cmd *cobra.Command, args []string) error {
			return app.facet("statuses", func(c *okf.Concept) []string { return []string{c.Status} })
		},
	}
}

func newTrustCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "trust",
		Short: "Count concepts by trust tier",
		RunE: func(cmd *cobra.Command, args []string) error {
			return app.facet("trust", func(c *okf.Concept) []string { return []string{c.Trust.String()} })
		},
	}
}

type facetEntry struct {
	Value string `json:"value"`
	Count int    `json:"count"`
}

func (a *App) facet(command string, values func(*okf.Concept) []string) error {
	result, err := a.load()
	if err != nil {
		return err
	}
	counts := map[string]int{}
	for _, concept := range result.Bundle.Concepts {
		for _, value := range values(concept) {
			if value = strings.TrimSpace(value); value != "" {
				counts[value]++
			}
		}
	}
	entries := make([]facetEntry, 0, len(counts))
	for value, count := range counts {
		entries = append(entries, facetEntry{Value: value, Count: count})
	}
	sort.SliceStable(entries, func(i, j int) bool {
		if entries[i].Count != entries[j].Count {
			return entries[i].Count > entries[j].Count
		}
		return entries[i].Value < entries[j].Value
	})
	if a.JSONL {
		items := make([]any, 0, len(entries))
		for _, entry := range entries {
			items = append(items, entry)
		}
		return a.writeJSONL(items)
	}
	if a.JSON {
		return a.writeJSON(command, map[string]any{"facets": entries}, result.Issues)
	}
	w := tabwriter.NewWriter(a.Out, 0, 0, 2, ' ', 0)
	for _, entry := range entries {
		fmt.Fprintf(w, "%s\t%d\n", entry.Value, entry.Count)
	}
	return w.Flush()
}
