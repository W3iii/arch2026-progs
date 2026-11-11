#include "bf16.h"

#define BF16_EXP_BIAS 127
#define BF16_NAN 0x7FC0u
#define BF16_INF 0x7F80u


uint16_t bf16_from_f32(uint32_t f32bits)
{
    if (((f32bits >> 23) & 0xFF) == 0xFF)
        return (uint16_t) (f32bits >> 16);
    f32bits += ((f32bits >> 16) & 1) + 0x7FFF;
    return (uint16_t) (f32bits >> 16);
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint32_t sign = (uint32_t) (a ^ b) & 0x8000u;
    int32_t exp_a = (a >> 7) & 0xFF, exp_b = (b >> 7) & 0xFF;
    uint32_t mant_a = a & 0x7F, mant_b = b & 0x7F;

    if (exp_a == 0xFF) {
        if (mant_a)
            return a;
        if (!exp_b && !mant_b)
            return BF16_NAN;
        return (uint16_t) (sign | BF16_INF);
    }
    if (exp_b == 0xFF) {
        if (mant_b)
            return b;
        if (!exp_a && !mant_a)
            return BF16_NAN;
        return (uint16_t) (sign | BF16_INF);
    }
    if ((!exp_a && !mant_a) || (!exp_b && !mant_b))
        return (uint16_t) sign;

    int32_t exp_adjust = 0;
    if (!exp_a) {
        while (!(mant_a & 0x80)) {
            mant_a <<= 1;
            exp_adjust--;
        }
        exp_a = 1;
    } else {
        mant_a |= 0x80;
    }
    if (!exp_b) {
        while (!(mant_b & 0x80)) {
            mant_b <<= 1;
            exp_adjust--;
        }
        exp_b = 1;
    } else {
        mant_b |= 0x80;
    }

    uint32_t result_mant = mant_a * mant_b;
    int32_t result_exp = exp_a + exp_b - BF16_EXP_BIAS + exp_adjust;
    if (result_mant & 0x8000) { /* ex. 1.5 x 1.5 = 2.25: mant / 2, exp + 1 */
        result_mant = (result_mant >> 8) & 0x7F;
        result_exp++;
    } else { /* ex. 1.5 x 1.25 = 1.875 */
        result_mant = (result_mant >> 7) & 0x7F;
    }

    if (result_exp >= 0xFF)
        return (uint16_t) (sign | BF16_INF);
    if (result_exp <= 0) {
        if (result_exp < -6)
            return (uint16_t) sign;
        result_mant >>= (1 - result_exp);
        result_exp = 0;
    }
    return (uint16_t) (sign | ((uint32_t) result_exp << 7) | result_mant);
}

uint16_t bf16_sqrt(uint16_t a)
{
    uint32_t sign = a >> 15;
    int32_t exp = (a >> 7) & 0xFF;
    uint32_t mant = a & 0x7F;

    if (exp == 0xFF) {
        if (mant)
            return a;
        return sign ? BF16_NAN : a;
    }
    if (!exp && !mant)
        return 0;
    if (sign)
        return BF16_NAN;
    if (!exp)
        return 0;

    int32_t e = exp - BF16_EXP_BIAS;
    int32_t new_exp;
    uint32_t m = 0x80 | mant;
    if (e & 1) {
        m <<= 1;
        new_exp = (e - 1) / 2 + BF16_EXP_BIAS;
    } else {
        new_exp = e / 2 + BF16_EXP_BIAS;
    }

    uint32_t low = 90, high = 256, result = 128;
    while (low <= high) {
        uint32_t mid = (low + high) >> 1;
        uint32_t sq = (mid * mid) / 128;
        if (sq <= m) {
            result = mid;
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }

    if (result >= 256) {
        result >>= 1;
        new_exp++;
    } else if (result < 128) {
        while (result < 128 && new_exp > 1) {
            result <<= 1;
            new_exp--;
        }
    }
    if (new_exp >= 0xFF)
        return BF16_INF;
    if (new_exp <= 0)
        return 0;
    return (uint16_t) (((uint32_t) new_exp << 7) | (result & 0x7F));
}
