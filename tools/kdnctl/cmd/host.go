/*
Copyright © 2025 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"path/filepath"

	"github.com/spf13/cobra"
	"github.com/spf13/pflag"
)

var (
	hostName   string
	hostDir    string
	hostSubDir string
)

// hostCmd represents the host command
var hostCmd = &cobra.Command{
	Use:     "host",
	Aliases: []string{"h"},
	Short:   "A brief description of your command",
	Long: `A longer description that spans multiple lines and likely contains examples
and usage of using your command. For example:

Cobra is a CLI library for Go that empowers applications.
This application is a tool to generate the needed files
to quickly create a Cobra application.`,
	PersistentPreRunE: func(cmd *cobra.Command, args []string) (err error) {
		if err = rootCmd.PersistentPreRunE(cmd, args); err != nil {
			return err
		}
		hostSubDir = filepath.Join("hosts", hostName)
		hostDir = filepath.Join(repoPath, hostSubDir)
		return
	},
}

func init() {
	aliases := make(map[string]string)
	rootCmd.AddCommand(hostCmd)

	hostCmd.PersistentFlags().StringVarP(&hostName, "hostname", "n", "", "hostname to handle")
	aliases["Name"] = "hostname"
	if err := hostCmd.MarkPersistentFlagRequired("hostname"); err != nil {
		panic(err)
	}

	hostCmd.PersistentFlags().SetNormalizeFunc(func(f *pflag.FlagSet, name string) pflag.NormalizedName {
		if alias, ok := aliases[name]; ok {
			name = alias
		}
		return pflag.NormalizedName(name)
	})
}
