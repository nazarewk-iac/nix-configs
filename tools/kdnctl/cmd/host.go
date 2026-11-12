/*
Copyright © 2025 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"fmt"
	hostmod "github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/host"
	"github.com/spf13/cobra"
	"github.com/spf13/pflag"
	"github.com/spf13/viper"
)

var host *hostmod.Host

// hostCmd represents the host command
var hostCmd = &cobra.Command{
	Use:     "host",
	Aliases: []string{"h"},
	Short:   "TODO",
	Long:    `TODO`,
	PersistentPreRunE: func(cmd *cobra.Command, args []string) (err error) {
		if err = rootCmd.PersistentPreRunE(cmd, args); err != nil {
			return err
		}
		hostName := viper.GetString("hostname")

		if hostName == "" {
			// `--all` replaces the single host with the set of hosts that have a committed key, so
			// the subcommand runs once per host and `host` stays nil.
			if all, _ := cmd.Flags().GetBool("all"); all {
				return nil
			}
			return fmt.Errorf("host: no hostname configured; pass --hostname before the subcommand or set `hostname` in the config file")
		}
		address := viper.GetString("address")
		if address == "" {
			address = hostName
		}
		host = hostmod.New(hostName, address)
		return
	},
}

func init() {
	aliases := make(map[string]string)
	rootCmd.AddCommand(hostCmd)

	// Persistent, not local: `host` is only a grouping command, so every real invocation is a
	// subcommand (`host ensure ssh-host-keys`, `host bootstrap`, ...). A flag registered on
	// `hostCmd.Flags()` is parsed only for `kdnctl host` itself, and a subcommand then rejects it
	// with "unknown flag: --hostname".
	hostCmd.PersistentFlags().StringP("hostname", "n", "", "host's name")
	hostCmd.PersistentFlags().StringP("address", "a", "", "host's address to handle")
	aliases["name"] = "hostname"
	// Not `MarkPersistentFlagRequired`: `--all` runs without a hostname, and the check lives in
	// `PersistentPreRunE`, which can see the leaf's own flags.

	// `SetGlobalNormalizationFunc` installs the alias on the inherited flag set too. Setting it
	// with `Flags().SetNormalizeFunc` normalized only `host`'s own parse, so `--name` was unknown
	// to the subcommands that actually run.
	hostCmd.SetGlobalNormalizationFunc(func(f *pflag.FlagSet, name string) pflag.NormalizedName {
		if alias, ok := aliases[name]; ok {
			name = alias
		}
		return pflag.NormalizedName(name)
	})
}
