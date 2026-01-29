# CLAUDE.md - rich_zig

## RULE 1 - ABSOLUTE (DO NOT EVER VIOLATE THIS)

You may NOT delete any file or directory unless I explicitly give the exact command **in this session**.

- This includes files you just created (tests, tmp files, scripts, etc.).
- You do not get to decide that something is "safe" to remove.
- If you think something should be removed, stop and ask. You must receive clear written approval **before** any deletion command is even proposed.

Treat "never delete files without permission" as a hard invariant.

---

### IRREVERSIBLE GIT & FILESYSTEM ACTIONS

Absolutely forbidden unless I give the **exact command and explicit approval** in the same message:

- `git reset --hard`
- `git clean -fd`
- `rm -rf`
- Any command that can delete or overwrite code/data

Rules:

1. If you are not 100% sure what a command will delete, do not propose or run it. Ask first.
2. Prefer safe tools: `git status`, `git diff`, `git stash`, copying to backups, etc.
3. After approval, restate the command verbatim, list what it will affect, and wait for confirmation.
4. When a destructive command is run, record in your response:
   - The exact user text authorizing it
   - The command run
   - When you ran it

If that audit trail is missing, then you must act as if the operation never happened.

### Version Updates (SemVer)

When making commits, update the `version` in `build.zig.zon` following [Semantic Versioning](https://semver.org/):

- **MAJOR** (X.0.0): Breaking changes or incompatible API modifications
- **MINOR** (0.X.0): New features, backward-compatible additions
- **PATCH** (0.0.X): Bug fixes, small improvements, documentation

---

### Code Editing Discipline

- Do **not** run scripts that bulk-modify code (codemods, invented one-off scripts, giant `sed`/regex refactors).
- Large mechanical changes: break into smaller, explicit edits and review diffs.
- Subtle/complex changes: edit by hand, file-by-file, with careful reasoning.
- **NO EMOJIS** - do not use emojis or non-textual characters.
- ASCII diagrams are encouraged for visualizing flows.
- Keep in-line comments to a minimum. Use external documentation for complex logic.
- In-line commentary should be value-add, concise, and focused on info not easily gleaned from the code.

---

### No Legacy Code - Full Migrations Only

We optimize for clean architecture, not backwards compatibility. **When we refactor, we fully migrate.**

- No "compat shims", "v2" file clones, or deprecation wrappers
- When changing behavior, migrate ALL callers and remove old code **in the same commit**
- No `_legacy` suffixes, no `_old` prefixes, no "will remove later" comments
- New files are only for genuinely new domains that don't fit existing modules
- The bar for adding files is very high

**Rationale**: Legacy compatibility code creates technical debt that compounds. A clean break is always better than a gradual migration that never completes.

---

## Beads (bd) - Task Management

Beads is a git-backed graph issue tracker. Use `--json` flags for all programmatic operations.

### Session Workflow

```
1. bd prime              # Auto-injected via SessionStart hook
2. bd ready --json       # Find unblocked work
3. bd update <id> --status in_progress --json   # Claim task
4. (do the work)
5. bd close <id> --reason "Done" --json         # Complete task
6. bd sync && git push   # End session - REQUIRED
```

### Key Commands

| Action | Command |
|--------|---------|
| Find ready work | `bd ready --json` |
| Find stale work | `bd stale --days 30 --json` |
| Create issue | `bd create "Title" --description="Context" -t bug\|feature\|task -p 0-4 --json` |
| Create discovered work | `bd create "Found bug" -t bug -p 1 --deps discovered-from:<parent-id> --json` |
| Claim task | `bd update <id> --status in_progress --json` |
| Complete task | `bd close <id> --reason "Done" --json` |
| Find duplicates | `bd duplicates` |
| Merge duplicates | `bd merge <id1> <id2> --into <canonical> --json` |

### Critical Rules

- Always include `--description` when creating issues - context prevents rework
- Use `discovered-from` links to connect work found during implementation
- Run `bd sync` at session end before pushing to git
- **Work is incomplete until `git push` succeeds**
- `.beads/` is authoritative state and **must always be committed** with code changes

### Dependency Thinking

Use requirement language, not temporal language:
```bash
bd dep add rendering layout      # rendering NEEDS layout (correct)
# NOT: bd dep add phase1 phase2   (temporal - inverts direction)
```

### After bd Upgrades

```bash
bd info --whats-new              # Check workflow-impacting changes
bd hooks install                 # Update git hooks
bd daemons killall               # Restart daemons
```

### Context Preservation During Debugging

Long debugging sessions can lose context during compaction. **Commit frequently to preserve investigation state.**

```bash
# During debugging - commit investigation findings periodically
git add -A && git commit -m "WIP: investigating X, found Y"
bd create "Discovered: Z needs fixing" -t bug -p 2 --description="Found while debugging X"
bd sync

# At natural breakpoints (every 30-60 min of active debugging)
bd sync  # Capture bead state changes
git push  # Push to remote
```

**Why this matters:**
- Compaction events lose conversational context but git history persists
- Beads issues survive across sessions - use them to capture findings
- "WIP" commits are fine - squash later when the fix is complete
- A partially-documented investigation beats starting over

---

## Session Completion Checklist

```
[ ] File issues for remaining work (bd create)
[ ] Run quality gates (zig build test)
[ ] Update issue statuses (bd update/close)
[ ] Run bd sync
[ ] Run git push and verify success
[ ] Confirm git status shows "up to date"
```

**Work is not complete until `git push` succeeds.**

### Post-Session Code Cleanup

After long or complex sessions, consider running the code-simplifier agent to clean up recently modified code:

```
Task(code-simplifier) - Simplifies and refines code for clarity, consistency, and maintainability
```

This agent focuses on recently modified files and helps reduce complexity that can accumulate during extended development sessions while preserving all functionality.

---

## Claude Agents

Specialized agents are available in `.claude/agents/`. Agents use YAML frontmatter format:

```yaml
---
name: agent-name
description: What this agent does
model: sonnet|haiku|opus
tools:
  - Bash
  - Read
  - Edit
---
```

### Available Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| coder-sonnet | sonnet | Fast, precise code changes with atomic commits |
| gemini-analyzer | sonnet | Large-context codebase analysis via Gemini CLI |
| build-verifier | sonnet | Build and test validation across optimization levels |

### Disabling Agents

To disable specific agents in `settings.json` or `--disallowedTools`:
```json
{
  "disallowedTools": ["Task(coder-sonnet)"]
}
```

---

## Claude Skills

Skills are invoked via `/skill-name`. Available in `.claude/skills/`.

### Skill Frontmatter (v2.1+)

Skills now support YAML frontmatter with advanced options:

```yaml
---
name: skill-name
description: What this skill does
# Run in forked sub-agent context (isolated from main conversation)
context: fork
# Specify which agent executes this skill
agent: coder-sonnet
---
```

| Field | Description |
|-------|-------------|
| `context: fork` | Run skill in isolated sub-agent context |
| `agent: <name>` | Execute skill using specified agent type |

### Built-in Commands

| Command | Purpose |
|---------|---------|
| `/plan` | Enter plan mode for implementation design |
| `/context` | Manage context files and imports |
| `/help` | Show available commands |

### Project Skills

| Skill | Purpose |
|-------|---------|
| `/test` | Run `zig build test` |

### Skill Hot-Reload

Skills in `.claude/skills/` are automatically discovered without restart. Edit or add skills and they become immediately available.

---

# PROJECT-LANGUAGE-SPECIFIC: Zig (v0.15.2)

## Project Overview

rich_zig is a Zig library project. The library module is exposed at `src/root.zig` and a CLI executable entry point is at `src/main.zig`.

---

## Zig Toolchain

- **Zig Version**: 0.15.2
- Build: `zig build`
- Test: `zig build test`
- Run: `zig build run`
- Format: `zig fmt` (run before commits)

### Build Commands

```bash
# Build the library and executable
zig build

# Run the executable
zig build run

# Run tests
zig build test

# Pass arguments to the executable
zig build run -- arg1 arg2
```

---

## Project Layout

```
rich_zig/
├── build.zig           # Build configuration
├── build.zig.zon       # Package manifest
├── src/
│   ├── root.zig        # Library root (public API)
│   └── main.zig        # Executable entry point
└── .claude/
    ├── agents/         # Claude agents
    ├── skills/         # Claude skills
    └── settings.local.json
```

### Module Structure

- `src/root.zig` - Library module exposed to consumers via `@import("rich_zig")`
- `src/main.zig` - CLI executable that imports the library module

---

## Zig Best Practices

### Error Handling

```zig
// Use error unions and try for propagation
fn loadConfig(path: []const u8) !Config {
    const file = try fs.open(path);
    defer file.close();
    return try parseConfig(file);
}

// Explicit error sets for API boundaries
const ConfigError = error{
    FileNotFound,
    ParseFailed,
    InvalidFormat,
};

fn parseConfig(data: []const u8) ConfigError!Config {
    // ...
}
```

### Optional Handling

```zig
// Prefer if/orelse over .? when handling is needed
if (items.get(index)) |item| {
    // safe to use item
} else {
    // handle missing case
}

// Use orelse for defaults
const value = optional orelse default_value;

// Use .? only when null is truly unexpected
const ptr = maybe_ptr.?;  // Will panic if null - use sparingly
```

### Memory Safety

```zig
// Always use defer for cleanup
const buffer = try allocator.alloc(u8, size);
defer allocator.free(buffer);

// Prefer slices over raw pointers
fn process(data: []const u8) void { ... }

// Use sentinel-terminated slices for C interop
fn cString(s: [:0]const u8) [*:0]const u8 { return s.ptr; }
```

### Comptime & Generics

```zig
// Use comptime for zero-cost abstractions
fn GenericList(comptime T: type) type {
    return struct {
        items: []T,

        pub fn get(self: @This(), index: usize) ?T {
            if (index >= self.items.len) return null;
            return self.items[index];
        }
    };
}

// Prefer comptime assertions over runtime checks
comptime {
    if (@sizeOf(Header) != 16) {
        @compileError("Header must be exactly 16 bytes");
    }
}
```

---

## Testing Guidelines

### Test Commands

```bash
# Run all tests
zig build test

# Run tests with specific options
zig build test -Doptimize=ReleaseSafe
```

### Test Patterns

```zig
test "descriptive test name" {
    const gpa = std.testing.allocator;

    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa);

    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

// Fuzz testing
test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Fuzz test logic
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
```

---

## Bug Severity

### Critical - Must Fix Immediately

- `.?` on null (panics)
- `unreachable` reached at runtime
- Index out of bounds on slices/arrays
- Integer overflow in release builds (undefined behavior)
- Use-after-free or double-free
- Memory leaks in long-running code paths

### Important - Fix Before Merge

- Missing error handling (`try` without proper catch/return)
- `catch unreachable` without justification comment
- Ignoring return values from functions returning `!T`
- Race conditions in threaded code

### Contextual - Address When Convenient

- TODO/FIXME comments
- Unused imports or variables
- Suboptimal comptime usage (could be comptime but isn't)
- Redundant code that could use generics
- Excessive debug output left in code

---

## Development Philosophy

**Make it work, make it right, make it fast** - in that order.

**Closed-Loop Testing**: Build testable components. Use `zig build test` for verification.

---

we love you, Claude! do your best today
