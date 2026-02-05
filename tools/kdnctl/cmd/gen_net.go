/*
Copyright © 2025 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"crypto/rand"
	"errors"
	"fmt"
	"net"
	"strconv"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

func RandomIP(network *net.IPNet) (*net.IP, error) {
	prefixBits, _ := network.Mask.Size()
	bytesLen := len(network.IP)

	newIP := make(net.IP, bytesLen)
	copy(newIP, network.IP)

	// Generate random bytes
	newData := make([]byte, bytesLen)
	_, err := rand.Read(newData)
	if err != nil {
		return nil, fmt.Errorf("generatind random bytes: %w", err)
	}

	for i := prefixBits / 8; i < bytesLen; i++ {
		bitPos := i * 8
		mask := byte(0x00)
		if bitPos < prefixBits {
			mask = byte(0xFF) << (8 - (prefixBits - bitPos))
		}
		newByte := newIP[i] & mask
		invertedMask := mask ^ 0xFF
		newByte |= (newData[i] & invertedMask)

		newIP[i] = newByte

	}

	return &newIP, nil
}

func IPToNetwork(ip *net.IP, prefixLen int) *net.IPNet {
	newMask := net.CIDRMask(prefixLen, len(*ip)*8)
	return &net.IPNet{
		IP:   ip.Mask(newMask),
		Mask: newMask,
	}
}

func mkGenIP(isSubnet bool) func(*cobra.Command, []string) error {
	return func(cmd *cobra.Command, args []string) (err error) {
		_, network, err := net.ParseCIDR(viper.GetString("cidr"))
		if err != nil {
			return fmt.Errorf("parsing base CIDR: %w", err)
		}
		basePrefix, _ := network.Mask.Size()
		maxPrefix := 128
		if network.IP.To4() != nil {
			maxPrefix = 32
		}
		for idx, arg := range args {
			prefix, e := strconv.Atoi(arg)
			if e != nil {
				err = errors.Join(err, fmt.Errorf("args[%d]: parsing prefix from %v: %w", idx, arg, e))
				continue
			}
			// handle relative prefix
			if arg[0] == '+' {
				prefix = basePrefix + prefix
			}
			if (isSubnet && prefix <= basePrefix || prefix < basePrefix) || prefix > maxPrefix {
				err = errors.Join(err, fmt.Errorf(
					"args[%d]: requested prefix %d must be between (%d,%d>",
					idx,
					prefix,
					basePrefix,
					maxPrefix,
				))
				continue
			}
			ip, e := RandomIP(network)
			if err != nil {
				err = errors.Join(err, fmt.Errorf("args[%d]: generating random subnet: %w", idx, e))
			}

			if isSubnet {
				fmt.Println(IPToNetwork(ip, prefix))
			} else {
				fmt.Printf("%s/%d\n", ip, prefix)
			}
		}
		return
	}
}

var genSubnetCmd = &cobra.Command{
	Use:     "subnet",
	Aliases: []string{"s"},
	Short:   "TODO1",
	Long:    `TODO2`,
	RunE:    mkGenIP(true),
}

var genIPCmd = &cobra.Command{
	Use:   "ip",
	Short: "TODO1",
	Long:  `TODO2`,
	RunE:  mkGenIP(false),
}

func init() {
	for _, cmd := range []*cobra.Command{genSubnetCmd, genIPCmd} {
		genCmd.AddCommand(cmd)
		cmd.Flags().StringP("cidr", "c", "", "a CIDR (super-net) to generate new subnets in")
		_ = cmd.MarkFlagRequired("cidr")
	}
}
