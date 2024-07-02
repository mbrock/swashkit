const std = @import("std");
const XCFrameworkStep = @import("./XCFrameworkStep.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = createStaticLib(b, null, optimize);
    b.installArtifact(lib);

    const xcframework = XCFrameworkStep.create(b, .{
        .name = "SwashKit",
        .optimize = optimize,
        .root_source_file = "src/mic.zig",
        .configure_lib = configureLib,
    });

    b.default_step.dependOn(xcframework.step);

    const exe = b.addExecutable(.{
        .name = "swash",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    configureLib(exe);
    b.installArtifact(exe);
}

fn createStaticLib(
    b: *std.Build,
    target_query: ?std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const target = if (target_query) |tq| b.resolveTargetQuery(tq) else b.host;
    const lib = b.addStaticLibrary(.{
        .name = b.fmt("swash-{s}", .{target.result.osArchName()}),
        .root_source_file = b.path("src/mic.zig"),
        .target = target,
        .optimize = optimize,
    });
    configureLib(lib);
    return lib;
}

fn configureLib(lib: *std.Build.Step.Compile) void {
    const b = lib.step.owner;
    lib.bundle_compiler_rt = true;
    lib.linkLibC();
    lib.addCSourceFile(.{ .file = b.path("src/miniaudio.c") });
    lib.addIncludePath(b.path("src"));

    const target = lib.root_module.resolved_target.?;
    const opusenc = b.dependency("opusenc", .{ .target = target, .optimize = .ReleaseSafe });
    const opusfile = b.dependency("opusfile", .{ .target = target, .optimize = .ReleaseSafe });
    const opus = b.dependency("opus", .{ .target = target, .optimize = .ReleaseSafe });
    const macsdk = b.dependency("macsdk", .{ .target = target });

    lib.linkLibrary(opusenc.artifact("opusenc"));
    lib.linkLibrary(opusfile.artifact("opusfile"));
    lib.linkLibrary(opus.artifact("opus"));

    if (lib.rootModuleTarget().isDarwin()) {
        lib.addSystemIncludePath(macsdk.path("include"));
        lib.addSystemFrameworkPath(macsdk.path("Frameworks"));
        lib.addLibraryPath(macsdk.path("lib"));
        lib.linkFramework("CoreAudio");
    }
}
