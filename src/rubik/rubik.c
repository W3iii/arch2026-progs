#include "rubik.h"
#include "rubik_tables.h"

/* Optimal 2x2x2 solver, ported from Assignment 1 (W3iii/minirubik, rv32/ida.c).
 *
 * IDA* on three coordinates: p = permutation rank (0..5039), o = orientation
 * rank (0..728), r = rank of the positions of cubies 3 and 6 (0..41).
 * h = max(hperm[p], pdb[r << 10 | o]); both tables hold exact distances in an
 * abstraction of the cube, so h never overestimates and the first solution
 * is a shortest one. Both are 0 only at the solved state.
 * No recursion (explicit frame per depth), no multiply or divide in the search.
 */

enum { MAX_DEPTH = 11 };

static const uint16_t *const perm_face[3] = {perm_q, perm_q + NPERM,
                                             perm_q + 2 * NPERM};
static const uint16_t *const ori_face[3] = {ori_q, ori_q + NORI,
                                            ori_q + 2 * NORI};
static const uint8_t *const pair_face[3] = {pair_q, pair_q + NPAIR,
                                            pair_q + 2 * NPAIR};

/* Move m = 3 * face + turn - 1, names in the order of the contract. */
static const char move_char[3] = {'R', 'B', 'D'};
static const char turn_char[3] = {0, '2', '\''};

/* Returns 0 and the three coordinates, or -1 for an invalid state. Reads
 * the string only up to its terminator.
 */
static int parse(const char *s, uint32_t *pp, uint32_t *po, uint32_t *pr)
{
    uint8_t perm[7], ori[7];
    uint32_t sum = 0;

    for (int i = 0; i < RUBIK_STATE_LEN; i++) {
        if (!s[i])
            return -1; /* too short */
    }
    if (s[RUBIK_STATE_LEN])
        return -1; /* too long */
    for (int i = 0; i < 7; i++) {
        uint32_t c = (uint32_t) (s[i] - '1'), t = (uint32_t) (s[i + 7] - '1');
        if (c > 6 || t > 2)
            return -1;
        for (int j = 0; j < i; j++) {
            if (perm[j] == c)
                return -1; /* repeated cubie */
        }
        perm[i] = (uint8_t) c;
        ori[i] = (uint8_t) t;
        sum += t;
    }
    while (sum >= 3) /* sum % 3, sum <= 14 */
        sum -= 3;
    if (sum)
        return -1;

    uint32_t p = 0, o = 0, a = 0, b = 0;
    for (int i = 0; i < 7; i++) {
        uint32_t c = 0;
        for (int j = i + 1; j < 7; j++)
            c += perm[j] < perm[i];
        /* Lehmer rank: p = p * (7 - i) + c, the multiply by adding */
        uint32_t q = 0;
        for (int k = i; k < 7; k++)
            q += p;
        p = q + c;
        if (i < 6)
            o = (o << 1) + o + ori[i]; /* base 3 */
        if (perm[i] == 3)
            a = (uint32_t) i;
        if (perm[i] == 6)
            b = (uint32_t) i;
    }
    *pp = p;
    *po = o;
    *pr = (a << 2) + (a << 1) + b - (b > a); /* 6a + b - (b > a) */
    return 0;
}

/* IDA*: fills path with moves 0..8 and returns their number. */
static int search(uint32_t p0, uint32_t o0, uint32_t r0, uint8_t *path)
{
    uint32_t node_p[MAX_DEPTH], node_o[MAX_DEPTH], node_r[MAX_DEPTH];
    uint32_t child_p[MAX_DEPTH], child_o[MAX_DEPTH], child_r[MAX_DEPTH];
    uint8_t face[MAX_DEPTH], turn[MAX_DEPTH], last[MAX_DEPTH];
    uint32_t hp0 = hperm[p0], hd0 = pdb[(r0 << 10) + o0];
    uint32_t bound = hp0 > hd0 ? hp0 : hd0;

    if (bound == 0)
        return 0;
    for (;;) {
        int d = 0;
        node_p[0] = child_p[0] = p0;
        node_o[0] = child_o[0] = o0;
        node_r[0] = child_r[0] = r0;
        face[0] = turn[0] = 0;
        last[0] = 3; /* no previous face */
        while (d >= 0) {
            if (turn[d] == 3) { /* three turns of this face done */
                face[d]++;
                turn[d] = 0;
                child_p[d] = node_p[d];
                child_o[d] = node_o[d];
                child_r[d] = node_r[d];
            }
            /* never turn the same face twice in a row */
            if (turn[d] == 0 && face[d] == last[d])
                face[d]++;
            if (face[d] >= 3) {
                d--;
                continue;
            }
            uint32_t f = face[d];
            child_p[d] = perm_face[f][child_p[d]];
            child_o[d] = ori_face[f][child_o[d]];
            child_r[d] = pair_face[f][child_r[d]];
            turn[d]++;

            /* hperm first: it alone prunes about half of the nodes */
            uint32_t g = (uint32_t) d + 1;
            uint32_t hp = hperm[child_p[d]];
            if (g + hp > bound)
                continue;
            uint32_t hd = pdb[(child_r[d] << 10) + child_o[d]];
            if (g + hd > bound)
                continue;
            path[d] = (uint8_t) ((f << 1) + f + turn[d] - 1);
            if ((hp | hd) == 0)
                return (int) g;
            d++; /* h >= 1 and g + h <= bound <= 11 keep d below 11 */
            node_p[d] = child_p[d] = child_p[d - 1];
            node_o[d] = child_o[d] = child_o[d - 1];
            node_r[d] = child_r[d] = child_r[d - 1];
            face[d] = turn[d] = 0;
            last[d] = (uint8_t) f;
        }
        bound++; /* costs are integers, so the next bound is bound + 1 */
    }
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    uint32_t p, o, r;
    uint8_t path[MAX_DEPTH];

    if (parse(state, &p, &o, &r))
        return -1;
    int n = search(p, o, r, path);

    /* text length with the NUL: each move is 1 or 2 characters, plus a space
     * after every move but the last
     */
    size_t need = 1;
    for (int k = 0; k < n; k++) {
        uint32_t t = path[k];
        while (t >= 3)
            t -= 3;
        need += (t ? 2 : 1) + (k ? 1 : 0);
    }
    if (need > cap) {
        if (cap)
            out[0] = '\0';
        return -2;
    }

    char *w = out;
    for (int k = 0; k < n; k++) {
        uint32_t f = 0, t = path[k];
        while (t >= 3) {
            t -= 3;
            f++;
        }
        if (k)
            *w++ = ' ';
        *w++ = move_char[f];
        if (t)
            *w++ = turn_char[t];
    }
    *w = '\0';
    return n;
}
