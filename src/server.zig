const std = @import("std");
const Allocator = std.mem.Allocator;
const net = std.net;
const logSetup = @import("logSetup.zig");
const util = @import("utils.zig");

pub const serverClass = struct {
    const Self = @This();

    address: net.Address,
    logger: logSetup.logStruct,

    var server: std.net.Server = undefined;

    pub fn init(strAddress: []const u8, port: u16, log: logSetup.logStruct) !Self {
        const address = try net.Address.resolveIp(strAddress, port);
        return Self{ .address = address, .logger = log };
    }

    pub fn start(self: Self, asyn: bool) !void {
        server = try self.address.listen(.{
            .reuse_port = true,
            .reuse_address = true,
        });

        const ok = try std.Thread.spawn(.{}, acceptConnection, .{self});
        if (asyn) ok.join();
    }

    pub fn acceptConnection(self: Self) !void {
        while (true) {
            const conn = try server.accept();
            errdefer {
                self.logger.err("Server failed to start", .{}, @src());
                conn.stream.close(); // If the thread fails to be created
            }
            self.logger.info("New connection from: {any}", .{conn.address}, @src());

            _ = try std.Thread.spawn(.{}, handleConnection, .{ self, conn });
        }
    }

    pub fn handleConnection(self: Self, conn: net.Server.Connection) !void {
        defer {
            self.logger.info("Connection from: {any} closed", .{conn.address}, @src());
            conn.stream.close();
        }

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit(); // Check for leaks in debug mode
        const alloc = gpa.allocator();

        const connReader = conn.stream.reader();
        const connWriter = conn.stream.writer();

        // Send welcome notification to client
        try connWriter.writeAll("/nWelcome to Quiz DT Server!\n");

        var currentQuiz: ?std.json.Parsed(util.Config) = null;
        defer if (currentQuiz != null) currentQuiz.?.deinit();

        // Main connection loop
        while (true) {
            // Wait for client packet
            const received = connReader.readUntilDelimiterOrEofAlloc(alloc, '\n', 4096) catch |err| {
                self.logger.err("Error reading from client: {}", .{err}, @src());
                break;
            } orelse break;
            defer alloc.free(received);

            if (received.len == 0 or std.mem.eql(u8, received[0..1], &[_]u8{0})) {
                continue;
            }

            // Process packet based on type
            if (received.len < 2 or received[0] != '/') {
                self.logger.warn("Invalid packet format: {s}", .{received}, @src());
                try connWriter.writeAll("/3Invalid packet format\n");
                continue;
            }

            const code = received[1];
            const payload = if (received.len > 2) received[2..] else "";
            self.logger.debug("Received packet id: {c}, -> {s}", .{ code, payload }, @src());
            switch (code) {
                'e' => {
                    self.logger.info("Client requested disconnect", .{}, @src());
                    break;
                },
                't' => try self.handleTestRequest(payload, alloc, connReader, connWriter, &currentQuiz),
                'c' => try self.handleCreateQuiz(payload, alloc, connReader, connWriter),
                else => {
                    self.logger.warn("Unknown packet code: {c}", .{code}, @src());
                    try connWriter.writeAll("/3Unknown command\n");
                },
            }
        }
    }

    fn handleTestRequest(self: Self, testId: []const u8, alloc: Allocator, connReader: net.Stream.Reader, connWriter: net.Stream.Writer, currentQuiz: *?std.json.Parsed(util.Config)) !void {
        if (currentQuiz.* != null) {
            currentQuiz.*.?.deinit();
            currentQuiz.* = null;
        }

        // Generate filename from test ID
        const fileName = try std.fmt.allocPrint(alloc, "{s}.json", .{testId});
        defer alloc.free(fileName);

        // Try to load the quiz file
        currentQuiz.* = util.readConfig(alloc, fileName) catch {
            self.logger.warn("Test ID not found: {s}", .{testId}, @src());
            try connWriter.writeAll("/3Test ID not found\n");
            return;
        };

        const quizData = currentQuiz.*.?.value;
        self.logger.info("Loading test: {s} with {d} questions", .{ quizData.id, quizData.domande.len }, @src());

        // Notify client that test is starting

        // Wait for client to acknowledge

        // Present each question
        var string = std.ArrayList(u8).init(alloc);
        defer string.deinit();

        var correctAnswers: usize = 0;
        const totalQuestions = quizData.domande.len;

        const startMsg = try std.fmt.allocPrint(alloc, "/T{d}", .{totalQuestions});
        defer alloc.free(startMsg);
        try connWriter.writeAll(startMsg);

        for (quizData.domande, 0..) |structDomanda, questionIdx| {
            string.clearRetainingCapacity();
            try std.json.stringify(structDomanda, .{}, string.writer());

            const message = try std.fmt.allocPrint(alloc, "/2{s}\n", .{string.items});
            defer alloc.free(message);
            try connWriter.writeAll(message);

            // Get the answer
            const answer = try connReader.readUntilDelimiterOrEofAlloc(alloc, '\n', 1024) orelse break;
            defer alloc.free(answer);

            if (answer.len >= 2 and std.mem.eql(u8, answer[0..2], "/e")) return;

            self.logger.debug("Answer for Q{d}: {s}", .{ questionIdx + 1, answer }, @src());

            if (answer.len > 0) {
                correctAnswers += 1;
            }

            // Notify progress
            if (questionIdx < totalQuestions - 1) {
                const progressMsg = try std.fmt.allocPrint(alloc, "/nQuestion {d} of {d} completed\n", .{ questionIdx + 1, totalQuestions });
                defer alloc.free(progressMsg);
                try connWriter.writeAll(progressMsg);
            }
        }

        // Send test completion notification
        const resultMsg = try std.fmt.allocPrint(alloc, "/TTest completed! Score: {d}/{d}\n", .{ correctAnswers, totalQuestions });
        defer alloc.free(resultMsg);
        try connWriter.writeAll(resultMsg);

        // Wait for acknowledgment
        const finalAck = try connReader.readUntilDelimiterOrEofAlloc(alloc, '\n', 1024) orelse return;
        defer alloc.free(finalAck);
    }

    fn handleCreateQuiz(self: Self, payload: []const u8, alloc: Allocator, connReader: net.Stream.Reader, connWriter: net.Stream.Writer) !void {
        _ = self;
        _ = payload;
        try connWriter.writeAll("/1Enter quiz ID:\n");

        // Get quiz ID
        const quizId = try connReader.readUntilDelimiterOrEofAlloc(alloc, '\n', 1024) orelse return;
        defer alloc.free(quizId);

        if (quizId.len == 0) {
            try connWriter.writeAll("/3Quiz ID cannot be empty\n");
            return;
        }

        var newQuiz = util.Config{
            .id = try alloc.dupe(u8, quizId),
            .domande = &[_]util.domanda{},
        };

        // Start interactive quiz creation
        try connWriter.writeAll("/1How many questions would you like to add?\n");

        const numQuestionsStr = try connReader.readUntilDelimiterOrEofAlloc(alloc, '\n', 1024) orelse return;
        defer alloc.free(numQuestionsStr);

        const numQuestions = std.fmt.parseInt(usize, numQuestionsStr, 10) catch {
            try connWriter.writeAll("/3Invalid number format\n");
            return;
        };

        if (numQuestions == 0 or numQuestions > 100) {
            try connWriter.writeAll("/3Please enter a number between 1 and 100\n");
            return;
        }

        // Allocate questions array
        var questions = try alloc.alloc(util.domanda, numQuestions);
        defer alloc.free(questions);

        // For each question, get the question text and options
        var i: usize = 0;
        while (i < numQuestions) : (i += 1) {
            const promptMsg = try std.fmt.allocPrint(alloc, "/1Enter question {d}/{d}:\n", .{ i + 1, numQuestions });
            defer alloc.free(promptMsg);
            try connWriter.writeAll(promptMsg);

            // Get question text
            const questionText = try connReader.readUntilDelimiterOrEofAlloc(alloc, '\n', 4096) orelse return;

            // Now get options
            try connWriter.writeAll("/1How many options for this question?\n");

            const numOptionsStr = try connReader.readUntilDelimiterOrEofAlloc(alloc, '\n', 1024) orelse {
                alloc.free(questionText);
                return;
            };

            const numOptions = std.fmt.parseInt(usize, numOptionsStr, 10) catch {
                alloc.free(questionText);
                alloc.free(numOptionsStr);
                try connWriter.writeAll("/3Invalid number format\n");
                continue;
            };
            alloc.free(numOptionsStr);

            if (numOptions < 2 or numOptions > 10) {
                alloc.free(questionText);
                try connWriter.writeAll("/3Please enter a number between 2 and 10\n");
                continue;
            }

            // Allocate options array
            var options = try alloc.alloc([]u8, numOptions);

            var j: usize = 0;
            var valid = true;
            while (j < numOptions) : (j += 1) {
                const optionPrompt = try std.fmt.allocPrint(alloc, "/1Enter option {d}/{d}:\n", .{ j + 1, numOptions });
                defer alloc.free(optionPrompt);
                try connWriter.writeAll(optionPrompt);

                options[j] = try connReader.readUntilDelimiterOrEofAlloc(alloc, '\n', 4096) orelse {
                    valid = false;
                    break;
                };
            }

            if (!valid) {
                alloc.free(questionText);

                for (options[0..j]) |option| {
                    alloc.free(option);
                }
                alloc.free(options);
                continue;
            }

            questions[i] = .{
                .domanda = questionText,
                .risposte = options,
            };
        }

        // Create quiz file
        const fileName = try std.fmt.allocPrint(alloc, "{s}.json", .{quizId});
        defer alloc.free(fileName);

        newQuiz.domande = questions[0..i];

        var outFile = try std.fs.cwd().createFile(fileName, .{});
        defer outFile.close();

        try std.json.stringify(newQuiz, .{}, outFile.writer());

        for (newQuiz.domande) |question| {
            for (question.risposte) |answer| {
                alloc.free(answer);
            }
            alloc.free(question.domanda);
        }
        alloc.free(newQuiz.id);

        try connWriter.writeAll("/nQuiz created successfully!\n");
    }

    pub fn stop(self: Self) void {
        _ = self;
        server.deinit();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit(); // Check for leaks in debug mode
    const alloc = gpa.allocator();

    const log = logSetup.logStruct.innit(alloc);

    const server = try serverClass.init("0.0.0.0", 3000, log);

    log.info("Server Started at {any}", .{server.address}, @src());
    try server.start(true);
    defer server.stop();
}
