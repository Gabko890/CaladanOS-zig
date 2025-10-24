const builtin = @import("builtin");

pub fn supports_port_io() bool {
    return switch (builtin.target.cpu.arch) {
        .x86, .x86_64 => true,
        else => false,
    };
}

pub fn out8(port: u16, value: u8) void {
    asm volatile ("mov %[value], %%al\nmov %[port], %%dx\noutb %%al, %%dx"
        :
        : [value] "r" (value),
          [port] "r" (port),
        : .{ .memory = false, .rax = true, .rdx = true });
}

pub fn in8(port: u16) u8 {
    var result: u8 = 0;
    asm volatile ("mov %[port], %%dx\ninb %%dx, %%al\nmov %%al, %[result]"
        : [result] "=r" (result),
        : [port] "r" (port),
        : .{ .memory = false, .rax = true, .rdx = true });
    return result;
}
