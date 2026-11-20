/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_ja.c -- Japanese front-end of the device (token set ja-en): JLEX reader and NFKC,
 * readings by forward longest match (mirrors src/vtts/frontend/ja/g2p_ja.py), kana -> phonemes
 * (ja/kana.py) and normalization (ja/normalize_ja.py). */
#include "vtts_langs.h"
#if VTTS_ENABLE_JA /* else an empty unit (vtts_langs.h) */

#include "vtts_text_ja.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "vtts_text_en.h"
#include "vtts_text_tables.h"

#define NUM_DIGITS 400 /* characters of one float() argument (Python reads any length; beyond 309 integer digits it is inf) */

static uint32_t rd32(const uint8_t *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

/* one UTF-8 sequence at s (NUL terminated): code point in *c, returns its length (0 at NUL) */
static int dec1(const char *s, uint32_t *c) {
    const unsigned char *p = (const unsigned char *)s;
    if (!p[0]) return 0;
    if (p[0] < 0x80) { *c = p[0]; return 1; }
    int extra = (p[0] >> 5) == 6 ? 1 : (p[0] >> 4) == 14 ? 2 : (p[0] >> 3) == 30 ? 3 : 0;
    if (!extra) { *c = 0xFFFD; return 1; }
    uint32_t v = p[0] & (0x3Fu >> extra);
    for (int k = 1; k <= extra; k++) {
        if ((p[k] & 0xC0) != 0x80) { *c = 0xFFFD; return k; }
        v = (v << 6) | (p[k] & 0x3F);
    }
    *c = v;
    return extra + 1;
}

/* decode one code point of a UTF-8 buffer of known length (valid UTF-8 from the blob) */
static int dec_n(const uint8_t *p, int n, uint32_t *c) {
    if (n <= 0) return 0;
    if (p[0] < 0x80) { *c = p[0]; return 1; }
    int extra = (p[0] >> 5) == 6 ? 1 : (p[0] >> 4) == 14 ? 2 : (p[0] >> 3) == 30 ? 3 : 0;
    if (!extra || extra >= n) { *c = 0xFFFD; return 1; }
    uint32_t v = p[0] & (0x3Fu >> extra);
    for (int k = 1; k <= extra; k++) v = (v << 6) | (p[k] & 0x3F);
    *c = v;
    return extra + 1;
}

static int enc1(uint32_t c, uint8_t *o) {
    if (c < 0x80) { o[0] = (uint8_t)c; return 1; }
    if (c < 0x800) { o[0] = (uint8_t)(0xC0 | (c >> 6)); o[1] = (uint8_t)(0x80 | (c & 0x3F)); return 2; }
    if (c < 0x10000) {
        o[0] = (uint8_t)(0xE0 | (c >> 12)); o[1] = (uint8_t)(0x80 | ((c >> 6) & 0x3F));
        o[2] = (uint8_t)(0x80 | (c & 0x3F)); return 3;
    }
    o[0] = (uint8_t)(0xF0 | (c >> 18)); o[1] = (uint8_t)(0x80 | ((c >> 12) & 0x3F));
    o[2] = (uint8_t)(0x80 | ((c >> 6) & 0x3F)); o[3] = (uint8_t)(0x80 | (c & 0x3F)); return 4;
}

/* ======================= JLEX reader ======================= */

#define JLEX_HEADER 128

int vtts_jlex_init(vtts_jlex *j, const uint8_t *blob, size_t size) {
    if (!j || !blob || size < JLEX_HEADER || memcmp(blob, "JLEX", 4) != 0 || blob[4] != 1 || blob[5] != 0 ||
        blob[6] != JLEX_HEADER || blob[7] != 0)
        return -1;
    memset(j, 0, sizeof *j);
    j->blob = blob;
    j->size = size;
    j->max_len = rd32(blob + 8);
    j->block = rd32(blob + 12);
    if (j->max_len == 0 || j->max_len > 64 || j->block == 0 || j->block > 1024) return -2;
    for (int k = 0; k < VTTS_JLEX_N_TABLES; k++) {
        const uint8_t *h = blob + 16 + 20 * k;
        vtts_jlex_table *t = &j->t[k];
        t->n = rd32(h);
        t->n_blocks = rd32(h + 4);
        uint32_t io = rd32(h + 8), dof = rd32(h + 12);
        t->data_size = rd32(h + 16);
        if (t->n_blocks != (t->n + j->block - 1) / j->block) return -2;
        if (io < JLEX_HEADER || io > size || 4ull * t->n_blocks > size - io) return -2;
        if (dof < JLEX_HEADER || dof > size || t->data_size > size - dof) return -2;
        t->index = blob + io;
        t->data = blob + dof;
        for (uint32_t b = 0; b < t->n_blocks; b++)
            if (rd32(t->index + 4 * b) >= t->data_size) return -3;
    }
    const uint8_t *h = blob + 96;
    j->n_dec = rd32(h);
    uint32_t dec_off = rd32(h + 4), data_off = rd32(h + 8);
    j->dec_data_size = rd32(h + 12);
    j->n_ccc = rd32(h + 16);
    uint32_t ccc_off = rd32(h + 20);
    j->n_comp = rd32(h + 24);
    uint32_t comp_off = rd32(h + 28);
    if (dec_off < JLEX_HEADER || dec_off > size || 8ull * j->n_dec > size - dec_off) return -2;
    if (data_off < JLEX_HEADER || data_off > size || j->dec_data_size > size - data_off) return -2;
    if (ccc_off < JLEX_HEADER || ccc_off > size || 4ull * j->n_ccc > size - ccc_off) return -2;
    if (comp_off < JLEX_HEADER || comp_off > size || 12ull * j->n_comp > size - comp_off) return -2;
    j->dec = blob + dec_off;
    j->dec_data = blob + data_off;
    j->ccc = blob + ccc_off;
    j->comp = blob + comp_off;
    for (uint32_t i = 0; i < j->n_dec; i++) {
        uint32_t e = rd32(j->dec + 8 * i), len = e >> 21, off = rd32(j->dec + 8 * i + 4);
        if (len == 0 || off > j->dec_data_size || len > j->dec_data_size - off) return -3;
    }
    return 0;
}

static int bytes_cmp(const uint8_t *a, int na, const uint8_t *b, int nb) {
    int m = na < nb ? na : nb;
    int c = memcmp(a, b, (size_t)m);
    if (c) return c;
    return na < nb ? -1 : na > nb ? 1 : 0;
}

int vtts_jlex_find(const vtts_jlex *j, int table, const uint8_t *key, int key_len, const uint8_t **reading) {
    if (!j || table < 0 || table >= VTTS_JLEX_N_TABLES || key_len <= 0) return -1;
    const vtts_jlex_table *t = &j->t[table];
    const uint8_t *d = t->data;
    const uint32_t size = t->data_size;
    /* last block whose first key <= key */
    uint32_t lo = 0, hi = t->n_blocks;
    while (lo < hi) {
        uint32_t mid = lo + (hi - lo) / 2, p = rd32(t->index + 4 * mid);
        int kl = d[p];
        if (p + 1 + (uint32_t)kl > size) return -1;
        if (bytes_cmp(d + p + 1, kl, key, key_len) <= 0) lo = mid + 1; else hi = mid;
    }
    if (lo == 0) return -1;
    uint32_t b = lo - 1, p = rd32(t->index + 4 * b);
    uint32_t count = t->n - b * j->block;
    if (count > j->block) count = j->block;
    uint8_t cur[256];
    int cl = 0;
    for (uint32_t e = 0; e < count; e++) {
        if (e == 0) {
            if (p + 1 > size) return -1;
            cl = d[p];
            if (p + 1 + (uint32_t)cl > size) return -1;
            memcpy(cur, d + p + 1, (size_t)cl);
            p += 1 + (uint32_t)cl;
        } else {
            if (p + 2 > size) return -1;
            int shared = d[p], sl = d[p + 1];
            if (shared > cl || shared + sl > 255 || p + 2 + (uint32_t)sl > size) return -1;
            memcpy(cur + shared, d + p + 2, (size_t)sl);
            cl = shared + sl;
            p += 2 + (uint32_t)sl;
        }
        if (p + 1 > size) return -1;
        int rl = d[p];
        if (p + 1 + (uint32_t)rl > size) return -1;
        int c = bytes_cmp(cur, cl, key, key_len);
        if (c == 0) {
            if (reading) *reading = d + p + 1;
            return rl;
        }
        if (c > 0) return -1;
        p += 1 + (uint32_t)rl;
    }
    return -1;
}

/* ---- NFKC: decomposition (table), canonical ordering, canonical composition ---- */

#define SBASE 0xAC00u
#define LBASE 0x1100u
#define VBASE 0x1161u
#define TBASE 0x11A7u
#define LCOUNT 19u
#define VCOUNT 21u
#define TCOUNT 28u
#define NCOUNT (VCOUNT * TCOUNT)
#define SCOUNT (LCOUNT * NCOUNT)

static int ccc_of(const vtts_jlex *j, uint32_t c) {
    if (c < 0x300) return 0;
    uint32_t lo = 0, hi = j->n_ccc;
    while (lo < hi) {
        uint32_t mid = lo + (hi - lo) / 2, e = rd32(j->ccc + 4 * mid), k = e & 0xFFFFFF;
        if (k == c) return (int)(e >> 24);
        if (k < c) lo = mid + 1; else hi = mid;
    }
    return 0;
}

static uint32_t compose(const vtts_jlex *j, uint32_t a, uint32_t b) {
    if (a >= LBASE && a < LBASE + LCOUNT && b >= VBASE && b < VBASE + VCOUNT)
        return SBASE + ((a - LBASE) * VCOUNT + (b - VBASE)) * TCOUNT;
    if (a >= SBASE && a < SBASE + SCOUNT && (a - SBASE) % TCOUNT == 0 && b > TBASE && b < TBASE + TCOUNT)
        return a + (b - TBASE);
    uint32_t lo = 0, hi = j->n_comp;
    while (lo < hi) {
        uint32_t mid = lo + (hi - lo) / 2;
        const uint8_t *e = j->comp + 12 * mid;
        uint32_t x = rd32(e), y = rd32(e + 4);
        if (x == a && y == b) return rd32(e + 8);
        if (x < a || (x == a && y < b)) lo = mid + 1; else hi = mid;
    }
    return 0;
}

int vtts_jlex_nfkc(const vtts_jlex *j, const uint32_t *in, int n, uint32_t *out, int cap) {
    int m = 0;
    for (int i = 0; i < n; i++) { /* full compatibility decomposition */
        uint32_t c = in[i];
        const uint8_t *seq = NULL;
        uint32_t len = 0;
        if (c >= 0xA0 && !(c >= SBASE && c < SBASE + SCOUNT)) {
            uint32_t lo = 0, hi = j->n_dec;
            while (lo < hi) {
                uint32_t mid = lo + (hi - lo) / 2, e = rd32(j->dec + 8 * mid), k = e & 0x1FFFFF;
                if (k == c) { len = e >> 21; seq = j->dec_data + rd32(j->dec + 8 * mid + 4); break; }
                if (k < c) lo = mid + 1; else hi = mid;
            }
        }
        if (!seq) {
            if (m >= cap) return -1;
            out[m++] = c;
            continue;
        }
        for (uint32_t k = 0; k < len;) {
            uint32_t d = 0;
            int l = dec_n(seq + k, (int)(len - k), &d);
            if (m >= cap) return -1;
            out[m++] = d;
            k += (uint32_t)l;
        }
    }
    /* canonical ordering: stable sort of each run of non-starters by combining class */
    for (int i = 1; i < m; i++) {
        int cc = ccc_of(j, out[i]);
        if (!cc) continue;
        uint32_t c = out[i];
        int k = i;
        while (k > 0) {
            int pc = ccc_of(j, out[k - 1]);
            if (pc <= cc) break;
            out[k] = out[k - 1];
            k--;
        }
        out[k] = c;
    }
    /* canonical composition */
    int st = -1, prev_cc = 0, w = 0;
    for (int i = 0; i < m; i++) {
        uint32_t c = out[i];
        int cc = ccc_of(j, c);
        if (st >= 0) {
            int adjacent = w - 1 == st;
            int blocked = !adjacent && (prev_cc == 0 || prev_cc >= cc);
            if (!blocked) {
                uint32_t x = compose(j, out[st], c);
                if (x) { out[st] = x; continue; }
            }
        }
        if (cc == 0) st = w;
        prev_cc = cc;
        out[w++] = c;
    }
    return w;
}

/* ======================= character classes ======================= */

static int is_kanji(uint32_t c) { return (c >= 0x4E00 && c <= 0x9FFF) || c == 0x3006; }
static int is_katakana(uint32_t c) { return (c >= 0x30A1 && c <= 0x30FA) || c == 0x30FC; }
static int is_kana(uint32_t c) {
    return (c >= 0x3041 && c <= 0x3096) || (c >= 0x30A1 && c <= 0x30FA) || c == 0x30FC || c == 0x309D ||
           c == 0x309E || c == 0x30FD || c == 0x30FE;
}
#define ODORIJI 0x3005u /* 々 */

int vtts_ja_is_ja_char(uint32_t c) { return is_kanji(c) || is_kana(c) || c == ODORIJI; }

int vtts_ja_script_class(uint32_t c) {
    if ((c >= 0x4E00 && c <= 0x9FFF) || (c >= 0x3040 && c <= 0x30FF && c != 0x30FB) || c == 0x3005 || c == 0x3006 ||
        (c >= 0xFF66 && c <= 0xFF9F))
        return 1;
    if ((c >= 0x3000 && c <= 0x303F) || (c >= 0xFF00 && c <= 0xFFEF) || c == 0x201C || c == 0x201D || c == 0x2018 ||
        c == 0x2019 || c == 0x2026 || c == 0x2014 || c == 0x30FB)
        return 2;
    return 0;
}

/* normalize_ja J: [一-鿿々〆ヶぁ-ゖァ-ヺー] */
static int is_j(uint32_t c) {
    return (c >= 0x4E00 && c <= 0x9FFF) || c == 0x3005 || c == 0x3006 || c == 0x30F6 || (c >= 0x3041 && c <= 0x3096) ||
           (c >= 0x30A1 && c <= 0x30FA) || c == 0x30FC;
}

/* ======================= kana -> phonemes (kana.py) ======================= */

/* code of a kana: hiragana - 0x3040, katakana folded to hiragana (ァ..ヶ, ヽ ヾ); ー VTTS_JA_LONG;
 * other characters 0x7F (no reading, but they still separate two kana of a pair) */
static uint8_t kana_code(uint32_t c) {
    if (c >= 0x3041 && c <= 0x309F) return (uint8_t)(c - 0x3040);
    if ((c >= 0x30A1 && c <= 0x30FA) || (c >= 0x30FC && c <= 0x30FE)) return (uint8_t)(c - 0x30A0);
    return 0x7F;
}

static const uint8_t *find_pair(uint8_t a, uint8_t b) {
    int lo = 0, hi = VTTS_JA_N_PAIRS;
    while (lo < hi) {
        int mid = (lo + hi) / 2;
        const uint8_t *e = VTTS_JA_PAIRS[mid];
        if (e[0] == a && e[1] == b) return e;
        if (e[0] < a || (e[0] == a && e[1] < b)) lo = mid + 1; else hi = mid;
    }
    return NULL;
}

static int is_vowel_id(int id) { return id >= VTTS_JA_V0 && id < VTTS_JA_V0 + 5; }
static int is_mora_id(int id) { return is_vowel_id(id) || id == VTTS_JA_N || id == VTTS_JA_CL; }

/* units of the phonemes of one segment: a new unit starts before a phoneme once the current one
 * holds MAX_UNIT_MORAE morae (_split_morae) */
typedef struct {
    vtts_ja_unit_cb cb;
    void *user;
    uint8_t buf[64];
    int n, morae, units;
    int last; /* last phoneme of the segment (0: none yet) */
} unit_t;

static void unit_flush(unit_t *u) {
    if (u->n) {
        if (u->cb) u->cb(u->user, u->buf, u->n);
        u->units++;
    }
    u->n = u->morae = 0;
}

static void unit_put(unit_t *u, int id) {
    if (u->morae == VTTS_JA_MAX_UNIT_MORAE) unit_flush(u);
    if (u->n < (int)sizeof u->buf) u->buf[u->n++] = (uint8_t)id;
    if (is_mora_id(id)) u->morae++;
    u->last = id;
}

/* kana_phonemes(codes, prev): the phonemes of one segment reading, emitted as units */
static void kana_phonemes(const uint8_t *s, int n, int prev_ph, unit_t *u) {
    int i = 0, prev = 0;
    u->last = 0;
    u->n = u->morae = 0;
    if (n > 0 && s[0] == VTTS_JA_LONG && is_vowel_id(prev_ph)) { unit_put(u, prev_ph); i = 1; }
    while (i < n) {
        if (i + 1 < n) {
            const uint8_t *p = find_pair(s[i], s[i + 1]);
            if (p) {
                for (int k = 0; k < p[2]; k++) unit_put(u, p[3 + k]);
                prev = s[i + 1];
                i += 2;
                continue;
            }
        }
        int ch = s[i];
        if ((ch == VTTS_JA_ITER || ch == VTTS_JA_ITER + 1) && prev)
            ch = ch == VTTS_JA_ITER + 1 ? (prev < 0x60 && VTTS_JA_VOICED[prev] ? VTTS_JA_VOICED[prev] : prev) : prev;
        if (ch == VTTS_JA_LONG) {
            if (is_vowel_id(u->last)) unit_put(u, u->last);
        } else if (ch < 0x60 && VTTS_JA_SINGLE[ch][0]) {
            for (int k = 0; k < VTTS_JA_SINGLE[ch][0]; k++) unit_put(u, VTTS_JA_SINGLE[ch][1 + k]);
            prev = ch;
        }
        i++;
    }
    unit_flush(u);
}

/* ======================= segmentation (g2p_ja.segment) ======================= */

typedef struct {
    const vtts_jlex *j;
    const uint32_t *w;
    const uint32_t *off;
    const uint8_t *utf8;
    int n;
} seg_ctx;

/* _longest: longest key of a table at i (no key ends inside a katakana run); its length or 0 */
static int longest(const seg_ctx *s, int i, int table, const uint8_t **reading, int *rlen) {
    int maxn = s->n - i < (int)s->j->max_len ? s->n - i : (int)s->j->max_len;
    for (int k = maxn; k >= 1; k--) {
        int e = i + k;
        if (e < s->n && is_katakana(s->w[e - 1]) && is_katakana(s->w[e])) continue;
        int r = vtts_jlex_find(s->j, table, s->utf8 + s->off[i], (int)(s->off[e] - s->off[i]), reading);
        if (r >= 0) { *rlen = r; return k; }
    }
    return 0;
}

/* _lookup: the table entry read at i (context table or words), its length or 0 */
static int lookup(const seg_ctx *s, int i, const uint8_t **reading, int *rlen) {
    if (i > 0 && is_katakana(s->w[i - 1]) && is_katakana(s->w[i])) return 0;
    const uint8_t *mr = NULL, *ar = NULL;
    int ml = 0, al = 0;
    int mn = longest(s, i, VTTS_JLEX_WORDS, &mr, &ml);
    int ctx = -1;
    if (i > 0) {
        uint32_t p = s->w[i - 1];
        if (is_kanji(p) || p == ODORIJI) ctx = VTTS_JLEX_AFTER_KANJI;
        else if (is_katakana(p)) ctx = VTTS_JLEX_AFTER_KATAKANA;
    }
    if (ctx >= 0) {
        int an = longest(s, i, ctx, &ar, &al);
        if (an) {
            int take = !mn || mn <= an;
            if (!take) {
                take = 1;
                for (int k = i + an; k < i + mn && take; k++) take = is_kana(s->w[k]);
            }
            if (take) { *reading = ar; *rlen = al; return an; }
        }
    }
    if (mn) { *reading = mr; *rlen = ml; }
    return mn;
}

static int kanji_reading(const vtts_jlex *j, uint32_t c, const uint8_t **reading) {
    uint8_t k[4];
    int l = enc1(c, k);
    return vtts_jlex_find(j, VTTS_JLEX_KANJI, k, l, reading);
}

enum { K_NONE, K_WORD, K_KANJI, K_KANA, K_UNKNOWN };

int vtts_ja_units(const vtts_jlex *j, const uint32_t *w, int n, uint32_t *off, uint8_t *scratch, int scratch_cap,
                  vtts_ja_unit_cb cb, void *user) {
    if (!j || n <= 0) return 0;
    if (scratch_cap < 5 * n + 64) return -1;
    uint8_t *utf8 = scratch, *codes = scratch + 4 * n + 4;
    uint32_t pos = 0;
    for (int i = 0; i < n; i++) {
        off[i] = pos;
        pos += (uint32_t)enc1(w[i], utf8 + pos);
    }
    off[n] = pos;
    seg_ctx s = {j, w, off, utf8, n};
    unit_t u = {cb, user, {0}, 0, 0, 0, 0};
    int prev_ph = 0;
    int last_kind = K_NONE, last_len = 0, last_rlen = 0;
    uint32_t last_char = 0;
    const uint8_t *last_reading = NULL;
    int kana_start = -1; /* pending kana run [kana_start, i) */

#define SEGMENT(codes_, len_)                                                  \
    do {                                                                       \
        kana_phonemes((codes_), (len_), prev_ph, &u);                          \
        if (u.last) prev_ph = u.last;                                          \
    } while (0)
#define FLUSH_KANA(end_)                                                       \
    do {                                                                       \
        if (kana_start >= 0) {                                                 \
            int kn_ = 0;                                                       \
            for (int q_ = kana_start; q_ < (end_); q_++) codes[kn_++] = kana_code(w[q_]); \
            SEGMENT(codes, kn_);                                               \
            kana_start = -1;                                                   \
        }                                                                      \
    } while (0)

    int i = 0;
    while (i < n) {
        const uint8_t *r = NULL;
        int rl = 0;
        int k = lookup(&s, i, &r, &rl);
        if (k) {
            FLUSH_KANA(i);
            SEGMENT(r, rl);
            last_kind = K_WORD; last_len = k; last_char = w[i + k - 1]; last_reading = r; last_rlen = rl;
            i += k;
            continue;
        }
        uint32_t ch = w[i];
        if (ch == ODORIJI) { /* repeat the previous kanji (no rendaku) */
            uint32_t prev = last_kind != K_NONE ? last_char : 0;
            const uint8_t *rr = NULL;
            int rn = 0;
            if (last_kind != K_NONE && last_len == 1 && is_kanji(prev)) { rr = last_reading; rn = last_rlen; }
            else if (is_kanji(prev)) { rn = kanji_reading(j, prev, &rr); if (rn < 0) rn = 0; }
            FLUSH_KANA(i);
            if (rn > 0) SEGMENT(rr, rn);
            last_kind = rn > 0 ? K_KANJI : K_UNKNOWN; last_len = 1; last_char = ch; last_reading = rr; last_rlen = rn;
        } else if (is_kanji(ch)) {
            const uint8_t *rr = NULL;
            int rn = kanji_reading(j, ch, &rr);
            if (rn < 0) rn = 0;
            FLUSH_KANA(i);
            if (rn > 0) SEGMENT(rr, rn);
            last_kind = rn > 0 ? K_KANJI : K_UNKNOWN; last_len = 1; last_char = ch; last_reading = rr; last_rlen = rn;
        } else if (is_kana(ch)) {
            if (last_kind == K_KANA) last_len++;
            else { kana_start = i; last_kind = K_KANA; last_len = 1; }
            last_char = ch; last_reading = NULL; last_rlen = 0;
        } else { /* not a Japanese character (the caller passes Japanese words only): no reading */
            FLUSH_KANA(i);
            last_kind = K_UNKNOWN; last_len = 1; last_char = ch; last_reading = NULL; last_rlen = 0;
        }
        i++;
    }
    FLUSH_KANA(n);
#undef FLUSH_KANA
#undef SEGMENT
    return u.units;
}

/* ======================= normalization (normalize_ja) =======================
 * Each regex pass of the Python normalizer is one function from buffer s (n code points) to
 * buffer d; matches are found left to right without overlap, like re.sub, and lookarounds look at
 * the pass's input. Backtracking is reproduced where it can change the result. \d is Python's
 * (Unicode decimal digits), [0-9] and [A-Za-z] are ASCII. */

typedef struct { uint32_t *p; int n, cap, err; } jb_t;

static void put(jb_t *d, uint32_t c) { if (d->n < d->cap) d->p[d->n++] = c; else d->err = 1; }
static void put_utf8(jb_t *d, const char *s) {
    uint32_t c;
    int l;
    while ((l = dec1(s, &c)) > 0) { put(d, c); s += l; }
}
static void put_ascii(jb_t *d, const char *s) { while (*s) put(d, (uint8_t)*s++); }
static void put_cps(jb_t *d, const uint32_t *s, int n) { for (int i = 0; i < n; i++) put(d, s[i]); }

/* value of a Unicode decimal digit (\d), -1 for other characters */
static int dval(uint32_t c) {
    if (c >= '0' && c <= '9') return (int)(c - '0');
    if (c < 0x660) return -1;
    int lo = 0, hi = VTTS_N_ND_ZEROS;
    while (lo < hi) { /* last zero <= c */
        int mid = (lo + hi) / 2;
        if (VTTS_ND_ZEROS[mid] <= c) lo = mid + 1; else hi = mid;
    }
    if (lo == 0) return -1;
    uint32_t z = VTTS_ND_ZEROS[lo - 1];
    return c - z < 10 ? (int)(c - z) : -1;
}

static int IN(int n, int i) { return i >= 0 && i < n; }
static int DG(const uint32_t *s, int n, int i) { return IN(n, i) && dval(s[i]) >= 0; }
static int AT(const uint32_t *s, int n, int i, uint32_t c) { return IN(n, i) && s[i] == c; }
static int SP(const uint32_t *s, int n, int i) { return IN(n, i) && vtts_cp_is_space(s[i]); }
static int ASC_ALPHA(const uint32_t *s, int n, int i) {
    return IN(n, i) && ((s[i] >= 'a' && s[i] <= 'z') || (s[i] >= 'A' && s[i] <= 'Z'));
}
static int ASC_ALNUM(const uint32_t *s, int n, int i) { return ASC_ALPHA(s, n, i) || (IN(n, i) && s[i] >= '0' && s[i] <= '9'); }
static int ASC_DIGIT(const uint32_t *s, int n, int i) { return IN(n, i) && s[i] >= '0' && s[i] <= '9'; }
static int digit_run(const uint32_t *s, int n, int i) { int j = i; while (DG(s, n, j)) j++; return j - i; }

static int key_at(const uint32_t *s, int n, int i, const char *k) { /* UTF-8 key at s[i]: its length or 0 */
    int m = 0;
    uint32_t c;
    int l;
    while ((l = dec1(k, &c)) > 0) {
        if (i + m >= n || s[i + m] != c) return 0;
        m++;
        k += l;
    }
    return m;
}

/* ---- numbers ----
 * A number is a range of code points holding \d digits and maybe commas (dropped, like
 * num.replace(",", "")). Values with at most 18 significant digits are held in v. */

typedef struct {
    const uint32_t *s;
    int a, b;  /* digits and commas */
    int nd;    /* significant digits (leading zeros dropped) */
    int first; /* index of the first significant digit (or b) */
    unsigned long long v; /* value when nd <= 18 */
    int last3; /* value mod 1000 */
} jnum;

static void num_init(jnum *x, const uint32_t *s, int a, int b) {
    x->s = s; x->a = a; x->b = b; x->nd = 0; x->first = b; x->v = 0; x->last3 = 0;
    for (int i = a; i < b; i++) {
        int dv = dval(s[i]);
        if (dv < 0) continue;
        if (!x->nd && dv == 0) continue;
        if (!x->nd) x->first = i;
        x->nd++;
        if (x->nd <= 18) x->v = x->v * 10 + (unsigned)dv;
        x->last3 = (x->last3 * 10 + dv) % 1000;
    }
}

static int num_last(const jnum *x) { return x->last3 % 10; }
static int num_is(const jnum *x, unsigned long long k) { return x->nd <= 18 && x->v == k; }
static int num_gt(const jnum *x, unsigned long long k) { return x->nd > 18 || x->v > k; }

static void put_digit(jb_t *d, int v) { put_utf8(d, VTTS_JA_DIGITS[v]); }

/* digits(s): one reading per \d digit of s[a..b) */
static void digits_u(jb_t *d, const uint32_t *s, int a, int b) {
    for (int i = a; i < b; i++) {
        int v = dval(s[i]);
        if (v >= 0) put_digit(d, v);
    }
}

/* _section(n, unit_after), n = 1..9999 */
static void section(jb_t *d, int v, int unit_after) {
    int th = v / 1000, h = v / 100 % 10, t = v / 10 % 10, o = v % 10;
    if (th) {
        if (th == 1 && unit_after) put_utf8(d, "イッセン");
        else if (VTTS_JA_THOUSANDS[th][0]) put_utf8(d, VTTS_JA_THOUSANDS[th]);
        else { put_digit(d, th); put_utf8(d, "セン"); }
    }
    if (h) {
        if (VTTS_JA_HUNDREDS[h][0]) put_utf8(d, VTTS_JA_HUNDREDS[h]);
        else { put_digit(d, h); put_utf8(d, "ヒャク"); }
    }
    if (t) {
        if (t != 1) put_digit(d, t);
        put_utf8(d, "ジュー");
    }
    if (o) put_digit(d, o);
}

/* cardinal(v) for v < 10**16 */
static void cardinal_v(jb_t *d, unsigned long long v) {
    if (v == 0) { put_digit(d, 0); return; }
    int g[4], ng = 0;
    while (v && ng < 4) { g[ng++] = (int)(v % 10000); v /= 10000; }
    for (int idx = ng - 1; idx >= 0; idx--) {
        if (!g[idx]) continue;
        if (idx == 3 && (g[idx] == 1 || g[idx] == 8 || g[idx] == 10))
            put_utf8(d, g[idx] == 1 ? "イッ" : g[idx] == 8 ? "ハッ" : "ジュッ");
        else
            section(d, g[idx], idx > 0);
        put_utf8(d, VTTS_JA_GROUPS[idx]);
    }
}

/* cardinal(int(x)), or cardinal(n - n % 10) with zero_last */
static void cardinal_n(jb_t *d, const jnum *x, int zero_last) {
    if (x->nd <= 16) {
        unsigned long long v = x->v;
        if (zero_last) v -= v % 10;
        cardinal_v(d, v);
        return;
    }
    /* more than four groups: the digits one by one (the last one 0 with zero_last) */
    int seen = 0;
    for (int i = x->first; i < x->b; i++) {
        int dv = dval(x->s[i]);
        if (dv < 0) continue;
        seen++;
        put_digit(d, zero_last && seen == x->nd ? 0 : dv);
    }
}

/* decimal(s[a..b)): commas dropped, a leading '-' is マイナス, "x.y" is cardinal(x) テン digits(y) */
static void decimal_u(jb_t *d, const uint32_t *s, int a, int b) {
    int neg = 0;
    while (a < b && (s[a] == '-' || s[a] == ',')) { if (s[a] == '-') neg = 1; a++; } /* lstrip('-') */
    int dot = -1;
    for (int i = a; i < b && dot < 0; i++) if (s[i] == '.') dot = i;
    if (neg) put_utf8(d, "マイナス");
    jnum x;
    num_init(&x, s, a, dot < 0 ? b : dot);
    cardinal_n(d, &x, 0);
    if (dot >= 0) {
        put_utf8(d, "テン");
        digits_u(d, s, dot + 1, b);
    }
}

static int ends_with(const jb_t *d, int start, const char *suffix) {
    uint32_t c[16];
    int m = 0, l;
    uint32_t x;
    while ((l = dec1(suffix, &x)) > 0 && m < 16) { c[m++] = x; suffix += l; }
    if (d->n - start < m) return 0;
    for (int k = 0; k < m; k++) if (d->p[d->n - m + k] != c[k]) return 0;
    return 1;
}

/* _geminate: the reading ends in イチ ロク ハチ ジュー ヒャク -> its last kana becomes ッ */
static int geminate(jb_t *d, int start) {
    static const char *const ENDS[] = {"イチ", "ロク", "ハチ", "ジュー", "ヒャク"};
    for (int k = 0; k < 5; k++)
        if (ends_with(d, start, ENDS[k])) { d->p[d->n - 1] = 0x30C3; return 1; }
    return 0;
}

static int ending(const jnum *x) { /* _ending as a bit of gem_mask */
    if (x->last3 % 10) return x->last3 % 10;
    if (x->last3 % 100) return 10;
    if (x->last3 % 1000) return 11;
    return 0;
}

/* whole[n] of a counter ("n=reading|..."): put it and return 1 */
static int put_whole(jb_t *d, const char *whole, const jnum *x) {
    if (!whole[0] || x->nd > 3) return 0;
    for (const char *p = whole; *p;) {
        unsigned long long k = 0;
        while (*p >= '0' && *p <= '9') k = k * 10 + (unsigned)(*p++ - '0');
        p++; /* '=' */
        const char *e = strchr(p, '|');
        int len = e ? (int)(e - p) : (int)strlen(p);
        if (num_is(x, k)) {
            char buf[64];
            if (len >= (int)sizeof buf) return 0;
            memcpy(buf, p, (size_t)len);
            buf[len] = 0;
            put_utf8(d, buf);
            return 1;
        }
        p += len;
        if (*p == '|') p++;
    }
    return 0;
}

static int counter_index(const char *key) {
    for (int k = 0; k < VTTS_JA_N_COUNTERS; k++) if (strcmp(VTTS_JA_COUNTERS[k].key, key) == 0) return k;
    return -1;
}

/* with_counter(num, counter, after_month): num = s[a..b) (\d digits, commas, maybe one '.') */
static void with_counter(jb_t *d, const uint32_t *s, int a, int b, int ci, int after_month) {
    const vtts_ja_counter *c = &VTTS_JA_COUNTERS[ci];
    int dot = 0;
    for (int i = a; i < b; i++) dot |= s[i] == '.';
    if (dot) { /* not plain.isdigit() */
        decimal_u(d, s, a, b);
        put_utf8(d, c->base[0] ? c->base : c->key);
        return;
    }
    jnum x;
    num_init(&x, s, a, b);
    int is_day = strcmp(c->key, "日") == 0, is_days = strcmp(c->key, "日間") == 0;
    if (is_day && num_is(&x, 1) && !after_month) { put_utf8(d, "イチニチ"); return; }
    if (put_whole(d, c->whole, &x)) return;
    if (strcmp(c->key, "つ") == 0) { cardinal_n(d, &x, 0); return; }
    int last = num_last(&x);
    if (c->last[last]) {
        if (num_gt(&x, (unsigned)last)) cardinal_n(d, &x, 1);
        put_utf8(d, c->last[last]);
        put_utf8(d, c->base);
        return;
    }
    if ((is_day || is_days) && last == 4 && num_gt(&x, 10)) {
        cardinal_n(d, &x, 1);
        put_utf8(d, "ヨッカ");
        if (is_days) put_utf8(d, "カン");
        return;
    }
    int start = d->n;
    cardinal_n(d, &x, 0);
    if (c->gem && (c->gem_mask >> ending(&x) & 1) && geminate(d, start)) { put_utf8(d, c->gem); return; }
    if (c->nasal) {
        for (const char *p = c->nasal_after; *p;) {
            const char *e = strchr(p, '|');
            int len = e ? (int)(e - p) : (int)strlen(p);
            char buf[32];
            if (len < (int)sizeof buf) {
                memcpy(buf, p, (size_t)len);
                buf[len] = 0;
                if (ends_with(d, start, buf)) { put_utf8(d, c->nasal); return; }
            }
            p += len;
            if (*p == '|') p++;
        }
    }
    put_utf8(d, c->base);
}

/* with_counter(str(v), counter) for a small int */
static void with_counter_int(jb_t *d, int v, const char *counter, int after_month) {
    uint32_t buf[12];
    int n = 0;
    char t[12];
    snprintf(t, sizeof t, "%d", v);
    for (char *p = t; *p; p++) buf[n++] = (uint8_t)*p;
    with_counter(d, buf, 0, n, counter_index(counter), after_month);
}

static int int_of(const uint32_t *s, int a, int b) { /* int() of a few \d digits */
    int v = 0;
    for (int i = a; i < b; i++) v = v * 10 + dval(s[i]);
    return v;
}

/* NUM = (?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)? at i: the ends a match can take when the next
 * character must not be a digit, in the regex's order of preference. Returns the count. */
#define MAX_CANDS 64
static int num_cands(const uint32_t *s, int n, int i, int *ends) {
    int r = digit_run(s, n, i), m = 0;
    if (!r) return 0;
    if (r <= 3) { /* \d{1,3} can only take the whole run (a shorter one is followed by a digit) */
        int k = i + r, groups = 0;
        while (AT(s, n, k, ',') && DG(s, n, k + 1) && DG(s, n, k + 2) && DG(s, n, k + 3)) { k += 4; groups++; }
        /* (?:,\d{3})+ from the most groups down; a group end followed by a digit fails */
        for (int g = groups; g >= 1 && m < MAX_CANDS - 2; g--) {
            int e = i + r + 4 * g;
            if (AT(s, n, e, '.') && DG(s, n, e + 1)) ends[m++] = e + 1 + digit_run(s, n, e + 1);
            if (!DG(s, n, e)) ends[m++] = e;
        }
    }
    int e = i + r;
    if (AT(s, n, e, '.') && DG(s, n, e + 1)) ends[m++] = e + 1 + digit_run(s, n, e + 1);
    ends[m++] = e;
    return m;
}

/* NUM at i with nothing after it (MONEY): the greedy match, its end or -1 */
static int num_first(const uint32_t *s, int n, int i) {
    int r = digit_run(s, n, i);
    if (!r) return -1;
    int e = i + r;
    if (r <= 3)
        while (AT(s, n, e, ',') && DG(s, n, e + 1) && DG(s, n, e + 2) && DG(s, n, e + 3)) e += 4;
    if (AT(s, n, e, '.') && DG(s, n, e + 1)) e += 1 + digit_run(s, n, e + 1);
    return e;
}

/* ---- passes, in the order of normalize_ja ---- */

static void p_tilde(const uint32_t *s, int n, jb_t *d) {
    for (int i = 0; i < n; i++) put(d, s[i] == 0x301C || s[i] == 0xFF5E ? '~' : s[i]);
}

static void p_fullwidth(const uint32_t *s, int n, jb_t *d) {
    for (int i = 0; i < n; i++) {
        uint32_t c = s[i];
        if (c >= 0xFF01 && c < 0xFF5F) c -= 0xFEE0;
        else for (int k = 0; k < VTTS_JA_N_FULLWIDTH; k++) if (VTTS_JA_FULLWIDTH[k][0] == c) { c = VTTS_JA_FULLWIDTH[k][1]; break; }
        put(d, c);
    }
}

static void p_pause(const uint32_t *s, int n, jb_t *d) { /* …+|‥+|—+|―+|\.{3,} -> "," */
    for (int i = 0; i < n;) {
        uint32_t c = s[i];
        if (c == 0x2026 || c == 0x2025 || c == 0x2014 || c == 0x2015 || c == '.') {
            int j = i;
            while (j < n && s[j] == c) j++;
            if (c != '.' || j - i >= 3) { put(d, ','); i = j; continue; }
        }
        put(d, c);
        i++;
    }
}

static void p_symbols(const uint32_t *s, int n, jb_t *d) {
    /* the str.replace calls in order; their outputs hold no key, so one pass is the same */
    for (int i = 0; i < n;) {
        int m = 0, k = 0;
        for (; k < VTTS_JA_N_SYMBOLS && !m; k++) m = key_at(s, n, i, VTTS_JA_SYMBOLS[k][0]);
        if (m) { put_utf8(d, VTTS_JA_SYMBOLS[k - 1][1]); i += m; continue; }
        put(d, s[i++]);
    }
}

static void p_drop(const uint32_t *s, int n, jb_t *d) {
    for (int i = 0; i < n; i++) {
        uint32_t c = s[i];
        for (int k = 0; k < VTTS_JA_N_DROP; k++) if (VTTS_JA_DROP[k] == c) { c = ' '; break; }
        put(d, c);
    }
}

/* (?<=[J\d])\s+(?=[J])|(?<=[J])\s+(?=\d) -> "" */
static void p_jspace(const uint32_t *s, int n, jb_t *d) {
    for (int i = 0; i < n;) {
        if (SP(s, n, i)) {
            int j = i;
            while (SP(s, n, j)) j++;
            int pj = i > 0 && is_j(s[i - 1]), pd = DG(s, n, i - 1);
            int qj = j < n && is_j(s[j]), qd = DG(s, n, j);
            if (!(((pj || pd) && qj) || (pj && qd))) put_cps(d, s + i, j - i);
            i = j;
            continue;
        }
        put(d, s[i++]);
    }
}

/* float -> str like Python: exact integers via int(n), others as repr(n) */
static void put_float(jb_t *d, double x) {
    uint64_t bits;
    memcpy(&bits, &x, sizeof bits);
    int ex = (int)(bits >> 52 & 0x7FF);
    uint64_t mant = bits & ((1ull << 52) - 1);
    if (ex == 0x7FF) { put_ascii(d, mant ? "nan" : "inf"); return; } /* Python raises here */
    int is_int;
    if (ex == 0) is_int = mant == 0;
    else {
        int sh = 1075 - ex; /* value = (mant | 1 << 52) >> sh */
        uint64_t m = mant | 1ull << 52;
        is_int = sh <= 0 || (sh < 64 && (m & ((1ull << sh) - 1)) == 0);
    }
    if (is_int) { /* exact decimal of an integral double: (mant | 1 << 52) * 2^(ex - 1075) */
        if (ex == 0) { put(d, '0'); return; }
        uint64_t m = mant | 1ull << 52;
        int sh = ex - 1075;
        if (sh <= 0) { char t[24]; snprintf(t, sizeof t, "%llu", (unsigned long long)(m >> -sh)); put_ascii(d, t); return; }
        uint32_t limb[40]; /* base 1e9, least significant first */
        int nl = 0;
        while (m) { limb[nl++] = (uint32_t)(m % 1000000000u); m /= 1000000000u; }
        for (int k = 0; k < sh; k++) {
            uint32_t carry = 0;
            for (int q = 0; q < nl; q++) {
                uint64_t v = (uint64_t)limb[q] * 2 + carry;
                limb[q] = (uint32_t)(v % 1000000000u);
                carry = (uint32_t)(v / 1000000000u);
            }
            if (carry && nl < 40) limb[nl++] = carry;
        }
        char t[16];
        snprintf(t, sizeof t, "%u", (unsigned)limb[nl - 1]);
        put_ascii(d, t);
        for (int q = nl - 2; q >= 0; q--) { snprintf(t, sizeof t, "%09u", (unsigned)limb[q]); put_ascii(d, t); }
        return;
    }
    /* repr: the shortest digits that round-trip */
    char buf[48];
    int p;
    for (p = 1; p <= 17; p++) {
        snprintf(buf, sizeof buf, "%.*e", p - 1, x);
        if (strtod(buf, NULL) == x) break;
    }
    char dg[24];
    int nd = 0;
    const char *q = buf;
    for (; *q && *q != 'e'; q++) if (*q >= '0' && *q <= '9' && nd < 23) dg[nd++] = *q;
    int e10 = *q == 'e' ? atoi(q + 1) : 0;
    while (nd > 1 && dg[nd - 1] == '0') nd--;
    dg[nd] = 0;
    if (e10 >= -4 && e10 < 16) {
        if (e10 >= 0) {
            for (int k = 0; k <= e10; k++) put(d, k < nd ? (uint8_t)dg[k] : '0');
            put(d, '.');
            if (nd > e10 + 1) for (int k = e10 + 1; k < nd; k++) put(d, (uint8_t)dg[k]);
            else put(d, '0');
        } else {
            put_ascii(d, "0.");
            for (int k = 0; k < -e10 - 1; k++) put(d, '0');
            put_ascii(d, dg);
        }
    } else {
        put(d, (uint8_t)dg[0]);
        if (nd > 1) { put(d, '.'); put_ascii(d, dg + 1); }
        char t[16];
        snprintf(t, sizeof t, "e%c%02d", e10 < 0 ? '-' : '+', e10 < 0 ? -e10 : e10);
        put_ascii(d, t);
    }
}

/* BIG[unit]: (?<![\d.])(\d+(?:\.\d+)?)unit MARK?(\d{1,L})?(?![\d.]) -> MARK + str(n) */
static void p_big(const uint32_t *s, int n, jb_t *d, int u) {
    const uint32_t unit = VTTS_JA_BIG[u].cp;
    const int L = VTTS_JA_BIG[u].max_digits;
    for (int i = 0; i < n;) {
        if (DG(s, n, i) && !DG(s, n, i - 1) && !AT(s, n, i - 1, '.')) {
            int e1 = i + digit_run(s, n, i), ends[2], ne = 0;
            if (AT(s, n, e1, '.') && DG(s, n, e1 + 1)) ends[ne++] = e1 + 1 + digit_run(s, n, e1 + 1);
            ends[ne++] = e1;
            int g1e = -1, g2a = -1, g2b = -1, end = -1;
            for (int k = 0; k < ne && end < 0; k++) {
                int p = ends[k];
                if (!AT(s, n, p, unit)) continue;
                int qs[2], nq = 0;
                if (AT(s, n, p + 1, VTTS_JA_MARK)) qs[nq++] = p + 2;
                qs[nq++] = p + 1;
                for (int t = 0; t < nq && end < 0; t++) {
                    int q = qs[t], r2 = digit_run(s, n, q);
                    if (r2 > 0) {
                        if (r2 <= L && !AT(s, n, q + r2, '.')) { g1e = p; g2a = q; g2b = q + r2; end = q + r2; }
                    } else if (!AT(s, n, q, '.')) {
                        g1e = p; end = q;
                    }
                }
            }
            if (end >= 0) {
                char num[NUM_DIGITS + 2];
                int m = 0;
                for (int k = i; k < g1e && m < NUM_DIGITS; k++) num[m++] = s[k] == '.' ? '.' : (char)('0' + dval(s[k]));
                num[m] = 0;
                double v = strtod(num, NULL) * VTTS_JA_BIG[u].value;
                if (g2a >= 0) {
                    double add = 0;
                    for (int k = g2a; k < g2b; k++) add = add * 10 + dval(s[k]);
                    v = v + add;
                }
                put(d, VTTS_JA_MARK);
                put_float(d, v);
                i = end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![A-Za-z0-9])(-?NUM)\s?(unit)(?![A-Za-z]) -> decimal + reading */
static void p_unit(const uint32_t *s, int n, jb_t *d) {
    for (int i = 0; i < n;) {
        if (!ASC_ALNUM(s, n, i - 1)) {
            int j = i + AT(s, n, i, '-'), ends[MAX_CANDS];
            int nc = num_cands(s, n, j, ends), done = 0;
            for (int c = 0; c < nc && !done; c++) {
                int k = ends[c] + SP(s, n, ends[c]);
                for (int u = 0; u < VTTS_JA_N_UNITS; u++) {
                    int m = key_at(s, n, k, VTTS_JA_UNITS[u][0]);
                    if (m && !ASC_ALPHA(s, n, k + m)) {
                        decimal_u(d, s, i, ends[c]);
                        put_utf8(d, VTTS_JA_UNITS[u][1]);
                        i = k + m;
                        done = 1;
                        break;
                    }
                }
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

static int upper(uint32_t c) { return c >= 'A' && c <= 'Z'; }

/* (?<![A-Za-z0-9])(?=[A-Z0-9]*[A-Z])(?=[A-Z0-9]*[0-9])[A-Z0-9]+(?![A-Za-z0-9]) -> letters and
 * English digit names, each between spaces */
static void p_code(const uint32_t *s, int n, jb_t *d) {
    for (int i = 0; i < n;) {
        if (!ASC_ALNUM(s, n, i - 1) && (upper(s[i]) || ASC_DIGIT(s, n, i))) {
            int j = i, up = 0, dg = 0;
            while (j < n && (upper(s[j]) || ASC_DIGIT(s, n, j))) { up |= upper(s[j]); dg |= ASC_DIGIT(s, n, j); j++; }
            if (up && dg && !ASC_ALNUM(s, n, j)) {
                put(d, ' ');
                for (int k = i; k < j; k++) {
                    put(d, ' ');
                    if (upper(s[k])) put(d, s[k] + 32);
                    else put_ascii(d, VTTS_EN_ONES[s[k] - '0']);
                    put(d, ' ');
                }
                put(d, ' ');
                i = j;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![\d-])0\d{1,4}-\d{1,4}-\d{3,4}(?![\d-]) -> digits joined by ノ */
static void p_phone(const uint32_t *s, int n, jb_t *d) {
    for (int i = 0; i < n;) {
        if (AT(s, n, i, '0') && !DG(s, n, i - 1) && !AT(s, n, i - 1, '-')) {
            int r1 = digit_run(s, n, i + 1), a2 = i + 1 + r1 + 1;
            if (r1 >= 1 && r1 <= 4 && AT(s, n, a2 - 1, '-')) {
                int r2 = digit_run(s, n, a2), a3 = a2 + r2 + 1;
                if (r2 >= 1 && r2 <= 4 && AT(s, n, a3 - 1, '-')) {
                    int r3 = digit_run(s, n, a3), e = a3 + r3;
                    if (r3 >= 3 && r3 <= 4 && !AT(s, n, e, '-')) {
                        digits_u(d, s, i, a2 - 1);
                        put_utf8(d, "ノ");
                        digits_u(d, s, a2, a3 - 1);
                        put_utf8(d, "ノ");
                        digits_u(d, s, a3, e);
                        i = e;
                        continue;
                    }
                }
            }
        }
        put(d, s[i++]);
    }
}

static int is_sep(uint32_t c) { return c == '-' || c == '/' || c == '.'; }

/* (?<!\d)(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?!\d) */
static void p_iso_date(const uint32_t *s, int n, jb_t *d) {
    for (int i = 0; i < n;) {
        if (!DG(s, n, i - 1) && digit_run(s, n, i) == 4 && i + 4 < n && is_sep(s[i + 4])) {
            int m0 = i + 5, ml = digit_run(s, n, m0);
            int d0 = m0 + ml + 1, dl = ml >= 1 && ml <= 2 && m0 + ml < n && is_sep(s[m0 + ml]) ? digit_run(s, n, d0) : 0;
            if (dl >= 1 && dl <= 2) {
                int y = int_of(s, i, i + 4), mo = int_of(s, m0, m0 + ml), dd = int_of(s, d0, d0 + dl), end = d0 + dl;
                if (mo >= 1 && mo <= 12 && dd >= 1 && dd <= 31) {
                    with_counter_int(d, y, "年", 0);
                    with_counter_int(d, mo, "月", 0);
                    with_counter_int(d, dd, "日", 1);
                } else {
                    put_cps(d, s + i, end - i);
                }
                i = end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int a05(const uint32_t *s, int n, int i) { return IN(n, i) && s[i] >= '0' && s[i] <= '5'; }
static int not_dc(const uint32_t *s, int n, int i) { return !DG(s, n, i) && !AT(s, n, i, ':'); }

/* (?<![\d:])([01]?\d|2[0-4]):([0-5]\d)(?::([0-5]\d))?(?![\d:]) */
static void p_time(const uint32_t *s, int n, jb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i) && not_dc(s, n, i - 1)) {
            int hl[3], nh = 0;
            if ((s[i] == '0' || s[i] == '1') && DG(s, n, i + 1)) hl[nh++] = 2; /* [01]\d */
            hl[nh++] = 1;                                                    /* \d */
            if (s[i] == '2' && i + 1 < n && s[i + 1] >= '0' && s[i + 1] <= '4') hl[nh++] = 2; /* 2[0-4] */
            int done = 0;
            for (int c = 0; c < nh && !done; c++) {
                int j = i + hl[c];
                if (!(AT(s, n, j, ':') && a05(s, n, j + 1) && DG(s, n, j + 2))) continue;
                int k = j + 3, sec = -1, end = -1;
                if (AT(s, n, k, ':') && a05(s, n, k + 1) && DG(s, n, k + 2) && not_dc(s, n, k + 3)) {
                    sec = int_of(s, k + 1, k + 3);
                    end = k + 3;
                } else if (not_dc(s, n, k)) {
                    end = k;
                }
                if (end < 0) continue;
                int h = int_of(s, i, i + hl[c]), mi = int_of(s, j + 1, j + 3);
                with_counter_int(d, h, "時", 0);
                if (mi) with_counter_int(d, mi, "分", 0);
                if (sec > 0) with_counter_int(d, sec, "秒", 0);
                i = end;
                done = 1;
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

static const char *currency(uint32_t c) {
    for (int k = 0; k < VTTS_JA_N_CURRENCY; k++) if (VTTS_JA_CURRENCY[k].cp == c) return VTTS_JA_CURRENCY[k].name;
    return NULL;
}

/* ([¥$€£])\s?(MARK?)(NUM) -> decimal + currency */
static void p_money(const uint32_t *s, int n, jb_t *d) {
    for (int i = 0; i < n;) {
        const char *name = currency(s[i]);
        if (name) {
            int j = i + 1 + SP(s, n, i + 1);
            int k = j + AT(s, n, j, VTTS_JA_MARK), e = num_first(s, n, k);
            if (e > 0) {
                decimal_u(d, s, k, e);
                put_utf8(d, name);
                i = e;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* (MARK?)(-?NUM)\s?% -> decimal + パーセント */
static void p_percent(const uint32_t *s, int n, jb_t *d) {
    for (int i = 0; i < n;) {
        int k = i + AT(s, n, i, VTTS_JA_MARK);
        int j = k + AT(s, n, k, '-'), ends[MAX_CANDS];
        int nc = num_cands(s, n, j, ends), done = 0;
        for (int c = 0; c < nc && !done; c++) {
            int t = ends[c] + SP(s, n, ends[c]);
            if (AT(s, n, t, '%')) {
                decimal_u(d, s, k, ends[c]);
                put_utf8(d, "パーセント");
                i = t + 1;
                done = 1;
            }
        }
        if (done) continue;
        put(d, s[i++]);
    }
}

static int is_dash(uint32_t c) { return c == '~' || c == 0x301C || c == '-'; }

/* (?<![\d.])(MARK?)(NUM)\s?[~〜-]\s?(?=MARK?\d) -> decimal + カラ */
static void p_range(const uint32_t *s, int n, jb_t *d) {
    for (int i = 0; i < n;) {
        if (!DG(s, n, i - 1) && !AT(s, n, i - 1, '.')) {
            int k = i + AT(s, n, i, VTTS_JA_MARK), ends[MAX_CANDS];
            int nc = num_cands(s, n, k, ends), done = 0;
            for (int c = 0; c < nc && !done; c++) {
                int t = ends[c] + SP(s, n, ends[c]);
                if (!(IN(n, t) && is_dash(s[t]))) continue;
                t++;
                t += SP(s, n, t);
                if (DG(s, n, t) || (AT(s, n, t, VTTS_JA_MARK) && DG(s, n, t + 1))) {
                    decimal_u(d, s, k, ends[c]);
                    put_utf8(d, "カラ");
                    i = t;
                    done = 1;
                }
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

/* m.string[:m.start()].rstrip().endswith(("月", "ガツ")) */
static int after_month(const uint32_t *s, int i) {
    while (i > 0 && vtts_cp_is_space(s[i - 1])) i--;
    if (i >= 1 && s[i - 1] == 0x6708) return 1;
    return i >= 2 && s[i - 2] == 0x30AC && s[i - 1] == 0x30C4;
}

/* (?<![A-Za-z0-9.])(-?)(MARK?)(NUM)(?!\d)\s?(COUNTER)? -> _number */
static void p_number(const uint32_t *s, int n, jb_t *d) {
    for (int i = 0; i < n;) {
        if (!ASC_ALNUM(s, n, i - 1) && !AT(s, n, i - 1, '.')) {
            int sign = AT(s, n, i, '-'), j = i + sign;
            int marked = AT(s, n, j, VTTS_JA_MARK), k = j + marked, ends[MAX_CANDS];
            if (num_cands(s, n, k, ends) > 0) {
                int e = ends[0], t = e + SP(s, n, e), ci = -1, m = 0;
                for (int c = 0; c < VTTS_JA_N_COUNTERS && !m; c++) {
                    m = key_at(s, n, t, VTTS_JA_COUNTERS[c].key);
                    if (m) ci = c;
                }
                if (sign) put_utf8(d, "マイナス");
                if (ci < 0) {
                    int dot = 0, comma = 0, len = 0;
                    for (int q = k; q < e; q++) {
                        dot |= s[q] == '.';
                        comma |= s[q] == ',';
                        len += s[q] != ',';
                    }
                    int lead0 = 0;
                    for (int q = k; q < e; q++) if (s[q] != ',') { lead0 = s[q] == '0'; break; }
                    if (!dot && !marked && ((len >= 5 && !comma) || (len > 1 && lead0))) digits_u(d, s, k, e);
                    else decimal_u(d, s, k, e);
                } else {
                    with_counter(d, s, k, e, ci, after_month(s, i));
                }
                i = t + m;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

typedef struct { uint32_t *a, *b; int cap; char *out; int out_cap; } en_scratch_t;

static int lat(uint32_t c) { return (c | 32) >= 'a' && (c | 32) <= 'z'; }

/* [A-Za-z](?:[A-Za-z'-]*[A-Za-z])? -> " " + normalize_en(word) + " " */
static void p_latin(const uint32_t *s, int n, jb_t *d, const en_scratch_t *e) {
    for (int i = 0; i < n;) {
        if (lat(s[i])) {
            int j = i + 1, end = i + 1;
            while (j < n && (lat(s[j]) || s[j] == '\'' || s[j] == '-')) { if (lat(s[j])) end = j + 1; j++; }
            int m = vtts_en_normalize(s + i, end - i, e->a, e->b, e->cap, e->out, e->out_cap);
            if (m < 0) { d->err = 1; return; }
            put(d, ' ');
            for (int k = 0; k < m; k++) put(d, (uint8_t)e->out[k]);
            put(d, ' ');
            i = end;
            continue;
        }
        put(d, s[i++]);
    }
}

static void p_unmark(const uint32_t *s, int n, jb_t *d) {
    for (int i = 0; i < n; i++) if (s[i] != VTTS_JA_MARK) put(d, s[i]);
}

static int is_mark(uint32_t c) { return c == ',' || c == '.' || c == '?' || c == '!' || c == ';' || c == ':'; }

/* findall([J]+|[a-z][a-z']*|[,.?!;:]) joined by single spaces; a mark after a mark is dropped */
static void p_words(const uint32_t *s, int n, jb_t *d) {
    int any = 0, last_mark = 0;
    for (int i = 0; i < n;) {
        int j = i;
        if (is_j(s[i])) {
            while (j < n && is_j(s[j])) j++;
        } else if (s[i] >= 'a' && s[i] <= 'z') {
            j = i + 1;
            while (j < n && ((s[j] >= 'a' && s[j] <= 'z') || s[j] == '\'')) j++;
        } else if (is_mark(s[i])) {
            if (!any || !last_mark) {
                if (any) put(d, ' ');
                put(d, s[i]);
                any = last_mark = 1;
            }
            i++;
            continue;
        } else {
            i++;
            continue;
        }
        if (any) put(d, ' ');
        put_cps(d, s + i, j - i);
        any = 1;
        last_mark = 0;
        i = j;
    }
}

int vtts_ja_normalize(const vtts_jlex *j, const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, uint32_t *ea,
                      uint32_t *eb, int ecap, char *eout, int eout_cap, const uint32_t **out) {
    jb_t x = {a, 0, cap, 0}, y = {b, 0, cap, 0};
    en_scratch_t e = {ea, eb, ecap, eout, eout_cap};
    p_tilde(in, n, &x);
    if (x.err) return -1;
#define PASS(call) do { y.n = 0; call; if (y.err) return -1; jb_t t_ = x; x = y; y = t_; } while (0)
    if (j) {
        y.n = vtts_jlex_nfkc(j, x.p, x.n, y.p, y.cap);
        if (y.n < 0) return -1;
        jb_t t_ = x; x = y; y = t_;
    }
    PASS(p_fullwidth(x.p, x.n, &y));
    PASS(p_pause(x.p, x.n, &y));
    PASS(p_symbols(x.p, x.n, &y));
    PASS(p_drop(x.p, x.n, &y));
    PASS(p_jspace(x.p, x.n, &y));
    for (int u = 0; u < VTTS_JA_N_BIG; u++) PASS(p_big(x.p, x.n, &y, u));
    PASS(p_unit(x.p, x.n, &y));
    PASS(p_code(x.p, x.n, &y));
    PASS(p_phone(x.p, x.n, &y));
    PASS(p_iso_date(x.p, x.n, &y));
    PASS(p_time(x.p, x.n, &y));
    PASS(p_money(x.p, x.n, &y));
    PASS(p_percent(x.p, x.n, &y));
    PASS(p_range(x.p, x.n, &y));
    PASS(p_number(x.p, x.n, &y));
    PASS(p_latin(x.p, x.n, &y, &e));
    PASS(p_unmark(x.p, x.n, &y));
    PASS(p_words(x.p, x.n, &y));
#undef PASS
    *out = x.p;
    return x.n;
}

#endif /* VTTS_ENABLE_JA */
