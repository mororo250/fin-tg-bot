const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tgbot_module = b.addModule("tgbot", .{
        .root_source_file = b.path("src/tgbot.zig"),
        .target = target,
        .optimize = optimize
    });

    const pluggy_module = b.addModule("pluggy", .{
        .root_source_file = b.path("src/pluggy_client.zig"),
        .target = target,
        .optimize = optimize
    });

    const gcp_lib = b.addLibrary(.{
        .name = "gcp_secret_manager",
        .root_module = b.createModule(.{
            .root_source_file = null,
            .optimize = optimize,
            .target = target,
        })
    });
    gcp_lib.addCSourceFile(.{
        .file = b.path("src/zig-gcp/zig_gcp_secret_manager.cc"),
    });
    gcp_lib.root_module.link_libcpp = true;
    try addSystemLibraryPath(b, gcp_lib, target);
    gcp_lib.linkSystemLibrary("google_cloud_cpp_secretmanager");

    const exe = b.addExecutable(.{
        .name = "exe_template",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "tgbot", .module = tgbot_module },
                .{ .name = "pluggy", .module = pluggy_module },
            },
        }),
    });

    try addSystemLibraryPath(b, exe, target);
    exe.root_module.linkLibrary(gcp_lib);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run tests");

    // test for pluggy module
    const pluggy_tests = b.addTest(.{
        .name = "pluggy_tests",
        .root_module = pluggy_module,
        .test_runner = .{ .path = b.path("src/test_runner.zig"), .mode = .simple },
    });
    const run_pluggy_tests = b.addRunArtifact(pluggy_tests);
    test_step.dependOn(&run_pluggy_tests.step);

    // Test for tgbot module
    const tgbot_tests = b.addTest(.{
        .name = "tgbot_tests",
        .root_module = tgbot_module,
        .test_runner = .{ .path = b.path("src/test_runner.zig"), .mode = .simple },
    });
    const run_tgbot_tests = b.addRunArtifact(tgbot_tests);
    test_step.dependOn(&run_tgbot_tests.step);

    // Test for GCP secret manager
    const gcp_tests = b.addTest(.{
        .name = "gcp_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zig-gcp/zig_gcp_secret_manager_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .test_runner = .{ .path = b.path("src/test_runner.zig"), .mode = .simple },
    });
    try addSystemLibraryPath(b, gcp_tests, target);
    gcp_tests.root_module.linkLibrary(gcp_lib);
    const run_gcp_tests = b.addRunArtifact(gcp_tests);
    test_step.dependOn(&run_gcp_tests.step);

    // Test for main executable module
    const exe_tests = b.addTest(.{
        .name = "exe_tests",
        .root_module = exe.root_module,
        .test_runner = .{ .path = b.path("src/test_runner.zig"), .mode = .simple },
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    test_step.dependOn(&run_exe_tests.step);

    const check_step = b.step("check", "Check for zls analysis");
    check_step.dependOn(&exe.step);
    check_step.dependOn(&pluggy_tests.step);
    check_step.dependOn(&tgbot_tests.step);
    check_step.dependOn(&gcp_tests.step);
    check_step.dependOn(&exe_tests.step);

    // Add args input to exe and tests
    if (b.args) |args| {
        run_cmd.addArgs(args);
        run_pluggy_tests.addArgs(args);
        run_tgbot_tests.addArgs(args);
        run_gcp_tests.addArgs(args);
        run_exe_tests.addArgs(args);
    }
}

// Todo: This needs to be called and allocated several times. Instead this function should be separated into two
fn addSystemLibraryPath(b: *std.Build, module: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) !void {
    const native_os = target.result.os.tag; // We have to do os specific handling here because zig didn't automatically handle vcpkg yet.
    switch (native_os) {
        .windows => {
            const vcpkg_root =  std.process.getEnvVarOwned(b.allocator, "VCPKG_ROOT") catch |err| switch (err) {
                error.EnvironmentVariableNotFound =>  try b.allocator.dupe(u8, "C:/vcpkg"),
                else => return err,
            };

            const triplet = blk: {
                if (std.process.getEnvVarOwned(b.allocator, "VCPKG_TRIPLET")) |t| break :blk t else |_| {}
                if (std.process.getEnvVarOwned(b.allocator, "VCPKG_DEFAULT_TRIPLET")) |t| break :blk t else |_| {}
                const arch = switch (target.result.cpu.arch) {
                    .x86_64 => "x64",
                    .x86 => "x86",
                    .aarch64 => "arm64",
                    .arm => "arm",
                    else => "x64",
                };
                break :blk try std.fmt.allocPrint(b.allocator, "{s}-windows", .{ arch });
            };

            const vcpkg_lib_path = try std.fs.path.join(b.allocator, &.{vcpkg_root, "installed", triplet, "lib"});
            const vcpkg_include_path = try std.fs.path.join(b.allocator, &.{vcpkg_root, "installed", triplet, "include"});

            module.addLibraryPath(.{.cwd_relative = vcpkg_lib_path});
            module.addIncludePath(.{.cwd_relative = vcpkg_include_path});
        },
        else => {},
    }
}
