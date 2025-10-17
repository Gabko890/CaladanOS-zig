const std = @import("std");
const console = @import("console");

// Custom panic handler: prints message to screen and halts the CPU.
pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    // Ensure a text console is available even very early.
    // console.initializeLegacy();

    const red_on_black: u8 = @intFromEnum(console.ConsoleColors.LightRed) | (@intFromEnum(console.ConsoleColors.Black) << 4);
    console.setColor(red_on_black);
    console.clear();
    console.homeTopLeft();

    printTitle();
    console.puts("Message: ");
    console.puts(message);
    console.puts("\n");

    if (ret_addr) |ra| {
        console.printf("RIP: 0x{X:0>16}\n", .{ra});
    }
    printDivider();
    dumpRegisters();

    // Halt forever
    while (true) {
        asm volatile ("hlt" ::: .{ .memory = true });
    }
}

const Regs = extern struct {
    // General-purpose registers (offsets 0x00..0x78)
    rax: usize, rbx: usize, rcx: usize, rdx: usize,
    rsi: usize, rdi: usize, rbp: usize, rsp: usize,
    r8: usize, r9: usize, r10: usize, r11: usize,
    r12: usize, r13: usize, r14: usize, r15: usize,
    // RFLAGS (0x80)
    rflags: usize,
    // Control registers (0x88..0xA8)
    cr0: usize, cr2: usize, cr3: usize, cr4: usize, cr8: usize,
    // Segment selectors, zero-extended (0xB0..0xD8)
    cs: usize, ds: usize, es: usize, fs: usize, gs: usize, ss: usize,
};

extern fn capture_regs(regs: *Regs) void;

fn dumpRegisters() void {
    var regs: Regs = undefined;
    capture_regs(&regs);

    console.puts("General Registers:\n");
    printReg2("RAX", regs.rax, "RBX", regs.rbx);
    printReg2("RCX", regs.rcx, "RDX", regs.rdx);
    printReg2("RSI", regs.rsi, "RDI", regs.rdi);
    printReg2("RBP", regs.rbp, "RSP", regs.rsp);
    printReg2(" R8", regs.r8,  " R9", regs.r9);
    printReg2("R10", regs.r10, "R11", regs.r11);
    printReg2("R12", regs.r12, "R13", regs.r13);
    printReg2("R14", regs.r14, "R15", regs.r15);

    console.puts("\nControl Registers:\n");
    printReg2("CR0", regs.cr0, "CR2", regs.cr2);
    printReg2("CR3", regs.cr3, "CR4", regs.cr4);
    printReg2("CR8", regs.cr8, "RFL", regs.rflags);

    console.puts("\nSegment Selectors:\n");
    printSeg2("CS", @as(u16, @truncate(regs.cs)), "DS", @as(u16, @truncate(regs.ds)));
    printSeg2("ES", @as(u16, @truncate(regs.es)), "FS", @as(u16, @truncate(regs.fs)));
    printSeg2("GS", @as(u16, @truncate(regs.gs)), "SS", @as(u16, @truncate(regs.ss)));
}

fn printTitle() void {
    console.puts("================== KERNEL PANIC ==================\n");
}

fn printDivider() void {
    console.puts("--------------------------------------------------\n");
}

fn printReg2(a: []const u8, va: usize, b: []const u8, vb: usize) void {
    console.printf(" {s}=0x{X:0>16}  {s}=0x{X:0>16}\n", .{ a, va, b, vb });
}

fn printSeg2(a: []const u8, va: u16, b: []const u8, vb: u16) void {
    console.printf(" {s}=0x{X:0>4}       {s}=0x{X:0>4}\n", .{ a, va, b, vb });
}
