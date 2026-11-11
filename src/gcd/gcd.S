# gcd_u32_asm: binary GCD implemented in RV32I assembly.
#
# uint32_t gcd_u32_asm(uint32_t a, uint32_t b)
# Arguments: a0 = a, a1 = b. Return value: a0 = gcd(a, b).
#
# Uses only RV32I and Zicsr; no multiply, divide, remainder, floating-point,
# or compressed instructions. Tests are in tests/tgcd.c.
#
# Register usage: a0 and a1 hold the current operands, t2 holds the exponent
# k of their shared factor 2^k, and t0 and t1 are scratch registers.
# Remove the shared factor first and restore it when returning the result.
# Two versions of the loop exchange operand roles through control flow,
# avoiding register moves:
#   Loop A keeps a0 odd and removes factors of two from a1 before comparing.
#   Loop B keeps a1 odd and removes factors of two from a0 before comparing.
# Subtract the smaller odd operand from the larger. A zero difference ends
# the loop; the remaining odd operand, shifted left by k, is the GCD.

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2
gcd_u32_asm:
    beqz    a0, .Lret_b             # Return b if a is zero
    beqz    a1, .Lret               # Return a if b is zero
    or      t0, a0, a1
    andi    t1, t0, 1
    li      t2, 0
    beqz    t1, .Lshared            # Both even: find the shared power of two
.Lstart:
    andi    t1, a0, 1
    bnez    t1, .LA_check           # a is odd: process b in loop A
    j       .LB_strip               # a is even and b is odd: process a in loop B

# Loop A: keep a0 odd and shift a1 right until it is odd.
.LB_swap:                           # Enter from loop B: a0 < a1, both odd
    sub     a1, a1, a0              # Nonzero even difference; keep a0 odd
.LA_strip:
    srli    a1, a1, 1
.LA_check:
    andi    t1, a1, 1
    beqz    t1, .LA_strip
    bltu    a1, a0, .LA_swap
    sub     a1, a1, a0              # Even difference; zero means the operands match
    bnez    a1, .LA_strip
    sll     a0, a0, t2              # Restore the shared factor 2^k
    ret

# Loop B: keep a1 odd and shift a0 right until it is odd.
.LA_swap:                           # Enter from loop A: a1 < a0, both odd
    sub     a0, a0, a1              # Nonzero even difference; keep a1 odd
.LB_strip:
    srli    a0, a0, 1
.LB_check:
    andi    t1, a0, 1
    beqz    t1, .LB_strip
    bltu    a0, a1, .LB_swap
    sub     a0, a0, a1
    bnez    a0, .LB_strip
    sll     a0, a1, t2
    ret

# Both operands are even. Count the trailing zero bits of a | b using
# checks of 16, 8, 4, 2, and 1 bits, then shift both operands right by k.
.Lshared:
    slli    t1, t0, 16
    bnez    t1, 1f
    addi    t2, t2, 16
    srli    t0, t0, 16
1:  andi    t1, t0, 0xff
    bnez    t1, 2f
    addi    t2, t2, 8
    srli    t0, t0, 8
2:  andi    t1, t0, 0xf
    bnez    t1, 3f
    addi    t2, t2, 4
    srli    t0, t0, 4
3:  andi    t1, t0, 3
    bnez    t1, 4f
    addi    t2, t2, 2
    srli    t0, t0, 2
4:  andi    t1, t0, 1
    bnez    t1, 5f
    addi    t2, t2, 1
5:  srl     a0, a0, t2
    srl     a1, a1, t2
    j       .Lstart

.Lret_b:
    mv      a0, a1
.Lret:
    ret
    .size   gcd_u32_asm, .-gcd_u32_asm
