/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_km.c -- Khmer front-end of the device (token set km-en): spelling folds, word
 * segmentation over the word list, orthographic clusters, syllables, onsets, rhymes and the
 * override readings (mirrors src/vtts/frontend/km/g2p_km.py), and the normalizer spec of
 * src/vtts/frontend/km/normalize_km.py on the shared engine (vtts_text_nsp.c). All tables are in
 * the generated vtts_text_km_tables.h (Khmer letters coded as code point - 0x1780 + 1); no blob. */
#include "vtts_text_km.h"

#include "vtts_langs.h"

#if VTTS_ENABLE_KM

#include <string.h>

#include "vtts_text_km_tables.h"
#include "vtts_text_nsp.h"

int vtts_km_is_khmer(uint32_t c) { return (c >= 0x1780 && c <= 0x17D3) || c == 0x17D7 || c == 0x17DD; }

int vtts_km_has_khmer(const uint32_t *w, int n) {
    for (int i = 0; i < n; i++) if (vtts_km_is_khmer(w[i])) return 1;
    return 0;
}

/* ======================= letters ======================= */

enum {
    K_BA = 0x1794 - 0x1780 + 1, K_NGO = 0x1784 - 0x1780 + 1, K_DA = 0x178A - 0x1780 + 1, K_TA = 0x178F - 0x1780 + 1,
    K_O = 0x17B2 - 0x1780 + 1, K_AU = 0x17B1 - 0x1780 + 1, K_RO = 0x179A - 0x1780 + 1,
    K_I = 0x17B7 - 0x1780 + 1, K_U = 0x17BB - 0x1780 + 1, K_NIKAHIT = 0x17C6 - 0x1780 + 1,
    K_COENG = 0x17D2 - 0x1780 + 1, K_REPEAT = 0x17D7 - 0x1780 + 1
};

static unsigned FL(uint8_t c) { return c >= 1 && c <= 128 ? VTTS_KM_LETTERS[c - 1].flags : 0; }
static int is_cons(uint8_t c) { return (FL(c) & VTTS_KM_CONS) != 0; }
static int is_indep(uint8_t c) { return (FL(c) & VTTS_KM_INDEP) != 0; }

/* ======================= spelling ======================= */

/* spell(): ignored signs dropped, subscript ដ as ត, ឲ as ឱ, coeng ro after the other subscripts */
static int spell(uint8_t *w, int n) {
    int m = 0;
    for (int i = 0; i < n; i++) if (!(FL(w[i]) & VTTS_KM_IGNORED)) w[m++] = w[i];
    n = m;
    for (int i = 0; i + 1 < n; i++) if (w[i] == K_COENG && w[i + 1] == K_DA) w[i + 1] = K_TA;
    for (int i = 0; i < n; i++) if (w[i] == K_O) w[i] = K_AU;
    int k = -1;
    for (int q = 0; q + 2 < n; q++) if (w[q] == K_COENG && w[q + 1] == K_RO && w[q + 2] == K_COENG) { k = q; break; }
    while (k >= 0) {
        if (k + 3 < n && is_cons(w[k + 3])) { /* w[:k] + w[k+2:k+4] + ro + w[k+4:] */
            uint8_t x = w[k + 3];
            w[k] = K_COENG; w[k + 1] = x; w[k + 2] = K_COENG; w[k + 3] = K_RO;
        }
        int from = k + 2;
        k = -1;
        for (int q = from; q + 2 < n; q++) if (w[q] == K_COENG && w[q + 1] == K_RO && w[q + 2] == K_COENG) { k = q; break; }
    }
    return n;
}

/* ======================= clusters and syllables ======================= */

/* A cluster's base and subscripts are stored together in the letter pool (lp), its vowel signs
 * (dependent vowels, then the signs of SIGNS) in the vowel pool (vp); a word of n code points
 * needs at most n entries in each, so nothing is cut. */
typedef struct {
    uint16_t at, vat, nsubs, nvowel; /* lp[at] = base, lp[at+1..] = subscripts; vp[vat..] = vowel */
    uint8_t shift, bantoc, silent, robat, signs;
} cl_t;

typedef struct {
    uint16_t oat, nonset, vat, nvowel; /* onset lp[oat..], vowel vp[vat..] */
    uint8_t shift, final, bantoc, indep, last, sub, signs;
} sy_t;

typedef struct {
    uint8_t lp[VTTS_KM_MAX_RUN + 1], vp[VTTS_KM_MAX_RUN + 1];
    cl_t cl[VTTS_KM_MAX_RUN];
    sy_t sy[VTTS_KM_MAX_RUN];
} km_syl_t;

static const uint8_t SIGNS_ORDER[5] = {0x17C6 - 0x1780 + 1, 0x17C7 - 0x1780 + 1, 0x17C8 - 0x1780 + 1,
                                       0x17D0 - 0x1780 + 1, 0x17CF - 0x1780 + 1}; /* ំ ះ ៈ ័ ៏ */

static int clusters(const uint8_t *w, int n, km_syl_t *z) {
    int m = 0, i = 0, nl = 0, nvp = 0;
    while (i < n) {
        uint8_t ch = w[i++];
        if (!is_cons(ch) && !is_indep(ch)) continue;
        cl_t *c = &z->cl[m++];
        memset(c, 0, sizeof *c);
        c->at = (uint16_t)nl;
        z->lp[nl++] = ch;
        c->vat = (uint16_t)nvp;
        uint8_t signs = 0, shift = 0;
        int nv = 0;
        while (i < n) {
            uint8_t x = w[i];
            unsigned f = FL(x);
            if (x == K_COENG) {
                if (i + 1 < n && is_cons(w[i + 1])) {
                    z->lp[nl++] = w[i + 1];
                    c->nsubs++;
                    i++;
                }
            } else if (f & VTTS_KM_DEP) {
                z->vp[nvp + nv++] = x;
            } else if (f & VTTS_KM_SIGN) {
                for (int k = 0; k < 5; k++) if (SIGNS_ORDER[k] == x) signs |= (uint8_t)(1u << k);
            } else if (f & (VTTS_KM_MUUS | VTTS_KM_TRII)) {
                if (!shift) shift = (f & VTTS_KM_MUUS) ? 1 : 2;
            } else if (f & VTTS_KM_BANTOC) {
                c->bantoc = 1;
            } else if (f & VTTS_KM_SILENCER) {
                c->silent = 1;
            } else if (f & VTTS_KM_ROBAT) {
                c->robat = 1;
            } else if (!(f & VTTS_KM_IGNORED)) {
                break;
            }
            i++;
        }
        uint8_t *v = z->vp + nvp;
        int has_u = -1, upper = 0;
        for (int k = 0; k < nv; k++) {
            if (v[k] == K_U && has_u < 0) has_u = k;
            if (FL(v[k]) & VTTS_KM_UPPER) upper = 1;
        }
        if (has_u >= 0 && upper) { /* ុ under an upper vowel: a shifter */
            for (int k = has_u; k + 1 < nv; k++) v[k] = v[k + 1];
            nv--;
            if (!shift) shift = 3;
        }
        for (int k = 0; k < 5; k++) if ((signs >> k) & 1) v[nv++] = SIGNS_ORDER[k];
        c->nvowel = (uint16_t)nv;
        nvp += nv;
        c->signs = signs;
        c->shift = shift;
    }
    return m;
}

#define BASE(c) (z->lp[(c)->at])
#define SUB0(c) (z->lp[(c)->at + 1])

static int bare(const km_syl_t *z, const cl_t *c) { return !c->nvowel && is_cons(BASE(c)); }

static int pair_splits(const km_syl_t *z, const cl_t *c) {
    uint8_t a = BASE(c), b = SUB0(c);
    if (a == b) return 1;
    uint8_t ra = VTTS_KM_LETTERS[a - 1].row, rb = VTTS_KM_LETTERS[b - 1].row;
    if (ra != 7 && ra == rb) return 1;
    for (int k = 0; k < VTTS_KM_N_EXTRA_SPLIT; k++)
        if ((uint8_t)VTTS_KM_EXTRA_SPLIT[2 * k] == a && (uint8_t)VTTS_KM_EXTRA_SPLIT[2 * k + 1] == b) return 1;
    return 0;
}

static int takes_final(const km_syl_t *z, const sy_t *s, const cl_t *c) {
    if (s->final) return 0;
    if ((s->signs & 1) && !(s->signs & 0x1E) && BASE(c) == K_NGO && !c->nsubs) return 1; /* ends in ំ: ាំង */
    return !(s->signs & 7); /* ំ ះ ៈ */
}

static int closes(const km_syl_t *z, const sy_t *prev, const cl_t *cs, int n, int i) {
    const cl_t *c = &cs[i];
    const cl_t *nx = i + 1 < n ? &cs[i + 1] : NULL;
    if (c->robat || c->bantoc || !nx) return 1;
    if (c->nsubs) return 0;
    if (prev->nonset > 1 && !prev->nvowel) return 0;
    if (bare(z, nx) && !nx->nsubs && (nx->bantoc || i + 2 == n)) return 0;
    return !(nx->nsubs && pair_splits(z, nx));
}

static int syllables(const uint8_t *w, int n, km_syl_t *z) {
    cl_t *cs = z->cl;
    int nc0 = clusters(w, n, z), nc = 0;
    for (int k = 0; k < nc0; k++) if (!(cs[k].silent && !cs[k].nvowel)) cs[nc++] = cs[k];
    sy_t *out = z->sy;
    int m = 0;
    for (int i = 0; i < nc; i++) {
        const cl_t *c = &cs[i];
        sy_t *prev = m ? &out[m - 1] : NULL;
        if (prev && takes_final(z, prev, c)) {
            if (bare(z, c) && closes(z, prev, cs, nc, i)) {
                prev->final = c->robat ? 0xFF : BASE(c);
                prev->bantoc = c->bantoc;
                continue;
            }
            uint8_t v0 = c->nvowel == 1 ? z->vp[c->vat] : 0;
            if (i + 1 == nc && (v0 == K_I || v0 == K_U) && !c->nsubs && is_cons(BASE(c)) &&
                (prev->nvowel || prev->indep)) {
                prev->final = BASE(c);
                continue;
            }
        }
        sy_t *s = &out[m++];
        memset(s, 0, sizeof *s);
        s->vat = c->vat;
        s->nvowel = c->nvowel;
        s->signs = c->signs;
        if (is_indep(BASE(c))) {
            s->indep = BASE(c);
            s->final = c->nsubs ? SUB0(c) : 0;
            continue;
        }
        s->shift = c->shift;
        if (c->nsubs && prev && takes_final(z, prev, c) && ((!prev->nvowel && !prev->indep) || pair_splits(z, c))) {
            prev->final = BASE(c);
            s->oat = (uint16_t)(c->at + 1);
            s->nonset = c->nsubs;
            s->sub = 1;
        } else {
            s->oat = c->at;
            s->nonset = (uint16_t)(1 + c->nsubs);
        }
    }
    if (m) out[m - 1].last = 1;
    return m;
}

/* ======================= readings ======================= */

static int series(const km_syl_t *z, const sy_t *s) {
    if (!s->nonset) return 1;
    const uint8_t *o = z->lp + s->oat;
    int ob = (FL(o[0]) & VTTS_KM_SERIES_O) != 0;
    if (s->shift == 3) return ob ? 1 : 2;
    if (s->shift) return s->shift;
    uint8_t c = s->nonset > 1 && !(FL(o[1]) & VTTS_KM_SONORANT) ? o[1] : o[0];
    return (FL(c) & VTTS_KM_SERIES_O) ? 2 : 1;
}

static int fin_code(uint8_t final) {
    if (!final) return VTTS_KM_FIN_NONE;
    if (final == 0xFF) return VTTS_KM_FIN_ROBAT;
    return VTTS_KM_LETTERS[final - 1].fin;
}

static int cmp_bytes(const char *a, int la, const uint8_t *b, int lb) {
    int m = la < lb ? la : lb;
    for (int i = 0; i < m; i++)
        if ((uint8_t)a[i] != b[i]) return (uint8_t)a[i] < b[i] ? -1 : 1;
    return la < lb ? -1 : la > lb ? 1 : 0;
}

static const char *find_entry(const vtts_km_entry *t, int nt, const uint8_t *key, int lk) {
    int lo = 0, hi = nt - 1;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        int c = cmp_bytes(t[mid].key, (int)strlen(t[mid].key), key, lk);
        if (!c) return t[mid].ids;
        if (c < 0) lo = mid + 1; else hi = mid - 1;
    }
    return NULL;
}

static int put_ids(uint8_t *out, int n, int cap, const char *ids) {
    for (const char *p = ids; *p && n < cap; p++) out[n++] = (uint8_t)*p;
    return n;
}

static uint8_t lose_asp(uint8_t t) {
    return t == VTTS_KM_T_KH ? VTTS_KM_T_K : t == VTTS_KM_T_CH ? VTTS_KM_T_C : t == VTTS_KM_T_TH ? VTTS_KM_T_T
         : t == VTTS_KM_T_PH ? VTTS_KM_T_P : t;
}

static int onset_ids(const km_syl_t *z, const sy_t *s, uint8_t *out, int cap) {
    int n = 0;
    const uint8_t *o = z->lp + s->oat;
    if (!s->nonset) return 0;
    if (s->nonset > 1) {
        const char *ids = find_entry(VTTS_KM_ONSETS, VTTS_KM_N_ONSETS, o, s->nonset);
        if (ids) return put_ids(out, 0, cap, ids);
        for (int k = 0; k < VTTS_KM_N_LOAN; k++)
            if (VTTS_KM_LOAN[k].a == o[0] && VTTS_KM_LOAN[k].b == o[1]) {
                out[n++] = VTTS_KM_LOAN[k].tok;
                for (int q = 2; q < s->nonset && n < cap; q++) out[n++] = VTTS_KM_LETTERS[o[q] - 1].onset;
                return n;
            }
    }
    for (int k = 0; k < s->nonset && n < cap; k++) {
        uint8_t ch = o[k], p = VTTS_KM_LETTERS[ch - 1].onset;
        if (ch == K_BA && (s->shift == 1 || s->nonset > 1 || s->sub)) p = VTTS_KM_T_P;
        if (k + 1 < s->nonset) p = lose_asp(p);
        out[n++] = p;
    }
    return n;
}

#define MAX_KEY 40 /* longer keys (many vowel signs) are in no table */

static int rhyme_ids(const km_syl_t *z, const sy_t *s, uint8_t *out, int cap) {
    uint8_t key[MAX_KEY + 4];
    int lk = 0, fc = fin_code(s->final);
    const char *ids = NULL;
    if (s->nvowel < MAX_KEY - 4) {
        key[lk++] = (uint8_t)series(z, s);
        for (int k = 0; k < s->nvowel; k++) key[lk++] = z->vp[s->vat + k];
        if (s->bantoc) key[lk++] = 0x17CB - 0x1780 + 1;
        key[lk++] = (uint8_t)(0x60 + fc);
        key[lk] = s->last ? 0x78 : (!s->final && s->nonset > 1) ? 0x79 : 0x7A;
        ids = find_entry(VTTS_KM_RHYMES, VTTS_KM_N_RHYMES, key, lk + 1);
        static const uint8_t ORDER[3] = {0x7A, 0x78, 0x79}; /* m, e, c */
        for (int k = 0; k < 3 && !ids; k++) {
            key[lk] = ORDER[k];
            ids = find_entry(VTTS_KM_RHYMES, VTTS_KM_N_RHYMES, key, lk + 1);
        }
    }
    if (ids) return put_ids(out, 0, cap, ids);
    int n = 0;
    out[n++] = series(z, s) == 1 ? VTTS_KM_T_AA : VTTS_KM_T_OO;
    if (VTTS_KM_FIN_TOKEN[fc] && n < cap) out[n++] = VTTS_KM_FIN_TOKEN[fc];
    return n;
}

static int syllable_ids(const km_syl_t *z, const sy_t *s, uint8_t *out, int cap) {
    if (s->indep) {
        int n = put_ids(out, 0, cap, VTTS_KM_INDEP_IDS[s->indep - 1]);
        int fc = fin_code(s->final);
        if (VTTS_KM_FIN_TOKEN[fc] && n < cap) out[n++] = VTTS_KM_FIN_TOKEN[fc];
        return n;
    }
    int n = onset_ids(z, s, out, cap);
    return n + rhyme_ids(z, s, out + n, cap - n);
}

/* ======================= words ======================= */

typedef struct { int16_t a, b, c; uint8_t f, valid; } dp_t;

typedef struct {
    uint8_t codes[VTTS_KM_MAX_RUN + 1];
    int16_t ends[VTTS_KM_MAX_RUN + 1];
    uint8_t starts[VTTS_KM_MAX_RUN + 1];
    dp_t dp[VTTS_KM_MAX_RUN + 1];
    int16_t cuts[VTTS_KM_MAX_RUN + 2];
    int16_t dict[VTTS_KM_MAX_WORD + 1];
    km_syl_t z;
} km_scratch_t;

static int decode_word(int off, uint8_t *buf, int *len) {
    int p = VTTS_KM_WORDS[off++] & 0x7F;
    while (VTTS_KM_WORDS[off] < 0x80) buf[p++] = VTTS_KM_WORDS[off++];
    *len = p;
    return off;
}

static int cmp_codes(const uint8_t *a, int la, const uint8_t *b, int lb) {
    int m = la < lb ? la : lb;
    for (int i = 0; i < m; i++) if (a[i] != b[i]) return a[i] < b[i] ? -1 : 1;
    return la < lb ? -1 : la > lb ? 1 : 0;
}

static int lower_bound(const uint8_t *key, int lk, uint8_t *buf, int *len) {
    uint8_t tmp[VTTS_KM_MAX_WORD + 1];
    int lo = 0, hi = VTTS_KM_N_BLOCKS - 1, b = -1, lt;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        decode_word((int)VTTS_KM_BLOCKS[mid], tmp, &lt);
        if (cmp_codes(tmp, lt, key, lk) <= 0) { b = mid; lo = mid + 1; } else hi = mid - 1;
    }
    if (b < 0) { decode_word(0, buf, len); return 1; }
    int off = (int)VTTS_KM_BLOCKS[b];
    int end = b + 1 < VTTS_KM_N_BLOCKS ? (int)VTTS_KM_BLOCKS[b + 1] : VTTS_KM_WORDS_BYTES - 1;
    while (off < end) {
        off = decode_word(off, buf, len);
        if (cmp_codes(buf, *len, key, lk) >= 0) return 1;
    }
    if (b + 1 < VTTS_KM_N_BLOCKS) { decode_word((int)VTTS_KM_BLOCKS[b + 1], buf, len); return 1; }
    return 0;
}

/* lengths l (ascending) of the listed words run[i:i+l] */
static int dict_lengths(const uint8_t *run, int n, int i, int16_t *lens) {
    uint8_t buf[VTTS_KM_MAX_WORD + 1];
    int m = 0, len, lim = n - i < VTTS_KM_MAX_WORD ? n - i : VTTS_KM_MAX_WORD;
    for (int l = 1; l <= lim; l++) {
        if (!lower_bound(run + i, l, buf, &len)) break;
        if (len < l || memcmp(buf, run + i, (size_t)l) != 0) break;
        if (len == l) lens[m++] = (int16_t)l;
    }
    return m;
}

static void cluster_ends(const uint8_t *r, int n, int16_t *ends, uint8_t *starts) {
    for (int j = 0; j <= n; j++) starts[j] = 0;
    int i = 0;
    while (i < n) {
        int j = i + 1;
        if (is_cons(r[i]) || is_indep(r[i])) {
            while (j < n) {
                uint8_t x = r[j];
                if (x == K_COENG && j + 1 < n && is_cons(r[j + 1])) j += 2;
                else if (is_cons(x) || is_indep(x)) break;
                else if ((x >= 0x17B4 - 0x1780 + 1 && x <= 0x17D3 - 0x1780 + 1) || x == 0x17DD - 0x1780 + 1) j++;
                else break;
            }
        }
        ends[i] = (int16_t)j;
        starts[i] = 1;
        i = j;
    }
    starts[n] = 1;
}

/* segment(): cut points of the words of run (np + 1, ascending); returns np */
static int segment(km_scratch_t *t, const uint8_t *run, int n, int16_t *cuts) {
    dp_t *best = t->dp;
    cluster_ends(run, n, t->ends, t->starts);
    for (int j = 0; j <= n; j++) best[j].valid = 0;
    best[0].a = 0; best[0].b = 0; best[0].c = 0; best[0].f = 0; best[0].valid = 1;
    for (int i = 0; i < n; i++) {
        if (!best[i].valid || !t->starts[i]) continue;
        int unk = best[i].a, cnt = best[i].b;
        int nl = dict_lengths(run, n, i, t->dict);
        for (int q = nl - 1; q >= -1; q--) { /* listed words, longest first, then the cluster */
            int j, u;
            if (q >= 0) {
                j = i + t->dict[q];
                if (!t->starts[j]) continue;
                u = 0;
            } else {
                j = t->ends[i];
                u = j - i;
            }
            int a = unk + u, b = cnt + 1;
            if (!best[j].valid || a < best[j].a || (a == best[j].a && b < best[j].b)) {
                best[j].a = (int16_t)a; best[j].b = (int16_t)b; best[j].c = (int16_t)i; best[j].f = u > 0; best[j].valid = 1;
            }
        }
    }
    /* back to front; consecutive pieces outside the list become one */
    int nc = 0, j = n;
    int16_t *tmp = t->cuts;
    uint8_t lastu = 0;
    tmp[nc++] = (int16_t)n;
    while (j > 0) {
        int i = best[j].c;
        uint8_t u = best[j].f;
        if (nc > 1 && u && lastu) tmp[nc - 1] = (int16_t)i;
        else tmp[nc++] = (int16_t)i;
        lastu = u;
        j = i;
    }
    for (int k = 0; k < nc; k++) cuts[k] = tmp[nc - 1 - k];
    return nc - 1;
}

typedef struct { vtts_km_syl_cb cb; void *user; int count; km_scratch_t *t; } km_ctx_t;

static void emit(km_ctx_t *c, const uint8_t *ids, int n) {
    if (n <= 0) return;
    c->cb(c->user, ids, n);
    c->count++;
}

static void read_word(km_ctx_t *c, const uint8_t *w, int n) {
    const char *ov = find_entry(VTTS_KM_OVERRIDES, VTTS_KM_N_OVERRIDES, w, n);
    uint8_t ids[160];
    if (ov) {
        int k = 0;
        for (const char *p = ov;; p++) {
            if (*p == 0 || (uint8_t)*p == 0xFF) {
                emit(c, ids, k);
                k = 0;
                if (!*p) break;
                continue;
            }
            if (k < (int)sizeof ids) ids[k++] = (uint8_t)*p;
        }
        return;
    }
    km_syl_t *z = &c->t->z;
    int ns = syllables(w, n, z);
    for (int k = 0; k < ns; k++) emit(c, ids, syllable_ids(z, &z->sy[k], ids, (int)sizeof ids));
}

static void read_piece(km_ctx_t *c, const uint8_t *r, int n, int *lw, int *ln) {
    int16_t cuts[VTTS_KM_MAX_RUN + 2];
    int np = segment(c->t, r, n, cuts);
    for (int k = 0; k < np; k++) {
        read_word(c, r + cuts[k], cuts[k + 1] - cuts[k]);
        *lw = (int)(r - c->t->codes) + cuts[k];
        *ln = cuts[k + 1] - cuts[k];
    }
}

static int dec_utf8(const char **ps, uint32_t *c) {
    const unsigned char *p = (const unsigned char *)*ps;
    if (!*p) return 0;
    int extra = *p < 0x80 ? 0 : (*p >> 5) == 6 ? 1 : (*p >> 4) == 14 ? 2 : 3;
    uint32_t v = extra ? (*p & (0x3Fu >> extra)) : *p;
    for (int k = 1; k <= extra; k++) {
        if (!p[k]) { *ps = (const char *)(p + k); *c = 0; return 1; }
        v = (v << 6) | (p[k] & 0x3F);
    }
    *ps = (const char *)(p + 1 + extra);
    *c = v;
    return 1;
}

int vtts_km_read(const char *utf8, void *scratch, size_t size, vtts_km_syl_cb cb, void *user) {
    if (!utf8 || !scratch || size < sizeof(km_scratch_t) || !cb) return -1;
    km_ctx_t c = {cb, user, 0, (km_scratch_t *)scratch};
    km_scratch_t *t = c.t;
    const char *p = utf8;
    uint32_t cp;
    int lw = -1, ln = 0; /* the last word (ៗ repeats it) */
    while (*p) {
        int n = 0;
        while (n < VTTS_KM_MAX_RUN && dec_utf8(&p, &cp)) {
            if (cp >= 0x1780 && cp < 0x1780 + 128) t->codes[n++] = (uint8_t)(cp - 0x1780 + 1);
        }
        n = spell(t->codes, n);
        int a = 0;
        for (int i = 0; i <= n; i++) {
            if (i < n && t->codes[i] != K_REPEAT) continue;
            if (i > a) read_piece(&c, t->codes + a, i - a, &lw, &ln);
            if (i < n && lw >= 0) read_word(&c, t->codes + lw, ln);
            a = i + 1;
        }
        lw = -1; /* the codes of a next piece overwrite the buffer */
    }
    return c.count;
}

/* ======================= normalization (normalize_km) ======================= */

static int km_letter(uint32_t c) { return c >= 0x1780 && c < 0x1800 && (VTTS_KM_LETTERS[c - 0x1780].flags & VTTS_KM_LETTER); }
static int km_word(uint32_t c) {
    if (c >= 0x1780 && c < 0x1800) return (VTTS_KM_LETTERS[c - 0x1780].flags & VTTS_KM_WORD) != 0;
    return -1;
}

static int km_pre(const uint32_t *in, int n, vtts_nsp_buf *d, vtts_nsp_buf *tmp) { /* zero-width spaces dropped */
    (void)tmp;
    for (int i = 0; i < n; i++) {
        uint32_t c = in[i];
        if (c == 0x200B || c == 0x200C || c == 0x200D || c == 0x2060 || c == 0xFEFF) continue;
        vtts_nsp_put(d, c);
    }
    return d->err ? -1 : 0;
}

static void km_below_million(vtts_nsp_buf *d, int v) {
    static const int PL[4] = {100000, 10000, 1000, 100};
    for (int k = 0; k < 4; k++) {
        int dg = v / PL[k];
        v %= PL[k];
        if (dg) { vtts_nsp_put_utf8(d, VTTS_KM_DIGITS[dg]); vtts_nsp_put_utf8(d, VTTS_KM_PLACES[k]); }
    }
    vtts_nsp_put_utf8(d, VTTS_KM_TENS[v / 10]);
    if (v % 10) vtts_nsp_put_utf8(d, VTTS_KM_DIGITS[v % 10]);
}

static void km_date(const vtts_nsp_spec *sp, vtts_nsp_buf *d, int day, int month, const uint32_t *y, int ny) {
    vtts_nsp_put_utf8(d, "ថ្ងៃទី");
    vtts_nsp_cardinal_i(sp, d, day);
    vtts_nsp_put_utf8(d, "ខែ");
    vtts_nsp_put_utf8(d, VTTS_KM_MONTHS[month]);
    vtts_nsp_put_utf8(d, "ឆ្នាំ");
    if (ny == 4) vtts_nsp_cardinal_u(sp, d, y, ny);
    else vtts_nsp_digits(sp, d, y, ny);
}

static void km_time(const vtts_nsp_spec *sp, vtts_nsp_buf *d, int h, int m, int s) {
    vtts_nsp_put_utf8(d, "ម៉ោង");
    vtts_nsp_cardinal_i(sp, d, h);
    if (m) { vtts_nsp_cardinal_i(sp, d, m); vtts_nsp_put_utf8(d, "នាទី"); }
    if (s) { vtts_nsp_cardinal_i(sp, d, s); vtts_nsp_put_utf8(d, "វិនាទី"); }
}

static const vtts_nsp_spec KM_SPEC = {
    km_letter, km_word, 0x17E0, km_pre, km_below_million, VTTS_KM_MILLION, VTTS_KM_DIGITS,
    VTTS_KM_POINT, VTTS_KM_MINUS, VTTS_KM_TO, VTTS_KM_PERCENT,
    VTTS_KM_CURRENCY, VTTS_KM_N_CURRENCY, VTTS_KM_UNITS, VTTS_KM_N_UNITS, VTTS_KM_ABBREV, VTTS_KM_N_ABBREV,
    VTTS_KM_PUNCT, VTTS_KM_N_PUNCT, VTTS_KM_SYMBOLS, km_date, km_time, 0x17D7, 1, VTTS_KM_DEDUPE, VTTS_KM_N_DEDUPE,
};

int vtts_km_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, uint32_t *ea,
                      uint32_t *eb, int ecap, char *eout, int eout_cap, const uint32_t **out) {
    return vtts_nsp_normalize(&KM_SPEC, in, n, a, b, cap, ea, eb, ecap, eout, eout_cap, out);
}

#else
typedef int vtts_text_km_unused;
#endif
