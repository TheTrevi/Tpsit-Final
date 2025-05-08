const rl = @import("raylib");
const std = @import("std");
pub const Vec2 = struct {
    x: f32,
    y: f32,
};

pub const TextBox = struct {
    buffer: [256]u8 = undefined,
    buffer_len: usize = 0,
    active: bool = false,

    visible: bool = true,
    position: Vec2,
    size: Vec2,
    normal_color: rl.Color,
    hover_color: rl.Color,
    active_color: rl.Color,
    text_color: rl.Color,

    cursor_timer: f32 = 0.0,
    cursor_visible: bool = true,
    cursor_index: usize = 0,

    text_visible: usize = 0,

    backspace_timer: f32 = 0.0,

    pub fn draw(self: *TextBox) void {
        if (self.visible == false) return;
        const mouse_over = self.isHovered();
        const outline_color = if (self.active) self.active_color else if (mouse_over) self.hover_color else self.normal_color;

        self.update();

        rl.drawRectangleRounded(.{
            .x = self.position.x,
            .y = self.position.y,
            .width = self.size.x,
            .height = self.size.y,
        }, 0.3, 10, self.normal_color);

        rl.drawRectangleRoundedLinesEx(rl.Rectangle{
            .x = self.position.x,
            .y = self.position.y,
            .width = self.size.x,
            .height = self.size.y,
        }, 0.3, // roundness
            10, // segments
            3, outline_color);

        const font_size = @max(10, @as(i32, @intFromFloat(self.size.y * 0.5)));
        const text_to_draw = self.getText(self.text_visible);

        rl.drawText(
            text_to_draw,
            @as(i32, @intFromFloat(self.position.x + 5)),
            @as(i32, @intFromFloat(self.position.y + (self.size.y - @as(f32, @floatFromInt(font_size))) / 2)),
            font_size,
            self.text_color,
        );

        if (self.active and self.cursor_visible) {
            const text_width = rl.measureText(text_to_draw, font_size);
            const cursor_x = self.position.x + 5 + @as(f32, @floatFromInt(text_width));
            // const cursor_x = self.position.x + 5 + rl.measureText(self.getText(self.text_visible), font_size);

            rl.drawLine(
                @as(i32, @intFromFloat(cursor_x)),
                @as(i32, @intFromFloat(self.position.y + 5)),
                @as(i32, @intFromFloat(cursor_x)),
                @as(i32, @intFromFloat(self.position.y + self.size.y - 5)),
                self.text_color,
            );
        }

        if (self.active) {
            self.captureInput();
        }

        self.updateCursor();
    }

    fn captureInput(self: *TextBox) void {
        while (true) {
            const key = rl.getCharPressed();
            if (key == 0) break;
            if (self.buffer_len < self.buffer.len - 1) {

                // WITH CURSON CHANGE
                // var i = self.buffer_len;
                // while (i > self.cursor_index) : (i -= 1) {
                // self.buffer[i] = self.buffer[i - 1];
                // }

                // // self.buffer[self.cursor_index] = @as(u8, @truncate(key));
                // self.buffer_len += 1;
                // self.cursor_index += 1;
                // self.buffer[self.buffer_len] = 0;

                // WITHOUT CURSOR CHANGE
                self.buffer[self.buffer_len] = @as(u8, @intCast(key));
                self.buffer_len += 1;
                self.buffer[self.buffer_len] = 0;

                self.checkTextSize();
            }
        }

        const frame_time = rl.getFrameTime();
        self.backspace_timer += frame_time;

        if ((rl.isKeyPressed(rl.KeyboardKey.backspace) or rl.isKeyDown(rl.KeyboardKey.backspace)) and self.buffer_len > 0 and self.backspace_timer > 0.14) {

            // CURSOR CHANGE
            // if (self.cursor_index > 0) {
            // var i = self.cursor_index - 1;
            // while (i < self.buffer_len - 1) : (i += 1) {
            // self.buffer[i] = self.buffer[i + 1];
            // }
            // self.buffer_len -= 1;
            // self.cursor_index -= 1;
            // self.buffer[self.buffer_len] = 0;
            // }

            self.buffer_len -= 1;
            self.buffer[self.buffer_len] = 0;

            if (self.text_visible >= 1) self.text_visible -= 1;
            if (self.backspace_timer > 0.14) self.backspace_timer = 0;
        }
        // CURSOR CHANGe
        // if (rl.isKeyPressed(rl.KeyboardKey.right) and self.cursor_index < self.buffer_len) {
        // self.cursor_index += 1;
        // }

        // // if (rl.isKeyPressed(rl.KeyboardKey.left) and self.cursor_index > 0) {
        // self.cursor_index -= 1;
        // }
    }

    fn checkTextSize(self: *TextBox) void {
        if (self.buffer_len == 0) return;
        const font_size = @max(10, @as(i32, @intFromFloat(self.size.y * 0.5)));
        const max_width = self.size.x - 10;
        const string = self.getText(0);
        const stringWidth = rl.measureText(string, font_size);

        if (@as(f32, @floatFromInt(stringWidth)) > max_width) {
            self.text_visible += 1;
        }
    }

    pub fn newVisibleSize(self: *TextBox) void {
        var newTextVisible: usize = 0;
        const font_size = @max(10, @as(i32, @intFromFloat(self.size.y * 0.5)));

        while (@as(f32, @floatFromInt(rl.measureText(self.getText(newTextVisible), font_size))) > self.size.x - 10) {
            newTextVisible += 1;
        }

        self.text_visible = newTextVisible;
    }

    fn updateCursor(self: *TextBox) void {
        self.cursor_timer += rl.getFrameTime();
        if (self.cursor_timer >= 0.5) {
            self.cursor_visible = !self.cursor_visible;
            self.cursor_timer = 0.0;
        }
    }

    fn getText(self: *TextBox, startIndex: usize) [:0]const u8 {
        return self.buffer[startIndex..self.buffer_len :0];
    }

    pub fn isHovered(self: *TextBox) bool {
        const mouse = rl.getMousePosition();
        return rl.checkCollisionPointRec(mouse, rl.Rectangle{
            .x = self.position.x,
            .y = self.position.y,
            .width = self.size.x,
            .height = self.size.y,
        });
    }

    pub fn update(self: *TextBox) void {
        if (self.isHovered() and rl.isMouseButtonPressed(rl.MouseButton.left)) {
            self.active = true;
        } else if (rl.isMouseButtonPressed(rl.MouseButton.left)) {
            self.active = false;
        }
    }
};

pub const Button = struct {
    text: [:0]const u8 = "placeholder",
    position: Vec2,
    size: Vec2,
    background_color: rl.Color = rl.Color.init(193, 11, 8, 1),
    hover_color: rl.Color = rl.Color.init(117, 10, 7, 1),
    disabled_color: rl.Color = rl.Color.init(48, 15, 3, 1),
    text_color: rl.Color = rl.Color.init(251, 255, 255, 1),
    enabled: bool = false,
    onClick: *const fn (ctx: *anyopaque) void,
    ctx: *anyopaque = undefined,
    clicked: bool = false,

    pub fn draw(self: *Button) void {
        const mouse_over = self.isHovered();

        rl.drawRectangleRounded(
            rl.Rectangle.init(
                self.position.x,
                self.position.y,
                self.size.x,
                self.size.y,
            ),
            0.4,
            10,
            if (!self.enabled) self.disabled_color else if (mouse_over) self.hover_color else self.background_color,
        );

        // const font_size = @min(@max(10, @as(i32, @intFromFloat(self.size.y * 0.5))), 45);

        var font_size = @as(i32, @intFromFloat(self.size.y * 0.5));

        const max_width = self.size.x * 0.9;
        var text_width: f32 = @floatFromInt(rl.measureText(self.text, font_size));

        while (text_width > max_width and font_size > 10) {
            font_size -= 1;
            text_width = @floatFromInt(rl.measureText(self.text, font_size));
        }

        if (font_size > 45) font_size = 45;

        text_width = @floatFromInt(rl.measureText(self.text, font_size));
        const text_x = self.position.x + (self.size.x - text_width) / 2;
        const text_y = self.position.y + (self.size.y - @as(f32, @floatFromInt(font_size))) / 2;

        rl.drawText(
            self.text,
            @as(i32, @intFromFloat(text_x)),
            @as(i32, @intFromFloat(text_y)),
            font_size,
            self.text_color,
        );

        if (self.enabled and self.isClicked()) {
            if (self.clicked == false) {
                self.onClick(self.ctx);
                self.clicked = true;
            }
        } else {
            self.clicked = false;
        }
    }

    pub fn update(self: *Button) void {
        _ = self;
        return;
    }

    pub fn isHovered(self: *Button) bool {
        const mouse = rl.getMousePosition();
        return rl.checkCollisionPointRec(mouse, rl.Rectangle{
            .x = self.position.x,
            .y = self.position.y,
            .width = self.size.x,
            .height = self.size.y,
        });
    }

    pub fn isClicked(self: *Button) bool {
        return self.isHovered() and rl.isMouseButtonPressed(rl.MouseButton.left);
    }

    pub fn enable(self: *Button, active: bool) void {
        self.enabled = active;
    }
};

pub const TextDisplay = struct {
    text: []const u8,
    position: Vec2,
    size: Vec2,
    background_color: rl.Color,
    text_color: rl.Color,
    border_color: rl.Color,
    font_size: i32,
    padding: f32 = 5.0,
    line_spacing: f32 = 2.0,
    show_border: bool = true,
    border_thickness: f32 = 2.0,

    // Cache for wrapped lines
    wrapped_lines: std.ArrayList([]const u8) = undefined,
    allocator: std.mem.Allocator = undefined,

    pub fn init(
        allocator: std.mem.Allocator,
        text: []const u8,
        position: Vec2,
        size: Vec2,
        background_color: rl.Color,
        text_color: rl.Color,
        border_color: rl.Color,
        font_size: i32,
    ) !TextDisplay {
        var self = TextDisplay{
            .text = text,
            .position = position,
            .size = size,
            .background_color = background_color,
            .text_color = text_color,
            .border_color = border_color,
            .font_size = font_size,
            .allocator = allocator,
            .wrapped_lines = std.ArrayList([]const u8).init(allocator),
        };

        try self.wrapText();
        return self;
    }

    pub fn deinit(self: *TextDisplay) void {
        self.wrapped_lines.deinit();
    }

    pub fn setText(self: *TextDisplay, new_text: []const u8) !void {
        self.text = new_text;
        self.wrapped_lines.clearRetainingCapacity();
        try self.wrapText();
    }

    fn wrapText(self: *TextDisplay) !void {
        const max_width = self.size.x - (self.padding * 2);
        var start: usize = 0;
        var end: usize = 0;
        var current_width: f32 = 0;

        while (start < self.text.len) {
            // Handle newline characters
            if (start < self.text.len and self.text[start] == '\n') {
                try self.wrapped_lines.append(self.text[start .. start + 1]);
                start += 1;
                end = start;
                current_width = 0;
                continue;
            }

            // Find space or end of text
            while (end < self.text.len and self.text[end] != ' ' and self.text[end] != '\n') {
                end += 1;
            }

            const word = self.text[start..end];
            const word_width = @as(f32, @floatFromInt(rl.measureText(word.ptr, self.font_size)));

            // If adding this word would exceed the line width
            if (current_width > 0 and current_width + word_width > max_width) {
                // Add the current line
                try self.wrapped_lines.append(self.text[start - current_width .. start - 1]);
                current_width = word_width + @as(f32, @floatFromInt(rl.measureText(" ", self.font_size)));
            } else {
                current_width += word_width + @as(f32, @floatFromInt(rl.measureText(" ", self.font_size)));
            }

            // If we've reached a newline or end of text
            if (end == self.text.len or self.text[end] == '\n') {
                try self.wrapped_lines.append(self.text[start..end]);
                if (end < self.text.len) {
                    // Skip the newline character
                    end += 1;
                }
                start = end;
                current_width = 0;
            } else {
                // Move past the space
                end += 1;
                start = end;
            }
        }

        // Add the last line if there's anything left
        if (current_width > 0) {
            try self.wrapped_lines.append(self.text[start - current_width .. self.text.len]);
        }
    }

    pub fn draw(self: *TextDisplay) void {
        // Draw background
        rl.drawRectangleRounded(
            rl.Rectangle{
                .x = self.position.x,
                .y = self.position.y,
                .width = self.size.x,
                .height = self.size.y,
            },
            0.3,
            10,
            self.background_color,
        );

        // Draw border if enabled
        if (self.show_border) {
            rl.drawRectangleRoundedLinesEx(
                rl.Rectangle{
                    .x = self.position.x,
                    .y = self.position.y,
                    .width = self.size.x,
                    .height = self.size.y,
                },
                0.3,
                10,
                self.border_thickness,
                self.border_color,
            );
        }

        // Draw text lines
        var y_offset: f32 = self.padding;
        const line_height: f32 = @as(f32, @floatFromInt(self.font_size)) + self.line_spacing;

        for (self.wrapped_lines.items) |line| {
            // Skip rendering if line would be outside the box
            if (y_offset > self.size.y - self.padding) {
                break;
            }

            // Draw the line
            rl.drawText(
                line.ptr,
                @as(i32, @intFromFloat(self.position.x + self.padding)),
                @as(i32, @intFromFloat(self.position.y + y_offset)),
                self.font_size,
                self.text_color,
            );

            y_offset += line_height;
        }
    }

    pub fn update(self: *TextDisplay) !void {
        _ = self;
    }

    pub fn setFontSize(self: *TextDisplay, new_font_size: i32) !void {
        self.font_size = new_font_size;
        try self.wrapText();
    }

    pub fn resize(self: *TextDisplay, new_size: Vec2) !void {
        self.size = new_size;
        try self.wrapText();
    }

    pub fn move(self: *TextDisplay, new_position: Vec2) void {
        self.position = new_position;
    }
};

pub const Colors = struct {
    pub const background = rl.Color{ .r = 55, .g = 55, .b = 55, .a = 255 };
    pub const button = rl.Color{ .r = 80, .g = 80, .b = 80, .a = 255 };
    pub const button_hover = rl.Color{ .r = 100, .g = 100, .b = 100, .a = 255 };
    pub const button_disabled = rl.Color{ .r = 110, .g = 110, .b = 110, .a = 255 };
    pub const text = rl.Color{ .r = 167, .g = 167, .b = 167, .a = 255 };
    pub const green_pastel = rl.Color{ .r = 144, .g = 238, .b = 144, .a = 255 };
    pub const red_pastel = rl.Color{ .r = 255, .g = 182, .b = 193, .a = 255 };
    pub const yellow_pastel = rl.Color{ .r = 255, .g = 255, .b = 153, .a = 255 };
    pub const popup_background = rl.Color{ .r = 33, .g = 33, .b = 33, .a = 255 };
};
