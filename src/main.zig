const std = @import("std");
const pcre = @import("pcre.zig");

const Allocator = std.mem.Allocator;
const Regex = pcre.Regex;

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

fn lineAsTodo(allocator: Allocator, line: []const u8) !?Todo {
    var unreportedTodo = try Regex.compile("^(.*)TODO: (.*)$", .{});
    defer unreportedTodo.deinit();

    const groups = unreportedTodo.groups(allocator, line, 0, .{}) catch |e| switch (e) {
        error.NoMatch => return null,
        else => return e,
    };
    defer allocator.free(groups);
    return try Todo.init(allocator, groups[1], groups[2], null, "", 0);
}

fn readLine(allocator: Allocator, reader: anytype) !?[]u8 {
    var len: usize = 1024;
    while (true) {
        return reader.readUntilDelimiterOrEofAlloc(allocator, '\n', len) catch |e| switch (e) {
            error.StreamTooLong => {
                len *= 2;
                continue;
            },
            else => return e,
        };
    }
}

fn todosOfFile(allocator: Allocator, path: []const u8) ![]Todo {
    var todos = std.ArrayList(Todo).init(allocator);
    var file = if (std.fs.path.isAbsolute(path))
        try std.fs.openFileAbsolute(path, .{})
    else
        try std.fs.cwd().openFile(path, .{});
    defer file.close();

    while (true) {
        var line = try readLine(allocator, file.reader()) orelse
            break;
        defer allocator.free(line);

        if (try lineAsTodo(allocator, line)) |t| {
            try todos.append(t);
        }
    }
    return todos.toOwnedSlice();
}

fn todosOfDir(allocator: Allocator, dirpath: []const u8) ![]Todo {
    var todos = std.ArrayList(Todo).init(allocator);
    var dir = if (std.fs.path.isAbsolute(dirpath))
        try std.fs.openIterableDirAbsolute(dirpath, .{})
    else
        try std.fs.cwd().openIterableDir(dirpath, .{});
    defer dir.close();
    var iter = try dir.walk(allocator);
    defer iter.deinit();
    while (try iter.next()) |entry| {
        if (entry.kind == .File) {
            const path = try std.fs.path.join(allocator, &.{ dirpath, entry.path });
            defer allocator.free(path);
            var fileTodos = try todosOfFile(allocator, path);
            defer allocator.free(fileTodos);
            try todos.appendSlice(fileTodos);
        }
    }
    return todos.toOwnedSlice();
}

fn listSubcommand(allocator: Allocator) !void {
    var todos = try todosOfDir(allocator, "src");
    defer {
        for (todos) |*t| {
            t.deinit();
        }
        allocator.free(todos);
    }
    for (todos) |t| {
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

    if (args.len < 2) {
        std.debug.print(
            \\snitch [opt]
            \\    list: lists all TODOs in the current directory
            \\    report: reports TODOs in the current directory
            \\
        , .{});
        return error.InvalidUsage;
    }

    if (std.mem.eql(u8, args[1], "list")) {
        try listSubcommand(allocator);
    } else if (std.mem.eql(u8, args[1], "report")) {
        try reportSubcommand(allocator);
    } else {
        std.debug.print("`{s}` unknown command\n", .{args[1]});
        return error.InvalidUsage;
    }
}
