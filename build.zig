const std = @import("std");
const XCFrameworkStep = @import("./XCFrameworkStep.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const deps = getDependencies(b, target);
    const lib = createStaticLib(b, null, optimize, deps);
    b.installArtifact(lib);

    const xcframework = XCFrameworkStep.create(b, .{
        .name = "SwashKit",
        .optimize = optimize,
        .root_source_file = "src/mic.zig",
        .configure_lib = configureXCFrameworkLib,
    });

    b.default_step.dependOn(xcframework.step);

    const exe = b.addExecutable(.{
        .name = "swash",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    configureExe(b, exe, deps);
    b.installArtifact(exe);
}

fn configureXCFrameworkLib(lib: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    const b = lib.step.owner;

    lib.addCSourceFile(.{ .file = b.path("src/miniaudio.c") });
    lib.addIncludePath(b.path("src"));

    const deps = getDependencies(b, target);

    lib.linkLibrary(deps.opusenc.artifact("opusenc"));
    lib.linkLibrary(deps.opusfile.artifact("opusfile"));
    lib.linkLibrary(deps.opus.artifact("opus"));

    if (target.result.isDarwin()) {
        lib.addSystemIncludePath(deps.macsdk.path("include"));
        lib.addSystemFrameworkPath(deps.macsdk.path("Frameworks"));
        lib.addLibraryPath(deps.macsdk.path("lib"));
        lib.linkFramework("CoreAudio");
    }
}

fn getDependencies(b: *std.Build, target: std.Build.ResolvedTarget) struct {
    opusenc: *std.Build.Dependency,
    opusfile: *std.Build.Dependency,
    opus: *std.Build.Dependency,
    macsdk: *std.Build.Dependency,
} {
    return .{
        .opusenc = b.dependency("opusenc", .{ .target = target, .optimize = .ReleaseSafe }),
        .opusfile = b.dependency("opusfile", .{ .target = target, .optimize = .ReleaseSafe }),
        .opus = b.dependency("opus", .{ .target = target, .optimize = .ReleaseSafe }),
        .macsdk = b.dependency("macsdk", .{ .target = target }),
    };
}

fn createStaticLib(
    b: *std.Build,
    target_query: ?std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
    deps: anytype,
) *std.Build.Step.Compile {
    const target = if (target_query) |tq| b.resolveTargetQuery(tq) else b.host;
    const lib = b.addStaticLibrary(.{
        .name = b.fmt("swash-{s}", .{target.result.osArchName()}),
        .root_source_file = b.path("src/mic.zig"),
        .target = target,
        .optimize = optimize,
    });
    configureLib(b, lib, deps);
    return lib;
}

fn configureLib(b: *std.Build, lib: *std.Build.Step.Compile, deps: anytype) void {
    lib.bundle_compiler_rt = true;
    lib.linkLibC();
    lib.linkLibrary(deps.opusenc.artifact("opusenc"));
    lib.linkLibrary(deps.opusfile.artifact("opusfile"));
    lib.linkLibrary(deps.opus.artifact("opus"));
    lib.addCSourceFile(.{ .file = b.path("src/miniaudio.c") });
    lib.addIncludePath(b.path("src"));

    if (lib.rootModuleTarget().isDarwin()) {
        configureMacFrameworks(lib, deps);
    }
}

fn configureMacFrameworks(lib: *std.Build.Step.Compile, deps: anytype) void {
    lib.addSystemIncludePath(deps.macsdk.path("include"));
    lib.addSystemFrameworkPath(deps.macsdk.path("Frameworks"));
    lib.addLibraryPath(deps.macsdk.path("lib"));
    lib.linkFramework("CoreAudio");
}

fn configureExe(b: *std.Build, exe: *std.Build.Step.Compile, deps: anytype) void {
    exe.addCSourceFile(.{ .file = b.path("src/miniaudio.c") });
    exe.addIncludePath(b.path("src"));
    exe.linkLibrary(deps.opusenc.artifact("opusenc"));
    exe.linkLibrary(deps.opusfile.artifact("opusfile"));
    exe.linkLibrary(deps.opus.artifact("opus"));
}
