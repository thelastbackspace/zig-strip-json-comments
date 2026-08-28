//! Port of the upstream test suite (test.js, ava) for
//! strip-json-comments v5.0.3.

const std = @import("std");
const sjc = @import("root.zig");

const t = std.testing;

fn check(input: []const u8, options: sjc.Options, want: []const u8) !void {
    const got = try sjc.stripJsonComments(t.allocator, input, options);
    defer t.allocator.free(got);
    t.expectEqualStrings(want, got) catch |e| {
        std.debug.print("input: {s}\n", .{input});
        return e;
    };
}

test "replace comments with whitespace" {
    try check("//comment\n{\"a\":\"b\"}", .{}, "         \n{\"a\":\"b\"}");
    try check("/*//comment*/{\"a\":\"b\"}", .{}, "             {\"a\":\"b\"}");
    try check("{\"a\":\"b\"//comment\n}", .{}, "{\"a\":\"b\"         \n}");
    try check("{\"a\":\"b\"/*comment*/}", .{}, "{\"a\":\"b\"           }");
    try check("{\"a\"/*\n\n\ncomment\r\n*/:\"b\"}", .{}, "{\"a\"  \n\n\n       \r\n  :\"b\"}");
    try check("/*!\n * comment\n */\n{\"a\":\"b\"}", .{}, "   \n          \n   \n{\"a\":\"b\"}");
    try check("{/*comment*/\"a\":\"b\"}", .{}, "{           \"a\":\"b\"}");
}

test "remove comments" {
    const o = sjc.Options{ .whitespace = false };
    try check("//comment\n{\"a\":\"b\"}", o, "\n{\"a\":\"b\"}");
    try check("/*//comment*/{\"a\":\"b\"}", o, "{\"a\":\"b\"}");
    try check("{\"a\":\"b\"//comment\n}", o, "{\"a\":\"b\"\n}");
    try check("{\"a\":\"b\"/*comment*/}", o, "{\"a\":\"b\"}");
    try check("{\"a\"/*\n\n\ncomment\r\n*/:\"b\"}", o, "{\"a\":\"b\"}");
    try check("/*!\n * comment\n */\n{\"a\":\"b\"}", o, "\n{\"a\":\"b\"}");
    try check("{/*comment*/\"a\":\"b\"}", o, "{\"a\":\"b\"}");
}

test "doesn't strip comments inside strings" {
    try check("{\"a\":\"b//c\"}", .{}, "{\"a\":\"b//c\"}");
    try check("{\"a\":\"b/*c*/\"}", .{}, "{\"a\":\"b/*c*/\"}");
    try check("{\"/*a\":\"b\"}", .{}, "{\"/*a\":\"b\"}");
    try check("{\"\\\"/*a\":\"b\"}", .{}, "{\"\\\"/*a\":\"b\"}");
}

test "considers escaped slashes when checking for escaped string quote" {
    try check("{\"\\\\\":\"https://foobar.com\"}", .{}, "{\"\\\\\":\"https://foobar.com\"}");
    try check("{\"foo\\\"\":\"https://foobar.com\"}", .{}, "{\"foo\\\"\":\"https://foobar.com\"}");
}

test "line endings: no comments" {
    try check("{\"a\":\"b\"\n}", .{}, "{\"a\":\"b\"\n}");
    try check("{\"a\":\"b\"\r\n}", .{}, "{\"a\":\"b\"\r\n}");
}

test "line endings: single line comment" {
    try check("{\"a\":\"b\"//c\n}", .{}, "{\"a\":\"b\"   \n}");
    try check("{\"a\":\"b\"//c\r\n}", .{}, "{\"a\":\"b\"   \r\n}");
}

test "line endings: single line block comment" {
    try check("{\"a\":\"b\"/*c*/\n}", .{}, "{\"a\":\"b\"     \n}");
    try check("{\"a\":\"b\"/*c*/\r\n}", .{}, "{\"a\":\"b\"     \r\n}");
}

test "line endings: multiline block comment" {
    try check("{\"a\":\"b\",/*c\nc2*/\"x\":\"y\"\n}", .{}, "{\"a\":\"b\",   \n    \"x\":\"y\"\n}");
    try check("{\"a\":\"b\",/*c\r\nc2*/\"x\":\"y\"\r\n}", .{}, "{\"a\":\"b\",   \r\n    \"x\":\"y\"\r\n}");
}

test "line endings: works at EOF" {
    const o = sjc.Options{ .whitespace = false };
    try check("{\r\n\t\"a\":\"b\"\r\n} //EOF", .{}, "{\r\n\t\"a\":\"b\"\r\n}      ");
    try check("{\r\n\t\"a\":\"b\"\r\n} //EOF", o, "{\r\n\t\"a\":\"b\"\r\n} ");
}

test "handles weird escaping" {
    const weird =
        \\{"x":"x \"sed -e \\\"s/^.\\\\{46\\\\}T//\\\" -e \\\"s/#033/\\\\x1b/g\\\"\""}
    ;
    const got = try sjc.stripJsonComments(t.allocator, weird, .{});
    defer t.allocator.free(got);
    try t.expectEqualStrings(weird, got);
}

test "strips trailing commas" {
    try check("{\"x\":true,}", .{ .trailing_commas = true }, "{\"x\":true }");
    try check("{\"x\":true,}", .{ .trailing_commas = true, .whitespace = false }, "{\"x\":true}");
    try check("{\"x\":true,\n  }", .{ .trailing_commas = true }, "{\"x\":true \n  }");
    try check("[true, false,]", .{ .trailing_commas = true }, "[true, false ]");
    try check("[true, false,]", .{ .trailing_commas = true, .whitespace = false }, "[true, false]");
    try check(
        "{\n  \"array\": [\n    true,\n    false,\n  ],\n}",
        .{ .trailing_commas = true, .whitespace = false },
        "{\n  \"array\": [\n    true,\n    false\n  ]\n}",
    );
    try check(
        "{\n  \"array\": [\n    true,\n    false /* comment */ ,\n /*comment*/ ],\n}",
        .{ .trailing_commas = true, .whitespace = false },
        "{\n  \"array\": [\n    true,\n    false  \n  ]\n}",
    );
}

test "handles malformed block comments" {
    try check("[] */", .{}, "[] */");
    try check("[] /*", .{}, "[] /*");
}

test "handles non-breaking space with preserved whitespace" {
    const fixture = "{\n\t// Comment with non-breaking-space: '\u{00A0}'\n\t\"a\": 1\n\t}";
    const stripped = try sjc.stripJsonComments(t.allocator, fixture, .{});
    defer t.allocator.free(stripped);

    var parsed = std.json.parseFromSlice(std.json.Value, t.allocator, stripped, .{}) catch |e| {
        std.debug.print("output not valid JSON: {s}\n", .{stripped});
        return e;
    };
    defer parsed.deinit();
    try t.expect(parsed.value == .object);
    try t.expect(parsed.value.object.get("a") != null);
}
