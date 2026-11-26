pub const MarkupError = @import("markup.zig").MarkupError;

pub const RenderError = error{
    OutOfMemory,
    InvalidWidth,
    ContentTooLarge,
};

pub const TableError = error{
    ColumnCountMismatch,
    InvalidSpan,
    OutOfMemory,
};

pub const ConsoleError = error{
    WriteError,
    InvalidTerminal,
    UnsupportedOperation,
};
