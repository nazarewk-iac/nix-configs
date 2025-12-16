/*
Copyright © 2025 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/host/bootstrap"
	"github.com/spf13/cobra"
)

// hostEnsureCmd represents the ensure command
var hostBootstrapCmd = &cobra.Command{
	Use:     "bootstrap",
	Aliases: []string{"b"},
	Short:   "TODO",
	Long:    `TODO`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return bootstrap.Bootstrap(repository, host, secretStorage, args)
	},
}

func init() {
	hostCmd.AddCommand(hostBootstrapCmd)

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// hostEnsureCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// hostEnsureCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}
