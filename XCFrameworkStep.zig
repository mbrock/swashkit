//! A zig builder step that runs "swift build" in the context of
//! a Swift project managed with SwiftPM. This is primarily meant to build
//! executables currently since that is what we build.
const XCFrameworkStep = @This();

const std = @import("std");
const Step = std.Build.Step;
const RunStep = std.Build.Step.Run;
const FileSource = std.Build.LazyPath;

pub const Options = struct {
    /// The name of the xcframework to create.
    name: []const u8,

    /// The path to write the framework
    out_path: []const u8,

    /// Library file (dylib, a) to package.
    library: std.Build.LazyPath,

    /// Path to a directory with the headers.
    headers: std.Build.LazyPath,
};

step: *Step,

pub fn create(b: *std.Build, opts: Options) *XCFrameworkStep {
    const self = b.allocator.create(XCFrameworkStep) catch @panic("OOM");

    // We have to delete the old xcframework first since we're writing
    // to a static path.
    const run_delete = run: {
        const run = RunStep.create(b, b.fmt("xcframework delete {s}", .{opts.name}));
        run.has_side_effects = true;
        run.addArgs(&.{ "rm", "-rf", opts.out_path });
        break :run run;
    };

    // Then we run xcodebuild to create the framework.
    const run_create = run: {
        const run = RunStep.create(b, b.fmt("xcframework {s}", .{opts.name}));
        run.has_side_effects = true;
        run.addArgs(&.{ "xcodebuild", "-create-xcframework" });
        run.addArg("-library");
        run.addFileArg(opts.library);
        run.addArg("-headers");
        run.addFileArg(opts.headers);
        run.addArg("-output");
        run.addArg(opts.out_path);
        break :run run;
    };
    run_create.step.dependOn(&run_delete.step);

    self.* = .{
        .step = &run_create.step,
    };

    return self;
}
