#!/usr/bin/env bash
#
# mayhem/test.sh — AUTHORED behavioral oracle for gvisor's pkg/state (see
# mayhem/katprobe/main.go for the full rationale).
#
# Upstream test-suite accounting (test policy):
#   * gVisor's real suite is Bazel-based (`make tests`) — it needs the Bazel
#     toolchain and frequently root/KVM; it is NOT runnable inside this image.
#   * The buildable `go` branch (the only tree that compiles under plain `go`)
#     ships ZERO *_test.go files — `go test ./...` finds no tests to run.
#   => tests_found(go-runnable)=0; we therefore author a known-answer oracle
#      over the exact fuzzed code path (state.Save -> state.Load round-trip).
#
# The oracle asserts DECODED VALUES (golden round-trips), not exit status: a
# patch that no-ops the binary (exit 0) produces no "CASE n OK"/"KAT passed="
# output and FAILS here.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
SRC="${SRC:-/mayhem}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

EXPECTED_CASES=3
KAT="$SRC/state_kat"
if [ ! -x "$KAT" ]; then
  echo "FATAL: $KAT missing — mayhem/build.sh should have built it" >&2
  emit_ctrf "gvisor-state-kat" 0 "$EXPECTED_CASES"
  exit 1
fi

out="$("$KAT" 2>&1)"; rc=$?
echo "$out"
passed="$(echo "$out" | grep -c '^CASE [0-9]* OK$')"
summary_ok=0
echo "$out" | grep -q "^KAT passed=${EXPECTED_CASES} failed=0$" && summary_ok=1

if [ "$rc" -eq 0 ] && [ "$passed" -eq "$EXPECTED_CASES" ] && [ "$summary_ok" -eq 1 ]; then
  emit_ctrf "gvisor-state-kat" "$EXPECTED_CASES" 0
else
  echo "KAT oracle FAILED (rc=$rc, ok-cases=$passed/$EXPECTED_CASES, summary_ok=$summary_ok)" >&2
  emit_ctrf "gvisor-state-kat" "$passed" $(( EXPECTED_CASES - passed ))
fi
