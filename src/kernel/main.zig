const std = @import("std");
const console = @import("console");
const mb2 = @import("arch_boot");
const cpu = @import("arch_cpu");
const idt = @import("idt.zig");
// Re-export custom panic handler from a dedicated file so it becomes the root panic.
pub const panic = @import("panic.zig").panic;

// 64-bit entry called by the bootstrap
// magic and info_addr follow Multiboot2
pub export fn kmain(magic: u32, info_addr: usize) noreturn {
    if (magic != mb2.bootloader_magic) {
        console.initializeLegacy();
        console.puts("Invalid boot magic\n");
        halt();
    }

    const init_console = @import("console_init.zig");
    init_console.initializeFromMultiboot(info_addr);

    console.clear();
    console.puts("CaladanOS-zig kernel (x86_64) loaded!\n");

    // Initialize and load a default IDT.
    idt.init();

    var brand_buf: [64]u8 = undefined;
    const brand = cpu.writeBrandString(&brand_buf);
    console.printf("CPU: {s}\n", .{brand});
    var vendor_buf: [16]u8 = undefined;
    const vendor = cpu.writeVendorString(&vendor_buf);
    console.printf("Vendor: {s}\n", .{vendor});
    const logical = cpu.logicalProcessorCount();
    console.printf("Logical processors: {d}\n", .{logical});

    if (mb2.BootloaderMemoryMap.init(info_addr)) |bl_map| {
        bl_map.print();
    } else {
        console.puts("No memory map provided by bootloader\n");
    }

    halt();
}

fn halt() noreturn {
    while (true) {
        asm volatile ("hlt" ::: .{ .memory = true });
    }
}
