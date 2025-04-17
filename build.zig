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
        } else print_err("error: `{s}` is not in PATH\n", .{fmt.exe});
    }

    return total;
}

pub const Formatter = struct {
    exe: []const u8,
    args: []const []const u8,
};

// The returned path is an allocated string that needs to be freed.
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
        std.posix.access(full, std.posix.X_OK) catch {
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
    std.mem.copyForwards([]const u8, argv[1..], args);

    var child = std.process.Child.init(argv, alloc);
    child.stdout_behavior = .Pipe;
    try child.spawn();

    const reader = child.stdout.?.reader();
    var buf: [1024]u8 = undefined;
    var count: usize = 0;

    while (true) {
        const n = reader.read(&buf) catch |err| {
            // Ignore because if we propagate, it'll obscure the real error.
            _ = child.kill() catch {};
            return err;
        };
        if (n == 0) break;

        for (buf[0..n]) |char| {
            if (char == '\n') count += 1;
        }
    }

    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) {
            print_err("{s} exited with error {d}\n", .{ exe, code });
            return error.CommandErrored;
        },
        else => {
            print_err("{s} terminated unexpectedly\n", .{exe});
            return error.CommandFailed;
        },
    }

    return count;
}

// Basically is std.debug.print but using stdout.
fn print_out(comptime fmt: []const u8, args: anytype) void {
    std.io.getStdOut().writer().print(fmt, args) catch {};
}
const print_err = std.debug.print;

pub fn build(_: *std.Build) void {}
