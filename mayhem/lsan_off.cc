// LeakSanitizer off-switch (build-time). The fleet fuzzes for ASan's
// memory-corruption checks + UBSan; leaks are noise here. `-fsanitize=address`
// always bundles LSan with no separate opt-out flag, so we link a tiny TU that
// tells LSan to stay quiet. ASan and UBSan remain fully active.
//
// This is the ONLY sanctioned LSan-off mechanism (SPEC §6.2 item 15):
// runtime __lsan_disable() wraps and ASAN_OPTIONS / compiled-in default-options
// overrides are all forbidden — Mayhem alone owns the runtime option set.
extern "C" int __lsan_is_turned_off() { return 1; }
