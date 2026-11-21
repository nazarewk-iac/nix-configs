package control

import (
	"crypto/rand"
	"fmt"
)

// newUUIDv4 returns a random RFC 4122 version 4 UUID, lower case, hyphenated.
//
// The eviction epoch is a compare-and-swap token, so it must be unpredictable and unique without a
// shared counter: two managers, a restart, or a state file restored from a backup must never hand
// out the same id for different plans. A version 4 UUID gives that with no dependency.
func newUUIDv4() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		// crypto/rand does not fail on Linux; reaching here means the host is broken in a way that
		// makes an eviction token meaningless, and a wrong token is worse than a crash.
		panic(fmt.Sprintf("control: no randomness for an eviction id: %v", err))
	}
	b[6] = (b[6] & 0x0f) | 0x40 // version 4
	b[8] = (b[8] & 0x3f) | 0x80 // variant 10
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}
