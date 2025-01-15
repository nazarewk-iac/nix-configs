package xdg

import (
	"errors"
	"os"
	"os/user"
	"path/filepath"
)

func GetXDGConfigDirs(subdir string) (dirs []string, err error) {
	subdirs := []string{subdir}
	var baseDirs []string
	dir, err := os.UserConfigDir()
	if err != nil {
		err = errors.Join(err)
	}
	baseDirs = append(baseDirs, dir)

	for _, dir := range filepath.SplitList(os.Getenv("XDG_CONFIG_DIRS")) {
		if dir == "" {
			continue
		}
		dir, _ = filepath.Abs(dir)
		baseDirs = append(baseDirs, dir)
	}

	for _, dir := range baseDirs {
		for _, subdir := range subdirs {
			dirs = append(dirs, filepath.Join(dir, subdir))
		}
	}
	return
}

func GetStateDir(subdir string) (dir string, err error) {
	home := os.Getenv("XDG_STATE_HOME")
	if home == "" {
		homeDir, err := os.UserHomeDir()
		if err != nil {
			return dir, err
		}
		home = filepath.Join(homeDir, ".local", "state")
	}

	dir = filepath.Join(home, subdir)
	return
}

func GetRuntimeDir(subdir string) (dir string, err error) {
	home := os.Getenv("XDG_RUNTIME_DIR")
	if home == "" {
		current, err := user.Current()
		if err != nil {
			return dir, err
		}
		home = filepath.Join("/run/user", current.Uid)
	}

	dir = filepath.Join(home, subdir)
	return
}
