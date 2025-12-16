/*
Copyright © 2025 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"github.com/spf13/cobra"

	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/host/luks"
)

var hostEnsureLuksKeyFilesCmd = &cobra.Command{
	Use:     "luks-keyfiles",
	Aliases: []string{"lkf"},
	Short:   "A brief description of your command",
	Long:    ``,
	RunE: func(cmd *cobra.Command, args []string) error {
		return luks.EnsureLUKSKeyfilesForHost(repository, host, secretStorage)
	},
}

func init() {
	hostEnsureCmd.AddCommand(hostEnsureLuksKeyFilesCmd)
}
