const std = @import("std");
const mm = @import("mm");

// Kernel heap using a FixedBufferAllocator over a mapped VMA window.

pub const InitResult = struct {
    base: [*]u8,
    len: usize,
};

var fba: std.heap.FixedBufferAllocator = undefined;
var buf_slice: []u8 = &[_]u8{};

pub fn init_fixed_buffer_heap() ?InitResult {
    const total_bytes = mm.pma.total_bytes();
    if (total_bytes == 0) return null;

    // Target ~50% of total, capped at 1 GiB heap window
    const GiB: usize = 1024 * 1024 * 1024;
    const TwoMiB: usize = 2 * 1024 * 1024;
    var target: usize = total_bytes / 2;
    if (target >= GiB) target = GiB - TwoMiB; // avoid potential wrap at top of window
    target = (target / TwoMiB) * TwoMiB;
    if (target == 0) return null;

    const heap_base = mm.vmm.heap_vbase();

    // Map physical memory into the heap window in 2 MiB chunks
    var mapped: usize = 0;
    while (mapped < target) : (mapped += TwoMiB) {
        const phys = mm.pma.alloc_frames(TwoMiB / mm.pma.PAGE_SIZE, mm.pma.Frame_type.KERNEL) orelse break;
        mm.vmm.map_2m_page(heap_base + mapped, phys, true);
    }
    if (mapped == 0) return null;

    buf_slice = @as([*]u8, @ptrFromInt(heap_base))[0..mapped];
    fba = std.heap.FixedBufferAllocator.init(buf_slice);
    return InitResult{ .base = buf_slice.ptr, .len = buf_slice.len };
}

pub fn allocator() std.mem.Allocator {
    return fba.allocator();
}

pub fn reset() void {
    fba.reset();
}

pub fn buffer() []u8 {
    return buf_slice;
}
