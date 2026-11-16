package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"
)

const skillID = "kdn-journal"

func newSkillCmd(app *App) *cobra.Command {
	var dir string
	cmd := &cobra.Command{
		Use:   "skill",
		Short: "Print the agent skill bundled with this tool",
		Long: "Print the bundled SKILL.md. Use --dir to install it as\n" +
			"<dir>/" + skillID + "/SKILL.md, the layout an agent harness reads.",
		RunE: func(cmd *cobra.Command, args []string) error {
			if strings.TrimSpace(app.Skill) == "" {
				return fmt.Errorf("this build carries no skill")
			}
			if dir == "" {
				if app.JSON {
					return app.writeJSON("skill", map[string]any{"id": skillID, "markdown": app.Skill}, nil)
				}
				fmt.Fprint(app.Out, app.Skill)
				return nil
			}
			path := filepath.Join(dir, skillID, "SKILL.md")
			if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
				return err
			}
			if err := os.WriteFile(path, []byte(app.Skill), 0o644); err != nil {
				return err
			}
			if app.JSON {
				return app.writeJSON("skill", map[string]any{"id": skillID, "path": path}, nil)
			}
			fmt.Fprintln(app.Out, path)
			return nil
		},
	}
	cmd.Flags().StringVar(&dir, "dir", "", "install into <dir>/"+skillID+"/SKILL.md")
	return cmd
}
