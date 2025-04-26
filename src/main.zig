const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const logSetup = @import("logSetup.zig");
const net = std.net;
// const serverSetup = @import("Server.zig");
const client = @import("client.zig");
const util = @import("utils.zig");
const gui = @import("gui/gui.zig");

var buttons: [10]gui.Button = undefined;
var textboxes: [10]gui.TextBox = undefined;
var button_count: usize = 0;
var textbox_count: usize = 0;

const base_width: f32 = 1600;
const base_height: f32 = 1000;

var connected: bool = false;

fn updateLayout() void {
    const screen_width = @as(f32, @floatFromInt(rl.getScreenWidth()));
    const screen_height = @as(f32, @floatFromInt(rl.getScreenHeight()));

    const scale_x = screen_width / base_width;
    const scale_y = screen_height / base_height;

    buttons[0].position = gui.Vec2{ .x = (screen_width - (200 * scale_x)) / 2, .y = screen_height / 2 - (50 * scale_y) };
    buttons[0].size = gui.Vec2{ .x = 200 * scale_x, .y = 50 * scale_y };

    buttons[1].position = gui.Vec2{ .x = (screen_width - (200 * scale_x)) / 2, .y = screen_height / 2 + (20 * scale_y) };
    buttons[1].size = gui.Vec2{ .x = 200 * scale_x, .y = 50 * scale_y };

    textboxes[0].position = gui.Vec2{ .x = (screen_width - (300 * scale_x)) / 2, .y = screen_height / 2 + (100 * scale_y) };
    textboxes[0].size = gui.Vec2{ .x = 300 * scale_x, .y = 40 * scale_y };
    textboxes[0].newVisibleSize();
}

fn drawHomeScreen() void {
    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();
    rl.beginDrawing();
    rl.clearBackground(rl.Color.init(255, 225, 255, 1));

    rl.drawText(
        "Quiz DT",
        @divTrunc((rl.getScreenWidth() - rl.measureText("Quiz DT", 40)), 2),
        50,
        40,
        rl.Color.black,
    );

    var text: [:0]u8 = @as([:0]u8, @constCast("Connessione eseguita"));
    if (!connected) text = @as([:0]u8, @constCast("Connessione non eseguita"));
    rl.drawText(text, screen_width - 50 - rl.measureText(text, 25), screen_height - 50, 25, if (connected) rl.Color.green else rl.Color.red);

    for (buttons[0..button_count]) |*b| {
        b.draw();
    }

    for (textboxes[0..textbox_count]) |*t| {
        t.draw();
    }

    rl.endDrawing();
}

pub fn main() !void {
    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(base_width, base_height, "Quiz DT");
    rl.setTargetFPS(60);

    buttons[0] = gui.Button{
        .text = "Connect",
        .position = gui.Vec2{ .x = 0, .y = 0 },
        .size = gui.Vec2{ .x = 0, .y = 0 },
        .background_color = rl.Color.green,
        .hover_color = rl.Color.dark_green,
        .disabled_color = rl.Color.light_gray,
        .text_color = rl.Color.white,
        .enabled = true,
        .onClick = struct {
            pub fn click() void {
                std.debug.print("connessione\n", .{});
                connected = !connected;
                buttons[1].enabled = !buttons[1].enabled;
            }
        }.click,
    };

    buttons[1] = gui.Button{
        .text = "Create",
        .position = gui.Vec2{ .x = 0, .y = 0 },
        .size = gui.Vec2{ .x = 0, .y = 0 },
        .background_color = rl.Color.orange,
        .hover_color = rl.Color.init(205, 161, 0, 255),
        .disabled_color = rl.Color.light_gray,
        .text_color = rl.Color.white,
        .enabled = true,
        .onClick = struct {
            pub fn click() void {
                std.debug.print("creazione\n", .{});
            }
        }.click,
    };

    buttons[1].enabled = false;

    textboxes[0] = gui.TextBox{
        .position = .{ .x = 0, .y = 0 },
        .size = .{ .x = 0, .y = 0 },
        .active_color = rl.Color.black,
        .hover_color = rl.Color.blue,
        .normal_color = rl.Color.white,
        .text_color = rl.Color.black,
    };

    button_count = 2;
    textbox_count = 1;

    updateLayout();

    while (!rl.windowShouldClose()) {
        if (rl.isWindowResized()) {
            updateLayout();
        }

        // for (buttons[0..button_count]) |*b| {
        // b.update();
        // }

        for (textboxes[0..textbox_count]) |*t| {
            t.update();
        }

        drawHomeScreen();
    }

    rl.closeWindow();
}

// pub fn main() !void {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     // defer if (gpa.deinit() == .leak) std.os.linux.kernel_fsid_t.ExitProcess(1);  // std.os.linux.kernel32.ExitProcess(1);
//     const alloc = gpa.allocator();
//     const log = logSetup.logStruct.innit(alloc);
//     //     // const server = try serverSetup.serverClass.init("0.0.0.0", 3000, log);
//     //     // try server.start();
//     // defer server.stop();
//     //     // log.info("Server Started at {any}", .{server.address}, @src());
//     // try server.start();
//     //     const cc = try client.client.init("0.0.0.0", 3000, log);
//     //     try cc.startStream();
//
//     //     var buf: [200]u8 = undefined;
//     //     var fba = std.heap.FixedBufferAllocator.init(&buf);
//     //     var string = std.ArrayList(u8).init(fba.allocator());
//     //     try std.json.stringify(quiz, .{}, string.writer());
//     //     log.info("Stringified JSON: {s}", .{string.items}, @src())
//     var stringa: []u8 = undefined;
//     var ok: client.client = undefined;
//     //     log.info("{s}", .{std.builtin.os.tag}, @src());
//     while (true) {
//         util.ask_user(&stringa, alloc);
//         defer alloc.free(stringa);
//         if (std.mem.eql(u8, stringa, "client")) {
//             ok = try client.client.init("0.0.0.0", 3000, log, alloc);
//             try ok.startStream();
//         } else if (std.mem.eql(u8, stringa, "q")) {
//             return;
//         }
//
//         //         ok.closeConnection();
//     }
// }
// //  pub fn main() !void {
// //     rl.setTraceLogLevel(rl.TraceLogLevel.none);
// //     rl.initWindow(1280, 640, "Prova Zig");
// //     defer rl.closeWindow();
// //     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
// //     // defer if (gpa.deinit() == .leak) std.os.linux.kernel_fsid_t.ExitProcess(1);  // std.os.linux.kernel32.ExitProcess(1);
// //     const alloc = gpa.allocator();
// //     const log = logSetup.logStruct.innit(alloc);
// //     log.info("Window Opened", .{}, @src());
// //     while (!rl.windowShouldClose()) {
// //         rl.beginDrawing();
// //         defer rl.endDrawing();
// //         rl.clearBackground(rl.Color.sky_blue);
// //     }
// // }
