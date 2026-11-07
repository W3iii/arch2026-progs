#include "gcd.h"

/* Count trailing zeros of a nonzero value by binary search. RV32I has no ctz
 * instruction, and __builtin_ctz would call __ctzsi2 from libgcc, which this
 * environment does not link.
 */
static unsigned ctz32(uint32_t x)
{
    unsigned n = 0;
    if (!(x & 0xFFFFu)) {
        n += 16;
        x >>= 16;
    }
    if (!(x & 0xFFu)) {
        n += 8;
        x >>= 8;
    }
    if (!(x & 0xFu)) {
        n += 4;
        x >>= 4;
    }
    if (!(x & 0x3u)) {
        n += 2;
        x >>= 2;
    }
    if (!(x & 0x1u))
        n += 1;
    return n;
}

/* Binary GCD (Stein): gcd(2u, 2v) = 2 gcd(u, v); gcd(2u, v) = gcd(u, v) for
 * odd v; gcd(u, v) = gcd(u, v - u) for odd u <= v. Each pass removes at least
 * one bit from the larger operand, so the loop runs at most about 64 times.
 */
uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (a == 0)
        return b;
    if (b == 0)
        return a;

    unsigned shift = ctz32(a | b); /* common factors of two */
    a >>= ctz32(a);                /* a is odd from here on */
    do {
        b >>= ctz32(b); /* b is nonzero here, make it odd */
        if (a > b) {
            uint32_t t = a;
            a = b;
            b = t;
        }
        b -= a; /* odd - odd: even, possibly zero */
    } while (b != 0);
    return a << shift;
}