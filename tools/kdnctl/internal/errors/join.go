package errors

import (
	"errors"
	"fmt"
	"slices"
	"strings"
)

func JoinIf(old, err error, format string, args ...any) error {
	if err == nil {
		return old
	}
	if !strings.Contains(format, "%w") {
		format = format + ": %w"
	}
	if !slices.Contains(args, err.(any)) {
		args = append(args, "error", err)
	}
	old = errors.Join(old, fmt.Errorf(format, args...))
	return old
}
