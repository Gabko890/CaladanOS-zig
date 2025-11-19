const std = @import("std");

const console = @import("console");
const init_console = @import("console_init.zig");
const mb2 = @import("arch_boot");

const cpu = @import("arch_cpu");
const idt = @import("idt.zig");
const mm = @import("mm");

const syms = @import("ld_syms");

//extern "__kernel_phys_end" const __kernel_phys_end: usize;

// Re-export custom panic handler from a dedicated file so it becomes the root panic.
pub const panic = @import("panic.zig").panic;

// 64-bit entry called by the bootstrap
pub export fn kmain(magic: u32, info_addr: usize) noreturn {
    if (magic != mb2.bootloader_magic) {
        console.initialize_legacy();
        console.puts("Invalid boot magic\n");
        halt();
    }

    init_console.initialize_from_multiboot(info_addr);

    //console.printf("kernel_phys_end: {x}\n", .{__kernel_phys_end});

    console.clear();
    console.puts("CaladanOS-zig kernel (x86_64) loaded!\n");

    console.printf("kernel physical addr: 0x{x}={d} - 0x{x}={d}\n", .{ syms.kphys_start(), syms.kphys_start(), syms.kphys_end(), syms.kphys_end() });

    // Initialize and load a default IDT.
    idt.init();
    idt.interrupts_enable();

    var brand_buf: [64]u8 = undefined;
    const brand = cpu.write_brand_string(&brand_buf);
    console.printf("CPU: {s}\n", .{brand});
    var vendor_buf: [16]u8 = undefined;
    const vendor = cpu.write_vendor_string(&vendor_buf);
    console.printf("Vendor: {s}\n", .{vendor});
    const logical = cpu.logical_processor_count();
    console.printf("Logical processors: {d}\n", .{logical});

    if (mb2.BootloaderMemoryMap.init(info_addr)) |bl_map| {
        bl_map.print();
    } else {
        console.puts("No memory map provided by bootloader\n");
    }

    // Run embedded selftests for the frame allocator
    // console.printf("MM selftest kernel_reuse: {s}\n", .{if (mm.selftest_kernel_reuse()) "PASS" else "FAIL"});
    // console.printf("MM selftest user_down: {s}\n", .{if (mm.selftest_user_down()) "PASS" else "FAIL"});
    // console.printf("MM selftest all: {s}\n", .{if (mm.selftest_all()) "PASS" else "FAIL"});

    // Initialize physical frame allocator from Multiboot2 map (restore real state)
    mm.pma.init(info_addr, syms.kphys_end());

    // Initialize virtual memory manager and install new page tables
    mm.vmm.init();
    mm.vmm.install_kernel_tables();

    const frame_ptr_1: ?usize = mm.pma.alloc_frames(4, mm.pma.Frame_type.KERNEL);
    console.printf("4 pages alocated at: {x}", .{frame_ptr_1 orelse 0x00});
    if (frame_ptr_1) |fp| mm.pma.free_frames(fp, 4);

    halt();
}

fn halt() noreturn {
    while (true) {
        asm volatile ("hlt" ::: .{ .memory = true });
    }
}
