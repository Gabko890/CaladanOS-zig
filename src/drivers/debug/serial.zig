const portio = @import("portio");

const port_base: u16 = 0x3F8; // COM1

var initialized: bool = false;

inline fn supportsPortIo() bool {
    return portio.supportsPortIo();
}

inline fn portOut8(port: u16, value: u8) void {
    portio.out8(port, value);
}

inline fn portIn8(port: u16) u8 {
    return portio.in8(port);
}

fn init() void {
    if (initialized or !supportsPortIo()) return;
    initialized = true;

    portOut8(port_base + 1, 0x00); // Disable interrupts
    portOut8(port_base + 3, 0x80); // Enable DLAB
    portOut8(port_base + 0, 0x03); // Divisor low byte (38400 baud)
    portOut8(port_base + 1, 0x00); // Divisor high byte
    portOut8(port_base + 3, 0x03); // 8 bits, no parity, one stop
    portOut8(port_base + 2, 0xC7); // Enable FIFO, clear, 14-byte threshold
    portOut8(port_base + 4, 0x0B); // IRQs enabled, RTS/DSR set
}

fn transmitReady() bool {
    return (portIn8(port_base + 5) & 0x20) != 0;
}

pub fn writeByte(byte: u8) void {
    if (!supportsPortIo()) return;
    init();

    while (!transmitReady()) {}
    if (byte == '\n') {
        while (!transmitReady()) {}
        portOut8(port_base + 0, '\r');
    }
    while (!transmitReady()) {}
    portOut8(port_base + 0, byte);
}

pub fn write(data: []const u8) void {
    for (data) |byte| {
        writeByte(byte);
    }
}
