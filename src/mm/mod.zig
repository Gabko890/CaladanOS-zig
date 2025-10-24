const pmm = @import("pmm.zig");

// Public API: refer to physical pages as frames.
pub const frames = enum { KERNEL, USER };

fn to_flag(kind: frames) pmm.PmPageFlag {
    return switch (kind) {
        .KERNEL => pmm.PmPageFlag.PM_PAGE_KERNEL,
        .USER => pmm.PmPageFlag.PM_PAGE_USER,
    };
}

pub fn pma_init(info_addr: usize, kernel_end_phys: ?usize) void {
    pmm.init(info_addr, kernel_end_phys);
}

pub fn alloc_frames(count: usize, kind: frames) ?usize {
    return pmm.alloc_pages(count, to_flag(kind));
}

pub fn free_frames(base_phys_addr: usize, count: usize) void {
    pmm.free_pages(base_phys_addr, count);
}
