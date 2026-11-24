package audio

import (
	"os"
	"path/filepath"
	"syscall"
)

// Lock takes the per-user tool lock and returns the release function.
//
// Two joins racing each other would leave a duplicate module behind, and the second one would
// adopt the first one's sink. The lock lives in the runtime directory, so a crash cannot leave a
// stale file behind: the kernel drops the lock with the process.
//
// A lock that cannot be taken is not a failure. The tool works without it; the lock only keeps
// two of our own runs apart.
func Lock() (func(), error) {
	dir := os.Getenv("XDG_RUNTIME_DIR")
	if dir == "" {
		dir = os.TempDir()
	}
	file, err := os.OpenFile(filepath.Join(dir, "kdn-audio.lock"), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return func() {}, nil
	}
	if err := syscall.Flock(int(file.Fd()), syscall.LOCK_EX); err != nil {
		_ = file.Close()
		return func() {}, nil
	}
	return func() {
		_ = syscall.Flock(int(file.Fd()), syscall.LOCK_UN)
		_ = file.Close()
	}, nil
}
