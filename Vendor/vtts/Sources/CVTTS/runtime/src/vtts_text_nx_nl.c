/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_nx_nl.c -- Dutch device front-end (token set nl-en): the number words of
 * nl/normalize_nl.py and the spelling rules of nl/g2p_nl.py, step by step, with the valid_spelling
 * check of the tagger. Tables: vtts_text_nx_tables.h (generated). Only with VTTS_ENABLE_NL. */
#include "vtts_text_nx.h"

#if VTTS_ENABLE_NL

#include <string.h>

#include "vtts_text_nx_int.h"
#include "vtts_text_nx_tables.h"

/* ======================= numbers (normalize_nl) ======================= */

static void below_100(nx_buf *b, int n) { /* concatenated to the current word */
    if (n < 20) { nx_cat(b, VTTS_NL_ONES[n]); return; }
    int t = n / 10, u = n % 10;
    if (!u) { nx_cat(b, VTTS_NL_TENS[t]); return; }
    const char *unit = VTTS_NL_ONES[u];
    nx_cat(b, unit);
    nx_cat(b, unit[strlen(unit) - 1] == 'e' ? "\xc3\xab" "n" : "en"); /* ën after e */
    nx_cat(b, VTTS_NL_TENS[t]);
}

static void below_1000(nx_buf *b, int n) {
    int h = n / 100, r = n % 100;
    if (h) { if (h != 1) nx_cat(b, VTTS_NL_ONES[h]); nx_cat(b, "honderd"); }
    if (r) below_100(b, r);
}

static void below_million(nx_buf *b, int n) {
    int th = n / 1000, r = n % 1000;
    if (th) { if (th != 1) below_1000(b, th); nx_cat(b, "duizend"); }
    if (r) below_1000(b, r);
}

static void cardinal(nx_buf *b, uint64_t n) {
    static const uint64_t S[3] = {1000000000000ull, 1000000000ull, 1000000ull};
    if (b->n) nx_cat(b, " ");
    if (n == 0) { nx_cat(b, "nul"); return; }
    if (n == 1) { nx_cat(b, "\xc3\xa9\xc3\xa9n"); return; }
    int first = 1;
    for (int k = 0; k < 3; k++) {
        uint64_t q = n / S[k];
        n %= S[k];
        if (!q) continue;
        if (!first) nx_cat(b, " ");
        /* cardinal(q) + " " + name; q < 1000 here except for 10**12 */
        nx_buf t = {b->p + b->n, 0, b->cap - b->n, 0};
        cardinal(&t, q);
        b->n += t.n;
        b->err |= t.err;
        nx_cat(b, " ");
        nx_cat(b, VTTS_NL_SCALES[k]);
        first = 0;
    }
    if (n) { if (!first) nx_cat(b, " "); below_million(b, (int)n); }
}

static void year(nx_buf *b, int n) {
    if (b->n) nx_cat(b, " ");
    below_100(b, n / 100);
    nx_cat(b, "honderd");
    if (n % 100) below_100(b, n % 100);
}

static int ends_with(const char *s, int len, const char *e) {
    int l = (int)strlen(e);
    return len >= l && memcmp(s + len - l, e, (size_t)l) == 0;
}

static void ordinal(nx_buf *b, uint64_t n) {
    char tmp[512];
    nx_buf t = {tmp, 0, (int)sizeof tmp, 0};
    tmp[0] = 0;
    cardinal(&t, n);
    int l = t.n;
    if (ends_with(tmp, l, "\xc3\xa9\xc3\xa9n")) { l -= 5; memcpy(tmp + l, "een", 4); l += 3; }
    tmp[l] = 0;
    static const char *const E[4][2] = {{"een", "eerste"}, {"twee", "tweede"}, {"drie", "derde"}, {"acht", "achtste"}};
    for (int k = 0; k < 4; k++) {
        int el = (int)strlen(E[k][0]);
        char tien[16];
        strcpy(tien, "tien");
        strcat(tien, E[k][0]);
        if (ends_with(tmp, l, E[k][0]) && !ends_with(tmp, l, tien)) {
            tmp[l - el] = 0;
            nx_word(b, tmp);
            nx_cat(b, E[k][1]);
            return;
        }
    }
    nx_word(b, tmp);
    if (ends_with(tmp, l, "tig") || ends_with(tmp, l, "honderd") || ends_with(tmp, l, "duizend") ||
        ends_with(tmp, l, "joen") || ends_with(tmp, l, "jard"))
        nx_cat(b, "ste");
    else nx_cat(b, "de");
}

static void date(nx_buf *b, int d, int m, int64_t y) {
    cardinal(b, (uint64_t)d);
    nx_word(b, VTTS_NL_MONTHS[m]);
    if (y >= 0) {
        if (y >= 1100 && y <= 1999) year(b, (int)y);
        else cardinal(b, (uint64_t)y);
    }
}

static void time_(nx_buf *b, int h, int mi, int sec) {
    cardinal(b, (uint64_t)h);
    nx_word(b, "uur");
    if (mi) cardinal(b, (uint64_t)mi);
    if (sec > 0) {
        nx_word(b, "en");
        cardinal(b, (uint64_t)sec);
        nx_word(b, sec == 1 ? "seconde" : "seconden");
    }
}

/* ======================= g2p (g2p_nl) ======================= */

#define MAXW VTTS_NX_MAXW
#define MAXP (4 * MAXW + 64)

typedef struct {
    char kind;          /* 'V' or 'C' */
    uint8_t v;          /* V: fixed vowel id (0: a single vowel letter, by the rules) */
    uint32_t letter;    /* V: the base letter */
    uint8_t glide;      /* V: a glide id after the vowel (0: none) */
    uint8_t acc;        /* V: accented */
    uint8_t gl;         /* grapheme length (letters) */
    uint32_t g[4];      /* grapheme (V: the table spelling, or the letter as written) */
    uint8_t ph[2], nph; /* C: phonemes */
} seg_t;

typedef struct {
    seg_t seg[MAXW + 4];
    int nuc[MAXW + 4];
    uint8_t out[MAXP], res[MAXP];
    uint32_t w[MAXW + 4], wd[MAXW + 4], plain[MAXW + 4], rest[MAXW + 4];
    char w8[4 * MAXW + 8];
} nl_scratch;

typedef char nl_scratch_fits[sizeof(nl_scratch) + 8 <= VTTS_NX_SCRATCH ? 1 : -1];

static uint32_t fold1(uint32_t c) {
    if (c < 0x80) return c >= 'a' && c <= 'z' ? c : c >= 'A' && c <= 'Z' ? c + 32 : 0;
    int lo = 0, hi = VTTS_NL_N_FOLD - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2;
        const vtts_nx_fold *r = &VTTS_NL_FOLD[m];
        if (c < r->start) hi = m - 1;
        else if (c >= r->start + r->count) lo = m + 1;
        else return r->first + (c - r->start) * r->step;
    }
    return 0;
}

static int g_eq(const seg_t *s, const char *k) { return nx_eq_u8(s->g, s->gl, k); }

static int in_list_cp(const char *const *list, int n, const uint32_t *w, int len) {
    for (int k = 0; k < n; k++) if (nx_eq_u8(w, len, list[k])) return 1;
    return 0;
}

static int starts(const uint32_t *w, int n, int i, const char *k) { return nx_at_u8(w, n, i, k) > 0; }

static int ends_plain(const uint32_t *w, int n, const char *k) { /* w.endswith(k) */
    int m = nx_u8_len(k);
    return n >= m && (m == 0 || nx_at_u8(w, n, n - m, k) == m);
}

static int ends_strict(const uint32_t *w, int n, const char *k) { return nx_ends_u8(w, n, k); }

static int segments(const uint32_t *w, int n, seg_t *out, uint32_t *plain) {
    int ns = 0, i = 0;
    for (int k = 0; k < n; k++) {
        int a = nx_index_u8(w[k], VTTS_NL_ACCENTED);
        uint32_t base = w[k];
        if (a >= 0) {
            const char *p = VTTS_NL_ACCENTED_BASE;
            uint32_t c;
            for (int q = 0; q <= a; q++) p += nx_dec1(p, &c);
            base = c;
        }
        plain[k] = base;
    }
    while (i < n) {
        seg_t *s = &out[ns];
        memset(s, 0, sizeof *s);
        int hit = 0;
        for (int k = 0; k < VTTS_NL_N_VGRAPH; k++) {
            int m = nx_at_u8(plain, n, i, VTTS_NL_VGRAPH[k].g);
            if (!m) continue;
            s->kind = 'V';
            s->v = VTTS_NL_VGRAPH[k].v;
            s->letter = plain[i];
            s->glide = VTTS_NL_VGRAPH[k].glide;
            for (int q = i; q < i + m; q++) s->acc |= nx_in_u8(w[q], VTTS_NL_ACCENTED);
            s->gl = (uint8_t)m;
            for (int q = 0; q < m; q++) s->g[q] = plain[i + q];
            i += m;
            ns++;
            hit = 1;
            break;
        }
        if (hit) continue;
        uint32_t c = w[i];
        if (nx_in_u8(c, VTTS_NL_SINGLE_VOWELS)) {
            if (c == 'y' && i + 1 < n && nx_in_u8(w[i + 1], "aeiou") && i == 0) {
                s->kind = 'C'; s->ph[0] = NL_j; s->nph = 1; s->gl = 1; s->g[0] = 'y';
            } else {
                s->kind = 'V';
                int a = nx_index_u8(c, VTTS_NL_ACCENTED), d = nx_index_u8(c, VTTS_NL_DIAERESIS);
                uint32_t base = c, x;
                if (a >= 0) { const char *p = VTTS_NL_ACCENTED_BASE; for (int q = 0; q <= a; q++) p += nx_dec1(p, &x); base = x; s->acc = 1; }
                else if (d >= 0) { const char *p = VTTS_NL_DIAERESIS_BASE; for (int q = 0; q <= d; q++) p += nx_dec1(p, &x); base = x; }
                s->letter = base;
                s->gl = 1;
                s->g[0] = c;
            }
            i++;
            ns++;
            continue;
        }
        if (c == 't' && starts(w, n, i, "tio") && i > 0) {
            s->kind = 'C'; s->ph[0] = NL_S; s->nph = 1; s->gl = 2; s->g[0] = 't'; s->g[1] = 'i';
            i += 2; ns++;
            continue;
        }
        if (c == 'n' && starts(w, n, i, "nge") &&
            (starts(w, n, 0, "aange") || starts(w, n, 0, "onge") || starts(w, n, 0, "inge")) && i >= 1 && i <= 3 &&
            (nx_eq_u8(w, i + 1, "aan") || nx_eq_u8(w, i + 1, "on") || nx_eq_u8(w, i + 1, "in"))) {
            s->kind = 'C'; s->ph[0] = NL_n; s->nph = 1; s->gl = 1; s->g[0] = 'n';
            i++; ns++;
            continue;
        }
        for (int k = 0; k < VTTS_NL_N_CGRAPH; k++) {
            int m = nx_at_u8(w, n, i, VTTS_NL_CGRAPH[k].g);
            if (!m) continue;
            s->kind = 'C';
            s->ph[0] = VTTS_NL_CGRAPH[k].ph[0];
            s->ph[1] = VTTS_NL_CGRAPH[k].ph[1];
            s->nph = VTTS_NL_CGRAPH[k].n;
            s->gl = (uint8_t)m;
            for (int q = 0; q < m; q++) s->g[q] = w[i + q];
            i += m;
            ns++;
            hit = 1;
            break;
        }
        if (hit) continue;
        if (c == 'c') {
            s->kind = 'C';
            if (i + 1 < n && w[i + 1] == 'c') {
                int front = i + 2 < n && nx_in_u8(w[i + 2], VTTS_NL_FRONT);
                s->ph[0] = NL_k; s->nph = 1;
                if (front) { s->ph[1] = NL_s; s->nph = 2; }
                s->gl = 2; s->g[0] = s->g[1] = 'c';
                i += 2; ns++;
                continue;
            }
            s->ph[0] = i + 1 < n && nx_in_u8(w[i + 1], VTTS_NL_FRONT) ? NL_s : NL_k;
            s->nph = 1; s->gl = 1; s->g[0] = 'c';
            i++; ns++;
            continue;
        }
        int sk = -1;
        for (int k = 0; k < VTTS_NL_N_SINGLE; k++) if (VTTS_NL_SINGLE[k].c == c) { sk = k; break; }
        if (sk < 0) { i++; continue; }
        s->kind = 'C';
        s->ph[0] = VTTS_NL_SINGLE[sk].id;
        s->nph = 1;
        if (i + 1 < n && w[i + 1] == c) { s->gl = 2; s->g[0] = s->g[1] = c; i += 2; }
        else { s->gl = 1; s->g[0] = c; i++; }
        ns++;
    }
    return ns;
}

static int in_closing(const seg_t *s) {
    for (int k = 0; k < (int)(sizeof VTTS_NL_CLOSING / sizeof *VTTS_NL_CLOSING); k++) if (g_eq(s, VTTS_NL_CLOSING[k])) return 1;
    return 0;
}

static int is_open(const seg_t *segs, int ns, int k) {
    int j = k + 1;
    if (j >= ns || segs[j].kind == 'V') return 1;
    const seg_t *c1 = &segs[j];
    if (j + 1 >= ns) return 0;
    if (segs[j + 1].kind == 'V')
        return (c1->gl == 1 && !in_closing(c1)) || g_eq(c1, "th") || g_eq(c1, "ph") || g_eq(c1, "ti");
    const seg_t *c2 = &segs[j + 1];
    return c1->gl == 1 && nx_in_u8(c1->g[0], VTTS_NL_OBSTRUENTS) && c2->gl == 1 && nx_in_u8(c2->g[0], VTTS_NL_LIQUIDS) &&
           j + 2 < ns && segs[j + 2].kind == 'V';
}

static int seg_start(const seg_t *segs, int k) {
    int p = 0;
    for (int q = 0; q < k; q++) p += segs[q].gl;
    return p;
}

static int nucleus_starting(const seg_t *segs, const int *nuc, int nn, int pos) {
    for (int q = 0; q < nn; q++) if (seg_start(segs, nuc[q]) == pos) return nuc[q];
    return -1;
}

/* _stress over the de-diaeresised word wd */
static int stress_of(const uint32_t *wd, int n, const seg_t *segs, const int *nuc, int nn) {
    if (!nn) return -1;
    for (int q = 0; q < nn; q++) if (segs[nuc[q]].acc) return nuc[q];
    if (nn == 1) return nuc[0];
    for (int f = -1; f < VTTS_NL_N_INFLECTIONS; f++) {
        int sl = n;
        if (f >= 0) {
            if (!ends_plain(wd, n, VTTS_NL_INFLECTIONS[f])) continue;
            sl = n - nx_u8_len(VTTS_NL_INFLECTIONS[f]);
        }
        for (int k = 0; k < VTTS_NL_N_STRESSED_ENDINGS; k++) {
            const char *e = VTTS_NL_STRESSED_ENDINGS[k].e;
            int el = nx_u8_len(e);
            if (!(sl > el && nx_at_u8(wd, sl, sl - el, e) == el)) continue;
            if (!strcmp(e, "ent")) {
                int un = 0;
                for (int q = 0; q < VTTS_NL_N_UNSTRESSED_ENT; q++) un |= ends_plain(wd, sl, VTTS_NL_UNSTRESSED_ENT[q]);
                if (un && !ends_plain(wd, sl, "dent") && !ends_plain(wd, sl, "gent")) continue;
            }
            int pos = nucleus_starting(segs, nuc, nn, sl - el + VTTS_NL_STRESSED_ENDINGS[k].off);
            if (pos >= 0) return pos;
        }
    }
    if (ends_plain(wd, n, "ie") && n > 3 && nx_in_u8(wd[n - 3], "rgfkmdpb") && g_eq(&segs[nuc[nn - 1]], "ie"))
        return nuc[nn - 1];
    for (int k = 0; k < VTTS_NL_N_EER_FORMS; k++) {
        int el = nx_u8_len(VTTS_NL_EER_FORMS[k]);
        if (ends_plain(wd, n, VTTS_NL_EER_FORMS[k]) && n > el + 1) {
            int pos = nucleus_starting(segs, nuc, nn, n - el);
            if (pos >= 0) return pos;
        }
    }
    if (ends_plain(wd, n, "eren") && nn >= 3) {
        int k = n - 4;
        if (k >= 2 && !nx_in_u8(wd[k - 1], "aeiouy") && nx_in_u8(wd[k - 2], "aeiouy")) {
            int pos = nucleus_starting(segs, nuc, nn, k);
            if (pos >= 0) return pos;
        }
    }
    for (int k = 0; k < VTTS_NL_N_PRESTRESS_ENDINGS; k++) {
        const char *e = VTTS_NL_PRESTRESS_ENDINGS[k];
        if (!ends_strict(wd, n, e)) continue;
        int lim = n - nx_u8_len(e), best = -1;
        for (int q = 0; q < nn; q++) if (seg_start(segs, nuc[q]) < lim) best = nuc[q];
        if (best >= 0) return best;
        break;
    }
    return nuc[0];
}

static int ls_index(uint32_t letter) { return nx_index_u8(letter, VTTS_NL_LS_LETTERS); }

static int schwa_coda(const seg_t *segs, int ns, int k) {
    int j = k + 1, ng = 0, gidx[MAXW];
    while (j < ns && segs[j].kind == 'C') {
        const seg_t *g = &segs[j];
        if (g->gl == 2 && g->g[0] == g->g[1]) return 0;
        gidx[ng++] = j;
        j++;
    }
    char cat[4 * MAXW + 4];
    if (j == ns) {
        int c = 0;
        for (int q = 0; q < ng && c < (int)sizeof cat - 8; q++)
            for (int r = 0; r < segs[gidx[q]].gl; r++) c += nx_encode(segs[gidx[q]].g[r], cat + c);
        cat[c] = 0;
        return nx_in_sorted(VTTS_NL_SCHWA_CODAS, VTTS_NL_N_SCHWA_CODAS, cat);
    }
    if (ng <= 1) return 1;
    int onset = 1;
    for (int m = 3; m >= 2; m--) {
        if (ng < m) continue;
        int c = 0;
        for (int q = ng - m; q < ng; q++)
            for (int r = 0; r < segs[gidx[q]].gl; r++) c += nx_encode(segs[gidx[q]].g[r], cat + c);
        cat[c] = 0;
        if (nx_in_sorted(VTTS_NL_ONSETS, VTTS_NL_N_ONSETS, cat)) { onset = m; break; }
    }
    int nc = ng - onset;
    if (nc == 0) return 1;
    if (nc != 1) return 0;
    const seg_t *c0 = &segs[gidx[0]];
    return g_eq(c0, "n") || g_eq(c0, "r") || g_eq(c0, "l") || g_eq(c0, "m");
}

static int ig_at(const seg_t *segs, int ns, int k) {
    static const char *const R[] = {"g", "ge", "gs", "gen", "gheid", "gheden", "ger", "gst", "gste"};
    uint32_t rest[MAXW + 8];
    int m = 0;
    for (int q = k + 1; q < ns; q++)
        for (int r = 0; r < segs[q].gl && m < MAXW + 4; r++) rest[m++] = segs[q].g[r];
    if (!(segs[k].gl == 1 && segs[k].g[0] == 'i')) return 0;
    for (size_t q = 0; q < sizeof R / sizeof *R; q++) if (nx_eq_u8(rest, m, R[q])) return 1;
    return 0;
}

static uint8_t single_vowel(const uint32_t *w, int n, const seg_t *segs, int ns, const int *nuc, int nn, int k,
                            uint32_t letter, int stress) {
    int open = is_open(segs, ns, k) && !(k == 0 && (starts(w, n, 0, "opl") || starts(w, n, 0, "opr")));
    int li = ls_index(letter);
    if (letter == 'e' && segs[k].gl == 1 && segs[k].g[0] == 0xEB /* ë */ && !open && stress != k) return NL_AT;
    if (stress == k || (stress < 0 && nn == 1 && letter != 'e')) return open ? VTTS_NL_LONG[li] : VTTS_NL_SHORT[li];
    if (letter == 'e') {
        if (k == ns - 1) return NL_AT;
        if (stress < 0) return nn == 1 && open ? NL_AT : (nn == 1 ? NL_E : NL_AT);
        if (k > stress) return schwa_coda(segs, ns, k) ? NL_AT : NL_E;
        if (open) {
            int q = 0;
            while (q < nn && nuc[q] != k) q++;
            return nuc[q + 1] == stress ? NL_AT : NL_eL;
        }
        return NL_E;
    }
    if (letter == 'i' && k > (stress < 0 ? 0 : stress) && ig_at(segs, ns, k)) return NL_AT;
    if (letter == 'i' && k + 1 < ns && g_eq(&segs[k + 1], "sch") &&
        (k + 2 == ns || (k + 3 == ns && segs[k + 2].gl == 1 && segs[k + 2].g[0] == 'e')))
        return NL_i;
    return open ? VTTS_NL_LONG[li] : VTTS_NL_SHORT[li];
}

static int is_vowel_id(uint8_t p) { return p >= 107 && VTTS_NL_IS_VOWEL[p - 107]; }
static uint8_t unstress(uint8_t p) { /* "a:1" -> "a:" */
    for (int k = 0; k < VTTS_NLEN_VOCAB - 107; k++) if (VTTS_NL_STRESSED[k] == p) return (uint8_t)(107 + k);
    return p;
}
static int is_stressed_id(uint8_t p) { return unstress(p) != p; }
static uint8_t stressed(uint8_t p) { uint8_t s = VTTS_NL_STRESSED[p - 107]; return s ? s : p; }

static int find_lijk(const uint8_t *out, int no) {
    for (int j = no - 3; j >= 0; j--)
        if (out[j] == NL_l && unstress(out[j + 1]) == NL_Ei && out[j + 2] == NL_k) return j + 1;
    return -1;
}

static int is_voiceless(uint8_t p) {
    for (int k = 0; k < VTTS_NL_N_VOICELESS; k++) if (VTTS_NL_VOICELESS[k] == p) return 1;
    return 0;
}

static int finish(const uint32_t *w, int n, uint8_t *out, int no, uint8_t *res) {
    static const char *const LIJK[] = {"lijk", "lijke", "lijks", "lijker", "lijkheid", "lijkheden"};
    for (size_t e = 0; e < sizeof LIJK / sizeof *LIJK; e++) {
        if (ends_strict(w, n, LIJK[e])) {
            int idx = find_lijk(out, no);
            if (idx >= 0) out[idx] = NL_AT;
            break;
        }
    }
    static const char *const TIE[] = {"tie", "ties"};
    for (int e = 0; e < 2; e++) {
        int el = (int)strlen(TIE[e]);
        if (ends_plain(w, n, TIE[e]) && n > el + 1) {
            int j = no - (e == 0 ? 2 : 3);
            if (j >= 0 && out[j] == NL_t && unstress(out[j + 1]) == NL_i) {
                if (nx_in_u8(w[n - el - 1], "aeiouy")) {
                    if (no < MAXP - 1) { memmove(out + j + 2, out + j + 1, (size_t)(no - j - 1)); out[j + 1] = NL_s; no++; }
                } else out[j] = NL_s;
            }
            break;
        }
    }
    if (ends_plain(w, n, "age") && no >= 3 && out[no - 2] == NL_x && n > 4) out[no - 2] = NL_Z;
    for (int j = 0; j < no; j++) {
        for (int k = 0; k < VTTS_NL_N_DEVOICE; k++)
            if (out[j] == VTTS_NL_DEVOICE[k][0] && (j == no - 1 || is_voiceless(out[j + 1]))) { out[j] = VTTS_NL_DEVOICE[k][1]; break; }
    }
    int nr = 0;
    for (int j = 0; j < no; j++) {
        uint8_t p = out[j];
        if (nr && p == res[nr - 1] && !is_vowel_id(p)) continue;
        res[nr++] = p;
    }
    return nr;
}

static int in_ch_s(const uint32_t *w, int n) { return nx_in_sorted_cp(VTTS_NL_CH_S, VTTS_NL_N_CH_S, w, n); }
static int is_function(const uint32_t *w, int n) { return nx_in_sorted_cp(VTTS_NL_FUNCTION_WORDS, VTTS_NL_N_FUNCTION_WORDS, w, n); }

/* _rules: phonemes of a word (stressed: mark the stressed vowel) into res; returns the count */
static int rules(nl_scratch *x, const uint32_t *w, int n, uint8_t *res) {
    seg_t *segs = x->seg;
    int ns = segments(w, n, segs, x->plain), nn = 0;
    for (int k = 0; k < ns; k++) if (segs[k].kind == 'V') x->nuc[nn++] = k;
    for (int k = 0; k < n; k++) {
        int d = nx_index_u8(w[k], VTTS_NL_DIAERESIS);
        uint32_t c = w[k];
        if (d >= 0) { const char *p = VTTS_NL_DIAERESIS_BASE; for (int q = 0; q <= d; q++) p += nx_dec1(p, &c); }
        x->wd[k] = c;
    }
    int stress = stress_of(x->wd, n, segs, x->nuc, nn);
    if (nn == 1 && is_function(w, n)) stress = -1;
    int last_c = ns - 1;
    while (last_c >= 0 && segs[last_c].kind != 'C') last_c--;
    int no = 0;
    uint8_t *out = x->out;
    for (int k = 0; k < ns && no < MAXP - 4; k++) {
        const seg_t *s = &segs[k];
        if (s->kind == 'C') {
            uint8_t ph[2] = {s->ph[0], s->ph[1]};
            int nph = s->nph;
            if (g_eq(s, "sch") && (k == ns - 1 || (k == ns - 2 && segs[ns - 1].kind == 'V' && segs[ns - 1].letter == 'e'))) {
                ph[0] = NL_s; nph = 1;
            }
            if (g_eq(s, "ch") && k == 0 && in_ch_s(w, n)) { ph[0] = NL_S; nph = 1; }
            if (g_eq(s, "g") && (ends_plain(w, n, "gie") || ends_plain(w, n, "gie\xc3\xabn") || ends_plain(w, n, "gies")) &&
                k == last_c && !(ends_plain(w, n, "logie") || ends_plain(w, n, "logie\xc3\xabn") || ends_plain(w, n, "logies"))) {
                ph[0] = NL_Z; nph = 1;
            }
            if (g_eq(s, "n") && k + 1 < ns && segs[k + 1].kind == 'C' && segs[k + 1].ph[0] == NL_k) { ph[0] = NL_N; nph = 1; }
            for (int q = 0; q < nph; q++) out[no++] = ph[q];
            continue;
        }
        uint8_t v = s->v;
        if (!v) v = single_vowel(w, n, segs, ns, x->nuc, nn, k, s->letter, stress);
        out[no++] = k == stress && v != NL_AT ? stressed(v) : v;
        if (s->glide) out[no++] = s->glide;
    }
    return finish(w, n, out, no, res);
}

static int mark_first(uint8_t *ph, int n) {
    for (int j = 0; j < n; j++) if (is_vowel_id(ph[j]) && ph[j] != NL_AT) { ph[j] = stressed(ph[j]); break; }
    return n;
}

static int any_stressed(const uint8_t *ph, int n) {
    for (int j = 0; j < n; j++) if (is_stressed_id(ph[j])) return 1;
    return 0;
}

static int merge(const uint8_t *in, int n, uint8_t *out) {
    int m = 0;
    for (int j = 0; j < n; j++) {
        if (m && in[j] == out[m - 1] && !is_vowel_id(unstress(in[j]))) continue;
        out[m++] = in[j];
    }
    return m;
}

/* _number_split: morph indices into parts (0: not a number word) */
static int number_split(const uint32_t *w, int n, int *parts) {
    static int16_t prev[MAXW + 1], morph[MAXW + 1];
    static uint8_t have[MAXW + 1];
    memset(have, 0, (size_t)(n + 1));
    have[0] = 1;
    for (int i = 0; i < n; i++) {
        if (!have[i]) continue;
        for (int k = 0; k < VTTS_NL_N_NUMBER_MORPHS; k++) {
            int m = nx_at_u8(w, n, i, VTTS_NL_NUMBER_MORPHS[k]);
            if (m && !have[i + m]) { have[i + m] = 1; prev[i + m] = (int16_t)i; morph[i + m] = (int16_t)k; }
        }
    }
    if (!have[n]) return 0;
    int cnt = 0, tmp[MAXW];
    for (int p = n; p > 0; p = prev[p]) tmp[cnt++] = morph[p];
    for (int k = 0; k < cnt; k++) parts[k] = tmp[cnt - 1 - k];
    const char *first = VTTS_NL_NUMBER_MORPHS[parts[0]];
    if (cnt < 2 || !strcmp(first, "en") || !strcmp(first, "\xc3\xabn") || !strcmp(first, "ste") || !strcmp(first, "de"))
        return 0;
    return cnt;
}

static const vtts_nx_entry *override_of(const uint32_t *w, int n) {
    char b[4 * MAXW + 4];
    int k = 0;
    if (n > MAXW) return 0;
    for (int i = 0; i < n; i++) k += nx_encode(w[i], b + k);
    b[k] = 0;
    int lo = 0, hi = VTTS_NL_N_OVERRIDES - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2, c = strcmp(VTTS_NL_OVERRIDES[m].w, b);
        if (!c) return &VTTS_NL_OVERRIDES[m];
        if (c < 0) lo = m + 1; else hi = m - 1;
    }
    return 0;
}

static int onset_ok(const uint32_t *rest, int rn, const char *p) {
    int k = 0;
    while (k < rn && !nx_in_u8(rest[k], VTTS_NL_SINGLE_VOWELS)) k++;
    if (k == rn) return 0;
    if (k == 0) return !strcmp(p, "ver") || !strcmp(p, "ont") || !strcmp(p, "her") || nx_in_u8(rest[0], VTTS_NL_DIAERESIS);
    return k == 1 || in_list_cp(VTTS_NL_ONSETS, VTTS_NL_N_ONSETS, rest, k);
}

static int not_prefix(const uint32_t *w, int n) {
    for (int k = 0; k < VTTS_NL_N_NOT_PREFIX; k++) {
        int m = nx_u8_len(VTTS_NL_NOT_PREFIX[k]);
        if (nx_at_u8(w, n, 0, VTTS_NL_NOT_PREFIX[k]) != m) continue;
        if (in_list_cp(VTTS_NL_NOT_PREFIX_ENDINGS, VTTS_NL_N_NOT_PREFIX_ENDINGS, w + m, n - m)) return 1;
    }
    return 0;
}

/* phonemes(word): raw = the word lower-cased, w = fold(word) */
static int phonemes(nl_scratch *x, const uint32_t *raw, int rn, const uint32_t *w, int n, uint8_t *res) {
    if (!n) return 0;
    const vtts_nx_entry *o = override_of(raw, rn);
    if (!o) o = override_of(w, n);
    if (o) { memcpy(res, o->ph, o->n); return o->n; }
    int parts[MAXW];
    int np = number_split(w, n, parts);
    if (np) {
        static uint8_t all[MAXP], ph[MAXP];
        int na = 0, pos = 0;
        for (int k = 0; k < np; k++) {
            const char *m = VTTS_NL_NUMBER_MORPHS[parts[k]];
            int ml = nx_u8_len(m), nph = -1;
            for (int r = 0; r < VTTS_NL_N_NUMBER_READINGS; r++)
                if (!strcmp(VTTS_NL_NUMBER_READINGS[r].m, m)) {
                    nph = VTTS_NL_NUMBER_READINGS[r].n;
                    memcpy(ph, VTTS_NL_NUMBER_READINGS[r].ph, (size_t)nph);
                }
            if (nph < 0) nph = rules(x, w + pos, ml, ph);
            if (k == 0 && !any_stressed(ph, nph)) mark_first(ph, nph);
            else if (k > 0) for (int j = 0; j < nph; j++) ph[j] = unstress(ph[j]);
            for (int j = 0; j < nph && na < MAXP; j++) all[na++] = ph[j];
            pos += ml;
        }
        return merge(all, na, res);
    }
    for (int p = 0; p < VTTS_NL_N_PREFIXES; p++) {
        const char *pre = VTTS_NL_PREFIXES[p].p;
        int pl = nx_u8_len(pre);
        if (nx_at_u8(w, n, 0, pre) != pl || n - pl < 3) continue;
        if (!onset_ok(w + pl, n - pl, pre) || not_prefix(w, n)) continue;
        static uint8_t body[MAXP], all[MAXP];
        int nb = rules(x, w + pl, n - pl, body);
        if (!any_stressed(body, nb)) mark_first(body, nb);
        int na = 0;
        for (int j = 0; j < VTTS_NL_PREFIXES[p].n; j++) all[na++] = VTTS_NL_PREFIXES[p].ph[j];
        for (int j = 0; j < nb && na < MAXP; j++) all[na++] = body[j];
        return merge(all, na, res);
    }
    return rules(x, w, n, res);
}

static int nl_word_ids(const uint32_t *word, int n, void *scratch, uint8_t *out, int cap);

static int letter_name_ids(nl_scratch *x, uint32_t ch, uint8_t *out, int cap) {
    for (int k = 0; k < VTTS_NL_SPEC.n_letters; k++) {
        uint32_t c;
        nx_dec1(VTTS_NL_SPEC.letters[k].key, &c);
        if (c != ch) continue;
        uint32_t nm[32];
        int m = 0, l;
        const char *p = VTTS_NL_SPEC.letters[k].val;
        while ((l = nx_dec1(p, &c)) > 0 && m < 32) { nm[m++] = c; p += l; }
        return nl_word_ids(nm, m, x, out, cap);
    }
    return 0;
}

static int nl_word_ids(const uint32_t *word, int n, void *scratch, uint8_t *out, int cap) {
    nl_scratch *x = (nl_scratch *)(((uintptr_t)scratch + 7) & ~(uintptr_t)7);
    if (n > MAXW) n = MAXW;
    uint32_t raw[MAXW + 4], w[MAXW + 4];
    int fn = 0;
    for (int i = 0; i < n; i++) {
        raw[i] = vtts_u_lower(word[i]);
        uint32_t f = fold1(word[i]);
        if (f) w[fn++] = f;
    }
    if (!fn) return 0;
    int vowel = 0;
    for (int i = 0; i < fn; i++) vowel |= nx_in_u8(w[i], VTTS_NL_SINGLE_VOWELS);
    if (!vowel && !(word[0] == '\'' || override_of(w, fn))) {
        int k = 0;
        for (int i = 0; i < fn; i++) {
            uint8_t ids[128];
            int m = letter_name_ids(x, w[i], ids, (int)sizeof ids);
            for (int j = 0; j < m && k < cap; j++) out[k++] = ids[j];
        }
        return k;
    }
    uint8_t res[MAXP];
    int m = phonemes(x, raw, n, w, fn, res);
    if (m > cap) m = cap;
    memcpy(out, res, (size_t)m);
    return m;
}

static int valid_spelling(const char *w, int n) {
    char b[256];
    if (n <= 0 || n >= (int)sizeof b) return 0;
    memcpy(b, w, (size_t)n);
    b[n] = 0;
    for (int i = 0; i < n; i++) if (b[i] < 'a' || b[i] > 'z') return 0;
    if (nx_in_sorted(VTTS_NL_SPEC.english, VTTS_NL_SPEC.n_english, b)) return 0;
    for (int k = 0; k < VTTS_NL_N_FOREIGN; k++) if (strstr(b, VTTS_NL_FOREIGN[k])) return 0;
    for (int k = 0; k < VTTS_NL_N_FOREIGN_START; k++)
        if (!strncmp(b, VTTS_NL_FOREIGN_START[k], strlen(VTTS_NL_FOREIGN_START[k]))) return 0;
    for (int k = 0; k < VTTS_NL_N_FOREIGN_END; k++) if (ends_with(b, n, VTTS_NL_FOREIGN_END[k])) return 0;
    if (strstr(b, "ph") && strncmp(b, "oph", 3)) return 0;
    return !(b[n - 1] == 'w' && !ends_with(b, n, "uw"));
}

const nx_lang_t vtts_nx_nl = {&VTTS_NL_SPEC, cardinal, ordinal, year, date, time_, nl_word_ids, valid_spelling};

#endif /* VTTS_ENABLE_NL */
