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

pub const domanda = struct { domanda: [:0]const u8, risposte: []const [:0]const u8, correct_answer: usize = 0 };

pub const QuizQuestion = struct {
    question: [:0]const u8,
    answers: [4][:0]const u8,
};

pub const Config = struct {
    id: []const u8,
    domande: []const domanda,
};

pub const State = enum {
    idle,
    waiting_user_input,
    user_error,
    waiting_question_response,
    ready_to_send,
    disconnecting,
    notification,
    invalidPacket,
    processing,
    ack,
    errorRead,
    changeQuiz,
};

pub const SharedState = struct {
    mutex: std.Thread.Mutex = .{},
    client_signal: std.Thread.Condition = .{},
    ui_signal: std.Thread.Condition = .{},

    // Connection state
    connected: bool = false,
    state: State = .idle,

    server_message: []u8 = &[_]u8{},
    user_input: []u8 = &[_]u8{},
    question: ?domanda = null,

    allocator: ?std.mem.Allocator = null,

    pub fn setServerMessage(self: *SharedState, alloc: std.mem.Allocator, message: []const u8) !void {
        if (self.server_message.len > 0) alloc.free(self.server_message);
        self.server_message = try alloc.dupe(u8, message);
    }

    pub fn setUserInput(self: *SharedState, alloc: std.mem.Allocator, input: []const u8) !void {
        if (self.user_input.len > 0) alloc.free(self.user_input);
        self.user_input = try alloc.dupe(u8, input);
    }

    pub fn deinit(self: *SharedState, alloc: std.mem.Allocator) void {
        if (self.server_message.len > 0) alloc.free(self.server_message);
        if (self.user_input.len > 0) alloc.free(self.user_input);
        if (self.question) |q| {
            alloc.free(q.domanda);
            for (q.risposte) |risposta| {
                alloc.free(risposta);
            }
            alloc.free(q.risposte);
        }
    }
};
