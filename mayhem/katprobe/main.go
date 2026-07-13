// AUTHORED behavioral oracle (KAT) for gvisor's pkg/state serializer.
//
// gVisor ships NO go-runnable unit test suite on the buildable `go` branch (its
// real suite is Bazel/`make tests`, which needs the full Bazel toolchain and
// often root/KVM and is not runnable inside a fuzzing container). Per the test
// policy, when upstream ships no usable suite we author a behavioral oracle.
//
// This oracle exercises the SAME code path the fuzzer drives — state.Load — by
// round-tripping known values through state.Save + state.Load and asserting the
// decoded values equal the originals. A patch that neuters the program (e.g.
// exit(0)/no-op) cannot reproduce the golden output, so test.sh FAILS on it.
package main

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"reflect"

	"gvisor.dev/gvisor/pkg/state"
)

// Rec is a hand-stateified record (StateSave/StateLoad below) so we do not
// depend on generated code being present in the build tree.
type Rec struct {
	N int64
	S string
	B []byte
	M map[string]int64
}

func init() { state.Register((*Rec)(nil)) }

func (r *Rec) StateTypeName() string { return "main.Rec" }
func (r *Rec) StateFields() []string { return []string{"N", "S", "B", "M"} }
func (r *Rec) StateSave(m state.Sink) {
	m.Save(0, &r.N)
	m.Save(1, &r.S)
	m.Save(2, &r.B)
	m.Save(3, &r.M)
}
func (r *Rec) StateLoad(ctx context.Context, m state.Source) {
	m.Load(0, &r.N)
	m.Load(1, &r.S)
	m.Load(2, &r.B)
	m.Load(3, &r.M)
}

func roundTrip(in *Rec) (*Rec, error) {
	ctx := context.Background()
	var buf bytes.Buffer
	if _, err := state.Save(ctx, &buf, in); err != nil {
		return nil, fmt.Errorf("save: %w", err)
	}
	out := &Rec{}
	if _, err := state.Load(ctx, bytes.NewReader(buf.Bytes()), out); err != nil {
		return nil, fmt.Errorf("load: %w", err)
	}
	return out, nil
}

func main() {
	cases := []*Rec{
		{N: 42, S: "hello", B: []byte{1, 2, 3}, M: map[string]int64{"a": 1}},
		{N: -9000000000, S: "", B: nil, M: map[string]int64{}},
		{N: 1 << 40, S: "gvisor/state", B: []byte("payload-bytes"), M: map[string]int64{"x": -5, "y": 7}},
	}
	passed, failed := 0, 0
	for i, in := range cases {
		out, err := roundTrip(in)
		if err != nil {
			fmt.Printf("CASE %d FAIL: %v\n", i, err)
			failed++
			continue
		}
		if out.N != in.N || out.S != in.S || !bytes.Equal(normBytes(out.B), normBytes(in.B)) || !reflect.DeepEqual(normMap(out.M), normMap(in.M)) {
			fmt.Printf("CASE %d MISMATCH: got %+v want %+v\n", i, out, in)
			failed++
			continue
		}
		fmt.Printf("CASE %d OK\n", i)
		passed++
	}
	fmt.Printf("KAT passed=%d failed=%d\n", passed, failed)
	if failed != 0 {
		os.Exit(1)
	}
}

func normBytes(b []byte) []byte {
	if len(b) == 0 {
		return []byte{}
	}
	return b
}

func normMap(m map[string]int64) map[string]int64 {
	if m == nil {
		return map[string]int64{}
	}
	return m
}
