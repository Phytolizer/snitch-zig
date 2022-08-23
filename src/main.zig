const std = @import("std");
const pcre = @import("pcre.zig");
const ini = @import("ini");

const Allocator = std.mem.Allocator;
const Regex = pcre.Regex;

fn openFile(path: []const u8) std.fs.File.OpenError!std.fs.File {
    if (std.fs.path.isAbsolute(path)) {
        return std.fs.openFileAbsolute(path, .{});
    }
    return std.fs.cwd().openFile(path, .{});
}

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
        return error.NotImplemented;
    }
};

const GithubCredentials = struct {
    allocator: Allocator,
    personalToken: []u8,

    pub fn fromFile(allocator: Allocator, filepath: []const u8) !GithubCredentials {
        const file = openFile(filepath) catch |e| {
            std.debug.print("opening {s}: {s}\n", .{ filepath, @errorName(e) });
            return e;
        };
        defer file.close();

        var parser = ini.parse(allocator, file.reader());
        defer parser.deinit();

        var githubSection = false;
        var personalToken: ?[]u8 = null;
        while (try parser.next()) |record| {
            switch (record) {
                .section => |heading| {
                    githubSection = std.mem.eql(u8, heading, "github");
                },
                .property => |kv| {
                    if (githubSection and std.mem.eql(u8, kv.key, "personal_token")) {
                        personalToken = try allocator.dupe(u8, kv.value);
                    }
                },
                .enumeration => {},
            }
        }

        if (personalToken) |tok| {
            return GithubCredentials{
                .allocator = allocator,
                .personalToken = tok,
            };
        }
        return error.NoPersonalToken;
    }

    pub fn deinit(self: *const GithubCredentials) void {
        self.allocator.free(self.personalToken);
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

const VisitError = error{NotImplemented} || Allocator.Error || std.fs.File.WriteError;

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
            defer t.deinit();
            try visit.cb(visit.state, t);
        }
    }
}

fn walkTodosOfDir(allocator: Allocator, dirpath: []const u8, comptime State: type, visit: VisitFn(State)) !void {
    defer switch (@typeInfo(State)) {
        .Struct => if (@hasDecl(State, "deinit")) {
            visit.state.deinit();
        },
        else => {},
    };
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
            try std.io.getStdOut().writer().print("{s}\n", .{t});
        }
    }.visitTodo;

    try walkTodosOfDir(allocator, ".", void, .{ .cb = visitTodo, .state = {} });
}

fn reportTodo(_: Todo, _: GithubCredentials, _: []const u8) !Todo {
    return error.NotImplemented;
}

fn reportSubcommand(allocator: Allocator, creds: GithubCredentials, repo: []const u8) !void {
    defer creds.deinit();
    var reportedTodos = std.ArrayList(Todo).init(allocator);
    errdefer reportedTodos.deinit();

    const State = struct {
        reportedTodos: std.ArrayList(Todo),
        creds: GithubCredentials,
        repo: []const u8,

        pub fn deinit(self: *const @This()) void {
            self.reportedTodos.deinit();
        }
    };

    const reportCb = struct {
        pub fn reportCb(state: *State, t: Todo) VisitError!void {
            if (t.id == null) {
                const reportedTodo = try reportTodo(t, state.creds, state.repo);
                try std.io.getStdOut().writer().print("[REPORTED] {s}\n", .{t});
                try state.reportedTodos.append(reportedTodo);
            }
        }
    }.reportCb;

    try walkTodosOfDir(allocator, ".", *State, .{
        .cb = reportCb,
        .state = &.{
            .reportedTodos = reportedTodos,
            .creds = creds,
            .repo = repo,
        },
    });

    for (reportedTodos.items) |*t| {
        try t.update();
    }
}

fn getCredsPath(allocator: Allocator) ![]u8 {
    if (std.os.getenv("XDG_CONFIG_HOME")) |xdg| {
        return try std.fs.path.join(allocator, &.{ xdg, "snitch", "github.ini" });
    }
    if (std.os.getenv("HOME")) |home| {
        return try std.fs.path.join(allocator, &.{ home, ".config", "snitch", "github.ini" });
    }
    var cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);
    return try std.fs.path.join(allocator, &.{ cwd, "config", "github.ini" });
}

fn usage() void {
    std.debug.print(
        \\snitch <subcommand>
        \\    list: lists all TODOs in the current directory
        \\    report <owner/repo>: reports TODOs in the current directory
        \\
    , .{});
}

pub fn main() !void {
    var gpAllocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpAllocator.detectLeaks();
    const allocator = gpAllocator.allocator();
    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        usage();
        return error.InvalidUsage;
    }

    if (std.mem.eql(u8, args[1], "list")) {
        try listSubcommand(allocator);
    } else if (std.mem.eql(u8, args[1], "report")) {
        if (args.len < 3) {
            usage();
            return error.InvalidUsage;
        }
        const credsPath = try getCredsPath(allocator);
        defer allocator.free(credsPath);
        try reportSubcommand(allocator, try GithubCredentials.fromFile(allocator, credsPath), args[2]);
    } else {
        std.debug.print("`{s}` unknown command\n", .{args[1]});
        return error.InvalidUsage;
    }
}
