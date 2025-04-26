const std = @import("std");
const net = std.net;
const logSetup = @import("logSetup.zig");
const util = @import("utils.zig");

pub const client = struct {
    const Self = @This();

    address: net.Address,
    logger: logSetup.logStruct,
    alloc: std.mem.Allocator,

    isConnected: bool = false,

    var stream: std.net.Stream = undefined;

    pub fn init(strAddress: []const u8, port: u16, log: logSetup.logStruct, alloc: std.mem.Allocator) !Self {
        const address = try net.Address.resolveIp(strAddress, port);
        return Self{ .address = address, .logger = log, .alloc = alloc };
    }

    pub fn startStream(self: Self) !void {
        stream = net.tcpConnectToAddress(self.address) catch {
            self.logger.err("Error connecting to server", .{}, @src());
            return undefined;
        };
        self.isConnected = true;
        self.logger.info("Connecting to {}", .{self.address}, @src());

        const connReader = stream.reader();
        const connWriter = stream.writer();

        var response: []u8 = undefined;
        var message: []u8 = undefined;
        var packet: []u8 = undefined;

        while (true) {
            packet = try connReader.readUntilDelimiterOrEofAlloc(self.alloc, '\n', 1024) orelse break;
            //self.logger.info("mes: {s}", .{packet}, @src());
            if (std.mem.eql(u8, packet[0..2], "/e")) {
                self.logger.warn("Connection to server ended", .{}, @src());
                break;
            } else if (std.mem.eql(u8, packet[0..2], "/1")) {
                self.logger.info("{s}", .{packet[2..]}, @src());
                util.ask_user(&response, self.alloc);
                defer self.alloc.free(response);

                message = try std.fmt.allocPrint(self.alloc, "{s}\n", .{response});
                _ = try connWriter.writeAll(message);
            } else if (std.mem.eql(u8, packet[0..2], "/2")) {
                const parsed = try std.json.parseFromSlice(util.domanda, self.alloc, packet[2..], .{});
                const domanda = parsed.value;

                std.log.info("{s}\n", .{domanda.domanda});
                for (domanda.risposte, 0..) |value, index| {
                    std.log.info("{d}) {s}", .{ index, value });
                }
                std.log.info("risposta: ", .{});

                util.ask_user(&response, self.alloc);
                defer self.alloc.free(response);
                message = try std.fmt.allocPrint(self.alloc, "{s}\n", .{response});
                _ = try connWriter.writeAll(message);
            }
        }
        self.isConnected = false;
    }

    pub fn closeConnection(self: Self) void {
        _ = self;
        stream.close();
    }
};
