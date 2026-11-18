# Testing

The binding testing and comment policy is [ENGINEERING.md](/home/hotschmoe/github/hotschmoe-setup/ENGINEERING.md).

Run `zig build test -j4` for the blocking gate. It builds the installed programs and runs the main binary and the `hello`, `panel`, `table`, `tree`, `json_syntax`, `markdown`, and `advanced_syntax` examples. These are nine checks including the build.

Run `zig build test-heavy -j4` for the background gate. It runs all installed examples in sequence and is intended for nightly or every 10–20 commits, without blocking ordinary work. Investigate failures by rerunning the failing example on earlier commits and bisecting as needed.

Do not add unit tests, output snapshots, or tests of internal structure. Preserve valuable regression cases through real program runs or fuzz/DST seeds in the background gate. The current repository does not yet have a real fuzz harness; the old fuzz placeholder was not one.
