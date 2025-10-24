const std = @import("std");
const fmt = std.fmt;
const build_options = @import("build_options");

const serial = if (build_options.enable_serial)
    @import("serial")
else
    struct {
        pub inline fn write_byte(_: u8) void {}
        pub inline fn write(_: []const u8) void {}
    };

pub const VGA_WIDTH = 80;
pub const VGA_HEIGHT = 25;

pub const ConsoleColors = enum(u8) {
    Black = 0,
    Blue = 1,
    Green = 2,
    Cyan = 3,
    Red = 4,
    Magenta = 5,
    Brown = 6,
    LightGray = 7,
    DarkGray = 8,
    LightBlue = 9,
    LightGreen = 10,
    LightCyan = 11,
    LightRed = 12,
    LightMagenta = 13,
    LightBrown = 14,
    White = 15,
};

// Font (PSF, Lat15-Terminus16)
const font_data = @embedFile("Lat15-Terminus16.psf");

const PSF1_MAGIC = [_]u8{ 0x36, 0x04 };

const PSF1Header = extern struct {
    magic0: u8,
    magic1: u8,
    mode: u8,
    charsize: u8,
};

const PSFFont = struct {
    width: usize = 8,
    height: usize,
    glyph_count: usize,
    glyph_size: usize,
    glyphs: []const u8,
};

fn load_embedded_font() PSFFont {
    const hdr = @as(*const PSF1Header, @ptrCast(font_data.ptr));
    if (!(hdr.magic0 == 0x36 and hdr.magic1 == 0x04))
        @panic("Invalid PSF font header");

    const glyph_count = if ((hdr.mode & 0x01) != 0) 512 else 256;
    const glyphs = font_data[@sizeOf(PSF1Header)..][0 .. @as(usize, glyph_count) * @as(usize, hdr.charsize)];

    return PSFFont{
        .height = hdr.charsize,
        .glyph_count = glyph_count,
        .glyph_size = hdr.charsize,
        .glyphs = glyphs,
    };
}

var psf_font: PSFFont = undefined;

// VGA color packing and palette
fn vga_entry_color(fg: ConsoleColors, bg: ConsoleColors) u8 {
    return @intFromEnum(fg) | (@intFromEnum(bg) << 4);
}

fn vga_entry(uc: u8, new_color: u8) u16 {
    const c: u16 = new_color;
    return uc | (c << 8);
}

const palette = [_][3]u8{
    .{ 0x00, 0x00, 0x00 }, // Black
    .{ 0x00, 0x00, 0xAA }, // Blue
    .{ 0x00, 0xAA, 0x00 }, // Green
    .{ 0x00, 0xAA, 0xAA }, // Cyan
    .{ 0xAA, 0x00, 0x00 }, // Red
    .{ 0xAA, 0x00, 0xAA }, // Magenta
    .{ 0xAA, 0x55, 0x00 }, // Brown
    .{ 0xAA, 0xAA, 0xAA }, // LightGray
    .{ 0x55, 0x55, 0x55 }, // DarkGray
    .{ 0x55, 0x55, 0xFF }, // LightBlue
    .{ 0x55, 0xFF, 0x55 }, // LightGreen
    .{ 0x55, 0xFF, 0xFF }, // LightCyan
    .{ 0xFF, 0x55, 0x55 }, // LightRed
    .{ 0xFF, 0x55, 0xFF }, // LightMagenta
    .{ 0xFF, 0xFF, 0x55 }, // Yellow
    .{ 0xFF, 0xFF, 0xFF }, // White
};

// Backend selection and state
const Backend = enum { text, graphics };

const GraphicsState = struct {
    buffer: [*]volatile u8,
    pitch: usize,
    fb_width: usize,
    fb_height: usize,
    bytes_per_pixel: usize,
};

var backend: Backend = .text;
var row: usize = 0;
var column: usize = 0;
var color = vga_entry_color(ConsoleColors.LightGray, ConsoleColors.Black);
var text_buffer: ?[*]volatile u16 = null;
var gfx_state: ?GraphicsState = null;
var width: usize = VGA_WIDTH;
var height: usize = VGA_HEIGHT;

// Initialization
pub fn initialize_legacy() void {
    initialize_text(@ptrFromInt(0xB8000), VGA_WIDTH, VGA_HEIGHT);
}

pub fn initialize_text(ptr: [*]volatile u16, w: u32, h: u32) void {
    backend = .text;
    text_buffer = ptr;
    gfx_state = null;
    width = @intCast(w);
    height = @intCast(h);
    row = 0;
    column = 0;
    clear();
}

pub fn initialize_framebuffer(ptr: [*]volatile u8, pitch: u32, w: u32, h: u32, bpp: u8) void {
    psf_font = load_embedded_font();
    backend = .graphics;
    text_buffer = null;
    gfx_state = GraphicsState{
        .buffer = ptr,
        .pitch = @intCast(pitch),
        .fb_width = @intCast(w),
        .fb_height = @intCast(h),
        .bytes_per_pixel = @max(1, (@as(usize, bpp) + 7) / 8),
    };

    const cols = w / @as(u32, @intCast(psf_font.width));
    const rows = h / @as(u32, @intCast(psf_font.height));
    width = @intCast(if (cols == 0) 1 else cols);
    height = @intCast(if (rows == 0) 1 else rows);
    row = 0;
    column = 0;
    clear();
}

// Utilities
pub fn set_color(new_color: u8) void {
    color = new_color;
}

pub fn clear() void {
    switch (backend) {
        .text => {
            const buf = text_buffer orelse return;
            const size = width * height;
            @memset(buf[0..size], vga_entry(' ', color));
        },
        .graphics => {
            if (gfx_state) |*state| {
                const bg = palette_color(background_index(color));
                fill_rect(state, 0, 0, state.fb_width, state.fb_height, bg);
            }
        },
    }
}

// Move the logical cursor to the top-left corner (column 0, row 0).
pub fn home_top_left() void {
    column = 0;
    row = 0;
}

fn foreground_index(value: u8) u8 {
    return value & 0x0F;
}

fn background_index(value: u8) u8 {
    return (value >> 4) & 0x0F;
}

fn palette_color(index: u8) [3]u8 {
    const idx: usize = @intCast(index & 0x0F);
    return palette[idx];
}

// Character output
pub fn put_char_at(c: u8, new_color: u8, x: usize, y: usize) void {
    if (x >= width or y >= height) return;

    switch (backend) {
        .text => {
            const buf = text_buffer orelse return;
            const index = y * width + x;
            buf[index] = vga_entry(c, new_color);
        },
        .graphics => {
            if (gfx_state) |*state| {
                const fg = palette_color(foreground_index(new_color));
                const bg = palette_color(background_index(new_color));
                draw_glyph(state, x, y, c, fg, bg);
            }
        },
    }
}

pub fn put_char(c: u8) void {
    if (build_options.enable_serial)
        serial.write_byte(c);

    if (c == '\n') {
        column = 0;
        newline();
        return;
    }

    put_char_at(c, color, column, row);
    column += 1;
    if (column == width) {
        column = 0;
        newline();
    }
}

fn newline() void {
    if (row + 1 < height) {
        row += 1;
        return;
    }
    // Need to scroll up by one row
    scroll_up();
    row = height - 1;
}

fn scroll_up() void {
    switch (backend) {
        .text => {
            const buf = text_buffer orelse return;
            if (height == 0) return;
            var y: usize = 0;
            while (y + 1 < height) : (y += 1) {
                const dst_idx = y * width;
                const src_idx = (y + 1) * width;
                var x: usize = 0;
                while (x < width) : (x += 1) {
                    buf[dst_idx + x] = buf[src_idx + x];
                }
            }
            // Clear last row
            const last_row = (height - 1) * width;
            var x: usize = 0;
            while (x < width) : (x += 1) {
                buf[last_row + x] = vga_entry(' ', color);
            }
        },
        .graphics => {
            if (gfx_state) |*state| {
                const row_px: usize = psf_font.height;
                if (row_px == 0 or state.fb_height <= row_px) {
                    // Just clear if we can't scroll meaningfully
                    const bg = palette_color(background_index(color));
                    fill_rect(state, 0, 0, state.fb_width, state.fb_height, bg);
                    return;
                }
                // Copy framebuffer up by one text row (row_px pixels)
                var y: usize = 0;
                while (y + row_px < state.fb_height) : (y += 1) {
                    const dst_off = y * state.pitch;
                    const src_off = (y + row_px) * state.pitch;
                    var i: usize = 0;
                    while (i < state.pitch) : (i += 1) {
                        state.buffer[dst_off + i] = state.buffer[src_off + i];
                    }
                }
                // Clear the bottom band
                const bg2 = palette_color(background_index(color));
                fill_rect(state, 0, state.fb_height - row_px, state.fb_width, row_px, bg2);
            }
        },
    }
}

// Glyph drawing
fn draw_glyph(state: *GraphicsState, cell_x: usize, cell_y: usize, ch: u8, fg: [3]u8, bg: [3]u8) void {
    const font = psf_font;
    const px = cell_x * font.width;
    const py = cell_y * font.height;

    const index = if (ch < font.glyph_count) ch else '?';
    const glyph = font.glyphs[index * font.glyph_size .. (index + 1) * font.glyph_size];

    var y: usize = 0;
    while (y < font.height and py + y < state.fb_height) : (y += 1) {
        const bits = glyph[y];
        var x: usize = 0;
        while (x < font.width and px + x < state.fb_width) : (x += 1) {
            const shift: u8 = @intCast(x & 7);

            const shift_amt: u3 = @truncate(shift & 7);
            const mask: u8 = @as(u8, 0x80) >> shift_amt;

            const rgb = if ((bits & mask) != 0) fg else bg;
            set_pixel(state, px + x, py + y, rgb);
        }
    }
}

// Framebuffer helpers
fn fill_rect(state: *GraphicsState, start_x: usize, start_y: usize, rect_w: usize, rect_h: usize, fill_rgb: [3]u8) void {
    var y = start_y;
    while (y < start_y + rect_h and y < state.fb_height) : (y += 1) {
        var x = start_x;
        while (x < start_x + rect_w and x < state.fb_width) : (x += 1) {
            set_pixel(state, x, y, fill_rgb);
        }
    }
}

fn set_pixel(state: *GraphicsState, x: usize, y: usize, rgb: [3]u8) void {
    if (x >= state.fb_width or y >= state.fb_height) return;
    const offset = y * state.pitch + x * state.bytes_per_pixel;
    const pixel_ptr = state.buffer + offset;

    switch (state.bytes_per_pixel) {
        4 => {
            pixel_ptr[0] = rgb[2];
            pixel_ptr[1] = rgb[1];
            pixel_ptr[2] = rgb[0];
            pixel_ptr[3] = 0xFF;
        },
        3 => {
            pixel_ptr[0] = rgb[2];
            pixel_ptr[1] = rgb[1];
            pixel_ptr[2] = rgb[0];
        },
        2 => {
            const r: u16 = (@as(u16, rgb[0]) & 0xF8) << 8;
            const g: u16 = (@as(u16, rgb[1]) & 0xFC) << 3;
            const b: u16 = (@as(u16, rgb[2]) & 0xF8) >> 3;
            const value: u16 = r | g | b;
            pixel_ptr[0] = @intCast(value & 0x00FF);
            pixel_ptr[1] = @intCast(value >> 8);
        },
        else => {},
    }
}

// Print utilities
pub fn puts(data: []const u8) void {
    for (data) |c|
        put_char(c);
}

pub fn printf(comptime format: []const u8, args: anytype) void {
    var scratch: [256]u8 = undefined;
    const message = fmt.bufPrint(&scratch, format, args) catch {
        puts("[printf overflow]\n");
        return;
    };
    puts(message);
}
