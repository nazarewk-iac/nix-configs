/*
Copyright © 2025 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"path/filepath"

	"github.com/spf13/cobra"

	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/nix"
	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/secrets"
)

// hostEnsureLuksKeyFilesCmd represents the keyFiles command
var hostEnsureLuksKeyFilesCmd = &cobra.Command{
	Use:     "luks-keyfiles",
	Aliases: []string{"lkf"},
	Short:   "A brief description of your command",
	Long:    ``,
	RunE: func(cmd *cobra.Command, args []string) error {
		var output []struct {
			Name string `json:"name"`
		}
		data, err := nix.EvalFlakeJSON(repoPath, fmt.Sprintf("hosts.%s.kdn.outputs.host.luks-keyfiles", hostName))
		if err != nil {
			return fmt.Errorf("error evaluating LUKS keyfiles output: %w", err)
		}
		err = json.Unmarshal(data, &output)
		if err != nil {
			return fmt.Errorf("error decoding JSON: %w", err)
		}
		for _, entry := range output {
			secretPath := filepath.Join(repoPath, hostSubDir, "luks-keyfiles", fmt.Sprintf("%s.key", entry.Name))
			if secrets.Exists(secretPath) {
				slog.Info("LUKS keyfile already exists", "host", hostName, "Name", entry.Name)
				continue
			}
			key := make([]byte, 2048)
			if _, e := rand.Read(key); e != nil {
				err = errors.Join(err, fmt.Errorf("failed to generate random data: %w", e))
				continue
			}
			if e := secrets.EncryptBytes(secretPath, key); e != nil {
				err = errors.Join(err, fmt.Errorf("error encrypting LUKS keyfile %s: %w", secretPath, e))
				continue
			}
			slog.Info("generated LUKS keyfile", "host", hostName, "keyfile", entry.Name)
		}
		return err
	},
}

func init() {
	hostEnsureCmd.AddCommand(hostEnsureLuksKeyFilesCmd)

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// hostEnsureLuksKeyFilesCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// hostEnsureLuksKeyFilesCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}
