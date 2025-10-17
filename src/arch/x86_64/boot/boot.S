.intel_syntax noprefix

// Multiboot2 header
.section .multiboot, "a", @progbits
.balign 8
multiboot_header:
    .set MB2_MAGIC,   0xE85250D6
    .set MB2_LENGTH,  64
    // checksum = -(magic + length)
    .long MB2_MAGIC
    .long 0
    .long MB2_LENGTH
    .long 0x17ADAEEA
    // info request (framebuffer)
    .long 0x00000001
    .long 0x0000000c
    .long 0x00000008
    .long 0x00000000
    // framebuffer tag: 1024x768x32
    .long 0x00000005
    .long 0x00000014
    .long 0x00000400
    .long 0x00000300
    .long 0x00000020         // depth = 32 bpp
    .long 0x00000000         // pad to 8-byte alignment
    // end tag
    .long 0x00000000
    .long 0x00000008

.section .bss, "aw", @nobits
.balign 16
boot_stack:
    .skip 16 * 1024

.balign 8
mb_magic:
    .long 0
.balign 8
mb_info:
    .quad 0

.balign 4096
pml4:
    .skip 4096
.balign 4096
pdpt:
    .skip 4096
.balign 4096
pd0:
    .skip 4096
.balign 4096
pd1:
    .skip 4096
.balign 4096
pd2:
    .skip 4096
.balign 4096
pd3:
    .skip 4096

.section .data, "aw", @progbits
.balign 8
gdt64:
    .quad 0x0000000000000000                // null
    .quad 0x00A09A0000000000                // code64: base=0, limit=0, G=1, L=1
    .quad 0x00A0920000000000                // data64: base=0, limit=0, G=1
gdt64_end:

.balign 1
gdt32_ptr:
    .word gdt64_end - gdt64 - 1
    .long gdt64

.section .text, "ax", @progbits
.globl _start
.type _start, @function
.code32
_start:
    cli

    // Setup temporary 32-bit stack
    mov     esp, OFFSET boot_stack + (16 * 1024)

    // Save Multiboot2 parameters
    mov     [mb_magic], eax
    mov     [mb_info], ebx

    // Load GDT
    lgdt    [gdt32_ptr]

    // Load data segments
    mov     ax, 0x10        // selector index 2 (data64)
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    mov     fs, ax
    mov     gs, ax

    // Identity-map 0..4 GiB using 2 MiB pages
    // PML4[0] = pdpt | flags
    mov     eax, OFFSET pdpt
    or      eax, 0x3
    mov     [pml4], eax
    mov     dword ptr [pml4 + 4], 0

    // PDPT entries -> 4 PDs
    mov     edi, OFFSET pdpt
    mov     eax, OFFSET pd0
    or      eax, 0x3
    mov     [edi + 0*8], eax
    mov     dword ptr [edi + 0*8 + 4], 0
    mov     eax, OFFSET pd1
    or      eax, 0x3
    mov     [edi + 1*8], eax
    mov     dword ptr [edi + 1*8 + 4], 0
    mov     eax, OFFSET pd2
    or      eax, 0x3
    mov     [edi + 2*8], eax
    mov     dword ptr [edi + 2*8 + 4], 0
    mov     eax, OFFSET pd3
    or      eax, 0x3
    mov     [edi + 3*8], eax
    mov     dword ptr [edi + 3*8 + 4], 0

    // Fill PD0..PD3 (2 MiB pages, present|write|PS)
    mov     edx, 0x83

    // PD0: base 0x00000000
    mov     edi, OFFSET pd0
    xor     ebx, ebx            // base
    mov     ecx, 512
.pd0_loop:
    mov     eax, ebx
    or      eax, edx
    mov     [edi], eax
    mov     dword ptr [edi + 4], 0
    add     ebx, 0x200000       // 2MiB
    add     edi, 8
    loop    .pd0_loop

    // PD1: base 0x40000000 (1 GiB)
    mov     edi, OFFSET pd1
    mov     ebx, 0x40000000
    mov     ecx, 512
.pd1_loop:
    mov     eax, ebx
    or      eax, edx
    mov     [edi], eax
    mov     dword ptr [edi + 4], 0
    add     ebx, 0x200000
    add     edi, 8
    loop    .pd1_loop

    // PD2: base 0x80000000 (2 GiB)
    mov     edi, OFFSET pd2
    mov     ebx, 0x80000000
    mov     ecx, 512
.pd2_loop:
    mov     eax, ebx
    or      eax, edx
    mov     [edi], eax
    mov     dword ptr [edi + 4], 0
    add     ebx, 0x200000
    add     edi, 8
    loop    .pd2_loop

    // PD3: base 0xC0000000 (3 GiB)
    mov     edi, OFFSET pd3
    mov     ebx, 0xC0000000
    mov     ecx, 512
.pd3_loop:
    mov     eax, ebx
    or      eax, edx
    mov     [edi], eax
    mov     dword ptr [edi + 4], 0
    add     ebx, 0x200000
    add     edi, 8
    loop    .pd3_loop

    // Enable PAE
    mov     eax, cr4
    or      eax, (1 << 5)       // PAE
    mov     cr4, eax

    // Load PML4 into CR3
    mov     eax, OFFSET pml4
    mov     cr3, eax

    // Enable long mode (EFER.LME)
    mov     ecx, 0xC0000080
    rdmsr
    or      eax, (1 << 8)
    wrmsr

    // Enable paging (CR0.PG)
    mov     eax, cr0
    or      eax, (1 << 31)
    mov     cr0, eax

    // Far jump to 64-bit code segment
    ljmp    [long_mode_ptr]

.code64
long_mode_entry:
    // Load 64-bit data segments
    mov     ax, 0x10            // data64 selector
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    mov     fs, ax
    mov     gs, ax

    // Initialize stack (16-byte aligned)
    lea     rsp, [boot_stack + (16 * 1024)]
    and     rsp, -16
    sub     rsp, 8

    // Pass Multiboot2 params: rdi=magic, rsi=info
    mov     edi, dword ptr [mb_magic]
    mov     rsi, qword ptr [mb_info]

    // Enter kernel
    .extern kmain
    call    kmain

.hang:
    cli
    hlt
    jmp     .hang

.size _start, . - _start

.section .rodata, "a", @progbits
.balign 4
long_mode_ptr:
    .long   long_mode_entry
    .word   0x0008             // code64 selector
