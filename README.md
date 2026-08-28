# strip-json-comments

Strip comments from JSON — turning JSONC (commented JSON) into
something a strict parser accepts.

```zig
const std = @import("std");
const stripJsonComments = @import("strip_json_comments");

const input =
    \\{
    \\  // service port
    \\  "port": 8080,
    \\  "hosts": [ /* local only */ "localhost" ]
    \\}
;

const json = try stripJsonComments.stripJsonComments(allocator, input, .{});
defer allocator.free(json);

const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
defer parsed.deinit();
```

Comment markers inside string values are left untouched, including
escaped quotes, so URLs like `"https://example.com"` survive.

## Installation

Requires Zig 0.16.0.

```sh
zig fetch --save git+https://github.com/thelastbackspace/zig-strip-json-comments#v1.0.0
```

Then in `build.zig`:

```zig
const dep = b.dependency("strip_json_comments", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("strip_json_comments", dep.module("strip_json_comments"));
```

## API

### `stripJsonComments(allocator, json: []const u8, options: Options) ![]u8`

Returns a new string with `//` line comments and `/* */` block
comments removed. Caller owns the result. Unterminated block comments
are passed through unchanged.

### `Options`

- `whitespace: bool = true` — replace comment characters with spaces,
  preserving positions and line endings (useful for error messages
  that reference offsets in the original). When `false`, comments are
  removed entirely.
- `trailing_commas: bool = false` — also strip trailing commas before
  `}` and `]`, producing output that strict JSON parsers accept.

## Notes

- Whitespace replacement maps each Unicode code point in a comment to
  one space; upstream counts UTF-16 units, which differs only for
  astral-plane characters inside comments.
- Input is treated as bytes; UTF-8 sequences inside strings are
  copied verbatim.

## Testing

```sh
zig build test
```

The suite ports upstream's test file: whitespace vs removal, comments
inside strings, escaped quotes, CRLF/CR line endings, EOF comments,
trailing commas, malformed comments, and a non-breaking-space
round-trip through `std.json`.

## Contributing

PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). The CI gate
(`zig fmt --check`, tests, build) must pass.

## Credits

Behavior and the test suite follow the npm package
[`strip-json-comments`](https://github.com/sindresorhus/strip-json-comments)
v5.0.3 (MIT, © Sindre Sorhus); the implementation is original. Zig
implementation © 2026 thelastbackspace, MIT — see [LICENSE](LICENSE).
