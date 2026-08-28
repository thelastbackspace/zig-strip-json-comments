//! Strip comments from JSON — turning JSONC into parseable JSON.
//!
//! A behavior-faithful Zig port of the npm package
//! [`strip-json-comments`](https://github.com/sindresorhus/strip-json-comments)
//! (v5.0.3). The upstream test suite is ported in `tests.zig`.

const std = @import("std");

/// Options mirroring the upstream package.
pub const Options = struct {
    /// Replace comment characters with spaces (default), keeping
    /// positions and line endings intact; when `false`, comments are
    /// removed entirely.
    whitespace: bool = true,
    /// Strip trailing commas before `}` and `]` as well, producing
    /// output that strict JSON parsers accept.
    trailing_commas: bool = false,
};

const Comment = enum { none, single, multi };

/// Strip comments (and optionally trailing commas) from a JSON string.
/// The result is allocated with `allocator`; the caller owns it.
///
/// Single-line `//` comments run to the end of the line (`\n` or
/// `\r\n`); `/* */` comments may span lines. Comment markers inside
/// string values are left untouched, including escaped quotes.
pub fn stripJsonComments(allocator: std.mem.Allocator, json: []const u8, options: Options) std.mem.Allocator.Error![]u8 {
    var result = std.ArrayList(u8).empty;
    var buffer = std.ArrayList(u8).empty;
    defer buffer.deinit(allocator);
    errdefer result.deinit(allocator);

    var inside_string = false;
    var inside_comment: Comment = .none;
    var offset: usize = 0;
    var comma_index: ?usize = null;

    var i: usize = 0;
    while (i < json.len) {
        const c = json[i];
        const next: u8 = if (i + 1 < json.len) json[i + 1] else 0;

        if (inside_comment == .none and c == '"') {
            if (!isEscaped(json, i)) {
                inside_string = !inside_string;
            }
        }

        if (inside_string) {
            i += 1;
            continue;
        }

        if (inside_comment == .none and c == '/' and next == '/') {
            try buffer.appendSlice(allocator, json[offset..i]);
            offset = i;
            inside_comment = .single;
            i += 2;
        } else if (inside_comment == .single and c == '\r' and next == '\n') {
            i += 1;
            inside_comment = .none;
            // The comment (and the \r) is stripped; the \n that follows
            // flows through the normal path and is preserved verbatim.
            try stripInto(allocator, &buffer, json[offset..i], options.whitespace);
            offset = i;
            continue;
        } else if (inside_comment == .single and c == '\n') {
            inside_comment = .none;
            try stripInto(allocator, &buffer, json[offset..i], options.whitespace);
            offset = i;
            i += 1;
        } else if (inside_comment == .none and c == '/' and next == '*') {
            try buffer.appendSlice(allocator, json[offset..i]);
            offset = i;
            inside_comment = .multi;
            i += 2;
            continue;
        } else if (inside_comment == .multi and c == '*' and next == '/') {
            i += 2;
            inside_comment = .none;
            try stripInto(allocator, &buffer, json[offset..i], options.whitespace);
            offset = i;
            continue;
        } else if (options.trailing_commas and inside_comment == .none) {
            if (comma_index != null) {
                if (c == '}' or c == ']') {
                    // Strip the pending comma (the first byte of buffer).
                    try buffer.appendSlice(allocator, json[offset..i]);
                    if (options.whitespace) {
                        try result.append(allocator, ' ');
                    }
                    try result.appendSlice(allocator, buffer.items[1..]);
                    buffer.clearRetainingCapacity();
                    offset = i;
                    comma_index = null;
                } else if (c != ' ' and c != '\t' and c != '\r' and c != '\n') {
                    // Something follows the comma: not trailing.
                    try buffer.appendSlice(allocator, json[offset..i]);
                    offset = i;
                    comma_index = null;
                }
            } else if (c == ',') {
                try result.appendSlice(allocator, buffer.items);
                try result.appendSlice(allocator, json[offset..i]);
                buffer.clearRetainingCapacity();
                offset = i;
                comma_index = i;
            }
            i += 1;
        } else {
            i += 1;
        }
    }

    if (inside_comment == .single) {
        try stripInto(allocator, &buffer, json[offset..], options.whitespace);
    } else {
        try buffer.appendSlice(allocator, json[offset..]);
    }

    try result.appendSlice(allocator, buffer.items);
    return result.toOwnedSlice(allocator);
}

/// Append the comment text with its non-whitespace characters replaced
/// by single spaces (or removed entirely).
fn stripInto(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comment: []const u8, whitespace: bool) std.mem.Allocator.Error!void {
    if (!whitespace) return;
    var i: usize = 0;
    while (i < comment.len) {
        const c = comment[i];
        if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
            try out.append(allocator, c);
            i += 1;
        } else if (c < 0x80) {
            try out.append(allocator, ' ');
            i += 1;
        } else {
            // One space per code point, matching upstream's per-character
            // replacement for BMP input.
            try out.append(allocator, ' ');
            i += 1;
            while (i < comment.len and (comment[i] & 0xC0) == 0x80) i += 1;
        }
    }
}

/// True when the quote at `quote_position` is preceded by an odd number
/// of backslashes.
fn isEscaped(json: []const u8, quote_position: usize) bool {
    var index: isize = @as(isize, @intCast(quote_position)) - 1;
    var backslashes: usize = 0;
    while (index >= 0 and json[@intCast(index)] == '\\') {
        index -= 1;
        backslashes += 1;
    }
    return backslashes % 2 == 1;
}
