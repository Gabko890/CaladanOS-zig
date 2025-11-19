const std = @import("std");
const pma = @import("pma.zig");
const syms = @import("ld_syms");

// Simple kernel-space VMA tracker and paging helpers (2MiB pages).

pub const PAGE_SIZE_4K: usize = 4096;
pub const PAGE_SIZE_2M: usize = 2 * 1024 * 1024;
pub const ENTRIES_PER_TABLE: usize = 512;

const PTE_P: u64 = 1 << 0; // present
const PTE_W: u64 = 1 << 1; // write
const PTE_U: u64 = 1 << 2; // user
const PTE_PS: u64 = 1 << 7; // page size (in PDE)
const PDE_2M_ADDR_MASK: u64 = 0x000FFFFFFFE00000; // phys addr bits for 2MiB PDE
const GIB: usize = 1024 * 1024 * 1024;

// Virtual address interval
pub const Vma = struct {
    start: usize,
    len: usize,
};

// Static VMA registry
const MaxVmas = 128;
var vmas: [MaxVmas]Vma = undefined;
var vma_count: usize = 0;

inline fn align_down(value: usize, alignment: usize) usize {
    return value & ~(@as(usize, alignment - 1));
}
inline fn align_up(value: usize, alignment: usize) usize {
    return (value + alignment - 1) & ~(@as(usize, alignment - 1));
}

fn add_vma(start: usize, len: usize) void {
    if (len == 0 or vma_count >= MaxVmas) return;
    vmas[vma_count] = .{ .start = start, .len = len };
    vma_count += 1;
}

pub fn reserve_kernel_image() void {
    const kstart = syms.kvirt_start();
    const kend = syms.kvirt_end();
    add_vma(kstart, kend - kstart);
}

// Read current CR3 (physical addr of PML4)
fn read_cr3() usize {
    var value: usize = 0;
    asm volatile ("mov %%cr3, %[v]" : [v] "=r" (value) :: .{ .memory = true });
    return value & ~@as(usize, 0xFFF);
}

fn write_cr3(value: usize) void {
    const aligned = value & ~@as(usize, 0xFFF);
    asm volatile ("mov %[v], %%cr3" :: [v] "r" (aligned) : .{ .memory = true });
}

fn invlpg(addr: usize) void {
    asm volatile (
        "mov %[a], %%rax\n"
        ++ "invlpg (%%rax)\n"
        :
        : [a] "r" (addr)
        : .{ .memory = true, .rax = true }
    );
}

const Table = [*]volatile u64;

inline fn pml4_index(virt: usize) usize { return (virt >> 39) & 0x1FF; }
inline fn pdpt_index(virt: usize) usize { return (virt >> 30) & 0x1FF; }
inline fn pd_index(virt: usize) usize { return (virt >> 21) & 0x1FF; }

inline fn entry_addr(e: u64) usize { return @as(usize, @intCast(e & 0x000FFFFF_FFFFF000)); }

fn table_from_phys(phys: usize) Table {
    // Identity map is in place for low memory; treat phys as virt
    return @as(Table, @ptrFromInt(phys));
}

fn detect_kernel_phys_base() usize {
    const sample = syms.kvirt_start();
    const cr3 = read_cr3();
    const pml4 = table_from_phys(cr3);
    const pml4e = pml4[pml4_index(sample)];
    const pdpt_phys = entry_addr(pml4e);
    const pdpt = table_from_phys(pdpt_phys);
    const pdpte = pdpt[pdpt_index(sample)];
    const pd_phys = entry_addr(pdpte);
    const pd = table_from_phys(pd_phys);
    const pde = pd[pd_index(sample)];
    // Assumes 2MiB mappings (PS)
    const pde_base_2m: usize = entry_addr(pde) & ~(@as(usize, PAGE_SIZE_2M - 1));
    const pdei = pd_index(sample);
    // Physical base for the whole 1GiB window = base of this PDE minus index*2MiB
    return pde_base_2m - (pdei * PAGE_SIZE_2M);
}

pub fn heap_vbase() usize {
    // Use the 1 GiB region above KERNEL_VMA (PDPT index 511)
    return syms.kvirt_start() + GIB;
}

pub fn map_2m_range(virt_start: usize, phys_start: usize, length: usize, rw: bool) void {
    const cr3 = read_cr3();
    const pml4 = table_from_phys(cr3);
    const flags: u64 = PTE_P | (if (rw) PTE_W else 0) | PTE_PS;
    var v = align_down(virt_start, PAGE_SIZE_2M);
    var p = align_down(phys_start, PAGE_SIZE_2M);
    const end = align_up(virt_start + length, PAGE_SIZE_2M);

    while (v < end) : (v += PAGE_SIZE_2M) {
        const l4 = pml4_index(v);
        const pdpt_phys = entry_addr(pml4[l4]);
        if (pdpt_phys == 0) @panic("PDPT missing for map_2m_range");
        const pdpt = table_from_phys(pdpt_phys);
        const l3 = pdpt_index(v);
        const pd_phys = entry_addr(pdpt[l3]);
        if (pd_phys == 0) @panic("PD missing for map_2m_range");
        const pd = table_from_phys(pd_phys);
        const l2 = pd_index(v);
        pd[l2] = (@as(u64, @intCast(p)) & PDE_2M_ADDR_MASK) | flags;
        invlpg(v);
        p += PAGE_SIZE_2M;
    }
}

pub fn map_2m_page(virt: usize, phys: usize, rw: bool) void {
    const cr3 = read_cr3();
    const pml4 = table_from_phys(cr3);
    const flags: u64 = PTE_P | (if (rw) PTE_W else 0) | PTE_PS;
    const v = align_down(virt, PAGE_SIZE_2M);
    const l4 = pml4_index(v);
    const pdpt_phys = entry_addr(pml4[l4]);
    if (pdpt_phys == 0) @panic("PDPT missing for map_2m_page");
    const pdpt = table_from_phys(pdpt_phys);
    const l3 = pdpt_index(v);
    const pd_phys = entry_addr(pdpt[l3]);
    if (pd_phys == 0) @panic("PD missing for map_2m_page");
    const pd = table_from_phys(pd_phys);
    const l2 = pd_index(v);
    pd[l2] = (@as(u64, @intCast(align_down(phys, PAGE_SIZE_2M))) & PDE_2M_ADDR_MASK) | flags;
    invlpg(v);
}

pub fn unmap_2m_range(virt_start: usize, length: usize) void {
    const cr3 = read_cr3();
    const pml4 = table_from_phys(cr3);
    var v = align_down(virt_start, PAGE_SIZE_2M);
    const end = align_up(virt_start + length, PAGE_SIZE_2M);

    while (v < end) : (v += PAGE_SIZE_2M) {
        const l4 = pml4_index(v);
        const pdpt_phys = entry_addr(pml4[l4]);
        if (pdpt_phys == 0) @panic("PDPT missing for unmap_2m_range");
        const pdpt = table_from_phys(pdpt_phys);
        const l3 = pdpt_index(v);
        const pd_phys = entry_addr(pdpt[l3]);
        if (pd_phys == 0) @panic("PD missing for unmap_2m_range");
        const pd = table_from_phys(pd_phys);
        const l2 = pd_index(v);
        pd[l2] = 0;
        invlpg(v);
    }
}

pub fn install_kernel_tables() void {
    // Allocate fresh paging structures
    const pml4_phys = pma.alloc_frames(1, pma.Frame_type.KERNEL) orelse @panic("no frames for pml4");
    const id_pdpt_phys = pma.alloc_frames(1, pma.Frame_type.KERNEL) orelse @panic("no frames for id pdpt");
    const id_pd0_phys = pma.alloc_frames(1, pma.Frame_type.KERNEL) orelse @panic("no frames for id pd0");
    const id_pd1_phys = pma.alloc_frames(1, pma.Frame_type.KERNEL) orelse @panic("no frames for id pd1");
    const id_pd2_phys = pma.alloc_frames(1, pma.Frame_type.KERNEL) orelse @panic("no frames for id pd2");
    const id_pd3_phys = pma.alloc_frames(1, pma.Frame_type.KERNEL) orelse @panic("no frames for id pd3");
    const k_pdpt_phys = pma.alloc_frames(1, pma.Frame_type.KERNEL) orelse @panic("no frames for k pdpt");
    const k_pd_phys = pma.alloc_frames(1, pma.Frame_type.KERNEL) orelse @panic("no frames for k pd");
    const heap_pd_phys = pma.alloc_frames(1, pma.Frame_type.KERNEL) orelse @panic("no frames for heap pd");

    const pml4 = table_from_phys(pml4_phys);
    const id_pdpt = table_from_phys(id_pdpt_phys);
    const id_pd0 = table_from_phys(id_pd0_phys);
    const id_pd1 = table_from_phys(id_pd1_phys);
    const id_pd2 = table_from_phys(id_pd2_phys);
    const id_pd3 = table_from_phys(id_pd3_phys);
    const k_pdpt = table_from_phys(k_pdpt_phys);
    const k_pd = table_from_phys(k_pd_phys);
    const heap_pd = table_from_phys(heap_pd_phys);

    // Zero all tables (volatile-safe)
    var zi: usize = 0;
    while (zi < ENTRIES_PER_TABLE) : (zi += 1) pml4[zi] = 0;
    zi = 0; while (zi < ENTRIES_PER_TABLE) : (zi += 1) id_pdpt[zi] = 0;
    zi = 0; while (zi < ENTRIES_PER_TABLE) : (zi += 1) id_pd0[zi] = 0;
    zi = 0; while (zi < ENTRIES_PER_TABLE) : (zi += 1) id_pd1[zi] = 0;
    zi = 0; while (zi < ENTRIES_PER_TABLE) : (zi += 1) id_pd2[zi] = 0;
    zi = 0; while (zi < ENTRIES_PER_TABLE) : (zi += 1) id_pd3[zi] = 0;
    zi = 0; while (zi < ENTRIES_PER_TABLE) : (zi += 1) k_pdpt[zi] = 0;
    zi = 0; while (zi < ENTRIES_PER_TABLE) : (zi += 1) k_pd[zi] = 0;
    zi = 0; while (zi < ENTRIES_PER_TABLE) : (zi += 1) heap_pd[zi] = 0;

    const pde_flags: u64 = PTE_P | PTE_W | PTE_PS;
    const pte_flags: u64 = PTE_P | PTE_W; // for pointers in upper levels

    // PML4 entries
    pml4[0] = (@as(u64, @intCast(id_pdpt_phys)) & 0x000FFFFF_FFFFF000) | pte_flags;
    pml4[511] = (@as(u64, @intCast(k_pdpt_phys)) & 0x000FFFFF_FFFFF000) | pte_flags;

    // Identity PDPT: map 0..4GiB via 2MiB PDEs
    id_pdpt[0] = (@as(u64, @intCast(id_pd0_phys)) & 0x000FFFFF_FFFFF000) | pte_flags;
    id_pdpt[1] = (@as(u64, @intCast(id_pd1_phys)) & 0x000FFFFF_FFFFF000) | pte_flags;
    id_pdpt[2] = (@as(u64, @intCast(id_pd2_phys)) & 0x000FFFFF_FFFFF000) | pte_flags;
    id_pdpt[3] = (@as(u64, @intCast(id_pd3_phys)) & 0x000FFFFF_FFFFF000) | pte_flags;

    var i: usize = 0;
    while (i < ENTRIES_PER_TABLE) : (i += 1) {
        id_pd0[i] = ((@as(u64, @intCast(i)) * PAGE_SIZE_2M) | pde_flags);
        id_pd1[i] = ((@as(u64, 0x40000000) + @as(u64, @intCast(i)) * PAGE_SIZE_2M) | pde_flags);
        id_pd2[i] = ((@as(u64, 0x80000000) + @as(u64, @intCast(i)) * PAGE_SIZE_2M) | pde_flags);
        id_pd3[i] = ((@as(u64, 0xC0000000) + @as(u64, @intCast(i)) * PAGE_SIZE_2M) | pde_flags);
    }

    // Kernel higher-half PDPT entry index 510
    k_pdpt[510] = (@as(u64, @intCast(k_pd_phys)) & 0x000FFFFF_FFFFF000) | pte_flags;
    // Heap region: PDPT entry index 511 (next 1 GiB window)
    k_pdpt[511] = (@as(u64, @intCast(heap_pd_phys)) & 0x000FFFFF_FFFFF000) | pte_flags;

    // Detect current kernel mapping physical base to keep execution seamless
    const k_phys_base = detect_kernel_phys_base();
    i = 0;
    while (i < ENTRIES_PER_TABLE) : (i += 1) {
        const phys: u64 = (@as(u64, @intCast(k_phys_base)) + @as(u64, @intCast(i)) * PAGE_SIZE_2M);
        k_pd[i] = (phys & PDE_2M_ADDR_MASK) | pde_flags;
    }

    // Switch to new tables: CR3 = pml4_phys
    write_cr3(pml4_phys);
}

pub fn init() void {
    // Start with reserving the kernel range in our VMA tracker.
    reserve_kernel_image();
}
