// https://gist.github.com/mitchellh/0ee168fb34915e96159b558b89c9a74b

const std = @import("std");
const Step = std.Build.Step;
const RunStep = std.Build.Step.Run;
const LazyPath = std.Build.LazyPath;

pub const XCFrameworkStep = struct {
    step: Step,

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
            .step = run_create.step,
        };

        return self;
    }
};

pub fn getStep(self: *XCFrameworkStep) *Step {
    return &self.step;
}

pub const LipoStep = struct {
    step: *Step,
    output: LazyPath,

    pub const Options = struct {
        /// The name of the xcframework to create.
        name: []const u8,

        /// The filename (not the path) of the file to create.
        out_name: []const u8,

        /// Library file (dylib, a) to package.
        input_a: LazyPath,
        input_b: LazyPath,
    };

    pub fn create(b: *std.Build, opts: Options) *LipoStep {
        const self = b.allocator.create(LipoStep) catch @panic("OOM");

        const run_step = RunStep.create(b, b.fmt("lipo {s}", .{opts.name}));
        run_step.addArgs(&.{ "lipo", "-create", "-output" });
        const output = run_step.addOutputFileArg(opts.out_name);
        run_step.addFileArg(opts.input_a);
        run_step.addFileArg(opts.input_b);

        self.* = .{
            .step = &run_step.step,
            .output = output,
        };

        return self;
    }
};

pub const LibtoolStep = struct {
    step: *Step,
    output: LazyPath,

    pub const Options = struct {
        /// The name of this step.
        name: []const u8,

        /// The filename (not the path) of the file to create. This will
        /// be placed in a unique hashed directory. Use out_path to access.
        out_name: []const u8,

        /// Library files (.a) to combine.
        sources: []const LazyPath,
    };

    pub fn create(b: *std.Build, opts: Options) *LibtoolStep {
        const self = b.allocator.create(LibtoolStep) catch @panic("OOM");

        const run_step = RunStep.create(b, b.fmt("libtool {s}", .{opts.name}));
        run_step.addArgs(&.{ "libtool", "-static", "-o" });
        const output = run_step.addOutputFileArg(opts.out_name);
        for (opts.sources) |source| run_step.addFileArg(source);

        self.* = .{
            .step = &run_step.step,
            .output = output,
        };

        return self;
    }
};
