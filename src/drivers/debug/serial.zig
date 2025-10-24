const portio = @import("portio");

const port_base: u16 = 0x3F8; // COM1

var initialized: bool = false;

inline fn supports_port_io() bool {
    return portio.supports_port_io();
}

inline fn port_out8(port: u16, value: u8) void {
    portio.out8(port, value);
}

inline fn port_in8(port: u16) u8 {
    return portio.in8(port);
}

fn init() void {
    if (initialized or !supports_port_io()) return;
    initialized = true;

    port_out8(port_base + 1, 0x00); // Disable interrupts
    port_out8(port_base + 3, 0x80); // Enable DLAB
    port_out8(port_base + 0, 0x03); // Divisor low byte (38400 baud)
    port_out8(port_base + 1, 0x00); // Divisor high byte
    port_out8(port_base + 3, 0x03); // 8 bits, no parity, one stop
    port_out8(port_base + 2, 0xC7); // Enable FIFO, clear, 14-byte threshold
    port_out8(port_base + 4, 0x0B); // IRQs enabled, RTS/DSR set
}

fn transmit_ready() bool {
    return (port_in8(port_base + 5) & 0x20) != 0;
}

pub fn write_byte(byte: u8) void {
    if (!supports_port_io()) return;
    init();

    while (!transmit_ready()) {}
    if (byte == '\n') {
        while (!transmit_ready()) {}
        port_out8(port_base + 0, '\r');
    }
    while (!transmit_ready()) {}
    port_out8(port_base + 0, byte);
}

pub fn write(data: []const u8) void {
    for (data) |byte| {
        write_byte(byte);
    }
}
