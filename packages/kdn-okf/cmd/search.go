package cmd

import (
	"fmt"
	"strings"
	"text/tabwriter"

	"github.com/spf13/cobra"

	"kdn-okf/internal/search"
)

func newSearchCmd(app *App) *cobra.Command {
	var (
		regex   bool
		exact   bool
		scope   string
		limit   int
		typeF   string
		tagF    string
		statusF string
	)
	cmd := &cobra.Command{
		Use:   "search <query...>",
		Short: "Search titles, headings and bodies",
		Args:  cobra.MinimumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			query := strings.Join(args, " ")
			result, err := app.load()
			if err != nil {
				return err
			}
			hits, err := search.Search(result.Bundle, search.Query{
				Text:   query,
				Regex:  regex,
				Exact:  exact,
				Scope:  scope,
				Type:   typeF,
				Tag:    tagF,
				Status: statusF,
				Limit:  limit,
			})
			if err != nil {
				return &ExitError{Code: 2, Err: err}
			}
			if app.JSONL {
				items := make([]any, 0, len(hits))
				for _, hit := range hits {
					items = append(items, hit)
				}
				return app.writeJSONL(items)
			}
			if app.JSON {
				return app.writeJSON("search", map[string]any{"query": query, "hits": hits}, result.Issues)
			}
			w := tabwriter.NewWriter(app.Out, 0, 0, 2, ' ', 0)
			fmt.Fprintln(w, "CONCEPT\tRANGE\tHEADING\tSNIPPET")
			for _, hit := range hits {
				fmt.Fprintf(w, "%s\t%d-%d\t%s\t%s\n",
					hit.ConceptID, hit.StartLine, hit.EndLine, hit.Heading,
					app.truncate(hit.Snippet, app.Width-60))
			}
			return w.Flush()
		},
	}
	flags := cmd.Flags()
	flags.BoolVar(&regex, "regex", false, "treat the query as a regular expression")
	flags.BoolVar(&exact, "exact", false, "case-sensitive literal match")
	flags.StringVar(&scope, "scope", "all", "search scope: title, heading, body or all")
	flags.IntVar(&limit, "limit", 20, "maximum hits")
	flags.StringVar(&typeF, "type", "", "only this type")
	flags.StringVar(&tagF, "tag", "", "only this tag")
	flags.StringVar(&statusF, "status", "", "only this status")
	return cmd
}
