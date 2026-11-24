# CPUlator rv32-de10-lite: load raw binary at 0x10000 and set PC to 0x10000.
# LEDR = 0x155 on success, 0x3FF on failure.
.equ LEDR, 0xFF200000
.globl _start
.text
_start:
    li sp, _stack_top
    la t0, values
    lw a0, (t0)
    lw a1, 4(t0)
    call multiply
    li t1, 42
    bne a0, t1, fail

    li t2, 0x12345FFF
    lw t3, 8(t0)
    bne t2, t3, fail

    la t4, scratch
    sw a0, (t4)
    lw t5, (t4)
    bne t5, a0, fail
    la t0, result
    sw a0, (t0)
    li a0, 0x155
    j show
fail:
    li a0, 0x3FF
show:
    li t0, LEDR
    sw a0, (t0)
halt:
    j halt

.data
values: .word 6, 7, 0x12345FFF
result: .word 0
message: .asciz "RV32IM test\n"

.bss
.align 2
scratch: .space 4

.text
multiply:
    mul a0, a0, a1
    ret
