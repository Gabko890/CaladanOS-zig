const std = @import("std");

// x86_64 Interrupt Descriptor Table (IDT)
// API:
// - init(): initializes and loads an IDT with default handlers
// - setEntry(i, handler, selector, flags): sets a specific gate
// - interruptsEnable(): enables maskable interrupts (STI)

pub const IDT_SIZE = 256;

/// Default code segment selector for 64-bit kernel code
pub const CODE_SELECTOR: u16 = 0x08;

/// Type attributes for a present 64-bit interrupt gate, DPL=0
/// 0x8E = P(1) DPL(00) Type(1110 = interrupt gate)
pub const TYPE_ATTR_INTERRUPT_GATE: u8 = 0x8E;

const Gate = extern struct {
    offset_low: u16,
    selector: u16,
    ist: u8, // 3-bit IST index in low bits; rest must be zero
    type_attr: u8,
    offset_mid: u16,
    offset_high: u32,
    zero: u32,
};

const Idtr = packed struct {
    limit: u16,
    base: u64,
};

var table: [IDT_SIZE]Gate = [_]Gate{Gate{
    .offset_low = 0,
    .selector = 0,
    .ist = 0,
    .type_attr = 0,
    .offset_mid = 0,
    .offset_high = 0,
    .zero = 0,
}} ** IDT_SIZE;

var idtr: Idtr = .{ .limit = 0, .base = 0 };

inline fn makeGate(addr: u64, selector: u16, type_attr: u8, ist: u8) Gate {
    return Gate{
        .offset_low = @intCast(addr & 0xFFFF),
        .selector = selector,
        .ist = ist & 0x7,
        .type_attr = type_attr,
        .offset_mid = @intCast((addr >> 16) & 0xFFFF),
        .offset_high = @intCast((addr >> 32) & 0xFFFFFFFF),
        .zero = 0,
    };
}

extern fn idt_lidt_load(idtr_ptr: *const Idtr) void;

// Default handler stubs are implemented in assembly for compatibility.
// We only reference their addresses here; we do not call them directly from Zig.
extern fn idt_default_interrupt_handler() void;
extern fn idt_default_exception_error() void;
extern fn idt_default_exception_noerror() void;
extern fn idt_double_fault_entry() void;
extern fn idt_machine_check_entry() void;

// Panic helper for Double Fault (#DF). Never returns.
pub export fn idt_double_fault_panic() noreturn {
    @panic("Double Fault (#DF)");
}

pub export fn idt_machine_check_panic() noreturn {
    @panic("Machine Check (#MC)");
}


/// Initialize IDT with default handlers and load it with LIDT.
pub fn init() void {
    // Populate all entries with safe defaults (exception without error code)
    const def_exc_addr: u64 = @intFromPtr(&idt_default_exception_noerror);
    for (table[0..]) |*g| {
        g.* = makeGate(def_exc_addr, CODE_SELECTOR, TYPE_ATTR_INTERRUPT_GATE, 0);
    }

    // Exceptions that push an error code
    const err_vecs = [_]u8{ 8, 10, 11, 12, 13, 14, 17, 21, 29, 30 };
    for (err_vecs) |v| {
        setEntry(v, &idt_default_exception_error, CODE_SELECTOR, TYPE_ATTR_INTERRUPT_GATE);
    }

    // Override Double Fault (#DF, vector 8) with dedicated panic stub
    setEntry(8, &idt_double_fault_entry, CODE_SELECTOR, TYPE_ATTR_INTERRUPT_GATE);
    // Override Machine Check (#MC, vector 18) with dedicated panic stub
    setEntry(18, &idt_machine_check_entry, CODE_SELECTOR, TYPE_ATTR_INTERRUPT_GATE);

    // Common PIC IRQ range when remapped: 0x20..0x2F
    var i: usize = 0x20;
    while (i <= 0x2F) : (i += 1) {
        setEntry(i, &idt_default_interrupt_handler, CODE_SELECTOR, TYPE_ATTR_INTERRUPT_GATE);
    }

    // Load IDTR
    idtr = .{
        .limit = @intCast(@sizeOf(@TypeOf(table)) - 1),
        .base = @intFromPtr(&table),
    };
    idt_lidt_load(&idtr);
}

/// Set an IDT entry.
pub fn setEntry(index: usize, handler: anytype, selector: u16, flags: u8) void {
    std.debug.assert(index < IDT_SIZE);
    const addr: u64 = @intFromPtr(handler);
    table[index] = makeGate(addr, selector, flags, 0);
}

/// Enable maskable interrupts (STI)
pub fn interruptsEnable() void {
    asm volatile ("sti" ::: .{ .memory = true });
}
