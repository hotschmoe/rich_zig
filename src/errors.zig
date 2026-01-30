// src/errors.zig
// Semantic error types for precise error handling

pub const MarkupError = error{
    UnmatchedTag, // [bold without closing [/]
    InvalidColorName, // [unknown_color]
    InvalidStyleAttribute, // [notareal]
    NestedTagMismatch, // [bold][italic][/bold]
};

pub const RenderError = error{
    OutOfMemory,
    InvalidWidth, // Width too small for content
    ContentTooLarge, // Exceeds max dimensions
};

pub const TableError = error{
    ColumnCountMismatch, // Row has wrong number of cells
    InvalidSpan, // Colspan/rowspan out of bounds
    OutOfMemory,
};

pub const ConsoleError = error{
    WriteError,
    InvalidTerminal,
    UnsupportedOperation,
};
