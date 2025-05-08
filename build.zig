const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // === CLIENT EXECUTABLE (MAIN.ZIG) ===
    
    // This creates a "module", which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Every executable or library we compile will be based on one or more modules.
    const client_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // This creates a `std.Build.Step.Compile` that builds an executable
    const client_exe = b.addExecutable(.{
        .name = "client",
        .root_module = client_mod,
    });
    
    const raylib_dep_client = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib_client = raylib_dep_client.module("raylib"); // main raylib module
    const raygui_client = raylib_dep_client.module("raygui"); // raygui module
    const raylib_artifact_client = raylib_dep_client.artifact("raylib"); // raylib C library
    
    client_exe.linkLibrary(raylib_artifact_client);
    client_exe.root_module.addImport("raylib", raylib_client);
    client_exe.root_module.addImport("raygui", raygui_client);
    
    const nexlog_client = b.dependency("nexlog", .{
        .target = target,
        .optimize = optimize,
    });
    client_exe.root_module.addImport("nexlog", nexlog_client.module("nexlog"));
    
    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(client_exe);
    
    // This creates a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it.
    const run_client_cmd = b.addRunArtifact(client_exe);
    
    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_client_cmd.step.dependOn(b.getInstallStep());
    
    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_client_cmd.addArgs(args);
    }
    
    // === SERVER EXECUTABLE (SERVER.ZIG) ===
    
    // Create a module for the server
    const server_mod = b.createModule(.{
        .root_source_file = b.path("src/server.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Create the server executable
    const server_exe = b.addExecutable(.{
        .name = "server",
        .root_module = server_mod,
    });
    
    const raylib_dep_server = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib_server = raylib_dep_server.module("raylib");
    const raygui_server = raylib_dep_server.module("raygui");
    const raylib_artifact_server = raylib_dep_server.artifact("raylib");
    
    server_exe.linkLibrary(raylib_artifact_server);
    server_exe.root_module.addImport("raylib", raylib_server);
    server_exe.root_module.addImport("raygui", raygui_server);
    
    const nexlog_server = b.dependency("nexlog", .{
        .target = target,
        .optimize = optimize,
    });
    server_exe.root_module.addImport("nexlog", nexlog_server.module("nexlog"));
    
    // Install the server executable
    b.installArtifact(server_exe);
    
    // Create a run command for the server
    const run_server_cmd = b.addRunArtifact(server_exe);
    run_server_cmd.step.dependOn(b.getInstallStep());
    
    // Allow passing arguments to the server executable
    if (b.args) |args| {
        run_server_cmd.addArgs(args);
    }
    
    // === BUILD STEPS ===
    
    // This creates a build step for the client. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build client`
    const run_client_step = b.step("client", "Run the client application");
    run_client_step.dependOn(&run_client_cmd.step);
    
    // Create a build step for the server
    const run_server_step = b.step("server", "Run the server application");
    run_server_step.dependOn(&run_server_cmd.step);
    
    // Default run step will run the client
    const run_step = b.step("run", "Run the client application (default)");
    run_step.dependOn(&run_client_cmd.step);
}