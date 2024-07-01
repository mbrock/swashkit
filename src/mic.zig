const std = @import("std");
const c = @cImport({
    @cInclude("miniaudio.h");
});
const Opus = @import("./opus.zig");

const Ctx = @This();

pub fn Callback(comptime T: type) type {
    return *const fn (context: *T) callconv(.C) void;
}

mem: std.mem.Allocator,
fun: ?Callback(Ctx),
arg: ?*anyopaque = null,
buf: []const u8,
pcm: []const f32,
enc: Opus,
snd: *c.ma_context,
dev: []c.ma_device_info,
cfg: ?*c.ma_device_config = null,
mic: ?*c.ma_device = null,

pub fn create(
    mem: std.mem.Allocator,
    fun: ?Callback(Ctx),
    arg: ?*anyopaque,
) !*Ctx {
    const ctx = try mem.create(Ctx);
    ctx.* = .{
        .mem = mem,
        .arg = arg,
        .fun = fun,
        .pcm = &[_]f32{},
        .buf = &[_]u8{},
        .snd = try mem.create(c.ma_context),
        .dev = undefined,
        .cfg = null,
        .mic = null,
        .enc = Opus{},
    };

    try ctx.enc.init(48000, 2, 0);
    try ctx.enc.setApplication(Opus.Application.VoIP);
    try ctx.enc.setSignal(Opus.Signal.Voice);
    try ctx.enc.setBitrate(32000);
    try ctx.enc.setMuxingDelay(0);
    try ctx.enc.setDecisionDelay(0);

    if (c.ma_context_init(
        null,
        0,
        null,
        ctx.snd,
    ) != c.MA_SUCCESS) {
        return error.MiniaudioInitializationFailed;
    }

    return ctx;
}

pub fn free(self: *Ctx) void {
    if (self.cfg) |cfg| self.mem.destroy(cfg);
    if (self.mic) |dev| {
        _ = c.ma_device_stop(dev);
        c.ma_device_uninit(dev);
        self.mem.destroy(dev);
    }
    _ = c.ma_context_uninit(self.snd);
    self.mem.destroy(self.snd);
    self.mem.destroy(self);
}

pub fn scan(self: *Ctx) !c_uint {
    var device_ptr: [*c]c.ma_device_info = undefined;
    var device_count: c_uint = 0;

    if (c.ma_context_get_devices(
        self.snd,
        null,
        null,
        @ptrCast(&device_ptr),
        @ptrCast(&device_count),
    ) != c.MA_SUCCESS) {
        return error.DeviceEnumerationFailed;
    }

    self.dev = @as([*]c.ma_device_info, @ptrCast(device_ptr))[0..device_count];

    return device_count;
}

pub fn play(ctx: *Ctx, idx: usize) !void {
    const selected_device = &ctx.dev[idx];
    ctx.cfg = try ctx.mem.create(c.ma_device_config);
    ctx.cfg.?.* = c.ma_device_config_init(c.ma_device_type_capture);
    ctx.cfg.?.capture.pDeviceID = &selected_device.id;
    ctx.cfg.?.pUserData = ctx;
    ctx.cfg.?.sampleRate = 48000;
    ctx.cfg.?.periodSizeInMilliseconds = 20;
    ctx.cfg.?.capture.format = c.ma_format_f32;
    ctx.cfg.?.capture.channels = 2;
    ctx.cfg.?.dataCallback = onAudioData;

    ctx.mic = try ctx.mem.create(c.ma_device);

    if (c.ma_device_init(
        ctx.snd,
        ctx.cfg,
        ctx.mic,
    ) != c.MA_SUCCESS) {
        return error.DeviceInitializationFailed;
    }

    if (c.ma_device_start(ctx.mic) != c.MA_SUCCESS) {
        return error.DeviceStartFailed;
    }
}

pub fn stop(self: *Ctx) !void {
    if (self.mic) |dev| {
        if (c.ma_device_stop(dev) != c.MA_SUCCESS) {
            return error.DeviceStopFailed;
        }
    }

    try self.enc.stop();
}

fn onAudioData(
    device: [*c]c.ma_device,
    output: ?*anyopaque,
    input: ?*const anyopaque,
    frame_count: c_uint,
) callconv(.C) void {
    _ = output;
    const ctx = @as(*Ctx, @ptrCast(@alignCast(device[0].pUserData)));
    ctx.pcm = @as([*]const f32, @ptrCast(@alignCast(input)))[0..frame_count];

    const page = ctx.enc.work(ctx.pcm.ptr, ctx.pcm.len) catch |err| {
        std.debug.print("Audio encoding error: {}\n", .{err});
        @panic("Audio encoding failed");
    };

    ctx.buf = page;
    if (ctx.fun) |fun| fun(ctx);
}

fn handleOggPage(
    ptr: ?*anyopaque,
    data: [*c]const u8,
    frame_count: c_int,
) callconv(.C) c_int {
    _ = frame_count; // autofix
    _ = data; // autofix
    _ = ptr; // autofix

    return 0;
}

fn handleOpusPacket(
    ptr: ?*anyopaque,
    data: [*c]const u8,
    frame_count: c_int,
    flags: c_int,
) callconv(.C) c_int {
    _ = flags; // autofix
    _ = frame_count; // autofix
    _ = data; // autofix
    _ = ptr; // autofix
    // _ = flags; // autofix
    // const ctx = @as(*Ctx, @ptrCast(@alignCast(ptr)));
    // ctx.buf = data[0..@intCast(frame_count)];
    // if (ctx.fun) |callback| callback(ctx);
    return 0;
}

fn handleOpusClose(ptr: ?*anyopaque) callconv(.C) c_int {
    _ = ptr;
    return 0;
}

// C API

export fn mic_init(
    fun: ?*const anyopaque,
    arg: ?*anyopaque,
) callconv(.C) ?*Ctx {
    return Ctx.create(
        std.heap.c_allocator,
        @ptrCast(@alignCast(fun)),
        arg,
    ) catch null;
}

export fn mic_free(ctx: *Ctx) callconv(.C) void {
    ctx.free();
}

export fn mic_play(
    ctx: *Ctx,
    idx: usize,
) callconv(.C) c_int {
    ctx.play(idx) catch |err| {
        std.debug.print("Capture start error: {}\n", .{err});
        return -1;
    };
    return 0;
}

export fn mic_stop(ctx: *Ctx) callconv(.C) c_int {
    ctx.stop() catch |err| {
        std.debug.print("Capture stop error: {}\n", .{err});
        return -1;
    };
    return 0;
}

export fn mic_scan(ctx: *Ctx) callconv(.C) c_int {
    const device_count = ctx.scan() catch |err| {
        std.debug.print("Device scanning error: {}\n", .{err});
        return -1;
    };
    return @intCast(device_count);
}

export fn mic_arg(ctx: *Ctx) ?*anyopaque {
    return ctx.arg;
}

export fn mic_buf(
    ctx: *Ctx,
    ptr: *[*]const u8,
    len: *usize,
) void {
    ptr.* = ctx.buf.ptr;
    len.* = ctx.buf.len;
}

export fn mic_dev(
    ctx: *Ctx,
    idx: usize,
    ptr: *[*:0]const u8,
    tag: *c_uint,
) void {
    ptr.* = @ptrCast(&ctx.dev[idx].name);
    tag.* = @intFromBool(ctx.dev[idx].isDefault != 0);
}
