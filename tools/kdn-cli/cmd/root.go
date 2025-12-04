/*
Copyright © 2025 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"

	"github.com/adrg/xdg"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"

	"github.com/nazarewk-iac/nix-configs/tools/kdn/pkg/log"
)

var (
	AppName    = "kdn"
	CLIName    = fmt.Sprintf("%s-cli", AppName)
	EnvVarName = strings.ReplaceAll(strings.ToUpper(CLIName), "-", "_")
)
var (
	configFile string
	logLevel   string
	logFiles   []string
	repoPath   string
	repoRemote string
)

// rootCmd represents the base command when called without any subcommands
var rootCmd = &cobra.Command{
	Use:   AppName,
	Short: "A brief description of your application",
	Long: `A longer description that spans multiple lines and likely contains
examples and usage of using your application. For example:

Cobra is a CLI library for Go that empowers applications.
This application is a tool to generate the needed files
to quickly create a Cobra application.`,
	// Uncomment the following line if your bare application
	// has an action associated with it:
	// Run: func(cmd *cobra.Command, args []string) { },
	PersistentPreRunE: func(cmd *cobra.Command, args []string) (err error) {
		if err = log.Reconfigure(logFiles, logLevel); err != nil {
			return err
		}
		if err = initializeConfig(cmd); err != nil {
			return err
		}

		var level slog.Level
		level, err = log.ParseLogLevel(logLevel)
		if err != nil {
			return
		}
		log.SetLevel(level)
		return
	},
}

// Execute adds all child commands to the root command and sets flags appropriately.
// This is called by main.main(). It only needs to happen once to the rootCmd.
func Execute() {
	err := rootCmd.Execute()
	if err != nil {
		os.Exit(1)
	}
}

func init() {
	// Here you will define your flags and configuration settings.
	// Cobra supports persistent flags, which, if defined here,
	// will be global for your application.

	// Cobra also supports local flags, which will only run
	// when this action is called directly.
	rootCmd.PersistentFlags().StringVarP(&configFile, "config-file", "c", "", fmt.Sprintf("config file (default locations: ., $HOME/.config/%s/)", CLIName))
	rootCmd.PersistentFlags().StringVarP(&repoRemote, "repo-remote", "r", "https://github.com/nazarewk-iac/nix-configs.git", "")
	rootCmd.PersistentFlags().StringVarP(&repoPath, "repo-path", "p", filepath.Join(xdg.Home, "dev/github.com/nazarewk-iac/nix-configs"), "")
	rootCmd.PersistentFlags().StringVarP(&logLevel, "log-level", "l", "info", "log level")
	rootCmd.PersistentFlags().StringSliceVarP(&logFiles, "log-file", "o", []string{"-"}, "log file, `-` for stderr")
}

func initializeConfig(cmd *cobra.Command) (err error) {
	// 1. Set up Viper to use environment variables.
	viper.SetEnvPrefix(EnvVarName)
	// Allow for nested keys in environment variables (e.g. `MYAPP_DATABASE_HOST`)
	viper.SetEnvKeyReplacer(strings.NewReplacer(".", "*", "-", "*"))
	viper.AutomaticEnv()
	configName := "config"
	configFormat := "toml"
	viper.SetConfigName(configName)
	viper.SetConfigType(configFormat)
	primaryConfigFile := filepath.Join(xdg.ConfigHome, AppName, fmt.Sprintf("%s.%s", configName, configFormat))

	// 2. Handle the configuration file.
	if configFile != "" {
		viper.SetConfigFile(configFile)
		primaryConfigFile = configFile
	}

	// Search for a config file with the name "config" (without extension).
	viper.AddConfigPath(".")
	viper.AddConfigPath(filepath.Dir(primaryConfigFile))
	viper.AddConfigPath(filepath.Join(xdg.Home, fmt.Sprintf(".%s", AppName)))
	for _, path := range xdg.ConfigDirs {
		viper.AddConfigPath(filepath.Join(path, AppName))
	}

	// 3. Read the configuration file.
	// If a config file is found, read it in. We use a robust error check
	// to ignore "file not found" errors, but panic on any other error.
	if err = viper.ReadInConfig(); err != nil {
		// It's okay if the config file doesn't exist.
		var configFileNotFoundError viper.ConfigFileNotFoundError
		if !errors.As(err, &configFileNotFoundError) {
			return err
		}
		viper.SetConfigFile(primaryConfigFile)
	}

	// 4. Bind Cobra flags to Viper.
	// This is the magic that makes the flag values available through Viper.
	// It binds the full flag set of the command passed in.
	err = viper.BindPFlags(cmd.Flags())
	if err != nil {
		return err
	}

	// This is an optional but useful step to debug your config.
	slog.Debug("configuration initialized", "config", viper.ConfigFileUsed())
	return err

}
