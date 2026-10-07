#!/usr/bin/env bash
#
# mayhem/build.sh — build the gvisor `state_load_fuzz` libFuzzer target (Go).
#
# gVisor's fuzzed code (pkg/state, pkg/buffer) is only `go build`-able from
# upstream's generated `go` branch (the default `master` tree is Bazel-only and
# does not compile under plain `go`). So this /mayhem checkout is the `master`
# mirror + our additive mayhem/ layer, and build.sh materializes the buildable
# `go`-branch tree at a pinned commit, drops our harness + KAT into it, and
# builds an in-process libFuzzer binary via go-118-fuzz-build + clang.
#
# Idempotent + air-gapped (SPEC §6.5): the go-branch clone and module cache are
# populated on the first (online) image build and reused on the offline re-run
# (the clone is skipped when the tree already exists; GOPROXY points at the
# in-image module cache first). go-fuzz-build path notes: we use go-118-fuzz-build
# (native `f.Fuzz` harness) rather than dvyukov go-fuzz-build; $GO_DEBUG_FLAGS
# carries DWARF<4 into the C/cgo CUs + the final clang link (playbook §6).
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${CC:=clang}"
: "${CXX:=clang++}"
: "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all}"
# DWARF debug info, version < 4 (Mayhem triage cannot read DWARF >= 4). For the Go
# path this is applied to the C/cgo compiles (CGO_CFLAGS) and the final clang link,
# plus a DWARF-3 anchor object placed first so the -m1 CU check sees DWARF 3.
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${GO_DEBUG_FLAGS:=-g -gdwarf-3}"
: "${MAYHEM_JOBS:=$(nproc)}"
export CC CXX LIB_FUZZING_ENGINE SANITIZER_FLAGS DEBUG_FLAGS GO_DEBUG_FLAGS MAYHEM_JOBS

export CGO_CFLAGS="${CGO_CFLAGS:-} ${GO_DEBUG_FLAGS}"
export CGO_CXXFLAGS="${CGO_CXXFLAGS:-} ${GO_DEBUG_FLAGS}"

export GOFLAGS="${GOFLAGS:--mod=mod}"
export GOPROXY="${GOPROXY:-file://$(go env GOMODCACHE)/cache/download,https://proxy.golang.org,direct}"
export PATH="$(go env GOPATH)/bin:${PATH}"

SRC="${SRC:-/mayhem}"
GVGO="${GVISOR_GO_SRC:-/opt/toolchains/src/gvisor}"
GVISOR_GO_COMMIT="${GVISOR_GO_COMMIT:?GVISOR_GO_COMMIT must be set (pinned upstream go-branch commit)}"
GO118FB_TESTING_VERSION="${GO118FB_TESTING_VERSION:-v0.0.0-20250520111509-a70c2aa677fa}"

# ── 1. materialize the buildable go-branch tree (once; reused offline) ─────────
if [ ! -d "$GVGO/.git" ]; then
  echo ">> cloning upstream go-branch @ $GVISOR_GO_COMMIT"
  git clone --single-branch --branch go https://github.com/google/gvisor "$GVGO"
  git -C "$GVGO" checkout --detach "$GVISOR_GO_COMMIT"
else
  echo ">> reusing existing go-branch tree at $GVGO (offline-safe)"
fi

# ── 2. drop our harness + KAT into the gvisor module ───────────────────────────
mkdir -p "$GVGO/mayhemfuzz" "$GVGO/katprobe"
cp "$SRC/mayhem/fuzz/state_fuzzer.go" "$GVGO/mayhemfuzz/state_fuzzer.go"
cp "$SRC/mayhem/katprobe/main.go"     "$GVGO/katprobe/main.go"

cd "$GVGO"
# go-118-fuzz-build's testing shim is a build dep of the (converted) native harness.
go get "github.com/AdamKorcz/go-118-fuzz-build/testing@${GO118FB_TESTING_VERSION}"

# ── 3. DWARF-3 anchor object (first CU => DWARF3 so the -m1 CU check sees DWARF 3) ──
# NOTE: sanitizer runtime option overrides are FORBIDDEN — Mayhem alone owns the runtime
# ASAN/LSan option set (SPEC §6.2 item 15). LSan is disabled at BUILD time via
# mayhem/lsan_off.cc (__lsan_is_turned_off), linked below.
cat > /tmp/mayhem_anchor.c <<'EOF'
/* First CU carries DWARF3 for Mayhem triage (playbook §6). */
int __mayhem_anchor = 0;
EOF
$CC $DEBUG_FLAGS -c /tmp/mayhem_anchor.c -o /tmp/mayhem_anchor.o

# LSan off-switch (build-time; ASan+UBSan stay on). Sanctioned form per SPEC §6.2 item 15.
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o /tmp/mayhem_lsan_off.o

# ── 4. build the libFuzzer archive for the native f.Fuzz harness, then link ────
mkdir -p /tmp/mayhem-build
( cd "$GVGO/mayhemfuzz" && go-118-fuzz-build -o /tmp/mayhem-build/state_load_fuzz.a -func FuzzStateLoad . )
$CXX $SANITIZER_FLAGS $LIB_FUZZING_ENGINE $DEBUG_FLAGS \
  /tmp/mayhem_anchor.o /tmp/mayhem_lsan_off.o /tmp/mayhem-build/state_load_fuzz.a \
  -o "$SRC/state_load_fuzz"
echo ">> built $SRC/state_load_fuzz"

# ── 5. build the authored behavioral KAT (run by mayhem/test.sh) ───────────────
# CGO + external linkmode => a dynamically-linked ELF that honors LD_PRELOAD, so the
# gate's behavioral-oracle sabotage (an _exit(0) constructor) actually neuters it.
CGO_ENABLED=1 CC="$CC" go build -buildvcs=false -ldflags '-linkmode=external' -o "$SRC/state_kat" ./katprobe
echo ">> built $SRC/state_kat"

echo "build.sh complete"
