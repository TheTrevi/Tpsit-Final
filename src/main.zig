const std = @import("std");
const rl = @import("raylib");
const gui = @import("gui/gui.zig");
const client = @import("client.zig");
const logSetup = @import("logSetup.zig");
const util = @import("utils.zig");

const Button = gui.Button;
const TextBox = gui.TextBox;
const Vec2 = gui.Vec2;
const Colors = gui.Colors;

var alloc: std.mem.Allocator = undefined;
var log: logSetup.logStruct = undefined;
var clientInstance: client.client = undefined;
var shared: util.SharedState = undefined;

const base_width: f32 = 1600;
const base_height: f32 = 1000;

var questionButton: [10]Button = undefined;
var questionButtonLen: usize = 0;

var homeButton: Button = undefined;

var buttons: [10]Button = undefined;
var buttonsLen: usize = 0;
var inputs: [10]TextBox = undefined;
var inputsLen: usize = 0;

var popupInput: TextBox = undefined;
var popupButton: Button = undefined;
var showPopup: bool = false;
var popupText: [:0]u8 = undefined;

var showError: bool = false;
var errorPopupText: [:0]const u8 = undefined;
var errorPopupTimer: usize = 0;

var notificationText: [:0]u8 = undefined;

var currentState: possibleStates = .homeScreen;

var bufEmpty: [1:0]u8 = undefined;
var emptyMessage = @as([:0]u8, &bufEmpty);

var nextMessageId: bool = true;

var domanda: util.domanda = undefined;
var risultati: [:0]const u8 = undefined;

const possibleStates = enum {
    homeScreen,
    quizScreen,
    createScren,
    resultScren,
};

fn startClientThread() void {
    clientInstance.startStream() catch {};
}

fn connectToServer() void {
    shared.mutex.lock();
    const currently_connected = shared.connected;
    shared.mutex.unlock();

    if (!currently_connected) {
        _ = std.Thread.spawn(.{}, startClientThread, .{}) catch {};
    } else {
        clientInstance.closeConnection();
    }
}

fn openPopup(string: []u8, input: bool) void {
    if (popupText.len > 1) alloc.free(popupText);
    popupText = alloc.dupeZ(u8, string) catch emptyMessage;
    // Show popup for user input
    showPopup = true;
    if (input) {
        popupInput.visible = true;
        popupInput.buffer = [_]u8{0} ** 256;
        popupInput.buffer_len = 0;
    } else {
        popupInput.visible = false;
    }
}

fn updateLayout() void {
    const screen_width = @as(f32, @floatFromInt(rl.getScreenWidth()));
    const screen_height = @as(f32, @floatFromInt(rl.getScreenHeight()));
    const scale_x = screen_width / base_width;
    const scale_y = screen_height / base_height;

    const button_width = 300 * scale_x;
    const button_height = 80 * scale_y;

    for (buttons[0..buttonsLen], 0..) |*b, i| {
        b.position = Vec2{
            .x = (screen_width - button_width) / 2,
            .y = screen_height * 0.3 + @as(f32, @floatFromInt(i)) * (button_height + 20 * scale_y),
        };
        b.size = Vec2{ .x = button_width, .y = button_height };
    }

    for (inputs[0..inputsLen]) |*value| {
        value.update();
    }

    popupInput.position = Vec2{ .x = (screen_width - 400) / 2, .y = (screen_height - 50) / 2 };
    popupInput.size = Vec2{ .x = 400, .y = 50 };
    popupInput.newVisibleSize();

    popupButton.position = Vec2{ .x = (screen_width - 150) / 2, .y = popupInput.position.y + 70 };
    popupButton.size = Vec2{ .x = 150, .y = 40 };
}

fn initiatePopup() void {
    popupInput = TextBox{
        .position = Vec2{ .x = 0, .y = 0 },
        .size = Vec2{ .x = 400, .y = 50 },
        .active_color = Colors.text,
        .hover_color = Colors.button_hover,
        .normal_color = Colors.button,
        .text_color = Colors.text,
    };

    popupButton = Button{
        .text = "OK",
        .position = Vec2{ .x = 0, .y = 0 },
        .size = Vec2{ .x = 150, .y = 40 },
        .background_color = Colors.button,
        .hover_color = Colors.button_hover,
        .disabled_color = Colors.button_disabled,
        .text_color = Colors.text,
        .enabled = true,
        .onClick = struct {
            pub fn click(ctx: *anyopaque) void {
                _ = ctx;
                if (showPopup) {
                    handlePopupSubmission();
                    nextMessageId = true;
                }
            }
        }.click,
    };
}

fn initiateHomeLayout() void {
    buttons[0] = Button{
        .text = "Connect to Server",
        .position = Vec2{ .x = 0, .y = 0 },
        .size = Vec2{ .x = 0, .y = 0 },
        .background_color = Colors.button,
        .hover_color = Colors.button_hover,
        .disabled_color = Colors.button_disabled,
        .text_color = Colors.text,
        .enabled = true,
        .onClick = struct {
            pub fn click(ctx: *anyopaque) void {
                _ = ctx;
                connectToServer();
            }
        }.click,
    };

    buttons[1] = Button{
        .text = "Start Test",
        .position = Vec2{ .x = 0, .y = 0 },
        .size = Vec2{ .x = 0, .y = 0 },
        .background_color = Colors.button,
        .hover_color = Colors.button_hover,
        .disabled_color = Colors.button_disabled,
        .text_color = Colors.text,
        .enabled = true,
        .onClick = struct {
            pub fn click(ctx: *anyopaque) void {
                _ = ctx;
                nextMessageId = true;
                openPopup(@constCast("Id Quiz da aprire:"), true);
            }
        }.click,
    };

    buttons[2] = Button{
        .text = "Create Quiz",
        .position = Vec2{ .x = 0, .y = 0 },
        .size = Vec2{ .x = 0, .y = 0 },
        .background_color = Colors.button,
        .hover_color = Colors.button_hover,
        .disabled_color = Colors.button_disabled,
        .text_color = Colors.text,
        .enabled = true,
        .onClick = struct {
            pub fn click(ctx: *anyopaque) void {
                _ = ctx;
            }
        }.click,
    };
    buttonsLen = 3;
}

fn initiateQuestionLayout() void {
    // Clear any existing question buttons

    // Create a button for each answer option
    const screen_width = @as(f32, @floatFromInt(rl.getScreenWidth()));
    const screen_height = @as(f32, @floatFromInt(rl.getScreenHeight()));
    const scale_x = screen_width / base_width;
    const scale_y = screen_height / base_height;

    const button_width = 400 * scale_x;
    const button_height = 60 * scale_y;

    const num_answers = domanda.risposte.len;

    for (0..num_answers) |i| {
        const answer_text = domanda.risposte[i];

        questionButton[i] = Button{
            .text = alloc.dupeZ(u8, answer_text) catch "Answer",
            .position = Vec2{
                .x = (screen_width - button_width) / 2,
                .y = screen_height * 0.4 + @as(f32, @floatFromInt(i)) * (button_height + 10 * scale_y),
            },
            .size = Vec2{ .x = button_width, .y = button_height },
            .background_color = Colors.button,
            .hover_color = Colors.button_hover,
            .disabled_color = Colors.button_disabled,
            .text_color = Colors.text,
            .enabled = true,
            .onClick = struct {
                pub fn click(ctx: *anyopaque) void {
                    _ = ctx;
                }
            }.click,
        };

        if (i == 0) {
            questionButton[i].onClick = struct {
                pub fn click(ctx: *anyopaque) void {
                    _ = ctx;
                    submitQuizAnswer(0);
                }
            }.click;
        } else if (i == 1) {
            questionButton[i].onClick = struct {
                pub fn click(ctx: *anyopaque) void {
                    _ = ctx;
                    submitQuizAnswer(1);
                }
            }.click;
        } else if (i == 2) {
            questionButton[i].onClick = struct {
                pub fn click(ctx: *anyopaque) void {
                    _ = ctx;
                    submitQuizAnswer(2);
                }
            }.click;
        } else if (i == 3) {
            questionButton[i].onClick = struct {
                pub fn click(ctx: *anyopaque) void {
                    _ = ctx;
                    submitQuizAnswer(3);
                }
            }.click;
        }
    }

    questionButtonLen = 4;
}

fn submitQuizAnswer(answer_index: usize) void {
    shared.mutex.lock();
    if (shared.question) |question| {
        if (answer_index < question.risposte.len) {
            // Get the selected answer
            const selected_answer = question.risposte[answer_index];

            // Submit this answer
            shared.setUserInput(alloc, selected_answer) catch {
                shared.mutex.unlock();
                displayError(@constCast("Failed to set answer"));
                return;
            };

            // Signal that we're ready to send
            shared.state = .ready_to_send;

            // Signal the client thread
            shared.client_signal.signal();
        }
    }
    shared.mutex.unlock();
}

fn initiateResultLayout() void {
    const screen_width = @as(f32, @floatFromInt(rl.getScreenWidth()));
    const screen_height = @as(f32, @floatFromInt(rl.getScreenHeight()));
    const scale_x = screen_width / base_width;
    const scale_y = screen_height / base_height;

    const button_width = 400 * scale_x;
    const button_height = 60 * scale_y;

    homeButton = Button{
        .text = "Home",
        .position = Vec2{
            .x = (screen_width - button_width) / 2,
            .y = screen_height * 0.4 + (button_height + 10 * scale_y) + 200,
        },
        .size = Vec2{ .x = button_width, .y = button_height },
        .background_color = Colors.button,
        .hover_color = Colors.button_hover,
        .disabled_color = Colors.button_disabled,
        .text_color = Colors.text,
        .enabled = true,
        .onClick = struct {
            pub fn click(ctx: *anyopaque) void {
                _ = ctx;
                currentState = .homeScreen;
                submitResponse("ack\n");
            }
        }.click,
    };
}

fn initiateCreationLayout() void {
    return;
}

fn handlePopupSubmission() void {
    showPopup = false;
    for (&buttons) |*b| {
        b.enabled = true;
    }
    // Check state to determine what to do with the input
    shared.mutex.lock();
    const state = shared.state;
    shared.mutex.unlock();

    var code: *const [2]u8 = undefined;
    if (nextMessageId) code = "/t";

    if (state == .waiting_user_input or state == .user_error or state == .ack) {
        const message = std.fmt.allocPrint(alloc, "{s}{s}\n", .{ code, popupInput.buffer[0..popupInput.buffer_len] }) catch emptyMessage;
        submitResponse(message);
        alloc.free(message);
    } else {
        // Starting a test - send the test ID
        clientInstance.sendMessage('t', popupInput.buffer[0..popupInput.buffer_len]) catch {
            displayError(@constCast("Couldn't send message"));
        };
    }
}

fn submitResponse(response: []const u8) void {
    shared.mutex.lock();
    defer shared.mutex.unlock();
    // Only process if we're in a state expecting user input
    if (shared.state == .waiting_user_input or
        shared.state == .waiting_question_response or
        shared.state == .user_error or
        shared.state == .ack or
        shared.state == .changeQuiz)
    {
        // Set the user input
        shared.setUserInput(alloc, response) catch {
            displayError(@constCast("Failed to set user input"));
            return;
        };

        // Signal that we're ready to send
        shared.state = .ready_to_send;

        // Signal the client threadzig build run
        shared.client_signal.signal();
    }
}

fn displayError(msg: []u8) void {
    if (errorPopupText.len > 1) alloc.free(errorPopupText);
    errorPopupText = alloc.dupeZ(u8, msg) catch emptyMessage;
    // Show error popup
    showError = true;
    errorPopupTimer = 180;
}

fn drawHomeScreen() void {
    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();

    rl.clearBackground(Colors.background);

    rl.drawText(
        "Quiz DT",
        @divTrunc(screen_width - rl.measureText("Quiz DT", 80), 2),
        50,
        80,
        Colors.text,
    );

    // Connection status
    shared.mutex.lock();
    const connected = shared.connected;
    shared.mutex.unlock();
    const conn_text = if (connected) "Connected" else "Disconnected";
    buttons[0].text = if (connected) "Disconnect from Server" else "Connect to Server";

    const conn_color = if (connected) Colors.green_pastel else Colors.red_pastel;

    rl.drawText(
        conn_text,
        screen_width - rl.measureText(conn_text, 25) - 100,
        screen_height - 50,
        30,
        conn_color,
    );

    for (buttons[0..buttonsLen]) |*b| {
        b.draw();
    }

    if (notificationText.len > 1) {
        rl.drawText(notificationText, @divTrunc(screen_width - rl.measureText(notificationText, 25), 2), screen_height - 100, 25, Colors.text);
    }
}

fn drawQuizScreen() void {
    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();

    rl.clearBackground(Colors.background);

    rl.drawText(
        "Quiz DT",
        @divTrunc(screen_width - rl.measureText("Quiz DT", 80), 2),
        50,
        80,
        Colors.text,
    );

    rl.drawText(
        domanda.domanda,
        @divTrunc(screen_width - rl.measureText(domanda.domanda, 50), 2),
        300,
        50,
        Colors.text,
    );

    // Connection status
    shared.mutex.lock();
    const connected = shared.connected;
    shared.mutex.unlock();
    const conn_text = if (connected) "Connected" else "Disconnected";

    const conn_color = if (connected) Colors.green_pastel else Colors.red_pastel;

    rl.drawText(
        conn_text,
        screen_width - rl.measureText(conn_text, 25) - 100,
        screen_height - 50,
        30,
        conn_color,
    );

    for (questionButton[0..questionButtonLen]) |*b| {
        b.draw();
    }

    if (notificationText.len > 1) {
        rl.drawText(notificationText, @divTrunc(screen_width - rl.measureText(notificationText, 25), 2), screen_height - 100, 25, Colors.text);
    }
}

fn drawResultScreen() void {
    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();

    rl.clearBackground(Colors.background);
    rl.drawText(
        "Quiz DT",
        @divTrunc(screen_width - rl.measureText("Quiz DT", 80), 2),
        50,
        80,
        Colors.text,
    );

    rl.drawText(
        risultati,
        @divTrunc(screen_width - rl.measureText(risultati, 50), 2),
        500,
        50,
        Colors.text,
    );

    shared.mutex.lock();
    const connected = shared.connected;
    shared.mutex.unlock();
    const conn_text = if (connected) "Connected" else "Disconnected";

    const conn_color = if (connected) Colors.green_pastel else Colors.red_pastel;

    rl.drawText(
        conn_text,
        screen_width - rl.measureText(conn_text, 25) - 100,
        screen_height - 50,
        30,
        conn_color,
    );

    if (notificationText.len > 1) {
        rl.drawText(notificationText, @divTrunc(screen_width - rl.measureText(notificationText, 25), 2), screen_height - 100, 25, Colors.text);
    }

    homeButton.draw();
}

fn drawCreateScreen() void {
    return;
}

fn drawPopup() void {
    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();

    popupInput.update();

    rl.drawRectangleRounded(rl.Rectangle.init(@floatFromInt(300), @floatFromInt(300), @floatFromInt(screen_width - 600), @floatFromInt(screen_height - 600)), 0.3, 10, Colors.popup_background);

    rl.drawText("Enter Test ID", @divTrunc(screen_width - rl.measureText("Enter Test ID", 30), 2), @as(i32, @intFromFloat(popupInput.position.y)) - 40, 30, Colors.text);

    popupInput.draw();
    popupButton.draw();
}

fn drawErrorMessage() void {
    const padding = 10;
    const width = rl.measureText(errorPopupText, 20) + 2 * padding;
    const height = 40;

    rl.drawRectangle(
        rl.getScreenWidth() - width - 20,
        20,
        width,
        height,
        Colors.red_pastel,
    );
    rl.drawText(
        errorPopupText,
        rl.getScreenWidth() - width - 10,
        30,
        20,
        Colors.text,
    );
}

fn checkClientUpdates() void {
    shared.mutex.lock();
    defer shared.mutex.unlock();

    // Check current state
    switch (shared.state) {
        .waiting_user_input => {
            // Copy message to display
            openPopup(shared.server_message, true);
            // Disable main buttons while popup is active
            for (&buttons) |*b| {
                b.enabled = false;
            }
        },
        .user_error => {
            // Copy error message to display
            displayError(shared.server_message);
        },
        .ack => {
            openPopup(@constCast("Iniziare Quiz"), false);

            // Disable main buttons while popup is active
            for (&buttons) |*b| {
                b.enabled = false;
            }
        },
        .notification => {
            // Just display the notification
            // setDisplayMessage(shared.server_message);
            if (notificationText.len > 1) alloc.free(notificationText);
            notificationText = alloc.dupeZ(u8, shared.server_message) catch emptyMessage;
            // Reset state to idle after processing
            shared.state = .idle;
        },
        .waiting_question_response => {
            currentState = .quizScreen;

            domanda = util.domanda{ .domanda = alloc.dupeZ(u8, shared.question.?.domanda) catch {
                return;
            }, .risposte = alloc.dupe([:0]const u8, shared.question.?.risposte) catch {
                return;
            } };

            initiateQuestionLayout();
        },
        .changeQuiz => {
            if (currentState == .quizScreen) {
                currentState = .resultScren;
                // domanda = undefined;

                if (risultati.len > 1) alloc.free(risultati);
                risultati = alloc.dupeZ(u8, shared.server_message) catch emptyMessage;

                initiateResultLayout();
            } else {
                currentState = .quizScreen;
            }
            shared.state = .idle;
        },
        else => {}, // Nothing to do for other states
    }
}

fn drawScreen() void {
    rl.beginDrawing();

    if (currentState == .homeScreen) {
        drawHomeScreen();
    } else if (currentState == .quizScreen) {
        drawQuizScreen();
    } else if (currentState == .resultScren) {
        drawResultScreen();
    } else if (currentState == .createScren) {
        drawCreateScreen();
    }
    if (showPopup) drawPopup();
    if (showError) drawErrorMessage();

    rl.endDrawing();
}

pub fn main() !void {
    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(base_width, base_height, "Quiz DT");
    rl.setTargetFPS(60);

    alloc = std.heap.page_allocator;
    log = logSetup.logStruct.innit(alloc);
    shared = util.SharedState{ .allocator = alloc };
    clientInstance = try client.client.init("127.0.0.1", 3000, log, alloc, &shared);

    initiateHomeLayout();
    // initiateQuestionLayout();
    // initiateResultLayout();
    // initiateCreationLayout();

    initiatePopup();
    updateLayout();

    while (!rl.windowShouldClose()) {
        if (rl.isWindowResized()) {
            updateLayout();
        }
        checkClientUpdates();
        drawScreen();

        // Handle error popup timer
        if (errorPopupTimer > 0) {
            errorPopupTimer -= 1;
            if (errorPopupTimer == 0) {
                showError = false;
            }
        }
    }

    rl.closeWindow();
}
