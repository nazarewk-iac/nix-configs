package cmd

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"sort"
	"strings"
	"syscall"
	"text/tabwriter"
	"time"

	"github.com/spf13/cobra"

	"kdn-audio/internal/audio"
	"kdn-audio/internal/combine"
	"kdn-audio/internal/pipewire"
	"kdn-audio/internal/profile"
	"kdn-audio/internal/tui"
)

type sinkView struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Kind        string `json:"kind"`
	State       string `json:"state"`
	Detail      string `json:"detail,omitempty"`
	MAC         string `json:"mac,omitempty"`
	NodeID      int    `json:"node_id"`
}

func sinkViews(sinks []pipewire.Sink) []sinkView {
	views := make([]sinkView, 0, len(sinks))
	for _, sink := range sinks {
		views = append(views, sinkView{
			ID:          sink.ID(),
			Name:        sink.Name,
			Description: sink.Description,
			Kind:        sink.Kind(),
			State:       sink.State,
			Detail:      sink.Detail(),
			MAC:         sink.MAC(),
			NodeID:      sink.NodeID,
		})
	}
	return views
}

type groupView struct {
	SinkName        string   `json:"sink_name"`
	Title           string   `json:"title"`
	Members         []string `json:"members"`
	MissingMembers  []string `json:"missing_members,omitempty"`
	Profile         string   `json:"profile,omitempty"`
	Default         bool     `json:"default"`
	PreviousDefault string   `json:"previous_default,omitempty"`
	CreatedAt       string   `json:"created_at,omitempty"`
}

func groupViews(groups []combine.Group, sinks []pipewire.Sink) []groupView {
	views := make([]groupView, 0, len(groups))
	for _, group := range groups {
		view := groupView{
			SinkName:        group.SinkName,
			Title:           group.Title,
			Members:         group.Members,
			MissingMembers:  combine.MissingMembers(group, sinks),
			Profile:         group.Profile,
			Default:         group.Default,
			PreviousDefault: group.PreviousDefault,
		}
		if !group.CreatedAt.IsZero() {
			view.CreatedAt = group.CreatedAt.Format(time.RFC3339)
		}
		views = append(views, view)
	}
	return views
}

func newDevicesCmd(app *App) *cobra.Command {
	var ids bool
	command := &cobra.Command{
		Use:     "devices",
		Aliases: []string{"list", "ls"},
		Short:   "List audio outputs with their stable ids",
		Long: `List every audio output, its stable id, its type and its state.

The id is what a profile stores: a Bluetooth address, an ALSA card and profile, or a node name.
Every command accepts an id, a device name, a node name, a Bluetooth address, or any
unambiguous part of one.`,
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			sinks, err := app.Manager.Sinks()
			if err != nil {
				return err
			}
			if ids {
				for _, sink := range sinks {
					fmt.Fprintln(app.Out, sink.ID())
				}
				return nil
			}
			if app.JSON {
				return app.writeJSON("devices", map[string]any{"sinks": sinkViews(sinks)})
			}
			writer := tabwriter.NewWriter(app.Out, 0, 0, 2, ' ', 0)
			fmt.Fprintln(writer, "ID\tNAME\tTYPE\tSTATE")
			for _, sink := range sinks {
				fmt.Fprintf(writer, "%s\t%s\t%s\t%s\n", sink.ID(), sink.Description, sink.Kind(), strings.ToLower(sink.State))
			}
			return writer.Flush()
		},
	}
	command.Flags().BoolVar(&ids, "ids", false, "print the id of every output, one per line")
	return command
}

func newShowCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "show OUTPUT",
		Short: "Show every property of one audio output",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			sinks, err := app.Manager.ResolveSinks(args)
			if err != nil {
				return err
			}
			sink := sinks[0]
			if app.JSON {
				return app.writeJSON("show", sinkViews(sinks)[0])
			}
			fmt.Fprintf(app.Out, "id:          %s\n", sink.ID())
			fmt.Fprintf(app.Out, "name:        %s\n", sink.Name)
			fmt.Fprintf(app.Out, "description: %s\n", sink.Description)
			fmt.Fprintf(app.Out, "kind:        %s\n", sink.Kind())
			fmt.Fprintf(app.Out, "state:       %s\n", sink.State)
			fmt.Fprintf(app.Out, "node id:     %d\n", sink.NodeID)
			if mac := sink.MAC(); mac != "" {
				fmt.Fprintf(app.Out, "address:     %s\n", mac)
			}
			keys := make([]string, 0, len(sink.Props))
			for key := range sink.Props {
				keys = append(keys, key)
			}
			sort.Strings(keys)
			fmt.Fprintln(app.Out, "properties:")
			for _, key := range keys {
				fmt.Fprintf(app.Out, "  %s=%s\n", key, sink.Props[key])
			}
			return nil
		},
	}
}

func newCreateCmd(app *App) *cobra.Command {
	var (
		name        string
		makeDefault bool
		moveStreams bool
		connect     bool
	)
	command := &cobra.Command{
		Use:   "create --name NAME OUTPUT...",
		Short: "Join several audio outputs into one virtual output",
		Long: `Join two or more audio outputs into one virtual output.

Each OUTPUT is a device id, a device name, a node name, a Bluetooth address, or any unambiguous
part of one.

Joining changes no routing on its own: the audio that plays now stays where it plays, and the
default output stays as it is. Pass --default to send new audio to the joined output, and
--move-streams to move the audio that plays now.`,
		Example: `  kdn-audio create --name "Both Ears" Earmuffs JBL
  kdn-audio create --connect --name Both --default --move-streams Earmuffs "JBL Endurance Peak 4"
  kdn-audio create --name Desk "alsa:pci-0000_07_00.6/analog-stereo" "alsa:pci-0000_03_00.1/hdmi-stereo"`,
		Args: cobra.MinimumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			created, err := app.Manager.Create(audio.CreateOptions{
				Title:       name,
				Members:     args,
				MakeDefault: makeDefault,
				MoveStreams: moveStreams,
				Connect:     connect,
			})
			if err != nil {
				return err
			}
			if app.JSON {
				return app.writeJSON("create", map[string]any{
					"group":             groupViews([]combine.Group{created.Group}, nil)[0],
					"moved_streams":     created.MovedStreams,
					"inherited_default": created.InheritedDefault,
					"warnings":          created.Warnings,
				})
			}
			fmt.Fprintf(app.Out, "joined %q: %s\n", created.Group.Title, strings.Join(created.MemberTitles, " + "))
			switch {
			case created.InheritedDefault:
				fmt.Fprintf(app.Out, "default output: %s (kept from the join it replaced)\n", created.Group.Title)
			case created.Group.Default:
				fmt.Fprintf(app.Out, "default output: %s\n", created.Group.Title)
			}
			if created.MovedStreams > 0 {
				fmt.Fprintf(app.Out, "moved streams: %d\n", created.MovedStreams)
			}
			if !created.Group.Default && created.MovedStreams == 0 {
				fmt.Fprintf(app.Out, "routing unchanged: pick %q in the app, or pass --default and --move-streams\n", created.Group.Title)
			}
			for _, warning := range created.Warnings {
				fmt.Fprintf(app.Err, "kdn-audio: warning: %s\n", warning)
			}
			fmt.Fprintf(app.Out, "remove with: kdn-audio remove %q\n", created.Group.Title)
			return nil
		},
	}
	command.Flags().StringVarP(&name, "name", "n", "", "name of the joined output (default: the member names)")
	command.Flags().BoolVar(&makeDefault, "default", false, "make the joined output the default")
	command.Flags().BoolVar(&moveStreams, "move-streams", false, "move the streams that play now to the joined output")
	command.Flags().BoolVar(&connect, "connect", false, "connect a matching paired Bluetooth device when an output is missing")
	return command
}

func newRemoveCmd(app *App) *cobra.Command {
	var all bool
	command := &cobra.Command{
		Use:     "remove NAME...",
		Aliases: []string{"unlink"},
		Short:   "Remove a joined output",
		Long:    "Remove one joined output. The default output goes back to what it was before the join.",
		RunE: func(cmd *cobra.Command, args []string) error {
			if all {
				return unlinkAll(app)
			}
			if len(args) == 0 {
				return fmt.Errorf("name at least one joined output, or pass --all")
			}
			removed := make([]string, 0, len(args))
			for _, pattern := range args {
				title, err := app.Manager.Unlink(pattern)
				if err != nil {
					return err
				}
				removed = append(removed, title)
			}
			if app.JSON {
				return app.writeJSON("remove", map[string]any{"removed": removed})
			}
			for _, title := range removed {
				fmt.Fprintf(app.Out, "unlinked %q\n", title)
			}
			return nil
		},
	}
	command.Flags().BoolVar(&all, "all", false, "remove every joined output (the same as `kdn-audio unlink-all`)")
	return command
}

func newUnlinkAllCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "unlink-all",
		Short: "Remove every joined output",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return unlinkAll(app)
		},
	}
}

func unlinkAll(app *App) error {
	titles, err := app.Manager.UnlinkAll()
	if err != nil {
		return err
	}
	if app.JSON {
		return app.writeJSON("unlink-all", map[string]any{"removed": titles})
	}
	if len(titles) == 0 {
		fmt.Fprintln(app.Out, "no joined output to remove")
		return nil
	}
	for _, title := range titles {
		fmt.Fprintf(app.Out, "unlinked %q\n", title)
	}
	return nil
}

func newStatusCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "status",
		Short: "Show the joined outputs and the active profile",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			groups, err := app.Manager.Groups()
			if err != nil {
				return err
			}
			sinks, err := app.Manager.Sinks()
			if err != nil {
				return err
			}
			active, hasActive, err := app.Manager.ActiveProfile()
			if err != nil {
				return err
			}
			if app.JSON {
				data := map[string]any{"groups": groupViews(groups, sinks)}
				if hasActive {
					data["active_profile"] = active.Profile
				}
				return app.writeJSON("status", data)
			}
			if len(groups) == 0 {
				fmt.Fprintln(app.Out, "no joined output")
				if profiles, err := app.Manager.Profiles(); err == nil && len(profiles) > 0 {
					best, _, matched, matchErr := app.Manager.SelectProfile(sinks)
					if matchErr == nil && matched {
						fmt.Fprintf(app.Out, "profile %q matches now; `kdn-audio profiles apply %q` joins it\n", best.Name, best.Name)
					} else {
						fmt.Fprintf(app.Out, "%d profile(s) stored, none matches now; see `kdn-audio profiles list`\n", len(profiles))
					}
				}
				return nil
			}
			writer := tabwriter.NewWriter(app.Out, 0, 0, 2, ' ', 0)
			fmt.Fprintln(writer, "NAME\tMEMBERS\tSTATE\tPROFILE\tCREATED")
			for _, group := range groups {
				state := "joined"
				if group.Default {
					state = "default"
				}
				if missing := combine.MissingMembers(group, sinks); len(missing) > 0 {
					ids := make([]string, 0, len(missing))
					for _, member := range missing {
						ids = append(ids, pipewire.IDForNodeName(member))
					}
					state += ", missing " + strings.Join(ids, ", ")
				}
				created := "-"
				if !group.CreatedAt.IsZero() {
					created = group.CreatedAt.Local().Format("2006-01-02 15:04:05")
				}
				profileName := group.Profile
				if profileName == "" {
					profileName = "-"
				}
				fmt.Fprintf(writer, "%s\t%s\t%s\t%s\t%s\n",
					group.Title, strings.Join(describeMembers(group.Members, sinks), ", "), state, profileName, created)
			}
			return writer.Flush()
		},
	}
}

// describeMembers turns member node names into descriptions where the output still exists.
func describeMembers(members []string, sinks []pipewire.Sink) []string {
	described := make([]string, 0, len(members))
	for _, member := range members {
		name := member
		for _, sink := range sinks {
			if sink.Name == member {
				name = sink.Description
				break
			}
		}
		described = append(described, name)
	}
	return described
}

func newConnectCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "connect [DEVICE...]",
		Short: "Connect paired Bluetooth audio devices",
		Long: `Connect paired Bluetooth audio devices that are currently off.

Without an argument every paired audio device is connected. Each DEVICE is a device name, a
Bluetooth address, or any unambiguous part of one.`,
		RunE: func(cmd *cobra.Command, args []string) error {
			results := app.Manager.Connect(args)
			if app.JSON {
				views := make([]map[string]any, 0, len(results))
				for _, result := range results {
					view := map[string]any{
						"name": result.Device.Name,
						"mac":  result.Device.MAC,
						"sink": result.Sink,
					}
					if result.Err != nil {
						view["error"] = result.Err.Error()
					}
					views = append(views, view)
				}
				return app.writeJSON("connect", map[string]any{"devices": views})
			}
			if len(results) == 0 {
				fmt.Fprintln(app.Out, "every paired Bluetooth audio device is already connected")
				return nil
			}
			failed := false
			for _, result := range results {
				switch {
				case result.Err != nil:
					failed = true
					fmt.Fprintf(app.Err, "kdn-audio: %s: %v\n", result.Device.Name, result.Err)
				default:
					fmt.Fprintf(app.Out, "connected %s (%s) as %s\n", result.Device.Name, result.Device.MAC, result.Sink)
				}
			}
			if failed {
				return &ExitError{Code: 1}
			}
			return nil
		},
	}
}

type profileView struct {
	Name        string   `json:"name"`
	Description string   `json:"description,omitempty"`
	Priority    int      `json:"priority"`
	Outputs     []string `json:"outputs"`
	Absent      []string `json:"absent,omitempty"`
	Default     bool     `json:"default"`
	MoveStreams bool     `json:"move_streams"`
	Matches     bool     `json:"matches"`
	Active      bool     `json:"active"`
	Path        string   `json:"path"`
}

func newProfilesCmd(app *App) *cobra.Command {
	command := &cobra.Command{
		Use:   "profiles",
		Short: "Manage the stored device-mix profiles",
		Long: `A profile is one joined output plus the device mix that turns it on.

Profiles live as YAML files in ` + pipewire.ConfigDir() + `. ` + "`kdn-audio daemon`" + ` applies the
highest-priority profile whose outputs are all connected, and removes the profile joins that no
longer apply. A join made by hand is never touched.`,
	}
	command.AddCommand(
		newProfilesListCmd(app),
		newProfilesShowCmd(app),
		newProfilesSaveCmd(app),
		newProfilesApplyCmd(app),
		newProfilesRemoveCmd(app),
		newProfilesActiveCmd(app),
		newProfilesCheckCmd(app),
		newProfilesDirCmd(app),
	)
	return command
}

func (a *App) profileViews() ([]profileView, error) {
	profiles, err := a.Manager.Profiles()
	if err != nil {
		return nil, err
	}
	sinks, err := a.Manager.Sinks()
	if err != nil {
		return nil, err
	}
	active, hasActive, err := a.Manager.ActiveProfile()
	if err != nil {
		return nil, err
	}
	views := make([]profileView, 0, len(profiles))
	for _, p := range profiles {
		matches, _, err := a.Manager.Match(p, sinks)
		if err != nil {
			matches = false
		}
		views = append(views, profileView{
			Name:        p.Name,
			Description: p.Description,
			Priority:    p.Priority,
			Outputs:     p.Outputs,
			Absent:      p.Absent,
			Default:     p.Default,
			MoveStreams: p.MoveStreams,
			Matches:     matches,
			Active:      hasActive && strings.EqualFold(active.Profile, p.Name),
			Path:        p.Path,
		})
	}
	return views, nil
}

func newProfilesListCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "list",
		Short: "List the profiles",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			views, err := app.profileViews()
			if err != nil {
				return err
			}
			if app.JSON {
				return app.writeJSON("profiles-list", map[string]any{"profiles": views})
			}
			if len(views) == 0 {
				fmt.Fprintf(app.Out, "no profile in %s\n", app.Manager.ProfileDir())
				return nil
			}
			sinks, err := app.Manager.Sinks()
			if err != nil {
				return err
			}
			writer := tabwriter.NewWriter(app.Out, 0, 0, 2, ' ', 0)
			fmt.Fprintln(writer, "NAME\tPRIORITY\tMATCH\tACTIVE\tOUTPUTS")
			for _, view := range views {
				match := "no"
				if view.Matches {
					match = "yes"
				}
				active := "-"
				if view.Active {
					active = "active"
				}
				fmt.Fprintf(writer, "%s\t%d\t%s\t%s\t%s\n",
					view.Name, view.Priority, match, active, strings.Join(describeIDs(view.Outputs, sinks), " + "))
			}
			return writer.Flush()
		},
	}
}

func describeIDs(ids []string, sinks []pipewire.Sink) []string {
	described := make([]string, 0, len(ids))
	for _, id := range ids {
		name := id
		for _, sink := range sinks {
			if strings.EqualFold(sink.ID(), id) || strings.EqualFold(sink.Name, id) || strings.EqualFold(sink.Description, id) {
				name = sink.Description + " (" + sink.ID() + ")"
				break
			}
		}
		described = append(described, name)
	}
	return described
}

func newProfilesShowCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "show NAME",
		Short: "Show one profile",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			views, err := app.profileViews()
			if err != nil {
				return err
			}
			for _, view := range views {
				if !strings.EqualFold(view.Name, args[0]) {
					continue
				}
				if app.JSON {
					return app.writeJSON("profiles-show", view)
				}
				fmt.Fprintf(app.Out, "name:        %s\n", view.Name)
				if view.Description != "" {
					fmt.Fprintf(app.Out, "description: %s\n", view.Description)
				}
				fmt.Fprintf(app.Out, "priority:    %d\n", view.Priority)
				fmt.Fprintf(app.Out, "matches now: %t\n", view.Matches)
				fmt.Fprintf(app.Out, "active:      %t\n", view.Active)
				fmt.Fprintf(app.Out, "default:     %t\n", view.Default)
				fmt.Fprintf(app.Out, "move:        %t\n", view.MoveStreams)
				fmt.Fprintf(app.Out, "file:        %s\n", view.Path)
				fmt.Fprintln(app.Out, "outputs:")
				for _, output := range view.Outputs {
					fmt.Fprintf(app.Out, "  %s\n", output)
				}
				for _, absent := range view.Absent {
					fmt.Fprintf(app.Out, "  not %s\n", absent)
				}
				return nil
			}
			return fmt.Errorf("no profile named %q", args[0])
		},
	}
}

func newProfilesSaveCmd(app *App) *cobra.Command {
	var (
		outputs     []string
		absent      []string
		description string
		priority    int
		makeDefault bool
		moveStreams bool
	)
	command := &cobra.Command{
		Use:   "save NAME --output DEVICE --output DEVICE",
		Short: "Write a profile to the profile directory",
		Long: `Write a profile file. Each --output takes a device id, a name, or any unambiguous part of one;
the ids are stored as given, so resolve them first with ` + "`kdn-audio devices`" + `.`,
		Example: `  kdn-audio profiles save "Both Ears" \
    --output bt:60:AB:D2:77:07:56 --output bt:38:D5:18:B6:64:93 --default`,
		Args: cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			p := profile.Profile{
				Name:        args[0],
				Description: description,
				Priority:    priority,
				Outputs:     app.resolveIDs(splitList(outputs)),
				Absent:      app.resolveIDs(splitList(absent)),
				Default:     makeDefault,
				MoveStreams: moveStreams,
			}
			path := profile.PathFor(app.Manager.ProfileDir(), p.Name)
			_, statErr := os.Stat(path)
			replaced := statErr == nil
			if _, err := p.Save(app.Manager.ProfileDir()); err != nil {
				return err
			}
			if app.JSON {
				return app.writeJSON("profiles-save", map[string]any{"path": path, "profile": p})
			}
			verb := "wrote"
			if replaced {
				verb = "replaced"
			}
			fmt.Fprintf(app.Out, "%s %s\n", verb, path)
			fmt.Fprintf(app.Out, "activate with: kdn-audio profiles apply %q\n", p.Name)
			return nil
		},
	}
	command.Flags().StringArrayVar(&outputs, "output", nil, "device id or name (repeatable, comma separated)")
	command.Flags().StringArrayVar(&absent, "absent", nil, "device whose presence blocks the profile (repeatable)")
	command.Flags().StringVar(&description, "description", "", "free text")
	command.Flags().IntVar(&priority, "priority", 0, "higher wins when several profiles match")
	command.Flags().BoolVar(&makeDefault, "default", false, "make the join the default output")
	command.Flags().BoolVar(&moveStreams, "move-streams", false, "move the playing streams when the profile activates")
	return command
}

// resolveIDs turns each device spelling into its stable id.
//
// A profile must keep working after PipeWire renumbers its nodes, so a name is stored as the id
// it resolves to now. A device that is simply off keeps the spelling the user gave.
func (a *App) resolveIDs(patterns []string) []string {
	ids := make([]string, 0, len(patterns))
	for _, pattern := range patterns {
		sinks, err := a.Manager.ResolveSinks([]string{pattern})
		if err != nil {
			fmt.Fprintf(a.Err, "kdn-audio: warning: %q does not resolve now; stored as given\n", pattern)
			ids = append(ids, pattern)
			continue
		}
		ids = append(ids, sinks[0].ID())
	}
	return ids
}

func splitList(values []string) []string {
	final := []string{}
	for _, value := range values {
		for _, part := range strings.Split(value, ",") {
			if part = strings.TrimSpace(part); part != "" {
				final = append(final, part)
			}
		}
	}
	return final
}

func newProfilesApplyCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "apply NAME",
		Short: "Activate one profile now",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			created, err := app.Manager.ApplyProfile(args[0])
			if err != nil {
				return err
			}
			if app.JSON {
				return app.writeJSON("profiles-apply", groupViews([]combine.Group{created.Group}, nil)[0])
			}
			fmt.Fprintf(app.Out, "activated profile %q as %q\n", created.Group.Profile, created.Group.Title)
			if created.Group.Default {
				fmt.Fprintf(app.Out, "default output: %s\n", created.Group.Title)
			}
			return nil
		},
	}
}

func newProfilesRemoveCmd(app *App) *cobra.Command {
	var all bool
	command := &cobra.Command{
		Use:     "remove NAME...",
		Aliases: []string{"rm", "delete"},
		Short:   "Delete stored profiles",
		Args:    cobra.ArbitraryArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			profiles, err := app.Manager.Profiles()
			if err != nil {
				return err
			}
			if all {
				if len(profiles) == 0 {
					fmt.Fprintf(app.Out, "no profile in %s\n", app.Manager.ProfileDir())
					return nil
				}
				removed := make([]string, 0, len(profiles))
				for _, p := range profiles {
					if err := os.Remove(p.Path); err != nil {
						return err
					}
					removed = append(removed, p.Path)
				}
				if app.JSON {
					return app.writeJSON("profiles-remove", map[string]any{"removed": removed})
				}
				for _, path := range removed {
					fmt.Fprintf(app.Out, "removed %s\n", path)
				}
				return nil
			}
			if len(args) == 0 {
				return fmt.Errorf("name at least one profile, or pass --all")
			}
			removed := make([]string, 0, len(args))
			for _, name := range args {
				chosen, ok := profile.Find(profiles, name)
				if !ok {
					return fmt.Errorf("no profile named %q in %s", name, app.Manager.ProfileDir())
				}
				if err := os.Remove(chosen.Path); err != nil {
					return err
				}
				removed = append(removed, chosen.Path)
			}
			if app.JSON {
				return app.writeJSON("profiles-remove", map[string]any{"removed": removed})
			}
			for _, path := range removed {
				fmt.Fprintf(app.Out, "removed %s\n", path)
			}
			return nil
		},
	}
	command.Flags().BoolVar(&all, "all", false, "delete every stored profile")
	return command
}

func newProfilesActiveCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "active",
		Short: "Print the active profile",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			group, ok, err := app.Manager.ActiveProfile()
			if err != nil {
				return err
			}
			if app.JSON {
				if !ok {
					return app.writeJSON("profiles-active", map[string]any{"active": false})
				}
				return app.writeJSON("profiles-active", map[string]any{
					"active": true, "profile": group.Profile, "title": group.Title,
				})
			}
			if !ok {
				fmt.Fprintln(app.Out, "no active profile")
				return nil
			}
			fmt.Fprintf(app.Out, "%s\n", group.Profile)
			return nil
		},
	}
}

func newProfilesCheckCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "check",
		Short: "Check that every profile names a device that exists",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			profiles, err := app.Manager.Profiles()
			if err != nil {
				return err
			}
			sinks, err := app.Manager.Sinks()
			if err != nil {
				return err
			}
			if len(profiles) == 0 {
				fmt.Fprintf(app.Out, "no profile in %s\n", app.Manager.ProfileDir())
				return nil
			}
			missing := 0
			for _, p := range profiles {
				for _, output := range p.Outputs {
					known := false
					for _, sink := range sinks {
						if strings.EqualFold(sink.ID(), output) || strings.EqualFold(sink.Name, output) || strings.EqualFold(sink.Description, output) {
							known = true
							break
						}
					}
					if !known {
						missing++
						fmt.Fprintf(app.Err, "kdn-audio: profile %q names %q, which is not connected now\n", p.Name, output)
					}
				}
			}
			if missing > 0 {
				fmt.Fprintf(app.Err, "kdn-audio: %d output(s) not connected; a profile is fine when they are simply off\n", missing)
			}
			return nil
		},
	}
}

func newProfilesDirCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "dir",
		Short: "Print the profile directory",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Fprintln(app.Out, app.Manager.ProfileDir())
			return nil
		},
	}
}

func newDaemonCmd(app *App) *cobra.Command {
	var interval time.Duration
	var once bool
	command := &cobra.Command{
		Use:   "daemon",
		Short: "Apply the profiles whenever the device mix changes",
		Long: `Watch the graph and keep the best matching profile active.

Every interval the highest-priority profile whose outputs are all connected is applied, and the
profile joins that no longer apply are removed. Joins made by hand are never touched. Run it as a
systemd user service; --once applies one pass and exits.`,
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			if once {
				activation, err := app.Manager.AutoActivate()
				if err != nil {
					return err
				}
				if app.JSON {
					return app.writeJSON("daemon", activation)
				}
				switch {
				case activation.Created:
					fmt.Fprintf(app.Out, "activated profile %q as %q\n", activation.Profile, activation.Title)
				case len(activation.Removed) > 0:
					fmt.Fprintf(app.Out, "removed %s\n", strings.Join(activation.Removed, ", "))
				case activation.Skipped != "":
					fmt.Fprintf(app.Out, "no change: %s\n", activation.Skipped)
				}
				return nil
			}
			ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
			defer stop()
			return app.Manager.Daemon(ctx, interval)
		},
	}
	command.Flags().DurationVar(&interval, "interval", 2*time.Second, "how often to check the device mix")
	command.Flags().BoolVar(&once, "once", false, "apply one pass and exit")
	return command
}

func newTUICmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "tui",
		Short: "Join and unlink outputs interactively",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return tui.Run(app.Manager)
		},
	}
}

func newHostCmd(app *App) *cobra.Command {
	var (
		sinkName        string
		title           string
		members         []string
		profileName     string
		previousDefault string
	)
	command := &cobra.Command{
		Use:    "host",
		Hidden: true,
		Short:  "Host one combine stream (used by the transient service)",
		Args:   cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			if sinkName == "" || len(members) < 2 {
				return fmt.Errorf("host needs --sink-name and at least two --member")
			}
			return pipewire.Host(pipewire.JoinSpec{
				SinkName:        sinkName,
				Title:           title,
				Members:         members,
				Profile:         profileName,
				PreviousDefault: previousDefault,
			}, app.Now(), app.Out, app.Err)
		},
	}
	command.Flags().StringVar(&sinkName, "sink-name", "", "node name of the joined output")
	command.Flags().StringVar(&title, "title", "", "displayed name of the joined output")
	command.Flags().StringArrayVar(&members, "member", nil, "node name of one member (repeatable)")
	command.Flags().StringVar(&profileName, "profile", "", "profile that asked for this join")
	command.Flags().StringVar(&previousDefault, "previous-default", "", "default output before the join")
	return command
}

func newVersionCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Print the version",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Fprintln(app.Out, app.Version)
			return nil
		},
	}
}
