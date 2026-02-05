/*
Copyright © 2025 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
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

	hostCmd.Flags().StringP("hostname", "n", "", "host's name")
	hostCmd.Flags().StringP("address", "a", "", "host's address to handle")
	aliases["name"] = "hostname"
	if err := hostCmd.MarkFlagRequired("hostname"); err != nil {
		panic(err)
	}

	hostCmd.Flags().SetNormalizeFunc(func(f *pflag.FlagSet, name string) pflag.NormalizedName {
		if alias, ok := aliases[name]; ok {
			name = alias
		}
		return pflag.NormalizedName(name)
	})
}
