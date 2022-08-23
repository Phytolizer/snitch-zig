const std = @import("std");
const builtin = @import("builtin");
const pkgs = @import("deps.zig").pkgs;

pub fn build(b: *std.build.Builder) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("snitch-zig", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    try linkPcre(exe);
    linkCurl(exe);
    pkgs.addAllTo(exe);
    exe.install();
    exe.use_stage1 = true;

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.expected_exit_code = null;
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}

fn linkPcre(exe: *std.build.LibExeObjStep) !void {
    exe.linkLibC();
    switch (builtin.os.tag) {
        .windows => {
            try exe.addVcpkgPaths(.static);
        },
        else => {},
    }
    exe.linkSystemLibrary("pcre2-8");
}

fn linkCurl(step: *std.build.LibExeObjStep) void {
    var libs = if (builtin.os.tag == .windows) [_][]const u8{
        "c",
        "curl",
        "bcrypt",
        "crypto",
        "crypt32",
        "ws2_32",
        "wldap32",
        "ssl",
        "psl",
        "iconv",
        "idn2",
        "unistring",
        "z",
        "zstd",
        "nghttp2",
        "ssh2",
        "brotlienc",
        "brotlidec",
        "brotlicommon",
    } else [_][]const u8{ "c", "curl" };
    for (libs) |i| {
        step.linkSystemLibrary(i);
    }
    if (builtin.os.tag == .linux) {
        step.linkSystemLibraryNeeded("libcurl");
    }
    if (builtin.os.tag == .windows) {
        step.include_dirs.append(.{ .raw_path = "c:/msys64/mingw64/include" }) catch unreachable;
        step.lib_paths.append("c:/msys64/mingw64/lib") catch unreachable;
    }
}
