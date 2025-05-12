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
var firstTime = true;

const possibleStates = enum {
    homeScreen,
    quizScreen,
    createScren,
    resultScren,
};

var createInputs: [10]TextBox = undefined;
var createInputsLen: usize = 0;
var createButtons: [10]Button = undefined;
var createButtonsLen: usize = 0;

var currentQuestion: usize = 0;
var totalQuestions: usize = 0;
var questionOptions: usize = 0;
var currentOption: usize = 0;
var questionTexts: std.ArrayList([:0]u8) = undefined;
var optionTexts: std.ArrayList(std.ArrayList([:0]u8)) = undefined;
var creationStep: enum {
    id,
    num_questions,
    question_text,
    num_options,
    option_text,
    complete,
} = .id;

fn startClientThread() void {
    clientInstance.startStream() catch {};
}

fn connectToServer() void {
    shared.mutex.lock();
    const currently_connected = shared.connected;
    shared.mutex.unlock();

    if (!currently_connected) {
        _ = std.Thread.spawn(.{}, startClientThread, .{}) catch |err| {
            // Handle thread creation error
            displayError(@constCast("Failed to start client thread"));
            log.err("Failed to spawn client thread: {}", .{err}, @src());
        };
    } else {
        clientInstance.closeConnection();
    }
}

fn openPopup(string: []u8, input: bool) void {
    if (popupText.len > 1) alloc.free(popupText);
    popupText = alloc.dupeZ(u8, string) catch emptyMessage;
    // Show popup for user input
    showPopup = true;
    for (&buttons) |*b| {
        b.enabled = false;
    }
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

    for (createInputs[0..createInputsLen]) |*input| {
        input.update();
    }

    for (createButtons[0..createButtonsLen]) |*button| {
        button.position.y = button.position.y; // Keep y position
        button.position.x = (screen_width - button.size.x) / 2; // Center horizontally
    }
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
                currentState = .createScren;
                initiateCreationLayout();
                updateLayout();
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
    const screen_width = @as(f32, @floatFromInt(rl.getScreenWidth()));
    const screen_height = @as(f32, @floatFromInt(rl.getScreenHeight()));
    const scale_x = screen_width / base_width;
    const scale_y = screen_height / base_height;

    const input_width = 600 * scale_x;
    const input_height = 50 * scale_y;
    const button_width = 250 * scale_x;
    const button_height = 60 * scale_y;

    // Create an input field for quiz ID or question text
    createInputs[0] = TextBox{
        .position = Vec2{ .x = (screen_width - input_width) / 2, .y = 300 },
        .size = Vec2{ .x = input_width, .y = input_height },
        .active_color = Colors.text,
        .hover_color = Colors.button_hover,
        .normal_color = Colors.button,
        .text_color = Colors.text,
    };
    createInputsLen = 1;

    // Submit button
    createButtons[0] = Button{
        .text = "Submit",
        .position = Vec2{ .x = (screen_width - button_width) / 2, .y = 400 },
        .size = Vec2{ .x = button_width, .y = button_height },
        .background_color = Colors.button,
        .hover_color = Colors.button_hover,
        .disabled_color = Colors.button_disabled,
        .text_color = Colors.text,
        .enabled = true,
        .onClick = struct {
            pub fn click(ctx: *anyopaque) void {
                _ = ctx;
                handleCreateSubmit();
            }
        }.click,
    };

    // Back to main menu button
    createButtons[1] = Button{
        .text = "Cancel",
        .position = Vec2{ .x = (screen_width - button_width) / 2, .y = 480 },
        .size = Vec2{ .x = button_width, .y = button_height },
        .background_color = Colors.button,
        .hover_color = Colors.button_hover,
        .disabled_color = Colors.button_disabled,
        .text_color = Colors.text,
        .enabled = true,
        .onClick = struct {
            pub fn click(ctx: *anyopaque) void {
                _ = ctx;
                cancelCreateQuiz();
            }
        }.click,
    };
    createButtonsLen = 2;

    // Initialize arraylists for storing question and option data
    questionTexts = std.ArrayList([:0]u8).init(alloc);
    optionTexts = std.ArrayList(std.ArrayList([:0]u8)).init(alloc);

    // Reset creation step
    creationStep = .id;
    firstTime = true;
}

fn handleCreateSubmit() void {
    log.debug("state: {any}", .{creationStep}, @src());
    switch (creationStep) {
        .id => {
            // Check if quiz ID is not empty
            if (createInputs[0].buffer_len == 0) {
                displayError(@constCast("Quiz ID cannot be empty"));
                return;
            }

            // Send quiz creation request to the server
            // The 'c' command tells the server we want to create a quiz
            if (firstTime) {
                clientInstance.sendMessage('c', "") catch {
                    displayError(@constCast("Failed to send message"));
                    return;
                };
                firstTime = false;
            } else {
                shared.state = .ready_to_send;
                shared.setUserInput(alloc, createInputs[0].buffer[0..createInputs[0].buffer_len]) catch {
                    return;
                };

                shared.client_signal.signal();
            }
        },
        .num_questions => {
            // Parse number of questions
            const num_str = createInputs[0].buffer[0..createInputs[0].buffer_len];
            log.debug("domande num: {s}", .{num_str}, @src());
            totalQuestions = std.fmt.parseInt(usize, num_str, 10) catch {
                displayError(@constCast("Invalid number format"));
                return;
            };

            if (totalQuestions == 0 or totalQuestions > 100) {
                displayError(@constCast("Please enter a number between 1 and 100"));
                return;
            }

            // Prepare for first question
            currentQuestion = 0;
            clearCreateInput();
            creationStep = .question_text;
            updatePromptText();

            // Send the number of questions to the server
            submitResponse(num_str);
        },
        .question_text => {
            // Store the question text
            if (createInputs[0].buffer_len == 0) {
                displayError(@constCast("Question text cannot be empty"));
                return;
            }

            const questionText = createInputs[0].buffer[0..createInputs[0].buffer_len];

            // Send question text to server
            submitResponse(questionText);

            // Move to number of options
            clearCreateInput();
            creationStep = .num_options;
            updatePromptText();
        },
        .num_options => {
            // Parse number of options
            const num_str = createInputs[0].buffer[0..createInputs[0].buffer_len];
            questionOptions = std.fmt.parseInt(usize, num_str, 10) catch {
                displayError(@constCast("Invalid number format"));
                return;
            };

            if (questionOptions < 2 or questionOptions > 10) {
                displayError(@constCast("Please enter a number between 2 and 10"));
                return;
            }

            // Send number of options to server
            submitResponse(num_str);

            // Prepare for option input
            currentOption = 0;
            clearCreateInput();
            creationStep = .option_text;
            updatePromptText();
        },
        .option_text => {
            // Store the option text
            if (createInputs[0].buffer_len == 0) {
                displayError(@constCast("Option text cannot be empty"));
                return;
            }

            const optionText = createInputs[0].buffer[0..createInputs[0].buffer_len];

            // Send option to server
            submitResponse(optionText);

            currentOption += 1;
            clearCreateInput();

            // Check if all options for this question are collected
            if (currentOption >= questionOptions) {
                // Move to next question or complete
                currentQuestion += 1;

                if (currentQuestion >= totalQuestions) {
                    // All questions collected, quiz creation is complete
                    creationStep = .complete;
                    updatePromptText();

                    // Wait for server confirmation
                    // We'll receive a notification from the server when done
                } else {
                    // Next question
                    creationStep = .question_text;
                }
            }

            updatePromptText();
        },
        .complete => {
            // Quiz creation complete
            resetQuizCreation();
            currentState = .homeScreen;
        },
    }
}

fn updatePromptText() void {
    switch (creationStep) {
        .id => {
            if (notificationText.len > 1) alloc.free(notificationText);
            notificationText = alloc.dupeZ(u8, "Enter Quiz ID") catch emptyMessage;
        },
        .num_questions => {
            if (notificationText.len > 1) alloc.free(notificationText);
            notificationText = alloc.dupeZ(u8, "How many questions would you like to add?") catch emptyMessage;
        },
        .question_text => {
            if (notificationText.len > 1) alloc.free(notificationText);
            const text: [:0]u8 = std.fmt.allocPrintZ(alloc, "Enter question {d}/{d}", .{ currentQuestion + 1, totalQuestions }) catch @constCast("Enter question");
            notificationText = text;
        },
        .num_options => {
            if (notificationText.len > 1) alloc.free(notificationText);
            notificationText = alloc.dupeZ(u8, "How many options for this question?") catch emptyMessage;
        },
        .option_text => {
            if (notificationText.len > 1) alloc.free(notificationText);
            const text = std.fmt.allocPrintZ(alloc, "Enter option {d}/{d}", .{ currentOption + 1, questionOptions }) catch @constCast("Enter option");
            notificationText = text;
        },
        .complete => {
            if (notificationText.len > 1) alloc.free(notificationText);
            notificationText = alloc.dupeZ(u8, "Quiz creation complete!") catch emptyMessage;
        },
    }
}

// Clear the input field
fn clearCreateInput() void {
    createInputs[0].buffer = [_]u8{0} ** 256;
    createInputs[0].buffer_len = 0;
}

fn cancelCreateQuiz() void {
    resetQuizCreation();
    currentState = .homeScreen;
}

// Reset quiz creation state
fn resetQuizCreation() void {
    // Free allocated memory
    for (questionTexts.items) |text| {
        alloc.free(text);
    }
    questionTexts.clearAndFree();

    for (optionTexts.items) |options| {
        for (options.items) |option| {
            alloc.free(option);
        }
        options.deinit();
    }
    optionTexts.clearAndFree();

    // Reset counters
    currentQuestion = 0;
    totalQuestions = 0;
    questionOptions = 0;
    currentOption = 0;
    creationStep = .id;

    // Clear input
    clearCreateInput();
}

// Submit the completed quiz to the server
fn submitQuizToServer() void {
    // Mark that we're complete on UI side
    creationStep = .complete;
    updatePromptText();

    // Do not send all quiz data at once - the server expects interactive communication
    // Just send the initial command to start quiz creation process
    clientInstance.sendMessage('c', "") catch {
        displayError(@constCast("Failed to start quiz creation"));
        return;
    };
}

// Variables to store quiz creation state
var currentQuizQuestions: std.ArrayList(util.QuizQuestion) = undefined;
var currentQuizTitle: []u8 = undefined;

fn initializeQuizCreation() void {
    // Initialize the array list for storing questions
    currentQuizQuestions = std.ArrayList(util.QuizQuestion).init(alloc);
    currentQuizTitle = alloc.alloc(u8, 0) catch "";

    // Switch to creation screen state
    currentState = .createScren;

    // Initialize the layout for creation
    initiateCreationLayout();
    updateLayout();
}

fn submitNewQuestion() void {
    // Validate inputs
    if (inputs[1].buffer_len == 0) {
        displayError(@constCast("Question cannot be empty"));
        return;
    }

    // Check all answers have content
    for (0..4) |i| {
        if (inputs[2 + i].buffer_len == 0) {
            displayError(@constCast("All answer options must be filled"));
            return;
        }
    }

    // Validate correct answer input (must be 1-4)
    if (inputs[6].buffer_len == 0 or inputs[6].buffer[0] < '1' or inputs[6].buffer[0] > '4') {
        displayError(@constCast("Correct answer must be 1-4"));
        return;
    }

    // Store quiz title if first question
    if (currentQuizTitle.len == 0 and inputs[0].buffer_len > 0) {
        currentQuizTitle = alloc.dupeZ(u8, inputs[0].buffer[0..inputs[0].buffer_len]) catch {
            displayError(@constCast("Memory allocation error"));
            return;
        };
    }

    // Create and store the new question
    var answers: [4][:0]const u8 = undefined;
    for (0..4) |i| {
        answers[i] = alloc.dupeZ(u8, inputs[2 + i].buffer[0..inputs[2 + i].buffer_len]) catch {
            displayError(@constCast("Memory allocation error"));
            return;
        };
    }

    const correct_index = @as(usize, @intCast(inputs[6].buffer[0] - '1'));

    const question = util.QuizQuestion{
        .question = alloc.dupeZ(u8, inputs[1].buffer[0..inputs[1].buffer_len]) catch {
            displayError(@constCast("Memory allocation error"));
            return;
        },
        .answers = answers,
        .correct_index = correct_index,
    };

    currentQuizQuestions.append(question) catch {
        displayError(@constCast("Memory allocation error"));
        return;
    };

    // Clear input fields except title
    for (1..inputsLen) |i| {
        inputs[i].buffer_len = 0;
        inputs[i].buffer[0] = 0;
    }

    // Show success notification
    if (notificationText.len > 1) alloc.free(notificationText);
    notificationText = alloc.dupeZ(u8, "Question added successfully") catch emptyMessage;
}

fn submitFullQuiz() void {
    // Validate that we have at least one question
    if (currentQuizQuestions.items.len == 0) {
        displayError(@constCast("Quiz must have at least one question"));
        return;
    }

    // Validate that we have a title
    if (currentQuizTitle.len == 0) {
        displayError(@constCast("Quiz must have a title"));
        return;
    }

    // Format the quiz data to send to server
    var quiz_data = std.ArrayList(u8).init(alloc);
    defer quiz_data.deinit();

    // Add title
    quiz_data.appendSlice(currentQuizTitle) catch {
        displayError(@constCast("Memory allocation error"));
        return;
    };
    quiz_data.append('\n') catch return;

    // Add question count
    const question_count_str = std.fmt.allocPrint(alloc, "{d}\n", .{currentQuizQuestions.items.len}) catch {
        displayError(@constCast("Memory allocation error"));
        return;
    };
    defer alloc.free(question_count_str);
    quiz_data.appendSlice(question_count_str) catch return;

    // Add each question
    for (currentQuizQuestions.items) |question| {
        // Question text
        quiz_data.appendSlice(question.question) catch return;
        quiz_data.append('\n') catch return;

        // Answer count
        quiz_data.appendSlice("4\n") catch return;

        // Each answer
        for (question.answers) |answer| {
            quiz_data.appendSlice(answer) catch return;
            quiz_data.append('\n') catch return;
        }

        // Correct answer index
        const correct_str = std.fmt.allocPrint(alloc, "{d}\n", .{question.correct_index}) catch {
            displayError(@constCast("Memory allocation error"));
            return;
        };
        defer alloc.free(correct_str);
        quiz_data.appendSlice(correct_str) catch return;
    }

    // Send the quiz data to server
    clientInstance.sendMessage('c', quiz_data.items) catch {
        displayError(@constCast("Failed to send quiz to server"));
        return;
    };

    // Clean up
    for (currentQuizQuestions.items) |question| {
        alloc.free(question.question);
        for (question.answers) |answer| {
            alloc.free(answer);
        }
    }
    currentQuizQuestions.deinit();
    alloc.free(currentQuizTitle);

    // Return to home screen
    currentState = .homeScreen;
    initiateHomeLayout();
    updateLayout();

    // Show success notification
    if (notificationText.len > 1) alloc.free(notificationText);
    notificationText = alloc.dupeZ(u8, "Quiz saved successfully") catch emptyMessage;
}

fn drawCreateScreen() void {
    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();

    rl.clearBackground(Colors.background);

    rl.drawText(
        "Create Quiz",
        @divTrunc(screen_width - rl.measureText("Create Quiz", 80), 2),
        50,
        80,
        Colors.text,
    );

    // Draw notification/prompt text
    if (notificationText.len > 1) {
        rl.drawText(notificationText, @divTrunc(screen_width - rl.measureText(notificationText, 30), 2), 200, 30, Colors.text);
    }

    // Draw input field and buttons
    for (createInputs[0..createInputsLen]) |*input| {
        input.draw();
    }

    for (createButtons[0..createButtonsLen]) |*button| {
        button.draw();
    }

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
}

fn handlePopupSubmission() void {
    showPopup = false;

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
    for (&buttons) |*b| {
        b.enabled = true;
    }
}

fn submitResponse(response: []const u8) void {
    shared.mutex.lock();
    defer shared.mutex.unlock();
    log.debug("state: {any}", .{shared.state}, @src());
    // Only process if we're in a state expecting user input
    if (shared.state == .waiting_user_input or
        shared.state == .waiting_question_response or
        shared.state == .user_error or
        shared.state == .ack or
        shared.state == .changeQuiz or shared.state == .idle)
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
            if (currentState == .createScren) {
                // Handle input request during quiz creation
                if (notificationText.len > 1) alloc.free(notificationText);
                notificationText = alloc.dupeZ(u8, shared.server_message) catch emptyMessage;

                // For quiz creation, we don't want to use the popup for input
                // Instead, we'll use the current input field
                shared.state = .idle;
                return;
            }

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
            shared.state = .idle;
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
            if (notificationText.len > 1) alloc.free(notificationText);
            notificationText = alloc.dupeZ(u8, shared.server_message) catch emptyMessage;

            // Check if this is the quiz creation complete message
            if (std.mem.indexOf(u8, shared.server_message, "Quiz created successfully") != null and currentState == .createScren) {
                // Reset quiz creation state and go back to home screen
                resetQuizCreation();
                currentState = .homeScreen;
                initiateHomeLayout();
                updateLayout();
            }

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
            // std.debug.print("ok: {d}", .{errorPopupTimer});
            errorPopupTimer -= 2;
            if (errorPopupTimer == 0) {
                showError = false;
            }
        }
    }

    rl.closeWindow();
}
