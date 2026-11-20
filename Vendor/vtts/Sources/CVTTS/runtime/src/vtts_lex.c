/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_lex.c -- VLEX reader: front-coded CMUdict blocks and the pruned letter-to-sound table. */
#include "vtts_lex.h"

#include <string.h>

#define ID_EN0 65  /* token id of EN:AA, the first ARPAbet phoneme (set v2) */
#define ID_S0 104  /* S0, S1, S2 follow the 39 phonemes */
#define WORD_MAX 256

static uint16_t rd16(const uint8_t *p) { return (uint16_t)(p[0] | p[1] << 8); }
static uint32_t rd32(const uint8_t *p) { return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }

int vtts_lex_init(vtts_lex *lx, const uint8_t *blob, size_t size) {
    if (!lx || !blob || size < 32 || memcmp(blob, "VLEX", 4) != 0 || rd16(blob + 4) != 1) return -1;
    memset(lx, 0, sizeof *lx);
    lx->blob = blob;
    lx->size = size;
    lx->block = rd16(blob + 6);
    lx->n_words = rd32(blob + 8);
    lx->n_blocks = rd32(blob + 12);
    lx->lts_off = rd32(blob + 16);
    lx->lts_n = rd32(blob + 20);
    lx->lab_off = rd32(blob + 24);
    lx->n_labels = rd16(blob + 28);
    if (!lx->block || lx->n_labels > VTTS_LEX_MAX_LABELS || 32 + 4ull * lx->n_blocks > size ||
        lx->lts_off + 6ull * lx->lts_n > size || lx->lab_off > size)
        return -2;
    lx->blocks = blob + 32 + 4 * (size_t)lx->n_blocks;
    size_t p = lx->lab_off;
    for (int i = 0; i < lx->n_labels; i++) {
        if (p >= size || p + 1 + blob[p] > size) return -3;
        lx->lab[i] = (uint32_t)p;
        p += 1 + (size_t)blob[p];
    }
    return 0;
}

/* first word of block b into w (NUL terminated); returns pointer to its phone count byte */
static const uint8_t *block_first(const vtts_lex *lx, uint32_t b, char *w) {
    const uint8_t *p = lx->blocks + rd32(lx->blob + 32 + 4 * (size_t)b);
    int sl = p[1];
    memcpy(w, p + 2, (size_t)sl);
    w[sl] = 0;
    return p + 2 + sl;
}

static int unpack(const uint8_t *ph, int n, uint8_t *out, int cap) {
    int k = 0;
    for (int i = 0; i < n; i++) {
        if (k >= cap) return -1;
        out[k++] = (uint8_t)(ID_EN0 + ph[i] % 40);
        if (ph[i] >= 40) {
            if (k >= cap) return -1;
            out[k++] = (uint8_t)(ID_S0 + ph[i] / 40 - 1);
        }
    }
    return k;
}

int vtts_lex_lookup(const vtts_lex *lx, const char *word, uint8_t *out, int cap) {
    char w[WORD_MAX];
    if (!lx || !word || !lx->n_blocks || strlen(word) >= WORD_MAX) return 0;
    uint32_t lo = 0, hi = lx->n_blocks - 1;
    while (lo < hi) { /* last block whose first word <= word */
        uint32_t mid = (lo + hi + 1) / 2;
        block_first(lx, mid, w);
        if (strcmp(w, word) <= 0) lo = mid; else hi = mid - 1;
    }
    const uint8_t *p = lx->blocks + rd32(lx->blob + 32 + 4 * (size_t)lo);
    uint32_t n = lx->n_words - lo * lx->block < lx->block ? lx->n_words - lo * lx->block : lx->block;
    w[0] = 0;
    for (uint32_t i = 0; i < n; i++) {
        int pre = p[0], sl = p[1];
        if (pre + sl >= WORD_MAX) return 0;
        memcpy(w + pre, p + 2, (size_t)sl);
        w[pre + sl] = 0;
        p += 2 + sl;
        int nph = *p++;
        int c = strcmp(w, word);
        if (c == 0) return unpack(p, nph, out, cap);
        if (c > 0) return 0;
        p += nph;
    }
    return 0;
}

/* --- letter-to-sound: windows tried in this order (left, right letters), '#' pads the word */
static const uint8_t WIN[10][2] = {{3, 3}, {3, 2}, {2, 3}, {2, 2}, {2, 1}, {1, 2}, {1, 1}, {1, 0}, {0, 1}, {0, 0}};

static uint64_t key_at(int widx, const uint8_t *sym, int i) { /* sym: padded word, 0 = '#' */
    int l = WIN[widx][0], r = WIN[widx][1];
    uint64_t v = (uint64_t)widx;
    for (int s = -3; s <= 3; s++) {
        int use = (s < 0 && -s <= l) || s == 0 || (s > 0 && s <= r);
        v = (v << 5) | (use ? sym[i + s] : 0u);
    }
    return v;
}

static int find_key(const vtts_lex *lx, uint64_t k) {
    uint32_t lo = 0, hi = lx->lts_n;
    while (lo < hi) {
        uint32_t mid = (lo + hi) / 2;
        const uint8_t *e = lx->blob + lx->lts_off + 6 * (size_t)mid;
        uint64_t v = (uint64_t)e[0] | (uint64_t)e[1] << 8 | (uint64_t)e[2] << 16 | (uint64_t)e[3] << 24 | (uint64_t)e[4] << 32;
        if (v == k) return e[5];
        if (v < k) lo = mid + 1; else hi = mid;
    }
    return -1;
}

int vtts_lex_predict(const vtts_lex *lx, const char *word, uint8_t *out, int cap) {
    uint8_t sym[WORD_MAX + 6];
    int n = 0;
    if (!lx || !word) return 0;
    memset(sym, 0, 3);
    for (const char *c = word; *c && n < WORD_MAX; c++) {
        char ch = *c >= 'A' && *c <= 'Z' ? (char)(*c - 'A' + 'a') : *c;
        if (ch >= 'a' && ch <= 'z') sym[3 + n++] = (uint8_t)(ch - 'a' + 1);
    }
    memset(sym + 3 + n, 0, 3);
    int k = 0;
    for (int i = 3; i < 3 + n; i++) {
        for (int w = 0; w < 10; w++) {
            int li = find_key(lx, key_at(w, sym, i));
            if (li < 0) continue;
            if (li < lx->n_labels) {
                const uint8_t *e = lx->blob + lx->lab[li];
                if (k + e[0] > cap) return -1;
                memcpy(out + k, e + 1, e[0]);
                k += e[0];
            }
            break;
        }
    }
    /* exactly one primary stress: promote the first stress mark if none, demote later S1 */
    int first = -1, prim = 0;
    for (int i = 0; i < k; i++) {
        if (out[i] < ID_S0 || out[i] > ID_S0 + 2) continue;
        if (first < 0) first = i;
        if (out[i] == ID_S0 + 1 && prim++) out[i] = ID_S0 + 2;
    }
    if (!prim && first >= 0) out[first] = ID_S0 + 1;
    return k;
}
