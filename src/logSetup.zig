const nexlog = @import("nexlog");
const std = @import("std");

fn defaultMetadata(location: std.builtin.SourceLocation) nexlog.LogMetadata {
    return .{
        .timestamp = @intCast(std.time.timestamp()),
        .thread_id = std.Thread.getCurrentId(),
        .file = location.file,
        .line = location.line,
        .function = location.fn_name,
    };
}

const config: nexlog.LogConfig = .{
    .min_level = .debug,
    .enable_colors = true,
    .enable_file_logging = true,
};

pub const logStruct = struct {
    const Self = @This();

    logger: *nexlog.Logger,
    alloc: std.mem.Allocator,

    pub fn innit(alloc: std.mem.Allocator) Self {
        const logger = nexlog.Logger.init(alloc, config) catch unreachable;
        return .{ .logger = logger, .alloc = alloc };
    }

    pub fn deinit(self: Self) void {
        defer self.logger.deinit();
    }

    pub fn trace(self: Self, comptime fmt: []const u8, args: anytype, source: std.builtin.SourceLocation) void {
        self.logger.log(.trace, fmt, args, defaultMetadata(source)) catch unreachable;
    }
    pub fn debug(self: Self, comptime fmt: []const u8, args: anytype, source: std.builtin.SourceLocation) void {
        self.logger.log(.debug, fmt, args, defaultMetadata(source)) catch unreachable;
    }
    pub fn info(self: Self, comptime fmt: []const u8, args: anytype, source: std.builtin.SourceLocation) void {
        self.logger.log(.info, fmt, args, defaultMetadata(source)) catch unreachable;
    }
    pub fn warn(self: Self, comptime fmt: []const u8, args: anytype, source: std.builtin.SourceLocation) void {
        self.logger.log(.warn, fmt, args, defaultMetadata(source)) catch unreachable;
    }
    pub fn err(self: Self, comptime fmt: []const u8, args: anytype, source: std.builtin.SourceLocation) void {
        self.logger.log(.err, fmt, args, defaultMetadata(source)) catch unreachable;
    }
    pub fn critical(self: Self, comptime fmt: []const u8, args: anytype, source: std.builtin.SourceLocation) void {
        self.logger.log(.critical, fmt, args, defaultMetadata(source)) catch unreachable;
    }
};
