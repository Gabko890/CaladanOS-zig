.intel_syntax noprefix

.globl capture_regs
.type capture_regs, @function
capture_regs:
    // rdi = pointer to Regs
    // General-purpose registers
    mov     [rdi + 0x00], rax
    mov     [rdi + 0x08], rbx
    mov     [rdi + 0x10], rcx
    mov     [rdi + 0x18], rdx
    mov     [rdi + 0x20], rsi
    mov     [rdi + 0x28], rdi
    mov     [rdi + 0x30], rbp
    mov     [rdi + 0x38], rsp
    mov     [rdi + 0x40], r8
    mov     [rdi + 0x48], r9
    mov     [rdi + 0x50], r10
    mov     [rdi + 0x58], r11
    mov     [rdi + 0x60], r12
    mov     [rdi + 0x68], r13
    mov     [rdi + 0x70], r14
    mov     [rdi + 0x78], r15

    // RFLAGS
    pushfq
    pop     rax
    mov     [rdi + 0x80], rax

    // Control registers
    mov     rax, cr0
    mov     [rdi + 0x88], rax
    mov     rax, cr2
    mov     [rdi + 0x90], rax
    mov     rax, cr3
    mov     [rdi + 0x98], rax
    mov     rax, cr4
    mov     [rdi + 0xA0], rax
    mov     rax, cr8
    mov     [rdi + 0xA8], rax

    // Segment selectors (store as zero-extended 64-bit)
    mov     qword ptr [rdi + 0xB0], 0
    mov     qword ptr [rdi + 0xB8], 0
    mov     qword ptr [rdi + 0xC0], 0
    mov     qword ptr [rdi + 0xC8], 0
    mov     qword ptr [rdi + 0xD0], 0
    mov     qword ptr [rdi + 0xD8], 0
    mov     word ptr  [rdi + 0xB0], cs
    mov     word ptr  [rdi + 0xB8], ds
    mov     word ptr  [rdi + 0xC0], es
    mov     word ptr  [rdi + 0xC8], fs
    mov     word ptr  [rdi + 0xD0], gs
    mov     word ptr  [rdi + 0xD8], ss

    ret
