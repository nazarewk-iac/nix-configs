package cli

import (
	"errors"
	"flag"
	"log/slog"
	"slices"
	"strings"
)

type Command struct {
	path        []string
	handleFlags func(fs *flag.FlagSet, args []string)
	subCommands map[string]*Command
	runDefault  func(args []string) (unhandled []string, shouldContinue bool, err error)
}

var ErrNoDefaultCommand = errors.New("there is no default command")

var DefaultRun = func(args []string) (unhandled []string, shouldContinue bool, err error) {
	err = ErrNoDefaultCommand
	return
}
var DefaultHandleFlags = func(fs *flag.FlagSet, args []string) {}

func NewCommand(program []string) *Command {
	c := &Command{
		path:        program,
		subCommands: map[string]*Command{},
		runDefault:  DefaultRun,
		handleFlags: DefaultHandleFlags,
	}
	return c
}

func (c *Command) String() string {
	return strings.Join(c.path, " ")
}

func (c *Command) WithHandleFlags(fun func(fs *flag.FlagSet, args []string)) *Command {
	c.handleFlags = fun
	return c
}
func (c *Command) WithRunDefault(fun func(args []string) (unhandled []string, shouldContinue bool, err error)) *Command {
	c.runDefault = fun
	return c
}

func (c *Command) Register(path []string, prepare func(cmd *Command)) (err error) {
	cur := c
	lastIdx := len(path) - 1
	for idx, subcommand := range path {
		nxt, found := cur.subCommands[subcommand]
		nxtPath := append(cur.path[:], subcommand)
		if !found {
			nxt = NewCommand(nxtPath)
			cur.subCommands[subcommand] = nxt
		}

		if !slices.Equal(nxt.path, nxtPath) {
			slog.Warn("Command.Register() paths do not match", "cur", cur.path, "nxt", nxt.path)
		}
		if idx == lastIdx {
			prepare(nxt)
			cur.subCommands[subcommand] = nxt
			return
		}
		cur = nxt
	}
	return
}

func (c *Command) Execute(args []string) (unhandled []string, shouldContinue bool, err error) {
	shouldContinue = true
	slog.Debug("executing command", "command", c.path, "args", args)
	fs := flag.NewFlagSet(strings.Join(c.path, " "), flag.ExitOnError)
	c.handleFlags(fs, args)
	if !fs.Parsed() {
		_ = fs.Parse(args)
	}
	unhandled = fs.Args()
	for shouldContinue && len(unhandled) > 0 {
		subcommand := unhandled[0]
		unhandled = unhandled[1:]
		if next, ok := c.subCommands[subcommand]; ok {
			unhandled, shouldContinue, err = next.Execute(unhandled)
		} else {
			slog.Warn("subcommand not found", "path", c.path, "subcommand", subcommand)
		}
	}
	if shouldContinue {
		return c.runDefault(unhandled)
	}
	return
}
