# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. All four are leaf functions: they touch no stack and call
# nothing. Tests: tests/tfixed.c.

    .text

# op1: a + b by the carry loop. Each pass is c = (a & b) << 1, a = a ^ b,
# b = c, and the loop ends when the carry word is zero. The loop is unrolled
# four times, so the pass counter is bumped once per four passes; a pass that
# ends the loop leaves through an exit that adds its position in the group.
    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    li      t1, 0                   # passes
    beqz    a1, .Lop1_store         # adding zero takes no pass
.Lop1_loop:
    and     t0, a0, a1
    xor     a0, a0, a1
    slli    a1, t0, 1
    beqz    a1, .Lop1_exit1
    and     t0, a0, a1
    xor     a0, a0, a1
    slli    a1, t0, 1
    beqz    a1, .Lop1_exit2
    and     t0, a0, a1
    xor     a0, a0, a1
    slli    a1, t0, 1
    beqz    a1, .Lop1_exit3
    and     t0, a0, a1
    xor     a0, a0, a1
    slli    a1, t0, 1
    addi    t1, t1, 4
    bnez    a1, .Lop1_loop
.Lop1_store:
    sw      t1, 0(a2)
    ret
.Lop1_exit3:
    addi    t1, t1, 3
    sw      t1, 0(a2)
    ret
.Lop1_exit2:
    addi    t1, t1, 2
    sw      t1, 0(a2)
    ret
.Lop1_exit1:
    addi    t1, t1, 1
    sw      t1, 0(a2)
    ret
    .size   op1_asm, .-op1_asm

# op2: a - b modulo 2^32, which is what sub computes.
    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub     a0, a0, a1
    ret
    .size   op2_asm, .-op2_asm

# op3: floor((a + b) / 2) = (a & b) + ((a ^ b) >> 1), with no 33-bit sum.
    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    and     t0, a0, a1
    xor     a0, a0, a1
    srli    a0, a0, 1
    add     a0, a0, t0
    ret
    .size   op3_asm, .-op3_asm

# q_mul: Q11.20 product, round half up, low 32 bits kept.
#
# The product is formed from the magnitudes and negated at the end when the
# signs differ, so a small negative operand costs as little as a small
# positive one. The smaller magnitude is the multiplier. The multiplicand is
# split into 16-bit halves xl and xh, and one shift-and-add loop per 16-bit
# half of the multiplier forms two partial products at once, each of which
# fits 32 bits; the loop ends as soon as that half has no bits left.
#
#   loop 1 (multiplier yl): t1 = xl * yl, t2 = xh * yl
#   loop 2 (multiplier yh): t5 = xl * yh, t6 = xh * yh
#   P = t1 + (t2 << 16) + (t5 << 16) + (t6 << 32), in t6:t1
#
# Rounding: (P + 2^19) >> 20 = (P >> 20) + bit 19 of P, and bits 20 to 51 of P
# are (lo >> 20) | (hi << 12).
    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    xor     a7, a0, a1              # bit 31: the sign of the product
    srai    t0, a0, 31              # |a| = (a ^ s) - s
    xor     a0, a0, t0
    sub     a0, a0, t0
    srai    t0, a1, 31              # |b|
    xor     a1, a1, t0
    sub     a1, a1, t0
    bgeu    a0, a1, 1f              # a1 becomes the smaller magnitude
    xor     a0, a0, a1
    xor     a1, a0, a1
    xor     a0, a0, a1
1:  srli    a3, a0, 16              # xh
    slli    a2, a0, 16
    srli    a2, a2, 16              # xl

    slli    a4, a1, 16
    srli    a4, a4, 16              # yl
    li      t1, 0
    li      t2, 0
    beqz    a4, 3f
    mv      t3, a2
    mv      t4, a3
2:  andi    t0, a4, 1
    beqz    t0, 4f
    add     t1, t1, t3
    add     t2, t2, t4
4:  slli    t3, t3, 1
    slli    t4, t4, 1
    srli    a4, a4, 1
    bnez    a4, 2b

3:  srli    a4, a1, 16              # yh
    li      t5, 0
    li      t6, 0
    beqz    a4, 6f
5:  andi    t0, a4, 1
    beqz    t0, 7f
    add     t5, t5, a2
    add     t6, t6, a3
7:  slli    a2, a2, 1
    slli    a3, a3, 1
    srli    a4, a4, 1
    bnez    a4, 5b

6:  slli    t0, t2, 16              # lo = t1 + (t2 << 16) + (t5 << 16)
    add     t1, t1, t0
    sltu    a5, t1, t0
    slli    t0, t5, 16
    add     t1, t1, t0
    sltu    t0, t1, t0
    add     a5, a5, t0              # carries into the high word
    srli    t0, t2, 16              # hi = t6 + (t2 >> 16) + (t5 >> 16) + carries
    add     t6, t6, t0
    srli    t0, t5, 16
    add     t6, t6, t0
    add     t6, t6, a5

    bgez    a7, 8f                  # signs differ: negate t6:t1
    seqz    t0, t1
    not     t6, t6
    add     t6, t6, t0
    neg     t1, t1
8:  srli    a0, t1, 20
    slli    t6, t6, 12
    or      a0, a0, t6
    srli    t1, t1, 19
    andi    t1, t1, 1
    add     a0, a0, t1
    ret
    .size   q_mul_asm, .-q_mul_asm
