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

    pub fn deinit(self: *const Todo) void {
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

    pub fn update(_: *Todo) !void {
        todo("Todo.update() is not implemented", .{});
    }
};

const GithubCredentials = struct {
    pub fn fromFile(_: []const u8) !GithubCredentials {
        return GithubCredentials{};
    }
};

fn lineAsUnreportedTodo(allocator: Allocator, line: []const u8) !?Todo {
    var unreportedTodo = try Regex.compile("^(.*)TODO: (.*)$", .{});
    defer unreportedTodo.deinit();

    const groups = unreportedTodo.groups(allocator, line, 0, .{}) catch |e| switch (e) {
        error.NoMatch => return null,
        else => return e,
    };
    defer allocator.free(groups);
    return try Todo.init(allocator, groups[1], groups[2], null, "", 0);
}

fn lineAsReportedTodo(allocator: Allocator, line: []const u8) !?Todo {
    var reportedTodo = try Regex.compile("^(.*)TODO\\((.*)\\): (.*)$", .{});
    defer reportedTodo.deinit();

    const groups = reportedTodo.groups(allocator, line, 0, .{}) catch |e| switch (e) {
        error.NoMatch => return null,
        else => return e,
    };
    defer allocator.free(groups);
    return try Todo.init(allocator, groups[1], groups[3], groups[2], "", 0);
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

fn lineAsTodo(allocator: Allocator, line: []const u8) !?Todo {
    if (try lineAsUnreportedTodo(allocator, line)) |t|
        return t;
    if (try lineAsReportedTodo(allocator, line)) |t|
        return t;

    return null;
}

const VisitError = Allocator.Error || std.fs.File.WriteError;

fn VisitFn(comptime State: type) type {
    return struct {
        cb: fn (state: State, t: Todo) VisitError!void,
        state: State,
    };
}

fn walkTodosOfFile(allocator: Allocator, path: []const u8, comptime State: type, visit: VisitFn(State)) !void {
    var file = if (std.fs.path.isAbsolute(path))
        try std.fs.openFileAbsolute(path, .{})
    else
        try std.fs.cwd().openFile(path, .{});
    defer file.close();

    while (true) {
        var maybeLine = try readLine(allocator, file.reader());
        var line = maybeLine orelse break;
        defer allocator.free(line);

        if (try lineAsTodo(allocator, line)) |t| {
            try visit.cb(visit.state, t);
        }
    }
}

fn walkTodosOfDir(allocator: Allocator, dirpath: []const u8, comptime State: type, visit: VisitFn(State)) !void {
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
            try walkTodosOfFile(allocator, path, State, visit);
        }
    }
}

fn listSubcommand(allocator: Allocator) !void {
    const visitTodo = struct {
        pub fn visitTodo(_: void, t: Todo) VisitError!void {
            defer t.deinit();
            try std.io.getStdOut().writer().print("{s}\n", .{t});
        }
    }.visitTodo;

    try walkTodosOfDir(allocator, ".", void, .{ .cb = visitTodo, .state = {} });
}

const todo = std.debug.panic;

fn reportTodo(_: Todo, _: GithubCredentials) !Todo {
    todo("reportTodo is not implemented", .{});
}

fn reportSubcommand(allocator: Allocator, creds: GithubCredentials) !void {
    var reportedTodos = std.ArrayList(Todo).init(allocator);
    defer reportedTodos.deinit();

    const State = struct {
        reportedTodos: *std.ArrayList(Todo),
        creds: GithubCredentials,
    };

    const reportCb = struct {
        pub fn reportCb(state: State, t: Todo) VisitError!void {
            if (t.id == null) {
                const reportedTodo = try reportTodo(t, state.creds);
                try std.io.getStdOut().writer().print("[REPORTED] {s}\n", .{t});
                try state.reportedTodos.append(reportedTodo);
            }
        }
    }.reportCb;

    try walkTodosOfDir(allocator, ".", State, .{
        .cb = reportCb,
        .state = .{ .reportedTodos = &reportedTodos, .creds = creds },
    });

    for (reportedTodos.items) |*t| {
        try t.update();
    }
}

pub fn main() !void {
    var gpAllocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpAllocator.detectLeaks();
    const allocator = gpAllocator.allocator();
    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print(
            \\snitch <subcommand>
            \\    list: lists all TODOs in the current directory
            \\    report: reports TODOs in the current directory
            \\
        , .{});
        return error.InvalidUsage;
    }

    if (std.mem.eql(u8, args[1], "list")) {
        try listSubcommand(allocator);
    } else if (std.mem.eql(u8, args[1], "report")) {
        try reportSubcommand(allocator, try GithubCredentials.fromFile("~/.snitch/github.ini"));
    } else {
        std.debug.print("`{s}` unknown command\n", .{args[1]});
        return error.InvalidUsage;
    }
}
