const builtin = @import("builtin");
const std = @import("std");

pub fn format(
    alloc: std.mem.Allocator,
    fmts: []const Formatter,
    print: bool,
) !usize {
    const path_env = try std.process.getEnvVarOwned(alloc, "PATH");
    defer alloc.free(path_env);

    var total: usize = 0;
    for (fmts) |fmt| {
        if (try find_exe(alloc, path_env, fmt.exe)) |path| {
            defer alloc.free(path);

            const count = try exe_and_count(alloc, fmt.exe, fmt.args);
            total += count;

            if (print and count != 0)
                print_out("{s}: {d}\n", .{ fmt.exe, count });
        } else std.debug.print("error: `{s}` is not in PATH\n", .{fmt.exe});
    }

    return total;
}

pub const Formatter = struct {
    exe: []const u8,
    args: []const []const u8,
};

fn find_exe(
    alloc: std.mem.Allocator,
    path: []const u8,
    exe: []const u8,
) !?[]const u8 {
    var split = std.mem.splitScalar(
        u8,
        path,
        if (builtin.target.os.tag == .windows) ';' else ':',
    );

    while (split.next()) |dir| {
        if (dir.len == 0)
            continue;

        const full = try std.fs.path.join(alloc, &.{ dir, exe });
        std.posix.access(full, 1) catch {
            alloc.free(full);
            continue;
        };

        return full;
    }
    return null;
}

fn exe_and_count(
    alloc: std.mem.Allocator,
    exe: []const u8,
    args: []const []const u8,
) !usize {
    const argv = try alloc.alloc([]const u8, args.len + 1);
    defer alloc.free(argv);

    argv[0] = exe;
    @memcpy(argv[1..], args);

    var child = std.process.Child.init(argv, alloc);
    child.stdout_behavior = .Pipe;
    try child.spawn();

    const bytes = try child.stdout.?.reader().readAllAlloc(alloc, 1024);
    defer alloc.free(bytes);

    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) {
            std.debug.print("{s} exited with error {d}\n", .{ exe, code });
            return error.CommandErrored;
        },
        else => {
            std.debug.print("{s} terminated unexpectedly\n", .{exe});
            return error.CommandFailed;
        },
    }

    var count: usize = 0;
    for (bytes) |char| {
        if (char == '\n') count += 1;
    }

    return count;
}

fn print_out(comptime fmt: []const u8, args: anytype) void {
    std.io.getStdOut().writer().print(fmt, args) catch {};
}

pub fn build(_: *std.Build) void {}
