const console = @import("console");
const mb2 = @import("arch_boot");

// Initialize the console based on Multiboot2 framebuffer tag if present.
// Falls back to legacy VGA text mode when no framebuffer information is provided.
pub fn initializeFromMultiboot(info_addr: usize) void {
    if (mb2.locateFramebuffer(info_addr)) |fb| {
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
}
