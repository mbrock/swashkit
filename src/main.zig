const std = @import("std");
const Mic = @import("mic.zig");

var global_ctx: ?*Mic = null;

fn trap(sig: c_int) callconv(.C) void {
    std.debug.assert(sig == std.posix.SIG.INT);

    if (global_ctx) |ctx| {
        ctx.stop() catch {
            std.debug.panic("failed to stop\n", .{});
        };
        ctx.free();
        std.process.exit(0);
    }
}

fn recv(ctx: *Mic) callconv(.C) void {
    std.io.getStdOut().writeAll(ctx.buf) catch {
        std.debug.panic("failed to write to stdout\n", .{});
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const mem = gpa.allocator();

    var ctx = try Mic.create(mem, recv, null);
    defer ctx.free();

    global_ctx = ctx;

    try std.posix.sigaction(std.posix.SIG.INT, &std.posix.Sigaction{
        .handler = .{ .handler = trap },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    }, null);

    var dev: ?usize = null;
    const n = try ctx.scan();

    if (n == 0) {
        std.debug.panic("no audio devices found\n", .{});
    }

    {
        const args = try std.process.argsAlloc(mem);
        defer std.process.argsFree(mem, args);

        if (args.len < 2) {
            for (0..n) |i| {
                std.debug.print("{s}\n", .{ctx.dev[i].name});
            }
            return;
        }

        for (0..n) |i| {
            const name: [*:0]const u8 = @ptrCast(@alignCast(&ctx.dev[i].name));
            if (std.mem.eql(u8, std.mem.span(name), args[1])) {
                dev = i;
                break;
            }
        }

        if (dev == null) {
            std.debug.panic("device not found\n", .{});
        }
    }

    std.debug.print("recording from {s}\n", .{ctx.dev[dev.?].name});
    _ = try ctx.play(dev.?);

    // C-d to stop
    const stdin = std.io.getStdIn();
    const reader = stdin.reader();
    while (true) {
        _ = reader.readByte() catch {
            break;
        };
    }

    try ctx.stop();
}
