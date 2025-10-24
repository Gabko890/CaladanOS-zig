const console = @import("console");
const mb2 = @import("arch_boot");

// Initialize the console based on Multiboot2 framebuffer tag if present.
// Falls back to legacy VGA text mode when no framebuffer information is provided.
pub fn initialize_from_multiboot(info_addr: usize) void {
    if (mb2.locate_framebuffer(info_addr)) |fb| {
        switch (fb.kind) {
            .text => {
                if (fb.text_buffer) |text_ptr| {
                    console.initialize_text(text_ptr, fb.width, fb.height);
                } else {
                    console.initialize_legacy();
                }
            },
            else => {
                if (fb.address) |addr| {
                    console.initialize_framebuffer(addr, fb.pitch, fb.width, fb.height, fb.bpp);
                } else {
                    console.initialize_legacy();
                }
            },
        }
    } else {
        console.initialize_legacy();
    }
}
