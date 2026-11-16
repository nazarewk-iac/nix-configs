package cmd

import (
	"fmt"
	"strings"

	"github.com/spf13/cobra"

	"kdn-okf/internal/index"
	"kdn-okf/internal/okf"
)

// gateCodes is the `doctor --parse-only` set: a concept that fails one of these is unparseable.
var gateCodes = map[string]bool{
	"frontmatter-missing":    true,
	"type-missing":           true,
	"type-not-string":        true,
	"index-reserved-shape":   true,
	"log-reserved-shape":     true,
	"duplicate-concept-id":   true,
	"concept-outside-bundle": true,
}

func newDoctorCmd(app *App) *cobra.Command {
	var (
		parseOnly bool
		ignore    []string
	)
	cmd := &cobra.Command{
		Use:   "doctor",
		Short: "Validate the bundle and report stable issue codes",
		RunE: func(cmd *cobra.Command, args []string) error {
			result, err := app.load()
			if err != nil {
				return err
			}
			issues := append([]okf.Issue{}, result.Issues...)
			issues = append(issues, index.MissingBacklinks(result.Bundle.Concepts)...)
			for _, concept := range result.Bundle.Concepts {
				if len(concept.Backlinks) == 0 {
					issues = append(issues, okf.Issue{
						Severity: okf.SeverityInfo,
						Code:     "orphan",
						Path:     concept.Path,
						Concept:  concept.ID,
						Message:  "no incoming links",
					})
				}
			}
			ignored := map[string]bool{}
			for _, code := range ignore {
				ignored[code] = true
			}
			filtered := make([]okf.Issue, 0, len(issues))
			for _, issue := range issues {
				if !ignored[issue.Code] {
					filtered = append(filtered, issue)
				}
			}
			suppressed := 0
			if parseOnly {
				var gate []okf.Issue
				for _, issue := range filtered {
					if gateCodes[issue.Code] {
						gate = append(gate, issue)
					}
				}
				suppressed = len(filtered) - len(gate)
				filtered = gate
			}
			counts := map[string]int{}
			for _, issue := range filtered {
				counts[issue.Severity]++
			}
			if app.JSONL {
				items := make([]any, 0, len(filtered))
				for _, issue := range filtered {
					items = append(items, issue)
				}
				if err := app.writeJSONL(items); err != nil {
					return err
				}
			} else if app.JSON {
				if err := app.writeJSON("doctor", map[string]any{
					"errors":     counts[okf.SeverityError],
					"warnings":   counts[okf.SeverityWarning],
					"infos":      counts[okf.SeverityInfo],
					"gate":       parseOnly,
					"suppressed": suppressed,
				}, filtered); err != nil {
					return err
				}
			} else {
				printIssues(app, filtered)
				fmt.Fprintf(app.Out, "%d errors, %d warnings, %d infos", counts[okf.SeverityError], counts[okf.SeverityWarning], counts[okf.SeverityInfo])
				if parseOnly {
					fmt.Fprintf(app.Out, " (gate only, %d suppressed)", suppressed)
				}
				fmt.Fprintln(app.Out)
			}
			if parseOnly {
				if counts[okf.SeverityError] > 0 {
					return &ExitError{Code: 1}
				}
				return nil
			}
			if counts[okf.SeverityError] > 0 {
				return &ExitError{Code: 1}
			}
			return nil
		},
	}
	cmd.Flags().BoolVar(&parseOnly, "parse-only", false, "only the parse gate: frontmatter, type, reserved files and IDs")
	cmd.Flags().StringArrayVar(&ignore, "ignore", nil, "ignore an issue code; repeatable")
	return cmd
}

func printIssues(app *App, issues []okf.Issue) {
	for _, issue := range issues {
		location := issue.Path
		if issue.Line > 0 {
			location = fmt.Sprintf("%s:%d", issue.Path, issue.Line)
		}
		if issue.Concept != "" && issue.Path == "" {
			location = issue.Concept
		}
		fmt.Fprintf(app.Out, "%-7s %-22s %s  %s\n", issue.Severity, issue.Code, location, strings.TrimSpace(issue.Message))
	}
}
