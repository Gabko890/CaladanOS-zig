// Runtime-populated values (written by boot.S long_mode_entry)
// Hardcoded bounds matching linker script start and a conservative image size.
// Start addresses must match src/arch/x86_64/linker/kernel.ld.
pub const KERNEL_VMA: usize = 0xFFFFFFFF80000000; // higher-half base (kernel.ld)
pub const KERNEL_LMA: usize = 2 * 1024 * 1024;   // physical load base 2MiB (kernel.ld)

// Reserve a reasonable image size for now and future growth.
// Keep in sync with PMM default (DEFAULT_KERNEL_RESERVE = 16 MiB).
pub const KERNEL_IMAGE_RESERVE: usize = 16 * 1024 * 1024;

pub inline fn kphys_start() usize {
    return KERNEL_LMA;
}
pub inline fn kphys_end() usize {
    return KERNEL_LMA + KERNEL_IMAGE_RESERVE;
}

pub inline fn kvirt_start() usize {
    return KERNEL_VMA;
}
pub inline fn kvirt_end() usize {
    return KERNEL_VMA + KERNEL_IMAGE_RESERVE;
}
