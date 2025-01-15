package state

import (
	"github.com/nazarewk-iac/nix-configs/packages/kdn-secrets/encrypted"
	"github.com/nazarewk-iac/nix-configs/packages/kdn-secrets/xdg"
)

type State struct {
	ProgramName      string
	ConfigSearchDirs []string
	EncryptedFiles   map[string]*encrypted.File
}

func NewState() *State {
	return &State{
		ConfigSearchDirs: []string{},
		EncryptedFiles:   make(map[string]*encrypted.File),
	}
}
func (s *State) AppendXDGConfigDirs() (err error) {
	dirs, err := xdg.GetXDGConfigDirs(s.ProgramName)
	s.ConfigSearchDirs = append(s.ConfigSearchDirs, dirs...)
	return
}

func (s *State) name() {

}
