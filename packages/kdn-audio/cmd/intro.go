package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

// introText is the plain-language guide. It is printed by `kdn-audio intro` and named by the
// root help, so a first-time reader never has to read the command reference to start.
const introText = `kdn-audio, in plain words

WHAT IT DOES
  An output is a device that makes sound: speakers, headphones, earbuds.
  kdn-audio adds one extra output that plays the same audio on several
  devices at once. It calls that extra output a join.

SEE YOUR OUTPUTS
  kdn-audio devices

    ID                                NAME                   TYPE
    bt:60:AB:D2:77:07:56              Earmuffs               bluetooth
    bt:38:D5:18:B6:64:93              JBL Endurance Peak 4   bluetooth

  Every command takes a device id, a device name, or any part of one.
  You almost never need to type an id: names are enough.

JOIN TWO DEVICES
  kdn-audio create --name "Both Ears" Earmuffs "JBL Endurance Peak 4"

  Nothing that plays now moves, and the default output stays as it is.
  Choose "Both Ears" in your player. Or pass --default to send new audio
  there, and --move-streams to move what plays now.

USE THE FULL-SCREEN LIST (TUI)
  kdn-audio

    space  select an output        enter  name it and join
    tab    switch to the joins     d      unlink one
    s      also set the default    D      unlink all
    m      also move the audio     c      connect Bluetooth devices
    r      reload                  q      quit

  The join list is the lower pane; tab moves the focus there, so d works.

UNDO IT
  kdn-audio unlink-all

MAKE IT AUTOMATIC
  kdn-audio profiles save "Both Ears" --output Earmuffs --output "JBL Endurance Peak 4"
  kdn-audio profiles list
  kdn-audio daemon --once

  A profile joins the same devices whenever they are connected. The daemon
  keeps that up to date; the Nix module runs it as a user service. A join
  that you make by hand is never touched.

WHERE THINGS LIVE
  profiles   ~/.config/kdn-audio/profiles/*.yaml
  help       kdn-audio <command> --help
  details    docs/kdn-audio.md
`

func newIntroCmd(app *App) *cobra.Command {
	return &cobra.Command{
		Use:     "intro",
		Aliases: []string{"eli5", "howto"},
		Short:   "Explain the tool in plain words",
		Args:    cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Fprint(app.Out, introText)
			return nil
		},
	}
}
