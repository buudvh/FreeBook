/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_nx_sc.c -- Swedish (token set sv-en) and Norwegian (no-en) device front-ends: the
 * number words of sv/normalize_sv.py and no/normalize_no.py, the spelling rules of scand_g2p.py with
 * each language's Rules (sv/g2p_sv.py, no/g2p_no.py), step by step, and the valid_spelling checks
 * of the tagger. Tables: vtts_text_nx_tables.h (generated). Swedish only with VTTS_ENABLE_SV,
 * Norwegian only with VTTS_ENABLE_NO. */
#include "vtts_text_nx.h"

#if VTTS_ENABLE_SV || VTTS_ENABLE_NO

#include <string.h>

#include "vtts_text_nx_int.h"
#include "vtts_text_nx_tables.h"

/* ======================= a string builder for number words ======================= */

typedef struct { char p[1024]; int n; } sb_t;

static void sb_cat(sb_t *s, const char *t) {
    int l = (int)strlen(t);
    if (s->n + l >= (int)sizeof s->p) return;
    memcpy(s->p + s->n, t, (size_t)l + 1);
    s->n += l;
}

#if VTTS_ENABLE_NO
static int sb_ends(const sb_t *s, const char *e) {
    int l = (int)strlen(e);
    return s->n >= l && memcmp(s->p + s->n - l, e, (size_t)l) == 0;
}
#endif

static void put(nx_buf *b, const sb_t *s) { nx_word(b, s->p); }

/* ======================= Swedish numbers ======================= */
#if VTTS_ENABLE_SV
static void sv_below_100(sb_t *s, int n) {
    if (n < 20) { sb_cat(s, VTTS_SV_ONES[n]); return; }
    sb_cat(s, VTTS_SV_TENS[n / 10]);
    if (n % 10) sb_cat(s, VTTS_SV_ONES[n % 10]);
}

static void sv_below_1000(sb_t *s, int n) {
    int h = n / 100, r = n % 100;
    if (h) { if (h != 1) sb_cat(s, VTTS_SV_ONES[h]); sb_cat(s, "hundra"); }
    if (r) sv_below_100(s, r);
}

static void sv_below_million(sb_t *s, int n) {
    int th = n / 1000, r = n % 1000;
    if (th) { if (th != 1) sv_below_1000(s, th); sb_cat(s, "tusen"); }
    if (r) sv_below_1000(s, r);
}

static void sv_card_s(sb_t *s, uint64_t n) {
    static const uint64_t S[3] = {1000000000000ull, 1000000000ull, 1000000ull};
    if (n == 0) { sb_cat(s, "noll"); return; }
    int first = 1;
    for (int k = 0; k < 3; k++) {
        uint64_t q = n / S[k];
        n %= S[k];
        if (!q) continue;
        if (!first) sb_cat(s, " ");
        if (q == 1) { sb_cat(s, "en "); sb_cat(s, VTTS_SV_SCALES[k][0]); }
        else { sv_card_s(s, q); sb_cat(s, " "); sb_cat(s, VTTS_SV_SCALES[k][1]); }
        first = 0;
    }
    if (n) { if (!first) sb_cat(s, " "); sv_below_million(s, (int)n); }
}

static void sv_cardinal(nx_buf *b, uint64_t n) { sb_t s = {{0}, 0}; sv_card_s(&s, n); put(b, &s); }

static void sv_year(nx_buf *b, int n) {
    sb_t s = {{0}, 0};
    sv_below_100(&s, n / 100);
    sb_cat(&s, "hundra");
    if (n % 100) sv_below_100(&s, n % 100);
    put(b, &s);
}

static void sv_ord_s(sb_t *s, uint64_t n) {
    if (n >= 1000000) { sv_card_s(s, n); return; }
    int r = (int)(n % 100);
    if (n - (uint64_t)r) sv_below_million(s, (int)(n - (uint64_t)r));
    if (r == 0) { sb_cat(s, "de"); return; }
    if (r <= 12) sb_cat(s, VTTS_SV_ORD[r]);
    else if (r < 20) { sb_cat(s, VTTS_SV_ONES[r]); sb_cat(s, "de"); }
    else if (r % 10 == 0) { sb_cat(s, VTTS_SV_TENS[r / 10]); sb_cat(s, "nde"); }
    else { sb_cat(s, VTTS_SV_TENS[r / 10]); sb_cat(s, VTTS_SV_ORD[r % 10]); }
}

static void sv_ordinal(nx_buf *b, uint64_t n) { sb_t s = {{0}, 0}; sv_ord_s(&s, n); put(b, &s); }

static void sv_date(nx_buf *b, int d, int m, int64_t y) {
    sv_ordinal(b, (uint64_t)d);
    nx_word(b, VTTS_SV_MONTHS[m]);
    if (y >= 0) { if (y >= 1100 && y <= 1999) sv_year(b, (int)y); else sv_cardinal(b, (uint64_t)y); }
}

static void sv_time(nx_buf *b, int h, int mi, int sec) {
    sv_cardinal(b, (uint64_t)h);
    if (mi) {
        if (mi < 10) { nx_word(b, "noll"); nx_word(b, VTTS_SV_ONES[mi]); }
        else sv_cardinal(b, (uint64_t)mi);
    }
    if (sec > 0) { nx_word(b, "och"); sv_cardinal(b, (uint64_t)sec); nx_word(b, sec == 1 ? "sekund" : "sekunder"); }
}
#endif

/* ======================= Norwegian numbers ======================= */
#if VTTS_ENABLE_NO
static void no_below_100(sb_t *s, int n) {
    if (n < 20) { sb_cat(s, VTTS_NO_ONES[n]); return; }
    sb_cat(s, VTTS_NO_TENS[n / 10]);
    if (n % 10) sb_cat(s, VTTS_NO_ONES[n % 10]);
}

static void no_below_1000(sb_t *s, int n) {
    int h = n / 100, r = n % 100;
    if (h) {
        if (h == 1) sb_cat(s, "hundre");
        else { sb_cat(s, VTTS_NO_ONES[h]); sb_cat(s, " hundre"); }
    }
    if (r) { if (h) sb_cat(s, " og "); no_below_100(s, r); }
}

static void no_card_s(sb_t *s, uint64_t n) {
    static const uint64_t S[3] = {1000000000000ull, 1000000000ull, 1000000ull};
    if (n == 0) { sb_cat(s, "null"); return; }
    int parts = 0;
    for (int k = 0; k < 3; k++) {
        uint64_t q = n / S[k];
        n %= S[k];
        if (!q) continue;
        if (parts) sb_cat(s, " ");
        if (q == 1) { sb_cat(s, "en "); sb_cat(s, VTTS_NO_SCALES[k][0]); }
        else { no_card_s(s, q); sb_cat(s, " "); sb_cat(s, VTTS_NO_SCALES[k][1]); }
        parts++;
    }
    int th = (int)(n / 1000), r = (int)(n % 1000);
    if (th) {
        if (parts) sb_cat(s, " ");
        if (th == 1) sb_cat(s, "tusen");
        else { no_below_1000(s, th); sb_cat(s, " tusen"); }
        parts++;
    }
    if (r) {
        if (parts) sb_cat(s, " ");
        if (parts && r < 100) sb_cat(s, "og ");
        no_below_1000(s, r);
    }
}

static void no_cardinal(nx_buf *b, uint64_t n) { sb_t s = {{0}, 0}; no_card_s(&s, n); put(b, &s); }

static void no_year(nx_buf *b, int n) {
    sb_t s = {{0}, 0};
    int h = n / 100, r = n % 100;
    no_below_100(&s, h);
    if (r == 0) sb_cat(&s, " hundre");
    else if (r < 10) { sb_cat(&s, " hundre og "); sb_cat(&s, VTTS_NO_ONES[r]); }
    else { sb_cat(&s, " "); no_below_100(&s, r); }
    put(b, &s);
}

static void no_ord_below_100(sb_t *s, int r) {
    if (r <= 12) { sb_cat(s, VTTS_NO_ORD[r]); return; }
    if (r < 20) { sb_cat(s, VTTS_NO_ONES[r]); sb_cat(s, "de"); return; }
    sb_cat(s, VTTS_NO_TENS[r / 10]);
    if (r % 10 == 0) sb_cat(s, sb_ends(s, "e") ? "nde" : "ende");
    else sb_cat(s, VTTS_NO_ORD[r % 10]);
}

static void no_ordinal(nx_buf *b, uint64_t n) {
    sb_t s = {{0}, 0};
    if (n >= 1000000) { no_card_s(&s, n); put(b, &s); return; }
    int r = (int)(n % 100);
    if (r == 0) {
        sb_t c = {{0}, 0};
        no_card_s(&c, n);
        for (int i = 0; i < c.n; i++) if (c.p[i] != ' ') { char ch[2] = {c.p[i], 0}; sb_cat(&s, ch); }
        sb_cat(&s, "de");
        put(b, &s);
        return;
    }
    if (n - (uint64_t)r) { no_card_s(&s, n - (uint64_t)r); sb_cat(&s, " og "); }
    no_ord_below_100(&s, r);
    put(b, &s);
}

static void no_date(nx_buf *b, int d, int m, int64_t y) {
    no_ordinal(b, (uint64_t)d);
    nx_word(b, VTTS_NO_MONTHS[m]);
    if (y >= 0) { if (y >= 1100 && y <= 1999) no_year(b, (int)y); else no_cardinal(b, (uint64_t)y); }
}

static void no_time(nx_buf *b, int h, int mi, int sec) {
    no_cardinal(b, (uint64_t)h);
    if (mi) {
        if (mi < 10) { nx_word(b, "null"); nx_word(b, VTTS_NO_ONES[mi]); }
        else no_cardinal(b, (uint64_t)mi);
    }
    if (sec > 0) { nx_word(b, "og"); no_cardinal(b, (uint64_t)sec); nx_word(b, sec == 1 ? "sekund" : "sekunder"); }
}
#endif

/* ======================= g2p (scand_g2p) ======================= */

#define MAXW VTTS_NX_MAXW
#define MAXP (4 * MAXW + 64)

typedef struct {
    char kind;       /* 'V' or 'C' */
    uint32_t v;      /* V: the vowel letter, or 0 for a diphthong (did) */
    uint8_t did;     /* V: diphthong token */
    uint8_t ph[3], nph;
    uint8_t gl;      /* spelling length */
    uint32_t g[4];
} sseg_t;

typedef struct {
    const vtts_nx_rules *r;
    uint32_t w[MAXW + 4];
    int n;
    sseg_t seg[MAXW + 4];
    int ns, nuc[MAXW + 4], nn;
} sc_t;

typedef struct {
    sc_t a;                  /* the word or the stem after a prefix */
    uint8_t out[MAXP], tmp[MAXP];
} sc_scratch;
typedef char sc_scratch_fits[sizeof(sc_scratch) + 8 <= VTTS_NX_SCRATCH ? 1 : -1];

static int ls_index(const vtts_nx_rules *r, uint32_t c) { return nx_index_u8(c, r->ls_letters); }

static int front_at(const vtts_nx_rules *r, const uint32_t *w, int n, int i) {
    for (int k = 0; k < r->n_front; k++) if (nx_at_u8(w, n, i, r->front[k])) return 1;
    return 0;
}

static void set_g(sseg_t *s, const uint32_t *w, int i, int m) {
    s->gl = (uint8_t)m;
    for (int q = 0; q < m && q < 4; q++) s->g[q] = w[i + q];
}

static int group_hit(sseg_t *s, const vtts_nx_group *gr, const uint32_t *w, int i, int m) {
    s->kind = 'C';
    memcpy(s->ph, gr->ph, 3);
    s->nph = gr->n;
    set_g(s, w, i, m);
    return 1;
}

static void segments(sc_t *x) {
    const vtts_nx_rules *r = x->r;
    const uint32_t *w = x->w;
    int n = x->n, i = 0, ns = 0;
    while (i < n) {
        sseg_t *s = &x->seg[ns];
        memset(s, 0, sizeof *s);
        uint32_t c = w[i];
        int hit = 0;
        for (int k = 0; k < r->n_diphthongs && !hit; k++) {
            int m = nx_at_u8(w, n, i, r->diphthongs[k].g);
            if (m) { s->kind = 'V'; s->did = r->diphthongs[k].ph[0]; set_g(s, w, i, m); hit = 1; }
        }
        if (!hit && nx_in_u8(c, r->vowels)) { s->kind = 'V'; s->v = c; set_g(s, w, i, 1); hit = 1; }
        if (!hit && i == 0) {
            for (int k = 0; k < r->n_soft && !hit; k++) {
                int m = nx_at_u8(w, n, i, r->soft[k].g);
                if (m && front_at(r, w, n, i + m)) hit = group_hit(s, &r->soft[k], w, i, m);
            }
            for (int k = 0; k < r->n_initial && !hit; k++) {
                int m = nx_at_u8(w, n, i, r->initial[k].g);
                if (m) hit = group_hit(s, &r->initial[k], w, i, m);
            }
        }
        for (int k = 0; k < r->n_graphemes && !hit; k++) {
            const char *g = r->graphemes[k].g, *bar = strchr(g, '|');
            char pre[16], post[16];
            if (bar) {
                memcpy(pre, g, (size_t)(bar - g));
                pre[bar - g] = 0;
                strcpy(post, bar + 1);
            } else {
                strcpy(pre, g);
                post[0] = 0;
            }
            int m = nx_at_u8(w, n, i, pre);
            if (m && (!post[0] || nx_at_u8(w, n, i + m, post))) hit = group_hit(s, &r->graphemes[k], w, i, m);
        }
        if (!hit && c == 'c') {
            s->kind = 'C';
            uint8_t sid = 0, kid = 0;
            for (int k = 0; k < r->n_single; k++) {
                if (r->single[k].c == 's') sid = r->single[k].id;
                if (r->single[k].c == 'k') kid = r->single[k].id;
            }
            s->ph[0] = i + 1 < n && nx_in_u8(w[i + 1], r->front_c) ? sid : kid;
            s->nph = 1;
            set_g(s, w, i, i + 1 < n && w[i + 1] == 'c' ? 2 : 1);
            hit = 1;
        }
        if (!hit && c == 'g' && r->final_g_j && i > 0 && (w[i - 1] == 'l' || w[i - 1] == 'r') &&
            (i == n - 1 || nx_in_u8(w[i + 1], r->front_c))) {
            uint8_t jid = 0;
            for (int k = 0; k < r->n_single; k++) if (r->single[k].c == 'j') jid = r->single[k].id;
            s->kind = 'C'; s->ph[0] = jid; s->nph = 1; set_g(s, w, i, 1);
            hit = 1;
        }
        if (!hit) {
            for (int k = 0; k < r->n_single; k++)
                if (r->single[k].c == c) {
                    s->kind = 'C'; s->ph[0] = r->single[k].id; s->nph = 1;
                    set_g(s, w, i, i + 1 < n && w[i + 1] == c ? 2 : 1);
                    hit = 1;
                    break;
                }
        }
        if (!hit) { i++; continue; }
        i += s->gl;
        ns++;
    }
    x->ns = ns;
    x->nn = 0;
    for (int k = 0; k < ns; k++) if (x->seg[k].kind == 'V') x->nuc[x->nn++] = k;
}

static int seg_start(const sc_t *x, int k) {
    int p = 0;
    for (int q = 0; q < k; q++) p += x->seg[q].gl;
    return p;
}

static int nucleus_at(const sc_t *x, int pos) {
    for (int q = 0; q < x->nn; q++) if (seg_start(x, x->nuc[q]) == pos) return x->nuc[q];
    return -1;
}

static int ends_strict(const uint32_t *w, int n, const char *e) { return nx_ends_u8(w, n, e); }

static int ends_plain(const uint32_t *w, int n, const char *e) {
    int m = nx_u8_len(e);
    return n >= m && (m == 0 || nx_at_u8(w, n, n - m, e) == m);
}

static int stress_index(const sc_t *x) {
    const vtts_nx_rules *r = x->r;
    const uint32_t *w = x->w;
    int n = x->n;
    if (!x->nn) return -1;
    if (x->nn == 1) return x->nuc[0];
    for (int k = 0; k < r->n_prestress; k++) {
        if (!ends_strict(w, n, r->prestress[k])) continue;
        int lim = n - nx_u8_len(r->prestress[k]), best = -1;
        for (int q = 0; q < x->nn; q++) if (seg_start(x, x->nuc[q]) < lim) best = x->nuc[q];
        if (best >= 0) return best;
    }
    for (int f = -1; f < r->n_inflections; f++) {
        int sl = n;
        if (f >= 0) {
            if (!ends_plain(w, n, r->inflections[f])) continue;
            sl = n - nx_u8_len(r->inflections[f]);
        }
        for (int k = 0; k < r->n_stressed_endings; k++) {
            const char *e = r->stressed_endings[k].e;
            int el = nx_u8_len(e), cut = sl - el;
            if (cut <= 0 || nx_at_u8(w, sl, cut, e) != el) continue;
            if (cut >= 2 && w[cut - 1] == w[cut - 2]) continue;
            int pos = nucleus_at(x, cut + r->stressed_endings[k].off);
            if (pos >= 0) return pos;
        }
    }
    return x->nuc[0];
}

static int cons_after(const sc_t *x, int k, uint32_t *out) { /* spelling of the consonants after segs[k] */
    int m = 0;
    for (int j = k + 1; j < x->ns && x->seg[j].kind == 'C'; j++)
        for (int q = 0; q < x->seg[j].gl && m < 64; q++) out[m++] = x->seg[j].g[q];
    return m;
}

static int is_long(const sc_t *x, int k) {
    uint32_t c[64];
    int m = cons_after(x, k, c);
    if (m >= 2 && c[0] == 'r' && (c[1] == 'd' || c[1] == 'n' || c[1] == 'l')) return 1;
    if (m == 1 && c[0] == 'm' && k + 2 == x->ns) return 0;
    return m == 0 || (m == 1 && c[0] != 'x');
}

static int first_vowel(const char *e) {
    uint32_t c;
    int l, j = 0;
    while ((l = nx_dec1(e, &c)) > 0) {
        if (nx_in_u8(c, "aeiouy\xc3\xa5\xc3\xa4\xc3\xb6\xc3\xa6\xc3\xb8\xc3\xa9\xc3\xa8\xc3\xb2\xc3\xb4\xc3\xb3\xc3\xbc")) return j;
        e += l;
        j++;
    }
    return -1;
}

static int ending_vowel(const sc_t *x, int k, const char *const *endings, int ne) {
    for (int q = 0; q < ne; q++) {
        if (!ends_strict(x->w, x->n, endings[q])) continue;
        int f = first_vowel(endings[q]);
        if (f >= 0 && seg_start(x, k) == x->n - nx_u8_len(endings[q]) + f) return 1;
    }
    return 0;
}

static int has_silent(const vtts_nx_rules *r, const char *rule) {
    for (int k = 0; k < r->n_silent; k++) if (!strcmp(r->silent[k], rule)) return 1;
    return 0;
}

static int g1(const sseg_t *s, uint32_t c) { return s->gl == 1 && s->g[0] == c; }

static int silent(const sc_t *x, int k, int stress) {
    const vtts_nx_rules *r = x->r;
    const sseg_t *s = &x->seg[k], *prev = k > 0 ? &x->seg[k - 1] : 0;
    int last = k == x->ns - 1;
    if (has_silent(r, "d") && g1(s, 'd') && prev) {
        if (last && (prev->kind == 'V' || g1(prev, 'l') || g1(prev, 'n') || g1(prev, 'r'))) return 1;
        if (g1(prev, 'l') || g1(prev, 'n')) {
            int p = seg_start(x, k) + 1;
            static const char *const T[] = {"e", "er", "en", "et", "es"};
            for (int q = 0; q < 5; q++) if (nx_eq_u8(x->w + p, x->n - p, T[q])) return 1;
        }
    }
    if (g1(s, 'g') && prev && g1(prev, 'i') && k - 1 != stress) {
        int p = seg_start(x, k) + 1, tl = x->n - p;
        if (has_silent(r, "ig") && tl == 0) return 1;
        if (has_silent(r, "igt") && nx_eq_u8(x->w + p, tl, "t")) return 1;
        if (has_silent(r, "ige") && (nx_eq_u8(x->w + p, tl, "e") || nx_eq_u8(x->w + p, tl, "es"))) return 1;
    }
    if (has_silent(r, "et") && g1(s, 't') && last && prev && g1(prev, 'e') && k - 1 != stress && stress >= 0 &&
        !ending_vowel(x, k - 1, r->secondary, r->n_secondary))
        return 1;
    return 0;
}

static int in_sorted_cp(const char *const *list, int n, const uint32_t *w, int len) {
    return nx_in_sorted_cp(list, n, w, len);
}

static int rules_phonemes(sc_t *x, int after_prefix, uint8_t *out) {
    const vtts_nx_rules *r = x->r;
    segments(x);
    int stress = stress_index(x), no = 0;
    uint8_t tone = 0;
    int function = x->nn == 1 && in_sorted_cp(r->function_words, r->n_function_words, x->w, x->n);
    if (stress >= 0 && !function) {
        if (stress == x->nuc[x->nn - 1] || after_prefix) tone = r->tone1;
        else {
            int acute = 0, sec = 0;
            if (x->nn == 2) {
                for (int q = 0; q < r->n_acute; q++) acute |= ends_strict(x->w, x->n, r->acute[q]);
                for (int q = 0; q < r->n_secondary; q++) sec |= ends_plain(x->w, x->n, r->secondary[q]);
            }
            tone = x->nn == 2 && acute && !sec ? r->tone1 : r->tone2;
        }
    }
    for (int k = 0; k < x->ns && no < MAXP - 4; k++) {
        const sseg_t *s = &x->seg[k];
        if (s->kind == 'C') {
            if (!silent(x, k, stress)) for (int q = 0; q < s->nph; q++) out[no++] = s->ph[q];
            continue;
        }
        int li = s->did ? -1 : ls_index(r, s->v);
        if (li < 0) { /* a diphthong token */
            out[no++] = s->did;
            if (k == stress && tone) out[no++] = tone;
            continue;
        }
        uint32_t nxt0 = k + 1 < x->ns ? x->seg[k + 1].g[0] : 0;
        int nxt_gl = k + 1 < x->ns ? x->seg[k + 1].gl : 0;
        int bri = nx_index_u8(s->v, r->before_r_letters);
        if (nxt0 == 'r' && nx_in_u8(s->v, r->before_r_coda) && nxt_gl == 1 && k + 2 < x->ns && x->seg[k + 2].kind == 'V')
            nxt0 = 0; /* e before an r and a vowel keeps its quality */
        if (k == stress) {
            int lg = is_long(x, k);
            if (nxt0 == 'r' && bri >= 0) out[no++] = r->before_r[bri][lg ? 0 : 1];
            else out[no++] = lg ? r->long_v[li] : r->short_v[li];
            if (tone) out[no++] = tone;
            continue;
        }
        int second = stress >= 0 && tone == r->tone2 && k > stress && ending_vowel(x, k, r->secondary, r->n_secondary);
        if (s->v == 'e' && !second && stress >= 0 && k > stress && ending_vowel(x, k, r->schwa, r->n_schwa)) {
            out[no++] = r->schwa_id;
            continue;
        }
        if (nxt0 == 'r' && bri >= 0) out[no++] = r->before_r[bri][1];
        else {
            int ui = nx_index_u8(s->v, r->unstressed_letters);
            out[no++] = k == x->ns - 1 && ui >= 0 ? r->unstressed[ui] : r->short_v[li];
        }
        if (second) out[no++] = r->sec;
    }
    return no;
}

static int is_tone(const vtts_nx_rules *r, uint8_t p) { return p == r->tone1 || p == r->tone2 || p == r->sec; }
static int is_vowel(const vtts_nx_rules *r, uint8_t p) { return p >= 107 && r->is_vowel[p - 107]; }

static int retro_of(const uint8_t (*rt)[2], uint8_t p) { /* the retroflex id of t d n s l, else 0 */
    for (int k = 0; k < 5; k++) if (rt[k][0] == p) return rt[k][1];
    return 0;
}

static int is_retro(const uint8_t (*rt)[2], uint8_t p) {
    for (int k = 0; k < 5; k++) if (rt[k][1] == p) return 1;
    return 0;
}

static int merge_retro(const vtts_nx_rules *r, const uint8_t (*rt)[2], const uint8_t *in, int n, uint8_t *out) {
    static uint8_t m[MAXP];
    int nm = 0, no = 0;
    for (int j = 0; j < n; j++) { /* merge */
        if (nm && in[j] == m[nm - 1] && !is_tone(r, in[j]) && !is_vowel(r, in[j])) continue;
        m[nm++] = in[j];
    }
    for (int j = 0; j < nm; j++) { /* retroflex */
        int rid = retro_of(rt, m[j]);
        if (rid && no && out[no - 1] == r->r_id) out[no - 1] = (uint8_t)rid;
        else if (rid && no && is_retro(rt, out[no - 1])) out[no++] = (uint8_t)rid;
        else out[no++] = m[j];
    }
    return no;
}

static const vtts_nx_entry *find_entry(const vtts_nx_entry *t, int n, const uint32_t *w, int len) {
    char b[4 * MAXW + 4];
    int k = 0;
    if (len > MAXW) return 0;
    for (int i = 0; i < len; i++) k += nx_encode(w[i], b + k);
    b[k] = 0;
    int lo = 0, hi = n - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2, c = strcmp(t[m].w, b);
        if (!c) return &t[m];
        if (c < 0) lo = m + 1; else hi = m - 1;
    }
    return 0;
}

static int number_split(const vtts_nx_rules *r, const uint32_t *w, int n, int *parts) {
    static int16_t cnt[MAXW + 1], prev[MAXW + 1], morph[MAXW + 1];
    for (int i = 0; i <= n; i++) cnt[i] = -1;
    cnt[0] = 0;
    for (int i = 0; i < n; i++) {
        if (cnt[i] < 0) continue;
        for (int k = 0; k < r->n_morphs; k++) {
            int m = nx_at_u8(w, n, i, r->morphs[k].w);
            if (!m) continue;
            int j = i + m;
            if (cnt[j] < 0 || cnt[i] + 1 < cnt[j]) { cnt[j] = (int16_t)(cnt[i] + 1); prev[j] = (int16_t)i; morph[j] = (int16_t)k; }
        }
    }
    if (cnt[n] < 2) return 0;
    int c = cnt[n];
    for (int p = n, q = c - 1; p > 0; p = prev[p], q--) parts[q] = morph[p];
    return c;
}

static int word_phonemes(sc_scratch *sc, const vtts_nx_rules *r, const uint8_t (*rt)[2], const uint32_t *w, int n,
                         uint8_t *res) {
    if (!n) return 0;
    const vtts_nx_entry *o = find_entry(r->overrides, r->n_overrides, w, n);
    if (o) { memcpy(res, o->ph, o->n); return o->n; }
    int parts[MAXW];
    int np = number_split(r, w, n, parts);
    uint8_t *all = sc->tmp;
    if (np) {
        int keep = -1, na = 0;
        for (int k = 0; k < np; k++)
            for (int j = 0; j < r->morphs[parts[k]].n; j++) if (is_tone(r, r->morphs[parts[k]].ph[j])) keep = k;
        for (int k = 0; k < np; k++)
            for (int j = 0; j < r->morphs[parts[k]].n; j++) {
                uint8_t p = r->morphs[parts[k]].ph[j];
                if (k == keep || !is_tone(r, p)) all[na++] = p;
            }
        return merge_retro(r, rt, all, na, res);
    }
    for (int p = 0; p < r->n_prefixes; p++) {
        const char *pre = r->prefixes[p].g;
        int pl = nx_u8_len(pre), rn = n - pl;
        if (nx_at_u8(w, n, 0, pre) != pl || rn < 3) continue;
        int skip = 0;
        for (int q = 0; q < r->n_not_prefix && !skip; q++) {
            int m = nx_u8_len(r->not_prefix[q]);
            if (nx_at_u8(w, n, 0, r->not_prefix[q]) != m) continue;
            if (m == n) skip = 1;
            for (int f = 0; f < r->n_inflections && !skip; f++) skip = nx_eq_u8(w + m, n - m, r->inflections[f]);
        }
        if (skip) continue;
        const uint32_t *rest = w + pl;
        int k = 0;
        while (k < rn && !nx_in_u8(rest[k], r->vowels)) k++;
        if (k == rn || k == 0) continue;
        if (k > 1) {
            int ok = 0;
            for (int q = 0; q < r->n_onsets && !ok; q++) ok = nx_eq_u8(rest, k, r->onsets[q]);
            if (!ok) continue;
        }
        int na = 0;
        for (int j = 0; j < r->prefixes[p].n; j++) all[na++] = r->prefixes[p].ph[j];
        const vtts_nx_entry *bo = find_entry(r->overrides, r->n_overrides, rest, rn);
        if (bo) {
            for (int j = 0; j < bo->n; j++) all[na++] = bo->ph[j] == r->tone2 ? r->tone1 : bo->ph[j];
        } else {
            sc->a.r = r;
            memmove(sc->a.w, rest, sizeof(uint32_t) * (size_t)rn);
            sc->a.n = rn;
            na += rules_phonemes(&sc->a, 1, all + na);
        }
        return merge_retro(r, rt, all, na, res);
    }
    sc->a.r = r;
    memcpy(sc->a.w, w, sizeof(uint32_t) * (size_t)n);
    sc->a.n = n;
    int na = rules_phonemes(&sc->a, 0, all);
    return merge_retro(r, rt, all, na, res);
}

typedef struct {
    const vtts_nx_rules *r;
    const uint8_t (*rt)[2];
    const vtts_nx_fold *fold;
    int n_fold;
    const vtts_nx_spec *spec;
} sc_lang_t;

static uint32_t fold1(const sc_lang_t *L, uint32_t c) {
    if (c < 0x80) return c >= 'a' && c <= 'z' ? c : c >= 'A' && c <= 'Z' ? c + 32 : 0;
    int lo = 0, hi = L->n_fold - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2;
        const vtts_nx_fold *f = &L->fold[m];
        if (c < f->start) hi = m - 1;
        else if (c >= f->start + f->count) lo = m + 1;
        else return f->first + (c - f->start) * f->step;
    }
    return 0;
}

static int word_ids(const sc_lang_t *L, const uint32_t *word, int n, void *scratch, uint8_t *out, int cap);

static int letter_ids(const sc_lang_t *L, uint32_t ch, void *scratch, uint8_t *out, int cap) {
    for (int k = 0; k < L->spec->n_letters; k++) {
        uint32_t c;
        nx_dec1(L->spec->letters[k].key, &c);
        if (c != ch) continue;
        uint32_t nm[32];
        int m = 0, l;
        const char *p = L->spec->letters[k].val;
        while ((l = nx_dec1(p, &c)) > 0 && m < 32) { nm[m++] = c; p += l; }
        return word_ids(L, nm, m, scratch, out, cap);
    }
    return 0;
}

static int word_ids(const sc_lang_t *L, const uint32_t *word, int n, void *scratch, uint8_t *out, int cap) {
    sc_scratch *sc = (sc_scratch *)(((uintptr_t)scratch + 7) & ~(uintptr_t)7);
    uint32_t w[MAXW + 4];
    int fn = 0;
    if (n > MAXW) n = MAXW;
    for (int i = 0; i < n; i++) {
        uint32_t f = fold1(L, word[i]);
        if (f) w[fn++] = f;
    }
    if (!fn) return 0;
    int vowel = 0;
    for (int i = 0; i < fn; i++) vowel |= nx_in_u8(w[i], L->r->vowels);
    if (!vowel && !find_entry(L->r->overrides, L->r->n_overrides, w, fn)) {
        int k = 0;
        for (int i = 0; i < fn; i++) {
            uint8_t ids[128];
            int m = letter_ids(L, w[i], scratch, ids, (int)sizeof ids);
            for (int j = 0; j < m && k < cap; j++) out[k++] = ids[j];
        }
        return k;
    }
    int m = word_phonemes(sc, L->r, L->rt, w, fn, sc->out);
    if (m > cap) m = cap;
    memcpy(out, sc->out, (size_t)m);
    return m;
}

static int ends_with(const char *s, int len, const char *e) {
    int l = (int)strlen(e);
    return len >= l && memcmp(s + len - l, e, (size_t)l) == 0;
}

/* g2p_sv / g2p_no valid_spelling: FOREIGN groups (sv: qv read as kv), FOREIGN_START / _END, c only in
 * ck (sv) or before e i y, not in the language's English list */
static int valid_common(const vtts_nx_spec *sp, const char *const *foreign, int nf, const char *const *fs, int nfs,
                        const char *const *fe, int nfe, int sv, const char *w, int n) {
    char b[256];
    if (n <= 0 || n >= (int)sizeof b) return 0;
    memcpy(b, w, (size_t)n);
    b[n] = 0;
    for (int i = 0; i < n; i++) if (b[i] < 'a' || b[i] > 'z') return 0;
    if (nx_in_sorted(sp->english, sp->n_english, b)) return 0;
    char q[256];
    memcpy(q, b, (size_t)n + 1);
    if (sv) for (int i = 0; i + 1 < n; i++) if (q[i] == 'q' && q[i + 1] == 'v') q[i] = 'k';
    for (int k = 0; k < nf; k++) if (strstr(q, foreign[k])) return 0;
    for (int k = 0; k < nfs; k++) if (!strncmp(b, fs[k], strlen(fs[k]))) return 0;
    for (int k = 0; k < nfe; k++) if (ends_with(b, n, fe[k])) return 0;
    for (int i = 0; i < n; i++) {
        if (b[i] != 'c') continue;
        char nx = i + 1 < n ? b[i + 1] : 0;
        if (!((sv && nx == 'k') || nx == 'e' || nx == 'i' || nx == 'y')) return 0;
    }
    return 1;
}

#if VTTS_ENABLE_SV
static const sc_lang_t SV = {&VTTS_SV_RULES, VTTS_SV_RETRO, VTTS_SV_FOLD, VTTS_SV_N_FOLD, &VTTS_SV_SPEC};
static int sv_word_ids(const uint32_t *w, int n, void *scratch, uint8_t *out, int cap) {
    return word_ids(&SV, w, n, scratch, out, cap);
}
static int sv_valid(const char *w, int n) {
    return valid_common(&VTTS_SV_SPEC, VTTS_SV_FOREIGN, (int)(sizeof VTTS_SV_FOREIGN / sizeof *VTTS_SV_FOREIGN),
                        VTTS_SV_FOREIGN_START, VTTS_SV_N_FOREIGN_START, VTTS_SV_FOREIGN_END, VTTS_SV_N_FOREIGN_END, 1, w, n);
}
const nx_lang_t vtts_nx_sv = {&VTTS_SV_SPEC, sv_cardinal, sv_ordinal, sv_year, sv_date, sv_time, sv_word_ids, sv_valid};
#endif

#if VTTS_ENABLE_NO
static const sc_lang_t NO = {&VTTS_NO_RULES, VTTS_NO_RETRO, VTTS_NO_FOLD, VTTS_NO_N_FOLD, &VTTS_NO_SPEC};
static int no_word_ids(const uint32_t *w, int n, void *scratch, uint8_t *out, int cap) {
    return word_ids(&NO, w, n, scratch, out, cap);
}
static int no_valid(const char *w, int n) {
    return valid_common(&VTTS_NO_SPEC, VTTS_NO_FOREIGN, (int)(sizeof VTTS_NO_FOREIGN / sizeof *VTTS_NO_FOREIGN),
                        VTTS_NO_FOREIGN_START, VTTS_NO_N_FOREIGN_START, VTTS_NO_FOREIGN_END, VTTS_NO_N_FOREIGN_END, 0, w, n);
}
const nx_lang_t vtts_nx_no = {&VTTS_NO_SPEC, no_cardinal, no_ordinal, no_year, no_date, no_time, no_word_ids, no_valid};
#endif

#endif /* VTTS_ENABLE_SV || VTTS_ENABLE_NO */
