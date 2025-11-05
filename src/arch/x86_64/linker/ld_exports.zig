// Export linker-provided values for use in Zig.
// We compute them robustly using the known VMA/LMA mapping and a
// sentinel placed at the end of .bss by the linker/asm.

pub const KERNEL_VMA: usize = 0xFFFFFFFF80000000; // must match kernel.ld
pub const KERNEL_LMA: usize = 2 * 1024 * 1024; // must match kernel.ld

extern var __kernel_end_sentinel: u8; // placed last in .bss

pub inline fn kernel_virt_start() usize {
    return KERNEL_VMA;
}
pub inline fn kernel_virt_end() usize {
    return @intFromPtr(&__kernel_end_sentinel);
}
pub inline fn kernel_phys_start() usize {
    return KERNEL_LMA;
}
pub inline fn kernel_phys_end() usize {
    const vend_u: usize = kernel_virt_end();
    const vma_u: usize = KERNEL_VMA;
    const vend_s: isize = @bitCast(vend_u);
    const vma_s: isize = @bitCast(vma_u);
    const off_s: isize = vend_s - vma_s;
    if (off_s < 0) return KERNEL_LMA; // fallback safeguard
    return KERNEL_LMA + @as(usize, @intCast(off_s));
}

// Aliases matching names of PROVIDE() symbols in kernel.ld
pub inline fn __kernel_virt_start() usize {
    return kernel_virt_start();
}
pub inline fn __kernel_virt_end() usize {
    return kernel_virt_end();
}
pub inline fn __kernel_phys_start() usize {
    return kernel_phys_start();
}
pub inline fn __kernel_phys_end() usize {
    return kernel_phys_end();
}
pub inline fn kphys_start() usize {
    return kernel_phys_start();
}
pub inline fn kphys_end() usize {
    return kernel_phys_end();
}
pub inline fn __kphys_start_value() usize {
    return kernel_phys_start();
}
pub inline fn __kphys_end_value() usize {
    return kernel_phys_end();
}
pub inline fn __kernel_image_size() usize {
    return kernel_virt_end() - kernel_virt_start();
}
