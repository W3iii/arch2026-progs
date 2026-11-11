# bf16_from_f32 / bf16_mul / bf16_sqrt (RV32I)
# args are uint16_t (already zero-extended), results zero-extended in a0
# leaf functions, no stack

    .text

# ---- bf16_from_f32(f32bits) ----
# exp == 0xFF: keep top half as is
# else: + 0x7FFF + bit16, keep top half  (round to nearest even)
    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    slli    t0, a0, 1               # drop sign
    lui     t1, 0xFF000
    bgeu    t0, t1, 1f              # exp == 0xFF
    srli    t0, a0, 16
    andi    t0, t0, 1               # bit16
    lui     t1, 0x8
    addi    t1, t1, -1              # 0x7FFF
    add     a0, a0, t1
    add     a0, a0, t0
1:  srli    a0, a0, 16
    ret
    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

# ---- bf16_mul(a, b) ----
# t0/t1 = exp_a/exp_b, a2/a3 = mant with hidden 1, t6 = sign (bit 15)
# a4 = mant product
    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:
    srli    t0, a0, 7
    andi    t0, t0, 0xFF            # exp_a
    srli    t1, a1, 7
    andi    t1, t1, 0xFF            # exp_b
    li      t5, 0xFF
    xor     t6, a0, a1
    srli    t6, t6, 15
    slli    t6, t6, 15              # sign
    beq     t0, t5, .Lmul_a_special
    beq     t1, t5, .Lmul_b_special
    slli    t2, a0, 17
    beqz    t2, .Lmul_zero          # a == +-0
    slli    t2, a1, 17
    beqz    t2, .Lmul_zero          # b == +-0

    andi    a2, a0, 0x7F
    beqz    t0, .Lmul_a_denormal
    ori     a2, a2, 0x80
.Lmul_a_ready:
    andi    a3, a1, 0x7F
    beqz    t1, .Lmul_b_denormal
    ori     a3, a3, 0x80
.Lmul_b_ready:
    add     t0, t0, t1
    addi    t0, t0, -127            # exp_a + exp_b - bias

    # 8x8 multiply, unrolled
    # a3 bit7 is always 1 -> start from a2 << 7, then bits 0..6
    slli    a4, a2, 7
    andi    t2, a3, 0x01
    beqz    t2, 1f
    add     a4, a4, a2
1:  andi    t2, a3, 0x02
    beqz    t2, 1f
    slli    t3, a2, 1
    add     a4, a4, t3
1:  andi    t2, a3, 0x04
    beqz    t2, 1f
    slli    t3, a2, 2
    add     a4, a4, t3
1:  andi    t2, a3, 0x08
    beqz    t2, 1f
    slli    t3, a2, 3
    add     a4, a4, t3
1:  andi    t2, a3, 0x10
    beqz    t2, 1f
    slli    t3, a2, 4
    add     a4, a4, t3
1:  andi    t2, a3, 0x20
    beqz    t2, 1f
    slli    t3, a2, 5
    add     a4, a4, t3
1:  andi    t2, a3, 0x40
    beqz    t2, 1f
    slli    t3, a2, 6
    add     a4, a4, t3
1:
    # product >= 2.0 (bit15): shift 8 and exp++, else shift 7
    # no branch: shift by 7 + bit15
    srli    t2, a4, 15
    add     t0, t0, t2
    addi    t2, t2, 7
    srl     a4, a4, t2
    andi    a4, a4, 0x7F            # truncate

    bge     t0, t5, .Lmul_inf
    blez    t0, .Lmul_small
    slli    t0, t0, 7
    or      a0, t6, t0
    or      a0, a0, a4
    ret

.Lmul_small:                        # exp <= 0
    li      t2, -6
    blt     t0, t2, .Lmul_zero      # too small -> 0
    li      t2, 1
    sub     t2, t2, t0
    srl     a4, a4, t2              # frac >>= (1 - exp)
    or      a0, t6, a4
    ret

.Lmul_a_denormal:                   # shift until bit7 is 1
    li      t0, 1
2:  slli    a2, a2, 1
    addi    t0, t0, -1
    andi    t2, a2, 0x80
    beqz    t2, 2b
    j       .Lmul_a_ready

.Lmul_b_denormal:
    li      t1, 1
2:  slli    a3, a3, 1
    addi    t1, t1, -1
    andi    t2, a3, 0x80
    beqz    t2, 2b
    j       .Lmul_b_ready

.Lmul_a_special:                    # a is Inf/NaN
    andi    t2, a0, 0x7F
    bnez    t2, .Lmul_ret           # NaN: return a
    slli    t2, a1, 17
    beqz    t2, .Lmul_nan           # Inf * 0
    j       .Lmul_inf

.Lmul_b_special:                    # b is Inf/NaN
    andi    t2, a1, 0x7F
    bnez    t2, .Lmul_ret_b         # NaN: return b
    slli    t2, a0, 17
    beqz    t2, .Lmul_nan           # 0 * Inf
.Lmul_inf:
    lui     a0, 0x8
    addi    a0, a0, -128            # 0x7F80
    or      a0, a0, t6
    ret
.Lmul_nan:
    lui     a0, 0x8
    addi    a0, a0, -64             # 0x7FC0
    ret
.Lmul_zero:
    mv      a0, t6
    ret
.Lmul_ret_b:
    mv      a0, a1
.Lmul_ret:
    ret
    .size   bf16_mul_asm, .-bf16_mul_asm

# ---- bf16_sqrt(a) ----
# C version: binary search for max r with r*r/128 <= m
# that r = isqrt(128*m + 127), so do digit-by-digit isqrt (no multiply)
# new exp = (E + 127) >> 1, m <<= 1 when E is even
# r is in [128, 255], no renormalize needed
    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
    srli    t0, a0, 7               # exp (sign at bit 8)
    addi    t1, t0, -1
    li      t2, 254
    bgeu    t1, t2, .Lsqrt_special  # not a positive normal

    andi    a1, a0, 0x7F
    ori     a1, a1, 0x80            # m
    andi    t1, t0, 1
    xori    t1, t1, 1
    sll     a1, a1, t1              # E even -> m <<= 1
    addi    t0, t0, 127
    srli    t0, t0, 1               # new exp
    slli    a1, a1, 7
    ori     a1, a1, 127             # N = 128*m + 127

    # isqrt(N), 8 steps:
    #   t = r + bit; r >>= 1; if (N >= t) { N -= t; r += bit; }
    # step 1 (bit 2^14): N >= 2^14 always
    lui     t2, 0x4
    sub     a1, a1, t2
    mv      a2, t2
    # step 2 (bit 2^12)
    lui     t3, 0x1
    add     t1, a2, t3
    srli    a2, a2, 1
    bltu    a1, t1, 1f
    sub     a1, a1, t1
    add     a2, a2, t3
1:  # steps 3-8 (bit 2^10 .. 2^0)
    addi    t1, a2, 1024
    srli    a2, a2, 1
    bltu    a1, t1, 1f
    sub     a1, a1, t1
    addi    a2, a2, 1024
1:  addi    t1, a2, 256
    srli    a2, a2, 1
    bltu    a1, t1, 1f
    sub     a1, a1, t1
    addi    a2, a2, 256
1:  addi    t1, a2, 64
    srli    a2, a2, 1
    bltu    a1, t1, 1f
    sub     a1, a1, t1
    addi    a2, a2, 64
1:  addi    t1, a2, 16
    srli    a2, a2, 1
    bltu    a1, t1, 1f
    sub     a1, a1, t1
    addi    a2, a2, 16
1:  addi    t1, a2, 4
    srli    a2, a2, 1
    bltu    a1, t1, 1f
    sub     a1, a1, t1
    addi    a2, a2, 4
1:  addi    t1, a2, 1
    srli    a2, a2, 1
    bltu    a1, t1, 1f
    addi    a2, a2, 1               # last step, N not needed
1:  andi    a2, a2, 0x7F
    slli    t0, t0, 7
    or      a0, t0, a2
    ret

.Lsqrt_special:
    beqz    t0, .Lsqrt_zero         # +0, +denormal -> 0
    li      t2, 0xFF
    beq     t0, t2, .Lsqrt_ret      # +Inf, +NaN unchanged
    slli    t1, a0, 17
    beqz    t1, .Lsqrt_zero         # -0 -> +0
    srli    t1, t1, 17              # |a|
    lui     t2, 0x8
    addi    t2, t2, -128            # 0x7F80
    bltu    t2, t1, .Lsqrt_ret      # -NaN unchanged
    addi    a0, t2, 64              # negative -> 0x7FC0
    ret
.Lsqrt_zero:
    li      a0, 0
.Lsqrt_ret:
    ret
    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
