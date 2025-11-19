.intel_syntax noprefix

// Writable 64-bit slots to hold kernel physical bounds.
// These are filled at runtime by the 64-bit bootstrap in boot.S.

.section .data, "aw", @progbits
.balign 8
.globl __kphys_start_value
.type __kphys_start_value, @object
__kphys_start_value:
    .quad 0
.size __kphys_start_value, 8

.balign 8
.globl __kphys_end_value
.type __kphys_end_value, @object
__kphys_end_value:
    .quad 0
.size __kphys_end_value, 8

// Writable 64-bit slots to hold kernel virtual bounds.
.balign 8
.globl __kvirt_start_value
.type __kvirt_start_value, @object
__kvirt_start_value:
    .quad 0
.size __kvirt_start_value, 8

.balign 8
.globl __kvirt_end_value
.type __kvirt_end_value, @object
__kvirt_end_value:
    .quad 0
.size __kvirt_end_value, 8
