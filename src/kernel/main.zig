const std = @import("std");
const console = @import("console");
const mb2 = @import("arch_boot");
const cpu = @import("arch_cpu");
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

    const info_ptr: usize = info_addr;

    const framebuffer = mb2.locateFramebuffer(info_ptr);
    if (framebuffer) |fb| {
        switch (fb.kind) {
            .text => {
                if (fb.text_buffer) |text_ptr| {
                    console.initializeText(text_ptr, fb.width, fb.height);
                } else {
                    console.initializeLegacy();
                }
            },
            else => {
                if (fb.address) |addr| {
                    console.initializeFramebuffer(addr, fb.pitch, fb.width, fb.height, fb.bpp);
                } else {
                    console.initializeLegacy();
                }
            },
        }
    } else {
        console.initializeLegacy();
    }

    console.clear();
    console.puts("CaladanOS-zig kernel (x86_64) loaded!\n");

    var brand_buf: [64]u8 = undefined;
    const brand = cpu.writeBrandString(&brand_buf);
    console.printf("CPU: {s}\n", .{brand});
    var vendor_buf: [16]u8 = undefined;
    const vendor = cpu.writeVendorString(&vendor_buf);
    console.printf("Vendor: {s}\n", .{vendor});
    const logical = cpu.logicalProcessorCount();
    console.printf("Logical processors: {d}\n", .{logical});

    if (mb2.memoryMap(info_ptr)) |map| {
        console.puts("Memory map (bootloader):\n");
        var total_usable: u64 = 0;
        var idx: usize = 0;
        while (idx < map.count) : (idx += 1) {
            const entry = map.entries[idx];
            const type_str = mb2.memoryTypeName(entry.type);
            console.printf(
                "  region {d}: base=0x{X:0>16}, len=0x{X:0>16} ({s})\n",
                .{ idx, entry.addr, entry.len, type_str },
            );
            if (entry.type == @intFromEnum(mb2.MemoryType.available)) {
                total_usable += entry.len;
            }
        }
        console.printf(
            "Total usable memory: {d} MiB\n",
            .{total_usable / (1024 * 1024)},
        );
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
