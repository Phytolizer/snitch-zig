const std = @import("std");

const Allocator = std.mem.Allocator;

const Todo = struct {
    allocator: Allocator,
    prefix: []u8,
    suffix: []u8,
    id: ?[]u8,
    filename: []u8,
    line: usize,

    pub fn init(
        allocator: Allocator,
        prefix: []const u8,
        suffix: []const u8,
        id: ?[]const u8,
        filename: []const u8,
        line: usize,
    ) !Todo {
        return Todo{
            .allocator = allocator,
            .prefix = try allocator.dupe(u8, prefix),
            .suffix = try allocator.dupe(u8, suffix),
            .id = if (id) |i| try allocator.dupe(u8, i) else null,
            .filename = try allocator.dupe(u8, filename),
            .line = line,
        };
    }

    pub fn deinit(self: *Todo) void {
        self.allocator.free(self.prefix);
        self.allocator.free(self.suffix);
        if (self.id) |id| {
            self.allocator.free(id);
        }
        self.allocator.free(self.filename);
    }

    pub fn format(self: *const Todo, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("{s}:{d}: {s}TODO", .{ self.filename, self.line, self.prefix });
        if (self.id) |id| {
            try writer.print("({s})", .{id});
        }
        try writer.print(": {s}", .{self.suffix});
    }
};

fn todosOfDir(allocator: Allocator, dirpath: []const u8) ![]Todo {
    _ = dirpath;
    var todos = std.ArrayList(Todo).init(allocator);
    try todos.append(try Todo.init(allocator, "// ", "khooy", "#42", "main.go", 10));
    try todos.append(try Todo.init(allocator, "// ", "foo", null, "src/foo.go", 0));
    return todos.toOwnedSlice();
}

fn listSubcommand(allocator: Allocator) !void {
    var todos = try todosOfDir(allocator, ".");
    defer allocator.free(todos);
    for (todos) |*t| {
        defer t.deinit();
        try std.io.getStdOut().writer().print("{s}\n", .{t});
    }
}

fn todo(comptime message: []const u8) noreturn {
    std.debug.panic(message, .{});
}

fn reportSubcommand(allocator: Allocator) !void {
    _ = allocator;
    todo("report is not implemented");
}

pub fn main() !void {
    var gpAllocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpAllocator.detectLeaks();
    const allocator = gpAllocator.allocator();
    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (std.mem.eql(u8, args[1], "list")) {
        try listSubcommand(allocator);
    } else if (std.mem.eql(u8, args[1], "report")) {
        try reportSubcommand(allocator);
    } else {
        std.debug.panic("`{s}` unknown command", .{args[1]});
    }
}
