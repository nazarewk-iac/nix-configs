/*
Copyright © 2025 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"github.com/spf13/cobra"
)

// hostCmd represents the host command
var genCmd = &cobra.Command{
	Use:     "gen",
	Aliases: []string{"g"},
	Short:   "TODO",
	Long:    `TODO`,
}

func init() {
	rootCmd.AddCommand(genCmd)
}
