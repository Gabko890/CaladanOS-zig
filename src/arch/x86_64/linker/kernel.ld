OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

/*
   Link the 64-bit kernel in the higher half while keeping it loaded
   at low physical memory. The 32-bit bootstrap and its data live in
   dedicated .boot.* sections mapped low and identity-mapped.
*/

KERNEL_VMA = 0xFFFFFFFF80000000;   /* higher-half base */
KERNEL_LMA = 2M;                   /* physical load base */

PHDRS {
    headers PT_PHDR PHDRS ;
    boottext PT_LOAD FILEHDR PHDRS FLAGS(4 | 1);  /* R | X */
    bootdata PT_LOAD               FLAGS(4 | 2);  /* R | W */
    ktext   PT_LOAD               FLAGS(4 | 1);   /* R | X */
    krodata PT_LOAD               FLAGS(4);       /* R */
    kdata   PT_LOAD               FLAGS(4 | 2);   /* R | W */
    note    PT_NOTE;
}

SECTIONS {
    /* Multiboot2 header must reside within the first 32KiB of the file. */
    . = 0;
    .multiboot : ALIGN(8) :boottext {
        KEEP(*(.multiboot))
    }

    /* Low bootstrap (32-bit + tiny 64-bit stub) */
    . = 1M; /* keep early code outside header area */
    __boot_start = .;
    .boot.text : ALIGN(4K) :boottext {
        *(.boot.text*)
    }
    .boot.rodata : ALIGN(4K) :bootdata {
        /* Export physical and size constants as concrete 32-bit values */
        PROVIDE(__kphys_start_ptr = .); LONG(LOADADDR(.text));
        PROVIDE(__kphys_end_ptr   = .); LONG(LOADADDR(.bss) + SIZEOF(.bss));
        PROVIDE(__kimg_size_ptr   = .); LONG(__kernel_virt_end - __kernel_virt_start);
        /* Offset of entry (kmain) within the kernel image (relative to __kernel_virt_start).
           This remains 32-bit as long as the image is < 4GiB. */
        PROVIDE(__kkmain_off_ptr  = .); LONG(kmain - __kernel_virt_start);
        *(.boot.rodata*)
    }
    .boot.data : ALIGN(4K) :bootdata {
        *(.boot.data*)
    }
    .boot.bss : ALIGN(4K) :bootdata {
        *(COMMON)
        *(.boot.bss*)
    }
    __boot_end = .;


    /*
      Higher-half kernel proper. VMA is KERNEL_VMA while LMA stays
      contiguous starting at KERNEL_LMA. We export both physical and
      virtual bounds to size page tables in the bootstrap.
    */
    . = KERNEL_VMA;

    PROVIDE(__kernel_virt_start = .);

    .text : ALIGN(4K) :ktext AT(KERNEL_LMA + (ADDR(.text) - KERNEL_VMA)) {
        __kernel_text_start = .;
        *(.text)
        __kernel_text_end = .;
    }

    .rodata : ALIGN(4K) :krodata AT(KERNEL_LMA + (ADDR(.rodata) - KERNEL_VMA)) {
        *(.rodata*)
    }

    .data : ALIGN(4K) :kdata AT(KERNEL_LMA + (ADDR(.data) - KERNEL_VMA)) {
        *(.data*)
        *(.got*)
    }

    .bss : ALIGN(4K) :kdata AT(KERNEL_LMA + (ADDR(.bss) - KERNEL_VMA)) {
        *(COMMON)
        *(.bss*)
    }

    PROVIDE(__kernel_virt_end = .);

    /* Physical bounds: derive from LMA of .text and end of .bss */
    __kernel_phys_start = LOADADDR(.text);
    __kernel_phys_end   = LOADADDR(.bss) + SIZEOF(.bss);
    /* Also expose them via PROVIDE to ensure they are visible to the linker */
    PROVIDE(__kernel_phys_start_sym = LOADADDR(.text));
    PROVIDE(__kernel_phys_end_sym   = LOADADDR(.bss) + SIZEOF(.bss));
    /* Simplified aliases without leading underscores for some toolchains */
    PROVIDE(kphys_start = LOADADDR(.text));
    PROVIDE(kphys_end   = LOADADDR(.bss) + SIZEOF(.bss));

    /* Also expose them as absolute symbols for 32-bit bootstrap */
    PROVIDE(__kphys_start_value = LOADADDR(.text));
    PROVIDE(__kphys_end_value   = LOADADDR(.bss) + SIZEOF(.bss));
    PROVIDE(__kernel_image_size = __kernel_virt_end - __kernel_virt_start);

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

PROVIDE(__kernel_virt_base = KERNEL_VMA);
