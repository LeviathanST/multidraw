const std = @import("std");

pub fn build(b: *std.Build) void {
    const o = b.standardOptimizeOption(.{});
    const t = b.standardTargetOptions(.{});

    {
        const exe = b.addExecutable(.{
            .name = "multidraw",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = t,
                .optimize = o,
            }),
            .use_llvm = true,
        });

        const ws = b.dependency("websocket", .{ .target = t, .optimize = o });
        exe.root_module.addImport("ws", ws.module("websocket"));

        const uuid = b.dependency("uuid", .{ .target = t, .optimize = o });
        exe.root_module.addImport("uuid", uuid.module("uuid"));

        const dotenv = b.dependency("zig_dotenv", .{});
        exe.root_module.addImport("dotenv", dotenv.module("zig-dotenv"));

        b.installArtifact(exe);
        const run_exe = b.addRunArtifact(exe);
        const run_step = b.step("run", "Run the application");
        run_step.dependOn(&run_exe.step);
    }

    {
        const test_exe = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tests.zig"),
                .target = t,
                .optimize = o,
            }),
            .use_llvm = true,
            .test_runner = .{
                .path = b.path("test_runner.zig"),
                .mode = .simple,
            },
        });

        const run_test_exe = b.addRunArtifact(test_exe);
        const run_test_step = b.step("test", "Run unit tests");

        run_test_step.dependOn(&run_test_exe.step);
    }
}
