.intel_syntax noprefix
.text
.globl idt_default_interrupt_handler
.type idt_default_interrupt_handler, @function
idt_default_interrupt_handler:
    // Save registers
    push    rax
    push    rcx
    push    rdx
    push    rbx
    push    rbp
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    push    r12
    push    r13
    push    r14
    push    r15
    // Send EOI to both PICs (master/slave)
    mov     al, 0x20
    mov     dx, 0x20
    out     dx, al
    mov     dx, 0xA0
    out     dx, al
    // Restore
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rbp
    pop     rbx
    pop     rdx
    pop     rcx
    pop     rax
    iretq

.globl idt_default_exception_noerror
.type idt_default_exception_noerror, @function
idt_default_exception_noerror:
    // Save registers
    push    rax
    push    rcx
    push    rdx
    push    rbx
    push    rbp
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    push    r12
    push    r13
    push    r14
    push    r15
    // Optional EOI (harmless for exceptions)
    mov     al, 0x20
    mov     dx, 0x20
    out     dx, al
    mov     dx, 0xA0
    out     dx, al
    // Restore
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rbp
    pop     rbx
    pop     rdx
    pop     rcx
    pop     rax
    iretq

.globl idt_default_exception_error
.type idt_default_exception_error, @function
idt_default_exception_error:
    // Save registers
    push    rax
    push    rcx
    push    rdx
    push    rbx
    push    rbp
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    push    r12
    push    r13
    push    r14
    push    r15
    // Optional EOI (harmless for exceptions)
    mov     al, 0x20
    mov     dx, 0x20
    out     dx, al
    mov     dx, 0xA0
    out     dx, al
    // Restore
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rbp
    pop     rbx
    pop     rdx
    pop     rcx
    pop     rax
    // Discard error code pushed by CPU
    add     rsp, 8
    iretq

.globl idt_lidt_load
.type idt_lidt_load, @function
// void idt_lidt_load(const struct { u16 limit; u64 base; } *ptr)
// rdi = pointer
idt_lidt_load:
    lidt    [rdi]
    ret
