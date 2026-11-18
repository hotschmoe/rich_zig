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
