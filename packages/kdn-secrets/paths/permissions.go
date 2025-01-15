package paths

import (
	"os"
	"runtime"
	"syscall"
)

func HasAnyPerm(path string, perms uint32) bool {
	stat, err := os.Stat(path)
	if err != nil {
		return false
	}
	return perms&uint32(stat.Mode().Perm()) != 0
}

func CanExecute(path string) bool {
	switch runtime.GOOS {
	case "linux":
		return syscall.Access(path, 0x1) == nil
	default:
		return HasAnyPerm(path, 0111)
	}
}

func CanWrite(path string) bool {
	switch runtime.GOOS {
	case "linux":
		return syscall.Access(path, 0x2) == nil
	default:
		return HasAnyPerm(path, 0222)
	}
}

func CanRead(path string) bool {
	switch runtime.GOOS {
	case "linux":
		return syscall.Access(path, 0x4) == nil
	default:
		return HasAnyPerm(path, 0444)
	}
}
