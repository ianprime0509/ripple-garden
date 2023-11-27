const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
    });
    const raygui = b.dependency("raygui", .{});

    const ripple_garden = b.addExecutable(.{
        .name = "ripple-garden",
        .root_source_file = .{ .path = "src/App.zig" },
        .target = target,
        .optimize = optimize,
    });
    ripple_garden.addIncludePath(.{ .path = "src" });
    ripple_garden.addIncludePath(raylib.path("src"));
    ripple_garden.linkLibrary(raylib.artifact("raylib"));
    ripple_garden.addIncludePath(raygui.path("src"));
    b.installArtifact(ripple_garden);

    const run_ripple_garden = b.addRunArtifact(ripple_garden);
    if (b.args) |args| {
        run_ripple_garden.addArgs(args);
    }
    b.step("run", "Run the executable").dependOn(&run_ripple_garden.step);
}
