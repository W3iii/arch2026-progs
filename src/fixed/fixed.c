#include "fixed.h"

/* a + b from logic alone: a ^ b is the sum without carries and (a & b) << 1
 * the carries, so each pass moves the carries one place left. A carry chain
 * can only grow by one bit per pass, so the loop ends after at most 32.
 */
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    int passes = 0;
    while (b) {
        uint32_t c = (a & b) << 1;
        a ^= b;
        b = c;
        passes++;
    }
    *n = passes;
    return a;
}

/* a - b modulo 2^32: the bitwise model a + ~b + 1 is exactly what the
 * subtraction instruction does, so the plain subtraction is used.
 */
uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

/* floor((a + b) / 2) without the 33-bit sum: a + b = 2 (a & b) + (a ^ b),
 * so halving gives (a & b) + ((a ^ b) >> 1), which cannot overflow.
 */
uint32_t op3(uint32_t a, uint32_t b)
{
    return (a & b) + ((a ^ b) >> 1);
}

/* Q11.20 product. The 64-bit product is assembled from four 16-bit by 16-bit
 * partial products, so no 64-bit multiply (__muldi3) is needed. The unsigned
 * product of the two bit patterns is corrected to the signed one by
 * subtracting b from the high word when a is negative and a when b is
 * negative. Bits 20 to 51 of the product are its arithmetic shift by 20
 * truncated to 32 bits, and adding 2^19 before the shift carries into bit 20
 * exactly when bit 19 is set, so the rounding adds bit 19 after the shift.
 */
int32_t q_mul(int32_t a, int32_t b)
{
    uint32_t ua = (uint32_t) a, ub = (uint32_t) b;
    uint32_t al = ua & 0xFFFFu, ah = ua >> 16;
    uint32_t bl = ub & 0xFFFFu, bh = ub >> 16;

    uint32_t ll = al * bl, lh = al * bh, hl = ah * bl, hh = ah * bh;
    uint32_t mid = (ll >> 16) + (lh & 0xFFFFu) + (hl & 0xFFFFu);
    uint32_t lo = (mid << 16) | (ll & 0xFFFFu);
    uint32_t hi = hh + (lh >> 16) + (hl >> 16) + (mid >> 16);

    if (a < 0)
        hi -= ub;
    if (b < 0)
        hi -= ua;

    uint32_t half = (lo >> (Q - 1)) & 1u; /* round half up */
    return (int32_t) (((lo >> Q) | (hi << (32 - Q))) + half);
}
