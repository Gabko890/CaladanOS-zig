const std = @import("std");
const arch_boot = @import("arch_boot");

pub const PAGE_SIZE: usize = 4096;

pub const Frame_type = enum(u1) {
    KERNEL = 0,
    USER = 1,
};

// Allocation policy for physical frames (4KiB units) is selected by a boolean
// flag at callsite: is_kernel = true reserves frames from the kernel region,
// false selects general/user frames above the kernel ceiling.

const PmmState = struct {
    bitmap: [*]u8 = undefined,
    bitmap_len: usize = 0,
    total_pages: usize = 0,
    kernel_ceiling_page: usize = 0,
    kernel_next_page: usize = 0,
    user_floor_page: usize = 0,
    user_next_page: usize = 0,
};

var state: PmmState = .{};

// Absolute symbols exported by the linker script for kernel physical bounds.
// These are absolute values (SHN_ABS); declare as integers and use directly.
// Pointers (in low boot rodata) to 32-bit physical values exported by the linker.
// These live in identity-mapped low memory, safe to read early on.
// Prefer direct absolute symbols if available; fall back to ptr indirection.
const KERNEL_LMA: usize = 2 * 1024 * 1024; // must match linker script
const DEFAULT_KERNEL_RESERVE: usize = 16 * 1024 * 1024; // conservative fallback
const LOW_MEM_RESERVE: usize = 1 * 1024 * 1024; // reserve first 1MiB
const KERNEL_BASE_PAGE: usize = KERNEL_LMA / PAGE_SIZE;

fn align_up(value: usize, alignment: usize) usize {
    return (value + alignment - 1) & ~(@as(usize, alignment - 1));
}

fn align_down(value: usize, alignment: usize) usize {
    return value & ~(@as(usize, alignment - 1));
}

fn set_bit(page_index: usize) void {
    const byte_index = page_index >> 3;
    const bit_index: u3 = @intCast(page_index & 7);
    state.bitmap[byte_index] |= (@as(u8, 1) << bit_index);
}

fn clear_bit(page_index: usize) void {
    const byte_index = page_index >> 3;
    const bit_index: u3 = @intCast(page_index & 7);
    state.bitmap[byte_index] &= ~(@as(u8, 1) << bit_index);
}

fn test_bit(page_index: usize) bool {
    const byte_index = page_index >> 3;
    const bit_index: u3 = @intCast(page_index & 7);
    return (state.bitmap[byte_index] & (@as(u8, 1) << bit_index)) != 0;
}

fn mark_range_reserved(phys_start: usize, phys_end_exclusive: usize) void {
    if (phys_end_exclusive <= phys_start) return;
    const start_page = align_down(phys_start, PAGE_SIZE) / PAGE_SIZE;
    const end_page = align_up(phys_end_exclusive, PAGE_SIZE) / PAGE_SIZE;
    var p = start_page;
    while (p < end_page and p < state.total_pages) : (p += 1) {
        set_bit(p);
    }
}

fn mark_range_free(phys_start: usize, phys_end_exclusive: usize) void {
    if (phys_end_exclusive <= phys_start) return;
    const start_page = align_up(phys_start, PAGE_SIZE) / PAGE_SIZE;
    const end_page = align_down(phys_end_exclusive, PAGE_SIZE) / PAGE_SIZE;
    var p = start_page;
    while (p < end_page and p < state.total_pages) : (p += 1) {
        clear_bit(p);
    }
}

const InfoHeader = extern struct {
    total_size: u32,
    reserved: u32,
};

const TagHeader = extern struct {
    type: u32,
    size: u32,
};

const ModuleTag = extern struct {
    header: TagHeader,
    mod_start: u32,
    mod_end: u32,
    // followed by zero-terminated string and padding
};

fn align_to_8(v: usize) usize {
    return (v + 7) & ~@as(usize, 7);
}

fn reserve_modules_from_mb2(info_addr: usize) void {
    const hdr = @as(*const InfoHeader, @ptrFromInt(info_addr));
    var cursor = info_addr + @sizeOf(InfoHeader);
    const end = info_addr + hdr.total_size;
    while (cursor < end) {
        const th = @as(*const TagHeader, @ptrFromInt(cursor));
        if (th.type == 0 or th.size == 0) break;
        if (th.type == 3) { // module
            const aligned = @as(*align(@alignOf(ModuleTag)) const TagHeader, @alignCast(th));
            const mt = @as(*const ModuleTag, @ptrCast(aligned));
            const start = @as(usize, mt.mod_start);
            const finish = @as(usize, mt.mod_end);
            mark_range_reserved(start, finish);
        }
        cursor = align_to_8(cursor + th.size);
    }
}

pub fn init(info_addr: usize, kernel_end_phys: ?usize) void {
    // Compute memory span from bootloader map
    const mmap = arch_boot.memory_map(info_addr) orelse {
        // If absent, assume a minimal 32 MiB span
        const fallback_bytes: usize = 32 * 1024 * 1024;
        const pages = fallback_bytes / PAGE_SIZE;
        state.total_pages = pages;
        // Place bitmap just after the kernel image, page-aligned
        const k_phys_end = kernel_end_phys orelse DEFAULT_KERNEL_RESERVE;
        const bmp_len = align_up((pages + 7) / 8, PAGE_SIZE);
        const bmp_phys = align_up(k_phys_end, PAGE_SIZE);
        state.bitmap = @as([*]u8, @ptrFromInt(bmp_phys));
        state.bitmap_len = bmp_len;
        // Default: mark everything reserved
        @memset(state.bitmap[0..bmp_len], 0xFF);
        // Reserve kernel image and bitmap
        mark_range_reserved(KERNEL_LMA, k_phys_end);
        mark_range_reserved(bmp_phys, bmp_phys + bmp_len);
        state.kernel_ceiling_page = align_up(k_phys_end, PAGE_SIZE) / PAGE_SIZE;
        return;
    };

    // Determine highest physical address
    var max_addr: usize = 0;
    var i: usize = 0;
    while (i < mmap.count) : (i += 1) {
        const e = mmap.entries[i];
        const end_addr = @as(usize, @intCast(e.addr)) + @as(usize, @intCast(e.len));
        if (end_addr > max_addr) max_addr = end_addr;
    }
    if (max_addr == 0) max_addr = 1 * 1024 * 1024; // safety

    const total_pages = align_up(max_addr, PAGE_SIZE) / PAGE_SIZE;
    state.total_pages = total_pages;

    // Decide bitmap placement: just after the kernel image
    const bmp_bytes = (total_pages + 7) / 8;
    const bmp_len = align_up(bmp_bytes, PAGE_SIZE);

    const k_end = kernel_end_phys orelse DEFAULT_KERNEL_RESERVE;
    var bmp_phys = align_up(k_end, PAGE_SIZE);
    // Try to find an available region that contains [bmp_phys, bmp_phys + bmp_len)
    var found: bool = false;
    i = 0;
    while (i < mmap.count) : (i += 1) {
        const e = mmap.entries[i];
        if (e.type != @intFromEnum(arch_boot.MemoryType.available)) continue;
        const base = @as(usize, @intCast(e.addr));
        const end = base + @as(usize, @intCast(e.len));
        var candidate = bmp_phys;
        if (candidate < base) candidate = base;
        candidate = align_up(candidate, PAGE_SIZE);
        if (candidate + bmp_len <= end) {
            bmp_phys = candidate;
            found = true;
            break;
        }
    }
    // If no suitable place found above, keep it just above the reserved window.

    state.bitmap = @as([*]u8, @ptrFromInt(bmp_phys));
    state.bitmap_len = bmp_len;
    @memset(state.bitmap[0..bmp_len], 0xFF); // default: reserved

    // Mark available RAM pages as free first
    i = 0;
    while (i < mmap.count) : (i += 1) {
        const e = mmap.entries[i];
        if (e.type == @intFromEnum(arch_boot.MemoryType.available)) {
            const base = @as(usize, @intCast(e.addr));
            const end = base + @as(usize, @intCast(e.len));
            mark_range_free(base, end);
        }
    }

    // Always reserve low memory (first 1MiB) including page 0
    mark_range_reserved(0, LOW_MEM_RESERVE);

    // Reserve kernel image and the PMM bitmap itself
    mark_range_reserved(KERNEL_LMA, k_end);
    mark_range_reserved(bmp_phys, bmp_phys + bmp_len);

    // Reserve the Multiboot2 info block itself
    const hdr = @as(*const InfoHeader, @ptrFromInt(info_addr));
    const mb_end = info_addr + hdr.total_size;
    mark_range_reserved(info_addr, mb_end);

    // Reserve any loaded modules
    reserve_modules_from_mb2(info_addr);

    // Initialize kernel ceiling and next pointer to the end of the kernel image
    state.kernel_ceiling_page = align_up(k_end, PAGE_SIZE) / PAGE_SIZE;
    state.kernel_next_page = state.kernel_ceiling_page;
    // Initialize user allocator high-water mark to the top and floor to kernel ceiling
    state.user_floor_page = state.kernel_ceiling_page;
    state.user_next_page = state.total_pages;
}

fn find_run(start_page: usize, end_page: usize, count: usize) ?usize {
    if (count == 0) return null;
    var p: usize = start_page;
    var run: usize = 0;
    var run_start: usize = p;
    while (p < end_page) : (p += 1) {
        if (!test_bit(p)) {
            if (run == 0) run_start = p;
            run += 1;
            if (run >= count) return run_start;
        } else {
            run = 0;
        }
    }
    return null;
}

fn range_is_free(start_page: usize, count: usize) bool {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (test_bit(start_page + i)) return false;
    }
    return true;
}

fn mark_run_used(start_page: usize, count: usize) void {
    var i: usize = 0;
    while (i < count) : (i += 1) set_bit(start_page + i);
}

fn find_run_down(high_exclusive: usize, low_inclusive: usize, count: usize) ?usize {
    if (high_exclusive <= low_inclusive or count == 0) return null;
    var p = high_exclusive;
    var run: usize = 0;
    while (p > low_inclusive) {
        p -= 1;
        if (!test_bit(p)) {
            run += 1;
            if (run >= count) {
                // Return the lowest page index of the contiguous run
                return p;
            }
        } else {
            run = 0;
        }
    }
    return null;
}

pub fn alloc_frames(count: usize, is_kernel: bool) ?usize {
    if (count == 0) return null;
    if (is_kernel) {
        // Reuse: first-fit below current kernel_next_page within kernel region.
        if (find_run(KERNEL_BASE_PAGE, state.kernel_next_page, count)) |run_start| {
            if (!range_is_free(run_start, count)) return null; // safety guard
            mark_run_used(run_start, count);
            return run_start * PAGE_SIZE;
        }
        // Append: first-fit at/above kernel_next_page, then advance next/ceiling.
        if (find_run(state.kernel_next_page, state.total_pages, count)) |run_start| {
            if (!range_is_free(run_start, count)) return null; // safety guard
            mark_run_used(run_start, count);
            const end = run_start + count;
            if (end > state.kernel_ceiling_page) state.kernel_ceiling_page = end;
            if (end > state.kernel_next_page) state.kernel_next_page = end;
            return run_start * PAGE_SIZE;
        }
        return null;
    } else {
        // Reuse: prefer freed holes above the current downwards frontier.
        if (find_run_down(state.total_pages, state.user_next_page, count)) |low_page| {
            if (!range_is_free(low_page, count)) return null; // safety guard
            mark_run_used(low_page, count);
            // Do not move frontier upward; keep growing down overall.
            return low_page * PAGE_SIZE;
        }
        // Allocate below current frontier and move it down.
        if (find_run_down(state.user_next_page, state.user_floor_page, count)) |low_page| {
            if (!range_is_free(low_page, count)) return null; // safety guard
            mark_run_used(low_page, count);
            if (low_page < state.user_next_page) state.user_next_page = low_page;
            return low_page * PAGE_SIZE;
        }
        return null;
    }
}

pub fn free_frames(base_phys_addr: usize, count: usize) void {
    if (count == 0) return;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const addr = base_phys_addr + i * PAGE_SIZE;
        const idx = addr / PAGE_SIZE;
        if (idx < state.total_pages) clear_bit(idx);
    }
}

pub fn stats_total_pages() usize {
    return state.total_pages;
}

pub fn stats_kernel_ceiling_page() usize {
    return state.kernel_ceiling_page;
}

// Embedded-friendly self-tests (pure functions using synthetic state)
// Return true on success, false on first failure.
// pub fn selftest_kernel_reuse() bool {
//     var bmp: [80]u8 = undefined; // 80*8 = 640 pages max
//     @memset(bmp[0..], 0);
//     state.bitmap = &bmp;
//     state.bitmap_len = bmp.len;
//     state.total_pages = 600;
//     // Simulate low memory reserved and kernel region starting at 512 pages
//     mark_range_reserved(0, KERNEL_LMA);
//     state.kernel_ceiling_page = 520;
//     state.kernel_next_page = 520;
//     state.user_floor_page = state.kernel_ceiling_page;
//     state.user_next_page = state.total_pages;
//     // Ensure no holes below kernel_next by marking [512..520) used
//     mark_run_used(KERNEL_BASE_PAGE, state.kernel_next_page - KERNEL_BASE_PAGE);
//
//     const a = alloc_frames(3, true) orelse return false;
//     if (a != 520 * PAGE_SIZE) return false;
//
//     const b = alloc_frames(5, true) orelse return false;
//     if (b != 523 * PAGE_SIZE) return false;
//
//     free_frames(a, 3);
//     const c = alloc_frames(3, true) orelse return false;
//     if (c != a) return false;
//     return true;
// }
//
// pub fn selftest_user_down() bool {
//     var bmp: [80]u8 = undefined;
//     @memset(bmp[0..], 0);
//     state.bitmap = &bmp;
//     state.bitmap_len = bmp.len;
//     state.total_pages = 600;
//     mark_range_reserved(0, KERNEL_LMA);
//     state.kernel_ceiling_page = 520;
//     state.kernel_next_page = 520;
//     state.user_floor_page = 520;
//     state.user_next_page = 600;
//
//     const user1 = alloc_frames(4, false) orelse return false;
//     if (user1 != 596 * PAGE_SIZE) return false;
//     const user2 = alloc_frames(2, false) orelse return false;
//     if (user2 != 594 * PAGE_SIZE) return false;
//     free_frames(user1, 4);
//     const user3 = alloc_frames(4, false) orelse return false;
//     if (user3 != user1) return false;
//     return true;
// }
//
// pub fn selftest_all() bool {
//     return selftest_kernel_reuse() and selftest_user_down();
// }
