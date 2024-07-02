// https://gist.github.com/mitchellh/0ee168fb34915e96159b558b89c9a74b

const std = @import("std");
const Step = std.Build.Step;
const RunStep = std.Build.Step.Run;
const LazyPath = std.Build.LazyPath;

pub const XCFrameworkBuilder = struct {
    b: *std.Build,
    name: []const u8,
    optimize: std.builtin.OptimizeMode,
    root_source_file: []const u8,
    configure_lib: *const fn (*std.Build.Step.Compile, *XCFrameworkBuilder, std.Build.ResolvedTarget) void,

    pub fn init(
        b: *std.Build,
        name: []const u8,
        optimize: std.builtin.OptimizeMode,
        root_source_file: []const u8,
        configure_lib: fn (*std.Build.Step.Compile, *XCFrameworkBuilder, std.Build.ResolvedTarget) void,
    ) XCFrameworkBuilder {
        return .{
            .b = b,
            .name = name,
            .optimize = optimize,
            .root_source_file = root_source_file,
            .configure_lib = configure_lib,
        };
    }

    pub fn build(self: *XCFrameworkBuilder) *XCFrameworkStep {
        const mac_libs = self.createMacLibs();
        const universal_lib = self.createUniversalBinary(mac_libs.aarch64, mac_libs.x86_64);
        const libtool = self.createLibtoolBundle(universal_lib, mac_libs);
        return self.createXCFramework(libtool);
    }

    const MacLibs = struct { aarch64: *std.Build.Step.Compile, x86_64: *std.Build.Step.Compile };

    fn createMacLibs(self: *XCFrameworkBuilder) MacLibs {
        const lib_aarch64 = self.createStaticLib(.{ .cpu_arch = .aarch64, .os_tag = .macos });
        const lib_x86_64 = self.createStaticLib(.{ .cpu_arch = .x86_64, .os_tag = .macos });
        return .{ .aarch64 = lib_aarch64, .x86_64 = lib_x86_64 };
    }

    fn createStaticLib(self: *XCFrameworkBuilder, target_query: std.zig.CrossTarget) *std.Build.Step.Compile {
        const target = self.b.resolveTargetQuery(target_query);
        const lib = self.b.addStaticLibrary(.{
            .name = self.b.fmt("{s}-{s}", .{ self.name, target.result.osArchName() }),
            .root_source_file = self.b.path(self.root_source_file),
            .target = target,
            .optimize = self.optimize,
        });

        lib.bundle_compiler_rt = true;
        lib.linkLibC();

        self.configure_lib(lib, self, target);
        return lib;
    }

    fn createUniversalBinary(self: *XCFrameworkBuilder, lib_aarch64: *std.Build.Step.Compile, lib_x86_64: *std.Build.Step.Compile) *LipoStep {
        return LipoStep.create(self.b, .{
            .name = self.b.fmt("{s}-universal", .{self.name}),
            .out_name = self.b.fmt("lib{s}.a", .{self.name}),
            .inputs = &[_]std.Build.LazyPath{
                lib_aarch64.getEmittedBin(),
                lib_x86_64.getEmittedBin(),
            },
        });
    }

    fn createLibtoolBundle(self: *XCFrameworkBuilder, universal_lib: *LipoStep, mac_libs: MacLibs) *LibtoolStep {
        var sources = std.ArrayList(std.Build.LazyPath).init(self.b.allocator);
        sources.append(universal_lib.output) catch unreachable;

        for (mac_libs.aarch64.root_module.link_objects.items) |item| switch (item) {
            .other_step => |step| {
                sources.append(step.getEmittedBin()) catch unreachable;
            },
            else => {},
        };

        for (mac_libs.x86_64.root_module.link_objects.items) |item| switch (item) {
            .other_step => |step| {
                sources.append(step.getEmittedBin()) catch unreachable;
            },
            else => {},
        };

        const libtool = LibtoolStep.create(self.b, .{
            .name = self.name,
            .out_name = self.b.fmt("{s}-bundle.a", .{self.name}),
            .sources = sources.items,
        });

        libtool.step.dependOn(universal_lib.step);

        return libtool;
    }

    fn createXCFramework(self: *XCFrameworkBuilder, libtool: *LibtoolStep) *XCFrameworkStep {
        const xcframework = XCFrameworkStep.create(self.b, .{
            .name = self.name,
            .out_path = self.b.fmt("build/{s}.xcframework", .{self.name}),
            .library = libtool.output,
            .headers = self.b.path("include"),
        });
        xcframework.step.dependOn(libtool.step);

        return xcframework;
    }
};

pub const XCFrameworkStep = struct {
    step: *Step,

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
            .step = &run_create.step,
        };

        return self;
    }
};

pub const LipoStep = struct {
    step: *Step,
    output: LazyPath,

    pub const Options = struct {
        /// The name of the xcframework to create.
        name: []const u8,

        /// The filename (not the path) of the file to create.
        out_name: []const u8,

        /// Library files (dylib, a) to package.
        inputs: []const LazyPath,
    };

    pub fn create(b: *std.Build, opts: Options) *LipoStep {
        const self = b.allocator.create(LipoStep) catch @panic("OOM");

        const run_step = RunStep.create(b, b.fmt("lipo {s}", .{opts.name}));
        run_step.addArgs(&.{ "lipo", "-create", "-output" });
        const output = run_step.addOutputFileArg(opts.out_name);
        for (opts.inputs) |input| {
            run_step.addFileArg(input);
        }

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
