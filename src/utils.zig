const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn readConfig(allocator: Allocator, path: []const u8) !std.json.Parsed(Config) {
    const data = try std.fs.cwd().readFileAlloc(allocator, path, 1048576);
    defer allocator.free(data);
    return std.json.parseFromSlice(Config, allocator, data, .{ .allocate = .alloc_always });
}

pub fn ask_user(input: *[]u8, alloc: Allocator) void {
    const stdin = std.io.getStdIn().reader();
    const value = stdin.readUntilDelimiterOrEofAlloc(alloc, '\n', 255) catch {
        return;
    };
    if (value) |val| input.* = val;
}

pub const domanda = struct { domanda: []const u8, risposte: []const []const u8 };

pub const Config = struct {
    id: []const u8,
    domande: []const domanda,
};

pub const SharedState = struct {
    mutex: std.Thread.Mutex = .{},
    response_buffer: [256]u8 = undefined,
    response_len: usize = 0,
    has_response: bool = false,
    connected: bool = false,
};
