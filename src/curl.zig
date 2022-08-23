const std = @import("std");
const c = @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", "1");
    @cInclude("curl/curl.h");
    @cInclude("string.h");
});

const Allocator = std.mem.Allocator;

pub const Response = struct {
    allocator: Allocator,
    hasStatus: bool = false,
    status: c_long = undefined,
    headers: Headers,
    body: std.ArrayList(u8),

    pub fn init(allocator: Allocator) Response {
        return Response{
            .allocator = allocator,
            .headers = Headers.init(allocator),
            .body = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *const Response) void {
        for (self.headers.items) |h| {
            self.allocator.free(h.name);
            self.allocator.free(h.value);
        }
        self.headers.deinit();
        self.body.deinit();
    }
};

pub const Options = struct {
    allocator: Allocator,
    headers: ?*Headers = null,
    body: ?[]const u8 = null,
};

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const Headers = std.ArrayList(Header);

pub const Error = error{
    CurlEasyInitFailed,
    CurlEasyPerformFailed,
} || Allocator.Error;

pub fn post(url: []const u8, options: Options) Error!Response {
    var curl = c.curl_easy_init();
    if (curl == null) {
        return error.CurlEasyInitFailed;
    }
    defer c.curl_easy_cleanup(curl);

    var urlC = try std.cstr.addNullByte(options.allocator, url);
    defer options.allocator.free(urlC);
    _ = c.curl_easy_setopt(curl, c.CURLOPT_URL, @ptrCast([*c]const u8, urlC.ptr));
    _ = c.curl_easy_setopt(curl, c.CURLOPT_POST, @as(c_long, 1));
    _ = c.curl_easy_setopt(curl, c.CURLOPT_FOLLOWLOCATION, @as(c_long, 1));
    _ = c.curl_easy_setopt(curl, c.CURLOPT_SSL_VERIFYPEER, @as(c_long, 1));

    var headerChunk: [*c]c.curl_slist = null;
    defer c.curl_slist_free_all(headerChunk);
    if (options.headers) |headers| {
        for (headers.items) |header| {
            var text = try std.mem.concatWithSentinel(options.allocator, u8, &.{ header.name, ": ", header.value }, 0);
            defer options.allocator.free(text);
            headerChunk = c.curl_slist_append(headerChunk, @ptrCast([*c]const u8, text.ptr));
        }
        _ = c.curl_easy_setopt(curl, c.CURLOPT_HTTPHEADER, headerChunk);
    }

    const Context = struct {
        curl: ?*c.CURL,
        body: []const u8,
        response: Response,

        const Self = @This();

        pub fn init(curlP: ?*c.CURL, body: []const u8, allocator: Allocator) Self {
            return Self{
                .curl = curlP,
                .body = body,
                .response = Response.init(allocator),
            };
        }

        pub fn headerFn(ptr: [*]const u8, size: usize, nmemb: usize, ctx: *Self) usize {
            const data = ptr[0 .. size * nmemb];
            if (!ctx.response.hasStatus) {
                ctx.response.hasStatus = true;
                _ = c.curl_easy_getinfo(ctx.curl, c.CURLINFO_RESPONSE_CODE, &ctx.response.status);
            }
            if (std.mem.indexOfScalar(u8, data, ':')) |i| {
                var name = ctx.response.allocator.dupe(u8, data[0..i]) catch unreachable;
                var valuePos = i + 1;
                while (valuePos < data.len and data[valuePos] == ' ') {
                    valuePos += 1;
                }
                var value = ctx.response.allocator.dupe(u8, data[valuePos..]) catch unreachable;
                ctx.response.headers.append(.{
                    .name = name,
                    .value = value,
                }) catch unreachable;
            }
            return size * nmemb;
        }

        pub fn readFn(dest: [*]u8, size: usize, nmemb: usize, ctx: *Self) usize {
            const bufferSize = size * nmemb;
            if (ctx.body.len > 0) {
                const n = std.math.min(ctx.body.len, bufferSize);
                std.mem.copy(u8, dest[0..n], ctx.body[0..n]);
                ctx.body = ctx.body[n..];
                return n;
            }
            return 0;
        }

        pub fn writeFn(contents: [*]const u8, size: usize, nmemb: usize, ctx: *Self) usize {
            const realsize = size * nmemb;
            ctx.response.body.appendSlice(contents[0..realsize]) catch unreachable;
            return realsize;
        }
    };
    var ctx = Context.init(curl, options.body orelse "", options.allocator);

    _ = c.curl_easy_setopt(curl, c.CURLOPT_HEADERFUNCTION, Context.headerFn);
    _ = c.curl_easy_setopt(curl, c.CURLOPT_HEADERDATA, &ctx);
    _ = c.curl_easy_setopt(curl, c.CURLOPT_READFUNCTION, Context.readFn);
    _ = c.curl_easy_setopt(curl, c.CURLOPT_READDATA, &ctx);
    _ = c.curl_easy_setopt(curl, c.CURLOPT_WRITEFUNCTION, Context.writeFn);
    _ = c.curl_easy_setopt(curl, c.CURLOPT_WRITEDATA, &ctx);

    const res = c.curl_easy_perform(curl);
    if (res != c.CURLE_OK) {
        const cError = c.curl_easy_strerror(res);
        const err = cError[0..@intCast(usize, c.strlen(cError))];
        std.debug.print("curl_easy_perform failed: {s}\n", .{err});
        return error.CurlEasyPerformFailed;
    }

    return ctx.response;
}
