const std = @import("std");
const net = std.net;
const logSetup = @import("logSetup.zig");
const util = @import("utils.zig");

pub const client = struct {
    const Self = @This();

    address: net.Address,
    logger: logSetup.logStruct,
    alloc: std.mem.Allocator,
    shared: *util.SharedState,

    isConnected: bool = false,
    var stream: ?std.net.Stream = null;

    // Connection settings
    const max_retries = 5;
    const retry_delay_ns = 1_000_000_000; // 1 second
    const buffer_size = 4096;

    pub fn init(strAddress: []const u8, port: u16, log: logSetup.logStruct, alloc: std.mem.Allocator, shared: *util.SharedState) !Self {
        const address = try net.Address.resolveIp(strAddress, port);
        return Self{ .address = address, .logger = log, .alloc = alloc, .shared = shared };
    }

    pub fn startStream(self: *Self) !void {
        var retry_count: usize = 0;

        while (retry_count < max_retries) {
            stream = net.tcpConnectToAddress(self.address) catch |err| {
                self.logger.err("Connection failed: {}, retrying ({}/{})", .{ err, retry_count + 1, max_retries }, @src());
                retry_count += 1;
                std.time.sleep(retry_delay_ns);
                continue;
            };

            retry_count = 0; // Reset on successful connection
            self.logger.info("Connected to {}", .{self.address}, @src());

            // Update shared state
            self.shared.mutex.lock();
            self.shared.connected = true;
            self.shared.state = .idle;
            self.shared.mutex.unlock();

            // Start communication loop
            const reader = stream.?.reader();
            const writer = stream.?.writer();

            // Main read loop
            while (true) {
                const packet = reader.readUntilDelimiterOrEofAlloc(self.alloc, '\n', buffer_size) catch |err| {
                    self.logger.err("Error reading packet: {}", .{err}, @src());
                    break;
                } orelse break;
                defer self.alloc.free(packet);

                const result = self.handlePacket(packet, writer) catch |err| {
                    self.logger.err("Error handling packet: {}", .{err}, @src());
                    continue;
                };

                if (result == .ConnectionClosed) break;
            }

            // Graceful shutdown
            _ = writer.writeAll("/e closeConnection\n") catch |err| {
                self.logger.err("Error sending close message: {}", .{err}, @src());
            };

            // Update shared state
            self.shared.mutex.lock();
            self.shared.connected = false;
            self.shared.state = .idle;
            self.shared.mutex.unlock();

            self.logger.warn("Connection to server closed", .{}, @src());
            break;
        }

        if (retry_count >= max_retries) {
            self.logger.err("Max reconnection attempts reached", .{}, @src());
        }
    }

    fn handlePacket(self: *Self, packet: []const u8, writer: std.net.Stream.Writer) !enum { ConnectionClosed, Idle } {
        if (packet.len < 2 or packet[0] != '/') {
            self.logger.err("Invalid packet received: {s}", .{packet}, @src());
            return .Idle;
        }

        const code = packet[1];
        const payload = packet[2..];

        self.logger.debug("packet with code:{c},received: {s}", .{ code, payload }, @src());
        switch (code) {
            '1' => try self.handleTextInput(payload, writer),
            '2' => try self.handleQuestion(payload, writer),
            '3' => try self.handleErrorInput(payload, writer),
            'n' => try self.handleNotification(payload),
            'N' => try self.handleAck(payload),
            'T' => try self.handleStartEndOfQuiz(payload, writer),
            'e' => return .ConnectionClosed,
            else => self.logger.warn("Unknown packet code: {c}", .{code}, @src()),
        }

        return .Idle;
    }

    fn handleTextInput(self: *Self, payload: []const u8, writer: std.net.Stream.Writer) !void {
        try self.waitForResponse(payload, .waiting_user_input, writer);
    }

    fn handleErrorInput(self: *Self, payload: []const u8, writer: std.net.Stream.Writer) !void {
        // try self.sendError(payload, .user_error);
        try self.waitForResponse(payload, .user_error, writer);
    }

    fn handleStartEndOfQuiz(self: *Self, payload: []const u8, writer: std.net.Stream.Writer) !void {
        try self.waitForResponse(payload, .changeQuiz, writer);
    }

    fn handleNotification(self: *Self, payload: []const u8) !void {
        self.logger.info("Server notification: {s}", .{payload}, @src());

        self.shared.mutex.lock();
        defer self.shared.mutex.unlock();

        try self.shared.setServerMessage(self.alloc, payload);
        self.shared.state = .notification;
        self.shared.ui_signal.signal();
    }

    fn handleAck(self: *Self, payload: []const u8) !void {
        self.logger.info("Server notification: {s}", .{payload}, @src());

        self.shared.mutex.lock();
        defer self.shared.mutex.unlock();

        try self.shared.setServerMessage(self.alloc, payload);
        self.shared.state = .ack;
        self.shared.ui_signal.signal();
    }

    // Unified function to handle user input requests (both normal and error)
    fn waitForResponse(self: *Self, payload: []const u8, state_type: util.State, writer: std.net.Stream.Writer) !void {
        self.shared.mutex.lock();

        // Store message and update state
        try self.shared.setServerMessage(self.alloc, payload);
        self.shared.state = state_type;

        // Signal the UI that new data is available
        self.shared.ui_signal.signal();

        // Wait for UI to provide input
        while (self.shared.state != .ready_to_send and self.shared.state != .disconnecting) {
            self.shared.client_signal.wait(&self.shared.mutex);
        }

        if (self.shared.state == .disconnecting) {
            self.shared.mutex.unlock();
            return;
        }
        // Get the response
        const response = self.shared.user_input;
        self.shared.state = .idle;
        self.shared.mutex.unlock();

        // Send response to server
        const message = try std.fmt.allocPrint(self.alloc, "{s}\n", .{response});
        defer self.alloc.free(message);

        self.logger.debug("sending: {s}", .{message}, @src());
        _ = try writer.writeAll(message);
    }

    fn sendError(self: *Self, payload: []const u8, state_type: util.State) !util.State {
        self.shared.mutex.lock();

        // Store message and update state
        try self.shared.setServerMessage(self.alloc, payload);
        self.shared.state = state_type;

        // Signal the UI that new data is available
        self.shared.ui_signal.signal();

        self.shared.mutex.unlock();
        return .errorRead;
    }

    fn handleQuestion(self: *Self, payload: []const u8, writer: std.net.Stream.Writer) !void {
        const parsed = try std.json.parseFromSlice(util.domanda, self.alloc, payload, .{});
        defer parsed.deinit();

        self.shared.mutex.lock();

        // Store question and update state
        self.shared.question = parsed.value;
        self.shared.state = .waiting_question_response;

        // Signal the UI
        self.shared.ui_signal.signal();

        // Wait for response
        while (self.shared.state != .ready_to_send and self.shared.state != .disconnecting) {
            self.shared.client_signal.wait(&self.shared.mutex);
        }

        if (self.shared.state == .disconnecting) {
            self.shared.mutex.unlock();
            return;
        }

        // Get the response
        const response = self.shared.user_input;
        self.shared.state = .idle;
        self.shared.mutex.unlock();

        // Send response to server
        const message = try std.fmt.allocPrint(self.alloc, "{s}\n", .{response});
        defer self.alloc.free(message);
        _ = try writer.writeAll(message);
    }

    pub fn closeConnection(self: *Self) void {
        self.shared.mutex.lock();
        self.shared.state = .disconnecting;
        self.shared.client_signal.signal(); // Wake up any waiting threads
        self.shared.mutex.unlock();

        if (stream) |s| {
            s.close();
        }
        self.shared.mutex.lock();
        self.shared.connected = false;
        self.shared.mutex.unlock();
    }

    pub fn sendMessage(self: *Self, message_type: u8, content: []const u8) !void {
        if (stream == null) return error.NotConnected;

        const writer = stream.?.writer();
        const message = try std.fmt.allocPrint(self.alloc, "/{c}{s}\n", .{ message_type, content });
        defer self.alloc.free(message);
        self.logger.debug("sending: {s}", .{message}, @src());
        _ = try writer.writeAll(message);
    }
};
