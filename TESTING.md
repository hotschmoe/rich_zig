# Testing

The binding testing and comment policy is [ENGINEERING.md](https://github.com/hotschmoe/hotschmoe-setup/blob/master/ENGINEERING.md).

Run `zig build test -j4` for the blocking gate. Tidy runs first. The gate builds the installed programs and runs the main binary, the `hello`, `panel`, `table`, `tree`, `json_syntax`, `markdown`, and `advanced_syntax` examples through `tools/console_gate.zig`, plus a 512-case markup campaign with seed 1. These are ten checks including the build; tidy is a lint. The build includes the public declaration program for the host, x86_64-windows-gnu and aarch64-macos.

For each of the eight programs, the console gate compares stdout and stderr from
a pipe against a second run redirected to regular files. No golden files are
used. Five environments cover forced colour, `NO_COLOR=1` both with and without
`FORCE_COLOR`, `TERM=dumb`, and ordinary non-terminal detection with empty
`NO_COLOR`. Every disabled-colour run must contain no SGR sequence. Captures under
`zig-out/gate/` allow independent `cmp` verification.

`zig build declarations -j4` compiles all public container declarations using a
bounded comptime traversal. Generic APIs also receive representative instantiations;
arbitrary downstream generic types remain the consumer's responsibility. Compilation
and linking retain function addresses; they do not run a pager, a password prompt,
live auto-refresh or foreign binaries.

Run `zig build test-heavy -j4` for the background gate. It runs all installed examples in sequence and is intended for nightly or every 10–20 commits, without blocking ordinary work. Investigate failures by rerunning the failing example on earlier commits and bisecting as needed.

Do not add unit tests, output snapshots, or tests of internal structure. Preserve valuable regression cases through real program runs or fuzz/DST seeds in the background gate.

`zig build fuzz -- --seed 1 --iterations 512` runs the public markup oracle.
`zig build fuzz-heavy` runs 200,000 cases with seed `0x72696368` in the background gate.
CI runs it after `test-heavy`. Coverage counters must all be nonzero, except when
replaying a saved failure with `zig build fuzz -- --replay zig-out/fuzz/<case>.markup`.
Keep the adjacent `.seed` file. See `SRC.md` for bounds, allocation accounting,
the watchdog and the independent oracle.

CI (`.github/workflows/ci.yml`): on a pull request, Format Check, Package Validation (a consumer project builds against the library), and the blocking gate on Ubuntu ReleaseFast and Windows ReleaseSafe; these four are the required checks for master. Nightly and on manual dispatch, the heavy gate runs on Linux, macOS, and Windows.
