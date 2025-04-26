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
        const mouse_over = self.isHovered();
        const outline_color = if (self.active) self.active_color else if (mouse_over) self.hover_color else self.normal_color;

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
    onClick: *const fn () void,

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

        const font_size = @max(10, @as(i32, @intFromFloat(self.size.y * 0.5)));

        const text_width: f32 = @floatFromInt(rl.measureText(self.text, font_size));
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
            self.onClick();
        }
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
