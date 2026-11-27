# Source notes

## build.zig.zon

The package fingerprint identifies the package across versions. A maintained fork must generate its own fingerprint rather than reuse the original package's identity.

## renderables/table/table.zig

`Table` owns its column and row collections. Its configuration methods return a pointer so that chaining does not shallow-copy those collections; `Panel` and `Rule` can return values because their content is borrowed.

## measure.zig

Layout containers use the optional `measure(max_width, allocator)` protocol to choose widths; renderables without it are rendered and measured instead. Single-line text has equal minimum and maximum widths, while multiline text uses its widest word and widest line.

## theme.zig

The console resolves named theme styles while processing markup. When themes are merged, styles from the incoming theme take precedence.

## logging.zig

Traceback parsing accepts `file.zig:line:col: 0xaddr in function_name`, `file.zig:line:col`, and `0xaddr in function_name (file.zig)` formats. Frames are stored most recent first and displayed in reverse order.

Current-stack capture uses `captureCurrentStackTrace` and `SelfInfo.getSymbols`.
Its symbol text arena lives with Traceback so frame names and file paths stay valid.
The standard log callback uses the locked stderr terminal mode for SGR suppression;
RichHandler carries detection's no-colour flag until `setColorSystem` explicitly overrides it.

## host.zig, host_real.zig

`Host` is a context pointer and a table of functions: write and flush for stdout and
stderr, read for stdin, capability probes, size, environment lookup, mode changes, a
monotonic and a wall clock, wait, pager start and file read. Everything the library does to
the outside world goes through it. `host_real.zig` is the only file in `src/` that touches
`std.Io` streams, the environment, the clock, processes or the console modes; its tidy
counts are the seam inventory. Nothing in it is reached unless a Console, handler, prompt or
progress value is built, so a wasm consumer that only parses markup compiles none of it.

Writes are unbuffered at the host and may be short. `write_all` retries until done and gives
up with `WriteFailed` after eight consecutive zero-byte writes. `HostWriter` adapts the
host to `std.Io.Writer`: its first failure is sticky, so nothing is written after a failure
has been reported, and its flush calls the host's flush. The failure is the typed error
`WriteFailed`; the old code reported write failures from prompts as `OutOfMemory`.

`Source` holds either the real host's state (an `Io` and an `Environ`, both plain values)
or a caller's `Host`. The real host cannot be a bare pointer in these structs, because
Console, ProgressBar and the others are returned and copied by value; the owner derives the
`Host` from its own storage at each use. This keeps `Console.init(allocator, io, environ)`,
`ProgressBar.init(io)`, `Prompt.ask(io, environ)` and the other `io` entry points working
unchanged; each has an `...WithHost`, `init_source` or `ask_host` twin that takes a `Host`.

The clock operation is called `wait`, not `sleep`: tidy counts calls named `sleep` as clock
access, and the interface file is not the seam. Environment values are copied into the
caller's buffer (256 bytes, longer values are truncated), so no lookup allocates and nothing
needs freeing on Windows. A terminal that reports zero columns or rows has no size, and
detection falls back to 80 by 24. Password input is a mode (`password_input`) plus ordinary
reads: the library masks and handles backspace, the host only hides the echo (ECHO off on
POSIX as before; echo and line input off on Windows, with `ReadConsoleA`). The std logging
callback cannot be given a host, so the seam provides `lock_stderr` and `stdLogFn` formats
through `write_log_line`, which the simulator drives directly.

## console.zig, terminal.zig, prompt.zig, logging.zig, renderables/live.zig, renderables/progress

Terminal detection carries suppression separately from `ColorSystem.standard`, which
still means sixteen colours. Nonempty NO_COLOR wins over FORCE_COLOR; FORCE_COLOR (any
value, including empty) wins over TERM=dumb, a legacy Windows console and non-terminal
detection. Console's explicit colour-system option overrides detection, while its no_color
option always wins. A terminal whose virtual-terminal mode cannot be enabled (legacy
Windows console) gets no colour and no synchronized-output sequences unless forced.
`TerminalInfo` no longer owns strings: `term` and `term_program` are 64-byte copies, so
`deinit` is gone. `Console.refresh_terminal` re-reads the size after a resize. The hyperlink
closer is written only when the opener was, so NO_COLOR output has no OSC 8 sequence.

Console reads stdin one byte at a time through the host, as the prompts already did; a
buffered reader dropped the lines after the first when input was piped. Console's write
buffer is an inline array, so `init` cannot fail.

Live refresh and progress groups no longer spawn a thread. `Live.tick(now_ms)` and
`ProgressDisplay.tick(now_ms)` render when the refresh interval has passed; `wait(ms)`
loops tick and `host.wait` on the calling thread and is bounded by the duration over the
refresh interval plus three rounds. A clock that steps backwards counts as due, so a display
cannot freeze until the clock catches up. `startAutoRefresh` and `stopAutoRefresh` were
removed rather than kept as no-ops: a thread would make the bytes depend on scheduling and
would need locking around every console write. The caller drives ticks, either itself or
through `wait`.

Progress structs read the monotonic clock through their own `Source`; elapsed time is a
saturating difference and a clock that went backwards reads as zero.

## tools/tidy.zig

`zig build tidy` measures source with Zig 0.17.1's `std.zig.Ast`. The blocking
`test` step runs tidy before the example runs and the short parser campaign.
Compilation can run in parallel; consumer artifacts have no tidy dependency.
Only the module, version options and shared owned assertion module are registered
when `b.pkg_hash` is nonempty. Build tools and examples are root-package work;
`tools` is not part of the published package paths. Four impossible build assertions
previously hid four units of assertion deficit: removing them exposes 4 -> 8,
with the same four nontrivial build functions. No replacement assertions count constants.
Tidy is a build lint, not another end-to-end test. `-- --table` prints
Markdown rows, source totals and repository totals. The longest-function total
is a maximum; other totals sum groups, including their separate deficits.
Wall time uses the awake clock and includes discovery, git and ratchet checking.

The program is copied between rich_zig, webzocket, zunk and teak. All repository policy lives in the
typed `config` block at its top: source roots, skipped directory names, group
rules, generated-file markers, script exclusions and additional banned helper
names. A compiled block keeps this policy small, checked by Zig and colocated
with the program; a separately parsed configuration file would add another
input and failure path. The ratchet remains runtime data so tightening does not
recompile the tool. There is no shared package or repository-name detection.

The style scope is `src/**/*.zig`, `tools/**/*.zig`, `examples/**/*.zig` and
`build.zig`. Root patterns ending in `/` include descendants; other patterns match exactly.
Groups are each direct directory under `src`, `src/*.zig`, `tools`, `examples`,
and the root build file. Group rules match prefixes in order; `directory`
selects the next directory component when present, otherwise the rule's name.
Discovery skips `.git`, `.zig-cache`, `zig-out`, `zig-pkg`, `.archive`,
`node_modules`, and does not follow symlinks. A file with `GENERATED`
or `Generated by` in its first eight lines is excluded and named in every report.

`held_files` in `tools/tidy_ratchet.zon` is a hand-maintained list of source
paths. Each file has its own group, excluded from its directory's counts, and
must meet every style target independently of its stored numbers. It must
exist, be in scope and not be skipped or generated. Duplicate and noncanonical
paths fail. Updates preserve the entire list, including when a file is missing;
they never remove entries. rich_zig holds `src/assert.zig`, `src/host.zig`, `src/host_real.zig`, `tools/tidy.zig`,
each `tools/fuzz*.zig` and each `tools/sim*.zig` source individually.
Seam inventories and globals may be nonzero; style targets are zero, with
longest function at most 70. Moving a held file
out of a group also moves its assertion demand and surplus credit.

The columns mean:

- `files`, `lines`, `functions`: included files, physical lines (a final newline
  adds no empty line), and function declarations with bodies. Bodiless
  prototypes and function pointer types are excluded. `type_functions` is the
  subset with explicit return expression `type`; it remains in `functions`.
- `long_lines`: lines exceeding 100 Unicode code points, including comments
  and ordinary quoted literals. Tabs count as one column; display widths are
  not modeled. A line whose AST token is `multiline_string_literal_line` goes
  into `literal_long_lines` instead. This reports embedded JavaScript, shaders
  and other multiline data without ratcheting them as Zig style violations.
- `long_functions`, `longest_function`: physical span from `fn` through the
  closing body token, inclusive of signatures, comments and blank lines. Type
  constructors are exempt from both metrics; their methods count.
- `assertions`: calls whose final identifier is `assert`, regardless of receiver.
  Ownership belongs to the innermost function, including nested methods.
  `trivial_functions` counts bodies with exactly one top-level AST statement,
  including a lone return or the owned assert's conditional panic. Such functions
  contribute neither assertion demand nor credit. Other functions require two
  assertions on average within their group: `assertion_deficit` is
  `max(0, 2 * nontrivial_functions - assertions_in_nontrivial_functions)`.
  Extra assertions in one nontrivial function can cover another's deficit.
  `functions_no_assert` still reports all bodies with no assertion calls.
  Sites sample under-asserted nontrivial functions, rather than numeric deficits.
- `usize_fields`, `sized_fields`: struct fields typed `usize` or `?usize`, versus
  explicit `uN`/`iN` or their optional form. Tuple fields count. Union members,
  enum tags, aliases, pointers, arrays and slices do not. `isize` is not `usize`.
- `self_recursion`: functions calling themselves. `mutual_recursion`: unordered
  function pairs with calls in both directions, once per pair. Bounded stacks
  assign container scopes and function ownership; measurements scan the flat
  AST. Bare names resolve through enclosing containers to file scope. Field
  calls resolve through a uniquely named local container, `self`, `Self`, or
  the caller's first parameter. Ambiguous names, imports, aliases, function
  pointers, arbitrary receiver types, indirect calls and cycles longer than two
  are not resolved. The first-parameter heuristic can mistake a function-pointer
  field for a method. Comptime and syntactically bounded recursion still count.
- `while_true`: while nodes with literal `true` conditions. This neither proves
  other loops bounded nor inspects exits within these loops.
- `camel_case`: lowercase-initial function names with an uppercase ASCII letter,
  excluding type constructors. Escaped identifiers are not normalized.
- `allocation`, `clock`, `environment`, `threads`, `files_io`, `processes`: potential banned
  calls, once per category per call. One call can count in several categories.
  These expose seams; they do not prove an allocation happens after startup.
- `globals`: container-member `var` declarations at file scope or in any struct,
  union or enum, including containers declared inside functions (static locals).
  `threadlocal` and extern variables count; `const`, instance fields and ordinary
  call-local variables do not. Membership comes from the AST, independent of
  function ownership. Each declaration counts once, even inside generic types.
  This inventory exposes persistent state for the simulator's repeated runs;
  it does not distinguish a cache from a registry or prove semantic determinism.
- `scripts`: all git-tracked `.sh`, `.py`, `.mjs`, `.js` and `.ps1` files.
  Untracked Zig files are measured too. `tests` counts AST test declarations in
  every discovered nongenerated Zig file, even outside style scope. Held files' tests belong to
  their individual group; all other tests and all scripts belong to `repository`,
  so totals do not double-count. Tests must always be zero.

The standard allocation field-call names are `alloc`, `alignedAlloc`,
`allocSentinel`, `allocWithOptions`, `allocAdvanced`, `create`, `realloc`, `remap`,
`dupe`, `dupeZ`, `dupeSentinel`, `allocPrint`, `allocPrintSentinel`, `append`,
`appendSlice`, `appendNTimes`, `appendFlattened`, `ensureTotalCapacity`,
`ensureTotalCapacityPrecise`, `ensureUnusedCapacity`, `addOne`, `addManyAsSlice`,
`resize`, `put`, `getOrPut`, `fetchPut`, `putNoClobber`, `initCapacity`,
`toOwnedSlice`, `toOwnedSliceSentinel`, `readFileAlloc`, `readFileAllocOptions`,
`utf16LeToUtf8Alloc` and `createMap`. `join` and `concat` also match through
`std.fs` or `std.mem`. Bounded forms such as `appendAssumeCapacity`,
`putAssumeCapacity` and `bufPrint` are excluded. Receiver types are not inferred:
GPU `resize` and our bounded `Buffer.append` can be false positives; aliases and
wrappers with different names can be missed. Native resource creation allocates too.

Clock calls contain `std.time`, `Io.Clock` or `std.Io.Timestamp.now`, or use the clock/timestamp names
in `clock_names`: libc and kernel clock queries, `sleep`, `nanosleep`, `usleep`,
Windows timing and Mach time. `std.Io.sleep` counts as clock access. Environment
names cover libc `getenv` and setters, standard environment helpers and Windows
get/set APIs, plus `init.environ_map` and `minimal.environ` chains. Thread calls
contain `std.Thread` or `Io.Threaded`, use `pthread_`/`thrd_` APIs, `io.concurrent`,
`io.async`, or thread helpers; raw futex operations count too. The raw clone syscall
counts as both thread and process access because flags determine what it creates;
an application method named `clone` does not.

File calls contain `std.fs` except `std.fs.path`, `Io.Dir`, `Io.File`, or use the
standard file names in `file_names`. Path helpers operate on strings and do not
count as IO; allocating `join` still counts as allocation. `stdio_names` adds
libc stdio, including `fopen`/`fopen64`, `fread`, `fwrite`, `fclose`, seeking,
stdio output, temporary files and pipe streams, plus `dlopen`/`dlclose`/`dlsym`.
`std.DynLib` calls count as file access. `raw_file_names` covers descriptor IO,
metadata, directories, links, mappings, sync and file watches through `std.c`,
`std.posix` and `std.os.linux`. Common names such as `read`, `close` and `remove`
require a raw receiver, so an application collection's `remove` is not file IO.
Raw reads/closes of sockets also count: descriptor kind is not inferred.

`processes` covers `std.process.spawn`, `run`, `replace`, libc/kernel exec,
fork, spawn, wait, process identity and signals, and Windows process launch APIs.
It counts call sites, not the number of children. `popen`/`pclose` count as both
file and process access. Ambiguous `wait`/`kill` require a raw receiver or bare
call; child instance `wait`/`kill` are not inferred, while their spawn is counted.

Token chains ignore whitespace and comments. One file-level `const` alias to a
field-access namespace is recognized for raw APIs, `std.Thread`, `std.DynLib`
and `std.process`. This is lexical inventory: it does not resolve local shadows,
alias chains, arbitrary receivers, imports, syscall numbers, function pointers,
native extern calls with other names or differently named application wrappers.
Name-only matching can overcount same-named application methods. The arrays in
the program are the complete name lists, reviewed against Zig 0.17.1's standard
sources; they also cover common libc externs a program can declare itself.

rich_zig adds `fromMarkup`, `fromMarkupWithTheme`, `stripMarkup` and `escape`
as allocating helpers, `getEnv` as an environment helper, and `loadFile` as a file helper. Tidy
necessarily uses allocation, a clock, files and git; held files allow and ratchet
these seam inventories and globals.

Every discovered `build.zig.zon` must have the same decoded
`minimum_zig_version`, including tool manifests. Missing values, invalid syntax
and disagreements fail independently of ratchets. This checks manifest agreement,
not CI's installer or agreement between separately reported repositories. CI and
the root manifest both currently specify 0.17.1; CI agreement is reviewed by hand.

`-- --table --root <path>` opens another tree read-only, measures all discovered
Zig files (including root-level files), and groups them by first directory or
`*.zig`. It never reads or writes a ratchet or applies rich_zig's held list. The
same directory and generated exclusions apply. Scripts use filesystem discovery
there, including untracked files, because fetched packages need not have git
metadata. Tests are reported without enforcing zero. `--root` and `--update`
cannot be combined. Use this for other owner packages, such as fetched webzocket;
their source and manifests are never modified.

The ratchet is parsed with `std.zon`. Its metric-name header fixes numeric row
order. Stored metrics are long lines/functions, longest function, deficit,
usize fields, recursion, literal infinite loops, camelCase, banned-call counts,
globals, scripts and tests. Sizes, assertions, trivial functions and literal long
lines are reported only. Every stored number must match exactly. Decreases fail until
`-- --update` records them; increases are refused even by update. A raise is
legitimate in three cases: a count that was always there has become
visible (tidy learned to see it, or an implicit operation was made explicit); a
call moved from one group into another, lowering the first by at least as much;
or a long function in old code was split, adding a function to the assertion
average. The stored number is then edited by hand and the change report explains
why.
Held-file regrouping can likewise remove surplus assertion credit from a group;
this accounting change needs an explained hand edit. New metrics are seeded by
hand. Replacing tidy itself re-seeds only its seam inventories; its style stays
at target. The complete snapshot is validated before writing. A new group must
start with zero long lines/functions, deficit, usize fields, recursion,
while-true, camelCase and tests,
and longest function at most 70. Seam counts may be nonzero. Existing debt is
seeded once by hand; update cannot bootstrap it. Removed groups measure zero
until update drops them. Failures name group, metric, before/after and at most
twenty current file:line samples. Vanished sites have no remaining location.

One startup allocation reserves `State`; it is released at shutdown. Limits:
2 MiB per input, 4,096 files/directories/held paths, 65,536 entries per directory,
2,048 functions and 4,096 containers per file, 524,288 tokens/nodes, nesting
depth 256, 128 groups, 512 bytes per path, 20 sites per metric/group, 256 KiB
report buffer and 64 MiB parser scratch. Git output is capped at 2 MiB and
4,096 names. Limits return named errors and fail; nothing is silently omitted.
No owned heap memory is acquired after startup. The standard AST/ZON parser
requests temporary allocations from the reserved scratch, reused between inputs.
This compiler-workspace exception permits the required standard parser API
without arena growth. Standard IO and process internals are outside that owned
workspace guarantee. Traversal uses a bounded queue; syntax ownership uses
bounded stacks. The standard parser may recurse; tidy's functions do not.

## assert.zig

The owned assertion uses the panic path in every optimize mode. ReleaseFast and
ReleaseSmall must stop at a broken programmer invariant rather than assume it away.

## markup.zig

Tokens borrow their source, including the complete opening tag. This lets the
segment renderer preserve unknown tags literally without returning a temporary
stack buffer or imposing a 128-byte truncation. The input must outlive the tokens
and rendered segments, including hyperlink URLs. `tag_style` keeps hyperlink
parameter interpretation consistent between the segment and Text entry points.
Unknown openers and closers are emitted literally and never change the style
stack. Named closers recognize styles but pop the latest style, without searching.
The tokenizer accepts unclosed styles and only rejects an empty tag or an opening
bracket with no later closing bracket. Bare numeric tags are literal array notation;
indexed colours remain available through `color(n)` and compound styles.

## style.zig

RGB syntax requires exactly three channels. Ignoring a fourth component silently
accepts a malformed colour and prevents the caller's invalid-style policy from
taking effect.

## text.zig

Markup plain text and spans transfer ownership separately. The plain allocation
needs an error cleanup after its transfer because allocating the final spans can
still fail. The same ownership boundary exists in the themed entry point.
Both constructors share the token walk. Hyperlink bytes are packed into one owned
allocation after spans are finalized. A temporary bounded-capacity hash map keys
URLs by source address and length, so each inherited URL is copied once even if
it appears in many spans. The map is sized from the link count before insertion.
Every owning copy duplicates its URLs before releasing old storage, including
clone, append, highlight, truncation, alignment, wrapping, justification and pattern
highlighting. `slice` and `withStyle` retain their borrowed-view contract.

## tools/fuzz_generate.zig

The generator writes plain text and expected styles while emitting markup, rather
than stripping tags through library calls. Expected colours and attribute masks
are data; no `Style.parse`, `combine`, `eql`, token walk or terminal participates in
the oracle. A per-case PRNG derived from seed and case index permits direct replay.
Nineteen profiles distribute styles, nesting and overlap, long runs and damage,
including literal status labels, indices, nested brackets, path closers and JSON arrays.
One profile inherits a 24–32 KiB URL across 96–127 styled runs; copying that URL
per span would exceed the ownership checker's fixed workspace.
Profile counters, all thirteen attributes, every named colour, five colour forms,
all text forms, hyperlinks and backgrounds must be exercised even on short runs.
An iteration count too small to cover these fails with `CoverageGap`.

## tools/fuzz_check.zig

Semantic styles are checked per plain-text byte so a future parser can merge or
split adjacent spans without changing the oracle. Determinism additionally checks
the exact span sequence from two runs in separately poisoned workspaces. UTF-8
boundaries are required for valid UTF-8; malformed UTF-8 is preserved as bytes,
so those cases check ranges, order and exact byte preservation instead.
The public token parser, segment renderer, stripping, escaping, normal Text and
Text with an empty theme are exercised without a terminal or files. There is no
public Text-to-markup direction, so a styled markup round trip is unavailable.
Escaping plain text and parsing it is a separate, unstyled round trip.

## tools/fuzz_memory.zig

Three 4 MiB workspaces are reserved at startup. The third is reused for allocation
failure sweeps and actual fixed buffers of 0, 1, 31, 127 and 1024 bytes. The tracker
counts live requested bytes rather than the fixed allocator's end index: freeing
out of order leaves unusable holes in that allocator without leaking ownership.
Growth is refused to force allocation/copy/free paths; shrinking is supported.
Every allocation ordinal is denied in turn in Text, themed Text, token parsing and
segment rendering. Every path must release all allocations, including on errors.

## tools/fuzz_ownership.zig

Each accepted generated case is parsed through normal and themed Text, then its
mutable input buffer is poisoned. The same independent byte/style oracle checks
plain text, span boundaries and URL contents. A clone is checked after poisoning
the original plain/span/link allocations and releasing the original Text. The tracker
must have no live bytes afterward; it uses the existing third workspace. The themed
run supplies named bold and link styles, including a conflicting link name to
verify that explicit hyperlink parameters still win.

## tools/console_gate.zig

The seven blocking programs (the main binary and six examples) run twice in each of five environments, once with pipes and
once with regular stdout/stderr files. Both streams must match byte for byte and
all colour-disabled modes reject SGR. Captures are evidence, never golden files.
Startup reserves 32 MiB for process collection and creates environment maps;
each run reuses the fixed workspace. Each stream is limited to 2 MiB. File/pipe
comparisons cover forced colour, NO_COLOR with and without FORCE_COLOR, dumb TERM,
and a non-terminal with empty NO_COLOR. No shell participates in the gate.

## tools/declarations.zig

A comptime queue visits each public container once, up to 4,096 distinct types,
and references every public declaration. Concrete generic instantiations cover
writers, renderable measurement with/without the optional protocol, formatted
console/logging calls, both gradient modes, scoped log methods and heterogeneous
pretty printing. This checks generic implementations for representative types,
not all possible consumer types. Build emits host, Windows GNU x86_64 and macOS
arm64 executables. Foreign binaries and interactive paths are compiled but not run.
A retained table of up to 4,096 function addresses forces code generation and
linking for nongeneric declarations and the representative generic driver; main
keeps the table live without calling those API paths.

## tools/fuzz_watch.zig

A watchdog bounds each complete observation, including allocation sweeps, to
100 ms plus 100 microseconds per input byte, with a 5 ms polling interval. This
is a hang detector, not a deterministic instruction counter or performance gate.
Allocation counts are also capped at 1024. The parser advances monotonically
through bytes and tokens; its work is linear in input bytes. An epoch ticket
prevents a delayed watchdog sample from timing out a subsequent case. The runner
waits if the watchdog claims a timeout, so the panic saver reads stable case data.
The watchdog has a 24-hour polling bound and is outside the library under test.

## tools/fuzz.zig

One active context lets the panic path save crashes and watchdog timeouts as well
as returned checker failures. Failures are raw `.markup` files under `zig-out/fuzz/`
with `.seed` metadata. `--replay` regenerates the independent expectation and
verifies the saved input matches it; changed generator semantics produce
`ReplayGeneratorChanged`, never a silently different replay. Raw input alone is
insufficient for replay. No failure corpus is added to the blocking gate.
`fuzz-heavy` fixes a background seed for reproducibility; additional CLI seeds
provide independent campaigns. No subprocess is spawned while configuring builds.

## tools/sim.zig, sim_host.zig, sim_generate.zig, sim_run.zig, sim_check.zig, sim_scan.zig

`zig build sim -- --seed N --steps M [--seeds K] [--replay file] [--cross-process] [--verbose]`.
A seed generates a terminal and a script; the same seed always generates the same bytes.
`sim_host.zig` implements `Host`: scripted size, tty flags, environment, legacy Windows,
password and pager results, input bytes, a clock that only moves when the script or
`wait` moves it, and write failures and short writes that apply to one step. Writes land
in 2 MiB captures. The library under test uses a fixed 48 MiB tracker (the allocator from
`fuzz_memory.zig`), reset between steps when nothing is live; limits are named constants.

`sim_generate.zig` draws the terminal (width 1 to 200 or a Console width override of
0 to 50, which is how zero and one column widths arrive), environment variables, colour
options and 22 step kinds, with text made of ASCII, wide, combining, right-to-left and very
long words and markup that includes literal and unknown tags. `sim_run.zig` builds each
renderable and prints it through a real `Console`; expected text is generated alongside the
markup, not derived from the library. `sim_scan.zig` parses escape sequences and measures cell
width with its own tables; it shares no code with `cells.zig`. `sim_check.zig` checks:

- same seed, same bytes: a second run in the process and (with `--cross-process`) a child
  process digest;
- no visible line wider than the terminal for a renderable that promises to fit;
- every SGR and OSC 8 closed by the end of a print, cursor and alternate-screen state paired
  by the end of a live display, synchronized output balanced;
- no SGR or OSC 8 when colour is disabled (computed from the documented precedence), and the
  visible text equal to a run with colour forced on;
- a write failure is the typed `WriteFailed`, nothing is accepted after it within the step,
  a short write changes no byte (run with and without short writes), no step leaks;
- progress and live frames depend only on tick times: the run is repeated with the monotonic
  clock shifted by a constant;
- a typed password never reaches stdout.

Table, panel and columns do not wrap or shrink their content, so their promise to fit is
made only when the generated content fits at its natural width; the number of prints wider
than the terminal below that width is reported as `wider_than_terminal` and is not a
failure. Tree and progress bars make no promise. A failing seed is saved under
`zig-out/sim/` for `--replay`; it is fixed or filed and is not added to the blocking gate.
