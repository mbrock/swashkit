const Self = @This();
const std = @import("std");

pub const c = @cImport({
    @cInclude("opusenc.h");
    @cInclude("opus.h");
});

pub const Application = enum(c_int) {
    VoIP = c.OPUS_APPLICATION_VOIP,
    Audio = c.OPUS_APPLICATION_AUDIO,
};

pub const Signal = enum(c_int) {
    Voice = c.OPUS_SIGNAL_VOICE,
    Music = c.OPUS_SIGNAL_MUSIC,
};

pub const Callbacks = c.OpusEncCallbacks;

enc: ?*c.OggOpusEnc = null,
callbacks: c.OpusEncCallbacks,

pub fn init(
    self: *Self,
    sampleRate: u32,
    channels: u32,
    family: c_int,
    arg: ?*anyopaque,
    fun: ?*const anyopaque,
) !void {
    var err: c_int = undefined;

    self.enc = c.ope_encoder_create_callbacks(
        &self.callbacks,
        arg,
        c.ope_comments_create(),
        @intCast(sampleRate),
        @intCast(channels),
        family,
        &err,
    );

    if (c.ope_encoder_ctl(self.enc, c.OPE_SET_PACKET_CALLBACK_REQUEST, fun, arg) != c.OPE_OK) {
        return error.SetPacketCallbackFailed;
    }

    self.callbacks.write = null;

    if (self.enc == null) {
        return error.EncoderCreationFailed;
    }
}

pub fn free(self: *Self) void {
    if (self.enc) |enc| {
        c.ope_encoder_destroy(enc);
        self.enc = null;
    }
}

pub fn work(self: *Self, pcm: [*]const f32, frameCount: usize) !void {
    if (c.ope_encoder_write_float(self.enc, pcm, @intCast(frameCount)) != c.OPE_OK) {
        return error.EncodingFailed;
    }
}

pub fn stop(self: *Self) !void {
    if (c.ope_encoder_drain(self.enc) != c.OPE_OK) {
        return error.DrainFailed;
    }
}

pub fn setApplication(self: *Self, application: Application) !void {
    if (c.ope_encoder_ctl(
        self.enc,
        c.OPUS_SET_APPLICATION_REQUEST,
        @intFromEnum(application),
    ) != c.OPE_OK) {
        return error.SetApplicationFailed;
    }
}

pub fn setSignal(self: *Self, signal: Signal) !void {
    if (c.ope_encoder_ctl(
        self.enc,
        c.OPUS_SET_SIGNAL_REQUEST,
        @intFromEnum(signal),
    ) != c.OPE_OK) {
        return error.SetSignalFailed;
    }
}

pub fn setBitrate(self: *Self, bitrate: c_int) !void {
    if (c.ope_encoder_ctl(self.enc, c.OPUS_SET_BITRATE_REQUEST, bitrate) != c.OPE_OK) {
        return error.SetBitrateFailed;
    }
}

pub fn setMuxingDelay(self: *Self, delay: c_int) !void {
    if (c.ope_encoder_ctl(self.enc, c.OPE_SET_MUXING_DELAY_REQUEST, delay) != c.OPE_OK) {
        return error.SetMuxingDelayFailed;
    }
}

pub fn setDecisionDelay(self: *Self, delay: c_int) !void {
    if (c.ope_encoder_ctl(self.enc, c.OPE_SET_DECISION_DELAY_REQUEST, delay) != c.OPE_OK) {
        return error.SetDecisionDelayFailed;
    }
}

pub const Comments = struct {
    comments: ?*c.OggOpusComments align(8),

    pub fn init() !Comments {
        const comments = c.ope_comments_create();
        if (comments == null) {
            return error.CommentsCreationFailed;
        }
        return Comments{ .comments = comments };
    }

    pub fn deinit(self: *Comments) void {
        if (self.comments) |comments| {
            c.ope_comments_destroy(comments);
            self.comments = null;
        }
    }
};
