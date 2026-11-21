package cmd

import (
	"errors"
	"flag"
	"fmt"
	"strings"
)

// completionCommands is the command list that every completion script offers.
var completionCommands = []string{"harvest", "extract", "dream", "apply", "run", "status", "completion", "version", "help"}

// completionFlags is the flag list of the whole command tree.
var completionFlags = []string{
	"--data-dir", "--json", "--quiet", "--endpoint", "--allow-host", "--manager", "--bundle",
	"--timeout", "--key-file", "--db", "--source", "--pi-root", "--since", "--project",
	"--limit", "--include-live", "--model", "--merge-model", "--force", "--dry-run",
	"--chunk-chars", "--max-chunks", "--threshold", "--min-sessions", "--proposal", "--yes",
	"--help",
}

func (a *App) runCompletion(args []string) error {
	fs := flag.NewFlagSet("completion", flag.ContinueOnError)
	fs.SetOutput(a.errOut)
	// The shell name is a positional argument, so this command cannot use the shared parser.
	if err := fs.Parse(args); err != nil {
		return &ExitError{Code: 2, Err: err}
	}
	if fs.NArg() != 1 {
		return &ExitError{Code: 2, Err: errors.New("usage: kdn-knowledge completion bash|fish|zsh")}
	}
	script, ok := completionScript(strings.ToLower(fs.Arg(0)))
	if !ok {
		return &ExitError{Code: 2, Err: fmt.Errorf("unsupported shell %q; use bash, fish or zsh", fs.Arg(0))}
	}
	fmt.Fprint(a.out, script)
	return nil
}

func completionScript(shell string) (string, bool) {
	commands := strings.Join(completionCommands, " ")
	flags := strings.Join(completionFlags, " ")
	switch shell {
	case "bash":
		return `# bash completion for kdn-knowledge
_kdn_knowledge() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "` + commands + `" -- "$cur") )
        return 0
    fi
    case "$prev" in
        --data-dir|--bundle|--proposal)
            COMPREPLY=( $(compgen -d -- "$cur") )
            return 0
            ;;
        --model|--merge-model)
            COMPREPLY=( $(compgen -W "` + modelCompletions() + `" -- "$cur") )
            return 0
            ;;
    esac
    COMPREPLY=( $(compgen -W "` + flags + `" -- "$cur") )
    return 0
}
complete -F _kdn_knowledge kdn-knowledge
`, true
	case "fish":
		var builder strings.Builder
		builder.WriteString("# fish completion for kdn-knowledge\n")
		builder.WriteString("complete -c kdn-knowledge -f\n")
		for _, command := range completionCommands {
			fmt.Fprintf(&builder, "complete -c kdn-knowledge -n '__fish_use_subcommand' -a %s\n", command)
		}
		for _, flag := range completionFlags {
			name := strings.TrimPrefix(flag, "--")
			fmt.Fprintf(&builder, "complete -c kdn-knowledge -l %s\n", name)
		}
		return builder.String(), true
	case "zsh":
		return `#compdef kdn-knowledge
_kdn_knowledge() {
    local -a commands flags
    commands=(` + commands + `)
    flags=(` + flags + `)
    if (( CURRENT == 2 )); then
        _describe 'command' commands
    else
        _describe 'flag' flags
    fi
}
compdef _kdn_knowledge kdn-knowledge
`, true
	default:
		return "", false
	}
}

// modelCompletions lists the model ids that the fleet catalogue offers, as a completion hint.
func modelCompletions() string {
	return "lfm2.5-24b-a2b nemotron-3-nano-30b-a3b gemma-4-e4b ministral-3-3b-reasoning qwen3.5-35b-a3b qfn"
}
