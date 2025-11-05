.section .bss.kernel_end, "aw", @nobits
.globl __kernel_end_sentinel
.type __kernel_end_sentinel, @object
.align 1
__kernel_end_sentinel:
    .zero 0
