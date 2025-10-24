const pma = @import("pma.zig");

pub const PAGE_SIZE = pma.PAGE_SIZE;

// Public API: refer to physical pages as frames.
pub const frames = enum { KERNEL, USER };

fn is_kernel(kind: frames) bool { return kind == .KERNEL; }

pub fn pma_init(info_addr: usize, kernel_end_phys: ?usize) void {
    pma.init(info_addr, kernel_end_phys);
}

pub fn alloc_frames(count: usize, kind: frames) ?usize {
    return pma.alloc_frames(count, is_kernel(kind));
}

pub fn free_frames(base_phys_addr: usize, count: usize) void {
    pma.free_frames(base_phys_addr, count);
}

// pub fn selftest_all() bool {
//     return pma.selftest_all();
// }
//
// pub fn selftest_kernel_reuse() bool {
//     return pma.selftest_kernel_reuse();
// }
//
// pub fn selftest_user_down() bool {
//     return pma.selftest_user_down();
// }
