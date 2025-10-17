ENTRY(_start)

SECTIONS {
    /* Put Multiboot2 header at the very start of the file (<32KiB). */
    . = 0;
    .multiboot : ALIGN(8) {
        KEEP(*(.multiboot))
    }

    /* Kernel proper linked at 2 MiB. */
    . = 2M;
    .text : ALIGN(4K) {
        __kernel_text_start = .;
        *(.text)
        __kernel_text_end = .;
    }

    .rodata : ALIGN(4K) {
        *(.rodata*)
    }

    .data : ALIGN(4K) {
        *(.data*)
        *(.got*)
    }

    .bss : ALIGN(4K) {
        *(COMMON)
        *(.bss*)
    }

    /* Ensure DWARF/debug sections come last so they do not push
       loadable sections forward in the file and hide the header. */
    .debug_abbrev     0 : { *(.debug_abbrev) }
    .debug_aranges    0 : { *(.debug_aranges) }
    .debug_info       0 : { *(.debug_info) }
    .debug_line       0 : { *(.debug_line) }
    .debug_line_str   0 : { *(.debug_line_str) }
    .debug_loc        0 : { *(.debug_loc) }
    .debug_loclists   0 : { *(.debug_loclists) }
    .debug_macinfo    0 : { *(.debug_macinfo) }
    .debug_macro      0 : { *(.debug_macro) }
    .debug_pubnames   0 : { *(.debug_pubnames) }
    .debug_pubtypes   0 : { *(.debug_pubtypes) }
    .debug_ranges     0 : { *(.debug_ranges) }
    .debug_rnglists   0 : { *(.debug_rnglists) }
    .debug_str        0 : { *(.debug_str) }
    .debug_frame      0 : { *(.debug_frame) }
    .eh_frame_hdr     0 : { *(.eh_frame_hdr) }
    .eh_frame         0 : { *(.eh_frame) }
}

/* Absolute symbols exported for stack scanning are defined within .text */
