package fuzz

import (
	"bytes"
	"context"
	"testing"

	"gvisor.dev/gvisor/pkg/buffer"
	"gvisor.dev/gvisor/pkg/state"
)

// FuzzStateLoad drives gvisor's state-serialization loader (pkg/state) with
// arbitrary bytes. This is the historical `state_load_fuzz` target.
func FuzzStateLoad(f *testing.F) {
	f.Fuzz(func(t *testing.T, data []byte) {
		ctx := context.Background()
		var toLoad *buffer.View
		_, _ = state.Load(ctx, bytes.NewReader(data), toLoad)
	})
}
