const std = @import("std");
const LibtoolStep = @import("./LibtoolStep.zig");
const XCFrameworkStep = @import("./XCFrameworkStep.zig");
const LipoStep = @import("./LipoStep.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const deps = getDependencies(b, target);

    const lib = createStaticLib(b, null, optimize, deps);
    const lib_aarch64 = createStaticLib(b, .aarch64, optimize, deps);
    const lib_x86_64 = createStaticLib(b, .x86_64, optimize, deps);

    const universal_lib = createUniversalBinary(b, lib_aarch64, lib_x86_64);
    const libtool = createLibtoolBundle(b, universal_lib, deps);
    const xcframework = createXCFramework(b, libtool);

    b.step("xcframework", "Create XCFramework").dependOn(xcframework.step);

    const exe = b.addExecutable(.{
        .name = "swash",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    configureExe(b, exe, deps);

    b.installArtifact(lib);
    b.installArtifact(exe);

    _ = createRunCommand(b, exe);
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
    arch: ?std.Target.Cpu.Arch,
    optimize: std.builtin.OptimizeMode,
    deps: anytype,
) *std.Build.Step.Compile {
    const target = b.resolveTargetQuery(.{ .cpu_arch = arch, .os_tag = .macos });
    const lib = b.addStaticLibrary(.{
        .name = b.fmt("swash-{s}", .{target.result.osArchName()}),
        .root_source_file = b.path("src/mic.zig"),
        .target = target,
        .optimize = optimize,
    });
    configureLib(b, lib, deps);
    return lib;
}

fn createUniversalBinary(
    b: *std.Build,
    lib_aarch64: *std.Build.Step.Compile,
    lib_x86_64: *std.Build.Step.Compile,
) *LipoStep {
    return LipoStep.create(b, .{
        .name = "swash-universal",
        .out_name = "libswash.a",
        .input_a = lib_aarch64.getEmittedBin(),
        .input_b = lib_x86_64.getEmittedBin(),
    });
}

fn configureLib(b: *std.Build, lib: *std.Build.Step.Compile, deps: anytype) void {
    lib.bundle_compiler_rt = true;
    lib.linkLibC();
    lib.linkLibrary(deps.opusenc.artifact("opusenc"));
    lib.linkLibrary(deps.opusfile.artifact("opusfile"));
    lib.linkLibrary(deps.opus.artifact("opus"));
    lib.addCSourceFile(.{ .file = b.path("src/miniaudio.c") });
    lib.addIncludePath(b.path("src"));

    lib.addSystemIncludePath(deps.macsdk.path("include"));
    lib.addSystemFrameworkPath(deps.macsdk.path("Frameworks"));
    lib.addLibraryPath(deps.macsdk.path("lib"));
    lib.linkFramework("CoreAudio");
}

fn createLibtoolBundle(b: *std.Build, universal_lib: *LipoStep, deps: anytype) *LibtoolStep {
    const libtool = LibtoolStep.create(b, .{
        .name = "swash",
        .out_name = "swash-bundle.a",
        .sources = &[_]std.Build.LazyPath{
            universal_lib.output,
            deps.opusenc.artifact("opusenc").getEmittedBin(),
            deps.opusfile.artifact("opusfile").getEmittedBin(),
            deps.opus.artifact("opus").getEmittedBin(),
        },
    });

    libtool.step.dependOn(universal_lib.step);

    return libtool;
}

fn createXCFramework(b: *std.Build, libtool: *LibtoolStep) *XCFrameworkStep {
    const xcframework = XCFrameworkStep.create(b, .{
        .name = "SwashKit",
        .out_path = "build/SwashKit.xcframework",
        .library = libtool.output,
        .headers = b.path("include"),
    });
    xcframework.step.dependOn(libtool.step);

    return xcframework;
}

fn configureExe(b: *std.Build, exe: *std.Build.Step.Compile, deps: anytype) void {
    exe.addCSourceFile(.{ .file = b.path("src/miniaudio.c") });
    exe.addIncludePath(b.path("src"));
    exe.linkLibrary(deps.opusenc.artifact("opusenc"));
    exe.linkLibrary(deps.opusfile.artifact("opusfile"));
    exe.linkLibrary(deps.opus.artifact("opus"));
}

fn createRunCommand(b: *std.Build, exe: *std.Build.Step.Compile) *std.Build.Step.Run {
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    return run_cmd;
}
