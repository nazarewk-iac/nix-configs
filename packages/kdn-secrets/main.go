package main

import (
	"encoding/json"
	"errors"
	"flag"
	"github.com/nazarewk-iac/nix-configs/packages/kdn-secrets/encrypted"
	"github.com/nazarewk-iac/nix-configs/packages/kdn-secrets/state"
	"log/slog"
	"os"
	"path/filepath"
	"strings"

	"github.com/nazarewk-iac/nix-configs/packages/kdn-secrets/cli"
)

var ProgramDir = filepath.Join("kdn", "secrets")

var logLevel = new(slog.LevelVar)

func outputJSON(v any) (err error) {
	var marshalled []byte
	marshalled, err = json.Marshal(v)
	_, err = os.Stdout.Write(marshalled)
	return
}

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{
		Level: logLevel,
	})))
	logLevel.Set(slog.LevelInfo)
	if err := os.Setenv("PATH", strings.Join([]string{
		/* EXTRA_PATH_PLACEHOLDER */
		os.Getenv("PATH"),
	}, string(os.PathListSeparator))); err != nil {
		slog.Error("failed to set $PATH", "error", err)
		os.Exit(1)
	}

	s := state.NewState()

	rootCmd := cli.NewCommand(os.Args[:1]).WithHandleFlags(func(fs *flag.FlagSet, args []string) {
		skipXDG := fs.Bool("no-xdg", false, "search in XDG_CONFIG_DIRS & XDG_CONFIG_HOME")
		_ = fs.Parse(args)
		if !*skipXDG {
			err := s.AppendXDGConfigDirs()
			if err != nil {
				slog.Error("failed to retrieve user config directories: %v", err)
				os.Exit(1)
			}
		}
	})
	var err error
	err = errors.Join(err, rootCmd.Register(
		[]string{"config", "list"},
		func(c *cli.Command) {
			c.WithRunDefault(func(args []string) (unhandled []string, shouldContinue bool, err error) {
				unhandled = args

				var outputs []string
				var errs []error
				for ef, err := range encrypted.IterEncrypted(s.ConfigSearchDirs) {
					if err == nil && ef == nil {
						slog.Error("invalid IterEncrypted() s")
						continue
					}
					if err != nil {
						errs = append(errs, err)
						continue
					}
					outputs = append(outputs, ef.Path)
				}
				if len(errs) > 0 {
					err = errors.Join(errs...)
					return
				}
				err = outputJSON(outputs)
				return
			})
		}))
	err = errors.Join(err, rootCmd.Register(
		[]string{"config", "dir", "list"},
		func(c *cli.Command) {
			c.WithRunDefault(func(args []string) (unhandled []string, shouldContinue bool, err error) {
				unhandled = args
				err = outputJSON(s.ConfigSearchDirs)
				return
			})
		}))
	_, _, err = rootCmd.Execute(os.Args[1:])
	if err != nil {
		slog.Error("error while executing", "error", err)
		os.Exit(1)
	}
}
