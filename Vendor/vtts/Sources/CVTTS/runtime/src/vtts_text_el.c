/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_el.c -- Greek front-end of the device (token set el-en). Mirrors
 * src/vtts/frontend/el/normalize_el.py (normalization, pass by pass) and el/g2p_el.py (letters,
 * digraphs, synizesis, stress). All tables are in the generated vtts_text_el_tables.h. */
#include "vtts_langs.h"
#if VTTS_ENABLE_EL /* else an empty unit (vtts_langs.h) */

#include "vtts_text_el.h"

#include <string.h>

#include "vtts_text_el_tables.h"
#include "vtts_text_en.h"     /* vtts_en_normalize */
#include "vtts_text_lt.h"     /* vtts_u_word, vtts_u_digit, vtts_u_space, vtts_u_lower */
#include "vtts_text_tables.h" /* VTTS_HI_FOLD: ASCII letters of the NFKD form of U+00C0..U+024F */

/* ======================= small helpers ======================= */

static int dec1(const char *s, uint32_t *c) { /* one UTF-8 sequence of a (valid) table string */
    const unsigned char *p = (const unsigned char *)s;
    if (!p[0]) return 0;
    if (p[0] < 0x80) { *c = p[0]; return 1; }
    int extra = (p[0] >> 5) == 6 ? 1 : (p[0] >> 4) == 14 ? 2 : 3;
    uint32_t v = p[0] & (0x3Fu >> extra);
    for (int k = 1; k <= extra; k++) v = (v << 6) | (p[k] & 0x3F);
    *c = v;
    return extra + 1;
}

static int in_u8(uint32_t c, const char *set) {
    uint32_t x;
    int l;
    if (!c) return 0;
    while ((l = dec1(set, &x)) > 0) { if (x == c) return 1; set += l; }
    return 0;
}

static int eq_u8(const uint32_t *w, int n, const char *k) {
    uint32_t x;
    int l, i = 0;
    while ((l = dec1(k, &x)) > 0) { if (i >= n || w[i] != x) return 0; i++; k += l; }
    return i == n;
}

static int ends_u8(const uint32_t *w, int n, const char *k) { /* w ends with the UTF-8 string k */
    uint32_t b[8], x;
    int m = 0, l;
    while ((l = dec1(k, &x)) > 0 && m < 8) { b[m++] = x; k += l; }
    if (n < m) return 0;
    for (int i = 0; i < m; i++) if (w[n - m + i] != b[i]) return 0;
    return 1;
}

static int is_letter(uint32_t c) { return c != '_' && vtts_u_word(c) && vtts_u_digit(c) < 0; } /* [^\W\d_] */

/* ======================= output buffer ======================= */

typedef struct { uint32_t *p; int n, cap, err; } lb_t;

static void put(lb_t *d, uint32_t c) { if (d->n < d->cap) d->p[d->n++] = c; else d->err = 1; }
static void puts8(lb_t *d, const char *s) {
    uint32_t c;
    int l;
    while ((l = dec1(s, &c)) > 0) { put(d, c); s += l; }
}
static void putn(lb_t *d, const uint32_t *s, int n) { for (int i = 0; i < n; i++) put(d, s[i]); }

#define IN(i) ((i) >= 0 && (i) < n)
#define W(i) (IN(i) && vtts_u_word(s[i]))
#define DG(i) (IN(i) && vtts_u_digit(s[i]) >= 0)
#define SP(i) (IN(i) && vtts_u_space(s[i]))
#define AT(i, c) (IN(i) && s[i] == (uint32_t)(c))
#define WDC(i) (W(i) || AT(i, '.') || AT(i, ','))
#define SPD(i) (SP(i) || AT(i, '-'))

static int drun(const uint32_t *s, int n, int i) {
    int j = i;
    while (IN(j) && vtts_u_digit(s[j]) >= 0) j++;
    return j - i;
}

static int val(const uint32_t *s, int i, int len) {
    int v = 0;
    for (int k = 0; k < len; k++) v = v * 10 + vtts_u_digit(s[i + k]);
    return v;
}

static int key_at(const uint32_t *s, int n, int i, const char *k) { /* UTF-8 key at s[i]: its length or 0 */
    int m = 0, l;
    uint32_t c;
    while ((l = dec1(k, &c)) > 0) {
        if (!IN(i + m) || s[i + m] != c) return 0;
        m++;
        k += l;
    }
    return m;
}

static int sig(const uint32_t *s, int n, int *st) {
    int cnt = 0;
    *st = n;
    for (int i = 0; i < n; i++) {
        int v = vtts_u_digit(s[i]);
        if (v < 0 || (!cnt && !v)) continue;
        if (!cnt) *st = i;
        cnt++;
    }
    return cnt;
}

static uint64_t value(const uint32_t *s, int n, int st) {
    uint64_t v = 0;
    for (int i = st; i < n; i++) { int x = vtts_u_digit(s[i]); if (x >= 0) v = v * 10 + (uint64_t)x; }
    return v;
}

static void digit_words(lb_t *d, const uint32_t *s, int n, int from) {
    int first = 1;
    for (int i = from; i < n; i++) {
        int v = vtts_u_digit(s[i]);
        if (v < 0) continue;
        if (!first) put(d, ' ');
        puts8(d, VTTS_EL_ONES_N[v]);
        first = 0;
    }
}

/* ======================= lower case (g2p_el.lower) ======================= */

/* str.lower() with Σ -> σ, then σ after a word character and before none -> ς; s[0..n) to d */
static void lower_el(const uint32_t *s, int n, lb_t *d) {
    int st = d->n;
    for (int i = 0; i < n; i++) {
        if (s[i] == 0x130) { put(d, 'i'); put(d, 0x307); }
        else put(d, s[i] == 0x3A3 ? 0x3C3 : vtts_u_lower(s[i]));
    }
    for (int i = st + 1; i < d->n; i++)
        if (d->p[i] == 0x3C3 && vtts_u_word(d->p[i - 1]) && !(i + 1 < d->n && vtts_u_word(d->p[i + 1]))) d->p[i] = 0x3C2;
}

/* decompose(ch): the Greek base letter of a code point (0: none), its stress mark and dialytika */
static uint32_t decompose(uint32_t c, int *acc, int *dia) {
    int lo = 0, hi = VTTS_EL_N_DECOMP - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2;
        if (VTTS_EL_DECOMP[m].cp == c) { *acc = VTTS_EL_DECOMP[m].acc; *dia = VTTS_EL_DECOMP[m].dia; return VTTS_EL_DECOMP[m].base; }
        if (VTTS_EL_DECOMP[m].cp < c) lo = m + 1; else hi = m - 1;
    }
    *acc = *dia = 0;
    return 0;
}

/* normalize_el._plain of one code point: its base letter (NFD), or itself */
static uint32_t plain1(uint32_t c) {
    int a, b;
    uint32_t base = decompose(c, &a, &b);
    return base ? base : c;
}

int vtts_el_is_greek_word(const uint32_t *w, int n) {
    for (int i = 0; i < n; i++) {
        uint32_t c = w[i];
        if (!((c >= 0x370 && c <= 0x3FF) || (c >= 0x1F00 && c <= 0x1FFF))) continue;
        for (int k = 0; k < VTTS_EL_N_ALPHA; k++)
            if (c >= VTTS_EL_ALPHA[k][0] && c <= VTTS_EL_ALPHA[k][1]) return 1;
    }
    return 0;
}

int vtts_el_latin_word(const uint32_t *w, int n) {
    for (int k = 0; k < VTTS_EL_N_LATIN_WORDS; k++) if (eq_u8(w, n, VTTS_EL_LATIN_WORDS[k])) return 1;
    return 0;
}

/* ======================= numbers ======================= */

static const char *const *ones_g(char g) { return g == 'm' ? VTTS_EL_ONES_M : g == 'f' ? VTTS_EL_ONES_F : VTTS_EL_ONES_N; }
static const char *const *teens_g(char g) { return g == 'm' ? VTTS_EL_TEENS_M : g == 'f' ? VTTS_EL_TEENS_F : VTTS_EL_TEENS_N; }

static void below_100(lb_t *d, int v, char g) {
    if (v < 10) { puts8(d, ones_g(g)[v]); return; }
    if (v < 20) { puts8(d, teens_g(g)[v - 10]); return; }
    puts8(d, VTTS_EL_TENS[v / 10]);
    if (v % 10) { put(d, ' '); puts8(d, ones_g(g)[v % 10]); }
}

static void below_1000(lb_t *d, int v, char g) {
    int h = v / 100, r = v % 100;
    if (h == 1) puts8(d, r ? "εκατόν" : "εκατό");
    else if (h) {
        puts8(d, VTTS_EL_HUNDRED_STEMS[h]);
        puts8(d, g == 'm' ? VTTS_EL_END_M : g == 'f' ? VTTS_EL_END_F : VTTS_EL_END_N);
    }
    if (r || !h) {
        if (h) put(d, ' ');
        below_100(d, r, g);
    }
}

static void below_million(lb_t *d, int v, char g) {
    int th = v / 1000, r = v % 1000;
    if (th == 1) puts8(d, g == 'm' ? VTTS_EL_THOUSAND_M : g == 'f' ? VTTS_EL_THOUSAND_F : VTTS_EL_THOUSAND_N);
    else if (th) { below_1000(d, th, 'f'); puts8(d, " χιλιάδες"); }
    if (r || !th) {
        if (th) put(d, ' ');
        below_1000(d, r, g);
    }
}

/* cardinal(v, g), v < 10^15 */
static void card_u64(lb_t *d, uint64_t v, char g) {
    static const uint64_t SC[2] = {1000000000ull, 1000000ull};
    int any = 0;
    for (int k = 0; k < 2; k++) {
        uint64_t q = v / SC[k];
        v %= SC[k];
        if (!q) continue;
        if (any) put(d, ' ');
        any = 1;
        if (q == 1) { puts8(d, VTTS_EL_SCALES[k][0]); continue; }
        card_u64(d, q, 'n');
        put(d, ' ');
        puts8(d, VTTS_EL_SCALES[k][1]);
    }
    if (v || !any) {
        if (any) put(d, ' ');
        below_million(d, (int)v, g);
    }
}

/* cardinal(int(s), g) of the digits s[0..n) (16+ significant digits: digit by digit) */
static void card(lb_t *d, const uint32_t *s, int n, char g) {
    int st, nd = sig(s, n, &st);
    if (nd > 15) { digit_words(d, s, n, st); return; }
    card_u64(d, nd ? value(s, n, st) : 0, g);
}

static void card_i(lb_t *d, int v, char g) { card_u64(d, (uint64_t)v, g); }

/* latin_norm.parse_number of a written number s[0..n) (no sign) */
static int groups_full(const uint32_t *s, int n, uint32_t gs, uint32_t dm, int *ie, int *f0) {
    int r = drun(s, n, 0), i, groups = 0;
    if (r < 1 || r > 3) return 0;
    for (i = r; AT(i, gs) && DG(i + 1) && DG(i + 2) && DG(i + 3); i += 4) groups++;
    if (!groups) return 0;
    if (i == n) { *ie = n; *f0 = -1; return 1; }
    if (AT(i, dm) && i + 1 < n && drun(s, n, i + 1) == n - i - 1) { *ie = i; *f0 = i + 1; return 1; }
    return 0;
}

static void parse_number(const uint32_t *s, int n, int *ie, int *f0) {
    if (groups_full(s, n, '.', ',', ie, f0)) return;
    if (groups_full(s, n, ',', '.', ie, f0)) return;
    for (int m = 0; m < 2; m++) {
        uint32_t c = m ? '.' : ',';
        for (int i = 0; i < n; i++)
            if (s[i] == c) { *ie = i; *f0 = i + 1; return; }
    }
    *ie = n;
    *f0 = -1;
}

static int int_is_one(const uint32_t *s, int ie) { /* int(integer part) == 1 */
    int st;
    return sig(s, ie, &st) == 1 && vtts_u_digit(s[st]) == 1;
}

static int is_one(const uint32_t *s, int n) {
    int ie, f0;
    parse_number(s, n, &ie, &f0);
    return f0 < 0 && int_is_one(s, ie);
}

/* number(sign + s, g) */
static void number(lb_t *d, const uint32_t *s, int n, int neg, char g) {
    int ie, f0;
    if (neg) puts8(d, "μείον ");
    parse_number(s, n, &ie, &f0);
    card(d, s, ie, f0 < 0 ? g : 'n');
    if (f0 < 0) return;
    puts8(d, " κόμμα ");
    if (f0 < n && n - f0 <= 2 && s[f0] != '0') card(d, s + f0, n - f0, 'n');
    else digit_words(d, s, n, f0);
}

/* ordinal(int(s), ending) with the ending k of VTTS_EL_ENDINGS */
static void ord_word(lb_t *d, const char *stem, int oxytone, int k) {
    puts8(d, stem);
    puts8(d, oxytone ? VTTS_EL_ENDINGS[k][2] : VTTS_EL_ENDINGS[k][1]);
}

static void ordinal(lb_t *d, const uint32_t *s, int n, int k) {
    int st, nd = sig(s, n, &st);
    if (nd < 1 || nd > 3) { card(d, s, n, 'n'); return; }
    int v = (int)value(s, n, st), h = v / 100, r = v % 100, t = r / 10, u = r % 10, any = 0;
    if (h) { ord_word(d, VTTS_EL_ORD_HUNDREDS[h], 1, k); any = 1; }
    if (r >= 10 && r <= 12) {
        if (any) put(d, ' ');
        ord_word(d, VTTS_EL_ORD_TEENS[r - 10].stem, VTTS_EL_ORD_TEENS[r - 10].oxytone, k);
        return;
    }
    if (t == 1) { if (any) put(d, ' '); ord_word(d, VTTS_EL_ORD_TEENS[0].stem, VTTS_EL_ORD_TEENS[0].oxytone, k); any = 1; }
    else if (t) { if (any) put(d, ' '); ord_word(d, VTTS_EL_ORD_TENS[t], 1, k); any = 1; }
    if (u) { if (any) put(d, ' '); ord_word(d, VTTS_EL_ORD_ONES[u].stem, VTTS_EL_ORD_ONES[u].oxytone, k); }
}

/* gender_of(word): 'f', 'm' or 'n' from the word's ending (lower case, base letters) */
static char gender_of(const uint32_t *w, int n) {
    uint32_t lw[64], pl[64];
    lb_t l = {lw, 0, 64, 0};
    if (n <= 0) return 'n';
    if (n > 60) { w += n - 60; n = 60; } /* only the ending matters (a long word is no table word) */
    lower_el(w, n, &l);
    for (int k = 0; k < VTTS_EL_N_FEMININE; k++) if (eq_u8(lw, l.n, VTTS_EL_FEMININE[k])) return 'f';
    int m = 0;
    for (int i = 0; i < l.n; i++) if (!(lw[i] >= 0x300 && lw[i] <= 0x36F)) pl[m++] = plain1(lw[i]);
    if (ends_u8(pl, m, "ες") || ends_u8(pl, m, "εις")) return 'f';
    if (ends_u8(pl, m, "οι") || ends_u8(pl, m, "ους") || ends_u8(pl, m, "ος") || ends_u8(pl, m, "ης") ||
        ends_u8(pl, m, "ας"))
        return 'm';
    return 'n';
}

/* ======================= normalization passes ======================= */

typedef int (*end_ok)(const uint32_t *s, int n, int end, void *u);

static int try_dec(const uint32_t *s, int n, int b, end_ok ok, void *u) { /* (?:,\d+)? at b, then ok() */
    if (AT(b, ',') && DG(b + 1))
        for (int k = drun(s, n, b + 1); k >= 1; k--) if (ok(s, n, b + 1 + k, u)) return b + 1 + k;
    return ok(s, n, b, u) ? b : -1;
}

/* NUM = \d{1,3}(?:\.\d{3})+(?:,\d+)?|\d+(?:,\d+)? at j: the first end, in the regex's order, that
 * ok() accepts; -1 if none */
static int num_match(const uint32_t *s, int n, int j, end_ok ok, void *u) {
    if (!DG(j)) return -1;
    int r = drun(s, n, j), e;
    if (r <= 3) {
        int p = j + r, g = 0;
        while (AT(p, '.') && DG(p + 1) && DG(p + 2) && DG(p + 3)) { p += 4; g++; }
        for (; g >= 1; g--) if ((e = try_dec(s, n, j + r + 4 * g, ok, u)) >= 0) return e;
    }
    for (int k = r; k >= 1; k--) if ((e = try_dec(s, n, j + k, ok, u)) >= 0) return e;
    return -1;
}

static int ok_always(const uint32_t *s, int n, int e, void *u) { (void)s; (void)n; (void)e; (void)u; return 1; }
static int ok_nodigit(const uint32_t *s, int n, int e, void *u) { (void)u; return !DG(e); }

static int ok_pct(const uint32_t *s, int n, int e, void *u) { /* \s?% */
    int *end = u;
    if (SP(e) && AT(e + 1, '%')) { *end = e + 2; return 1; }
    if (AT(e, '%')) { *end = e + 1; return 1; }
    return 0;
}

typedef struct { const vtts_el_reading *keys; int nk, key, end; } keys_m;

static int ok_keys(const uint32_t *s, int n, int e, void *u) { /* \s?(k1|k2|...)(?![\w]) */
    keys_m *m = u;
    for (int sp = SP(e); sp >= 0; sp--)
        for (int k = 0; k < m->nk; k++) {
            int l = key_at(s, n, e + sp, m->keys[k].key);
            if (l && !W(e + sp + l)) { m->key = k; m->end = e + sp + l; return 1; }
        }
    return 0;
}

static void p_marks(const uint32_t *s, int n, lb_t *d) { /* ; U+037E -> ?, U+0387 · -> ; */
    for (int i = 0; i < n; i++) {
        uint32_t c = s[i];
        put(d, c == ';' || c == 0x37E ? '?' : c == 0x387 || c == 0xB7 ? ';' : c);
    }
}

/* UNIT (?<![\w.,])(-?)(NUM)\s?(UNITS)(?![\w]) */
static void p_unit(const uint32_t *s, int n, lb_t *d) {
    keys_m m = {VTTS_EL_UNITS, VTTS_EL_N_UNITS, 0, 0};
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int j = i + AT(i, '-'), e = num_match(s, n, j, ok_keys, &m);
            if (e >= 0) {
                const vtts_el_reading *r = &m.keys[m.key];
                put(d, ' ');
                number(d, s + j, e - j, j > i, r->gender);
                put(d, ' ');
                puts8(d, is_one(s + j, e - j) ? r->one : r->many);
                put(d, ' ');
                i = m.end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* _abbreviations, one key: (?<![\w.])KEY[(?![\w])] -> " reading " */
static void p_abbrev(int k, const uint32_t *s, int n, lb_t *d) {
    const char *key = VTTS_EL_ABBREV[k][0];
    int dot = key[strlen(key) - 1] == '.';
    for (int i = 0; i < n;) {
        int m;
        if (!W(i - 1) && !AT(i - 1, '.') && (m = key_at(s, n, i, key)) && (dot || !W(i + m))) {
            put(d, ' ');
            puts8(d, VTTS_EL_ABBREV[k][1]);
            put(d, ' ');
            i += m;
            continue;
        }
        put(d, s[i++]);
    }
}

static void p_drop(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n; i++) put(d, in_u8(s[i], VTTS_EL_DROP) ? ' ' : s[i]);
}

/* _date(d, m, y): " day month [year] " or the original text when out of range */
static void date_out(lb_t *d, int dd, int mm, const uint32_t *y, int yl, const uint32_t *orig, int on) {
    if (!(dd >= 1 && dd <= 31 && mm >= 1 && mm <= 12)) { putn(d, orig, on); return; }
    put(d, ' ');
    if (dd == 1) puts8(d, "πρώτη"); else card_i(d, dd, 'f');
    put(d, ' ');
    puts8(d, VTTS_EL_MONTHS[mm]);
    if (y) { put(d, ' '); card_i(d, val(y, 0, yl) + (yl == 2 ? 2000 : 0), 'n'); }
    put(d, ' ');
}

/* DATE_ISO (?<![\d-])(\d{4})-(\d{1,2})-(\d{1,2})(?![\d-]) */
static void p_date_iso(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !DG(i - 1) && !AT(i - 1, '-') && DG(i + 1) && DG(i + 2) && DG(i + 3) && AT(i + 4, '-')) {
            int m0 = i + 5, ml = drun(s, n, m0);
            if (ml >= 1 && ml <= 2 && AT(m0 + ml, '-')) {
                int d0 = m0 + ml + 1, dl = drun(s, n, d0);
                if (dl >= 1 && dl <= 2 && !AT(d0 + dl, '-')) {
                    date_out(d, val(s, d0, dl), val(s, m0, ml), s + i, 4, s + i, d0 + dl - i);
                    i = d0 + dl;
                    continue;
                }
            }
        }
        put(d, s[i++]);
    }
}

/* DATE_DMY (?<![\d/.-])(\d{1,2})([/.-])(\d{1,2})\2(\d{4}|\d{2})(?![\d/-]|[.,]\d) */
static void p_date_dmy(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !DG(i - 1) && !AT(i - 1, '/') && !AT(i - 1, '.') && !AT(i - 1, '-')) {
            int r1 = drun(s, n, i);
            uint32_t sep = IN(i + r1) ? s[i + r1] : 0;
            if (r1 <= 2 && (sep == '/' || sep == '.' || sep == '-')) {
                int m0 = i + r1 + 1, r2 = drun(s, n, m0);
                if (r2 >= 1 && r2 <= 2 && AT(m0 + r2, sep)) {
                    int y0 = m0 + r2 + 1, ry = drun(s, n, y0), e = y0 + ry;
                    if ((ry == 4 || ry == 2) && !AT(e, '/') && !AT(e, '-') && !((AT(e, '.') || AT(e, ',')) && DG(e + 1))) {
                        date_out(d, val(s, i, r1), val(s, m0, r2), s + y0, ry, s + i, e - i);
                        i = e;
                        continue;
                    }
                }
            }
        }
        put(d, s[i++]);
    }
}

static int hours(const uint32_t *s, int n, int i, int hl[3]) { /* ([01]?\d|2[0-4]) */
    int k = 0;
    if ((AT(i, '0') || AT(i, '1')) && DG(i + 1)) hl[k++] = 2;
    if (DG(i)) hl[k++] = 1;
    if (AT(i, '2') && IN(i + 1) && s[i + 1] >= '0' && s[i + 1] <= '4') hl[k++] = 2;
    return k;
}

static int m05(const uint32_t *s, int n, int j) { return IN(j) && s[j] >= '0' && s[j] <= '5' && DG(j + 1); }

static void time_out(lb_t *d, int h, int mi, int sec) {
    put(d, ' ');
    card_i(d, h, 'f');
    if (mi) { puts8(d, " και "); card_i(d, mi, 'n'); }
    if (sec) { puts8(d, " και "); card_i(d, sec, 'n'); puts8(d, " δευτερόλεπτα"); }
    put(d, ' ');
}

/* TIME (?<![\d:.])H:M(?::S)?(?![\d:]) | (?<=στις )H\.M(?![\d]|[.,]\d) */
static void p_time(const uint32_t *s, int n, lb_t *d) {
    static const uint32_t STIS[5] = {0x3C3, 0x3C4, 0x3B9, 0x3C2, ' '};
    for (int i = 0; i < n;) {
        int hl[3], nh = DG(i) ? hours(s, n, i, hl) : 0, end = -1, h = 0, mi = 0, sec = 0;
        if (nh && !DG(i - 1) && !AT(i - 1, ':') && !AT(i - 1, '.'))
            for (int c = 0; c < nh && end < 0; c++) {
                int j = i + hl[c];
                if (!(AT(j, ':') && m05(s, n, j + 1))) continue;
                int k = j + 3, has = AT(k, ':') && m05(s, n, k + 1);
                for (int sv = has; sv >= 0 && end < 0; sv--) {
                    int e = sv ? k + 3 : k;
                    if (DG(e) || AT(e, ':')) continue;
                    end = e;
                    h = val(s, i, hl[c]);
                    mi = val(s, j + 1, 2);
                    sec = sv ? val(s, k + 1, 2) : 0;
                }
            }
        if (end < 0 && nh && i >= 5 && memcmp(s + i - 5, STIS, sizeof STIS) == 0)
            for (int c = 0; c < nh && end < 0; c++) {
                int j = i + hl[c], e = j + 3;
                if (AT(j, '.') && m05(s, n, j + 1) && !DG(e) && !((AT(e, '.') || AT(e, ',')) && DG(e + 1))) {
                    end = e;
                    h = val(s, i, hl[c]);
                    mi = val(s, j + 1, 2);
                    sec = 0;
                }
            }
        if (end >= 0) { time_out(d, h, mi, sec); i = end; continue; }
        put(d, s[i++]);
    }
}

/* the end after the body of PHONE at p (?:\d{3,5}(?:[\s-]\d{2,7}){1,3}|(?:2|69)\d{8,9}|0\d{9,11})(?![\d.,]) */
static int phone_body(const uint32_t *s, int n, int p) {
    int r = drun(s, n, p);
#define END_OK(e) (!DG(e) && !AT(e, '.') && !AT(e, ','))
    if (r >= 3 && r <= 5) { /* groups of full runs; fewer when a group ends before . or , */
        int ends[4], cnt = 0, e = p + r;
        while (cnt < 3 && SPD(e)) {
            int r2 = drun(s, n, e + 1);
            if (r2 < 2 || r2 > 7) break;
            e += 1 + r2;
            ends[++cnt] = e;
        }
        for (; cnt >= 1; cnt--) if (END_OK(ends[cnt])) return ends[cnt];
    }
    if (AT(p, '2') && (r == 9 || r == 10) && END_OK(p + r)) return p + r;
    if (AT(p, '6') && AT(p + 1, '9') && (r == 10 || r == 11) && END_OK(p + r)) return p + r;
    if (AT(p, '0') && r >= 10 && r <= 12 && END_OK(p + r)) return p + r;
#undef END_OK
    return -1;
}

/* PHONE (?<![\d.,])(?:\+\d{1,3}[\s-]?)?BODY -> phone_digits(..., "συν") */
static void p_phone(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        int e = -1;
        if (!DG(i - 1) && !AT(i - 1, '.') && !AT(i - 1, ',')) {
            if (AT(i, '+')) {
                int r = drun(s, n, i + 1);
                for (int k = r < 3 ? r : 3; k >= 1 && e < 0; k--)
                    for (int sep = SPD(i + 1 + k); sep >= 0 && e < 0; sep--) {
                        int p = i + 1 + k + sep;
                        if (!sep && k < r) { e = phone_body(s, n, p); continue; } /* the body starts inside the run */
                        e = phone_body(s, n, p);
                    }
            } else if (DG(i)) {
                e = phone_body(s, n, i);
            }
        }
        if (e >= 0) {
            int cnt = 0;
            for (int q = i; q < e; q++) cnt += vtts_u_digit(s[q]) >= 0;
            if (cnt < 7 && s[i] != '0') putn(d, s + i, e - i);
            else {
                put(d, ' ');
                if (s[i] == '+') puts8(d, "συν ");
                digit_words(d, s, e, i);
                put(d, ' ');
            }
            i = e;
            continue;
        }
        put(d, s[i++]);
    }
}

/* _money(num, cur, sign) */
static void money_out(lb_t *d, const uint32_t *num, int nn, const vtts_el_reading *cur, int neg) {
    int ie, f0;
    parse_number(num, nn, &ie, &f0);
    put(d, ' ');
    if (f0 >= 0 && nn - f0 == 2 && (strcmp(cur->key, "€") == 0 || strcmp(cur->key, "EUR") == 0)) {
        int cents = val(num, f0, 2);
        if (neg) puts8(d, "μείον ");
        card(d, num, ie, 'n');
        puts8(d, " ευρώ");
        if (cents) { puts8(d, " και "); card_i(d, cents, 'n'); puts8(d, cents == 1 ? " λεπτό" : " λεπτά"); }
        put(d, ' ');
        return;
    }
    number(d, num, nn, neg, cur->gender);
    put(d, ' ');
    puts8(d, is_one(num, nn) ? cur->one : cur->many);
    put(d, ' ');
}

/* MONEY_BEFORE (CUR)\s?(NUM) */
static void p_money_before(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        int e = -1, j = 0, k;
        for (k = 0; k < VTTS_EL_N_CURRENCY && e < 0; k++) {
            int l = key_at(s, n, i, VTTS_EL_CURRENCY[k].key);
            if (!l) continue;
            for (int sp = SP(i + l); sp >= 0 && e < 0; sp--) {
                j = i + l + sp;
                e = num_match(s, n, j, ok_always, NULL);
            }
        }
        if (e >= 0) { money_out(d, s + j, e - j, &VTTS_EL_CURRENCY[k - 1], 0); i = e; continue; }
        put(d, s[i++]);
    }
}

/* MONEY_AFTER (?<![\w.,])(-?)(NUM)\s?(CUR)(?![\w]) */
static void p_money_after(const uint32_t *s, int n, lb_t *d) {
    keys_m m = {VTTS_EL_CURRENCY, VTTS_EL_N_CURRENCY, 0, 0};
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int j = i + AT(i, '-'), e = num_match(s, n, j, ok_keys, &m);
            if (e >= 0) { money_out(d, s + j, e - j, &m.keys[m.key], j > i); i = m.end; continue; }
        }
        put(d, s[i++]);
    }
}

/* PERCENT (?<![\w.,])(-?)(NUM)\s?% */
static void p_percent(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int j = i + AT(i, '-'), end = 0, e = num_match(s, n, j, ok_pct, &end);
            if (e >= 0) {
                put(d, ' ');
                number(d, s + j, e - j, j > i, 'n');
                puts8(d, " τοις εκατό ");
                i = end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* ORDINAL (?<![\w.,])(\d+)(?:-?)(ENDINGS)(?![\w]) */
static void p_ordinal(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !WDC(i - 1)) {
            int r = drun(s, n, i), done = 0;
            for (int dash = AT(i + r, '-'); dash >= 0 && !done; dash--)
                for (int k = 0; k < VTTS_EL_N_ENDINGS && !done; k++) {
                    int p = i + r + dash, l = key_at(s, n, p, VTTS_EL_ENDINGS[k][0]);
                    if (!l || W(p + l)) continue;
                    put(d, ' ');
                    ordinal(d, s + i, r, k);
                    put(d, ' ');
                    i = p + l;
                    done = 1;
                }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

/* RANGE (?<![\w.,])(\d+)\s?[-–]\s?(\d+)(?![\w]) -> " a έως b " */
static void p_range(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !WDC(i - 1)) {
            int r1 = drun(s, n, i), p = i + r1, q = -1;
            if (SP(p)) { if (AT(p + 1, '-') || AT(p + 1, 0x2013)) q = p + 2; }
            else if (AT(p, '-') || AT(p, 0x2013)) q = p + 1;
            if (q >= 0) {
                int b0 = SP(q) && DG(q + 1) ? q + 1 : DG(q) ? q : -1;
                if (b0 >= 0) {
                    int r2 = drun(s, n, b0);
                    if (!W(b0 + r2)) {
                        put(d, ' ');
                        card(d, s + i, r1, 'n');
                        puts8(d, " έως ");
                        card(d, s + b0, r2, 'n');
                        put(d, ' ');
                        i = b0 + r2;
                        continue;
                    }
                }
            }
        }
        put(d, s[i++]);
    }
}

static int is_dash(uint32_t c) { return c == 0x2014 || c == 0x2013 || c == '-'; }

/* PAUSE = …+|\.{3,}|\s[—–-]+\s|—+|–+ -> " , " */
static void p_pause(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        int e = -1;
        uint32_t c = s[i];
        if (c == 0x2026 || c == 0x2014 || c == 0x2013) { e = i; while (AT(e, c)) e++; }
        else if (c == '.') { e = i; while (AT(e, '.')) e++; if (e - i < 3) e = -1; }
        else if (SP(i) && IN(i + 1) && is_dash(s[i + 1])) {
            int j = i + 1;
            while (IN(j) && is_dash(s[j])) j++;
            if (SP(j)) e = j + 1;
        }
        if (e >= 0) { puts8(d, " , "); i = e; continue; }
        put(d, s[i++]);
    }
}

static const char *letter_of(const vtts_el_letter *t, int nt, uint32_t c) {
    for (int k = 0; k < nt; k++) if (t[k].cp == c) return t[k].name;
    return NULL;
}

static int upper_az(uint32_t c) { return c >= 'A' && c <= 'Z'; }

/* PRODUCT_CODE -> Latin letters by their Greek names, digits one by one */
static void p_code(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if ((upper_az(s[i]) || (s[i] >= '0' && s[i] <= '9')) && !W(i - 1)) {
            int j = i, up = 0, dg = 0;
            while (IN(j) && (upper_az(s[j]) || (s[j] >= '0' && s[j] <= '9'))) { up |= upper_az(s[j]); dg |= !upper_az(s[j]); j++; }
            if (up && dg && !W(j)) {
                put(d, ' ');
                for (int k = i; k < j; k++) {
                    if (k > i) put(d, ' ');
                    puts8(d, upper_az(s[k]) ? letter_of(VTTS_EL_LATIN_LETTERS, VTTS_EL_N_LATIN_LETTERS, s[k] + 32)
                                            : VTTS_EL_ONES_N[s[k] - '0']);
                }
                put(d, ' ');
                i = j;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* NUMBER (?<![\w.,])(-?)(NUM)(?![\d])(?:\s*(?=([^\W\d_]+)))? -> _number (gender of the next word) */
static void p_number(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int j = i + AT(i, '-'), e = num_match(s, n, j, ok_nodigit, NULL);
            if (e >= 0) {
                int f = e, w0 = -1, w1 = -1;
                while (SP(f)) f++;
                if (IN(f) && is_letter(s[f])) {
                    w0 = f;
                    w1 = f;
                    while (IN(w1) && is_letter(s[w1])) w1++;
                }
                int ie, f0, month = 0;
                if (w0 >= 0) {
                    uint32_t lw[24];
                    lb_t l = {lw, 0, 24, 0};
                    if (w1 - w0 <= 20) {
                        lower_el(s + w0, w1 - w0, &l);
                        for (int k = 1; k <= 12 && !month; k++) month = !l.err && eq_u8(lw, l.n, VTTS_EL_MONTHS[k]);
                    }
                }
                parse_number(s + j, e - j, &ie, &f0);
                put(d, ' ');
                if (month && int_is_one(s + j, ie)) puts8(d, "πρώτη");
                else number(d, s + j, e - j, j > i, w0 >= 0 ? gender_of(s + w0, w1 - w0) : 'n');
                put(d, ' ');
                i = w0 >= 0 ? w0 : e;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int greek_cap(uint32_t c) { /* [Α-ΩΆΈΉΊΌΎΏΪΫ] */
    return (c >= 0x391 && c <= 0x3A9) || c == 0x386 || c == 0x388 || c == 0x389 || c == 0x38A || c == 0x38C ||
           c == 0x38E || c == 0x38F || c == 0x3AA || c == 0x3AB;
}

/* words = findall([^\W\d_]{2,}); in capitals when every letter has a lower-case form */
static int text_in_capitals(const uint32_t *s, int n) {
    int words = 0, caps = 0;
    for (int i = 0; i < n;) {
        if (!is_letter(s[i])) { i++; continue; }
        int j = i, up = 1;
        while (j < n && is_letter(s[j])) { up &= s[j] == 0x130 || vtts_u_lower(s[j]) != s[j]; j++; }
        if (j - i >= 2) { words++; caps += up; }
        i = j;
    }
    return caps * 2 > words;
}

/* GREEK_CAPS (?<![\w])[Α-Ω...]{2,5}(?![\w]) -> a word of ACRONYM_WORDS or the letter names */
static void p_greek_caps(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (greek_cap(s[i]) && !W(i - 1)) {
            int j = i;
            while (IN(j) && greek_cap(s[j])) j++;
            if (j - i >= 2 && j - i <= 5 && !W(j)) {
                uint32_t lw[12], pl[12];
                lb_t l = {lw, 0, 12, 0};
                lower_el(s + i, j - i, &l);
                int m = 0;
                for (int k = 0; k < l.n; k++) pl[m++] = plain1(lw[k]);
                const char *r = NULL;
                for (int k = 0; k < VTTS_EL_N_ACRONYM_WORDS && !r; k++)
                    if (eq_u8(pl, m, VTTS_EL_ACRONYM_WORDS[k][0])) r = VTTS_EL_ACRONYM_WORDS[k][1];
                put(d, ' ');
                if (r) puts8(d, r);
                else {
                    int first = 1;
                    for (int k = 0; k < m; k++) {
                        const char *name = letter_of(VTTS_EL_GREEK_LETTERS, VTTS_EL_N_GREEK_LETTERS, pl[k]);
                        if (!name) continue;
                        if (!first) put(d, ' ');
                        puts8(d, name);
                        first = 0;
                    }
                }
                put(d, ' ');
                i = j;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

typedef struct { uint32_t *a, *b; int cap; char *out; int out_cap; } en_scratch_t;

static int lat(const uint32_t *s, int n, int i) { /* [A-Za-zÀ-ɏ] */
    if (i < 0 || i >= n) return 0;
    uint32_t c = s[i];
    return ((c | 32) >= 'a' && (c | 32) <= 'z') || (c >= 0xC0 && c <= 0x24F);
}

/* LATIN [A-Za-zÀ-ɏ](?:[A-Za-zÀ-ɏ'-]*[A-Za-zÀ-ɏ])? -> " " + normalize_en(ASCII of its NFKD form) + " " */
static void p_latin(const uint32_t *s, int n, lb_t *d, const en_scratch_t *x) {
    const int half = x->cap / 2;
    for (int i = 0; i < n;) {
        if (lat(s, n, i)) {
            int j = i + 1, e = i + 1, f = 0;
            while (j < n && (lat(s, n, j) || s[j] == '\'' || s[j] == '-')) { j++; if (lat(s, n, j - 1)) e = j; }
            for (int k = i; k < e; k++) {
                uint32_t c = s[k];
                if (c < 0x80) { if (f < x->cap) x->b[f++] = c; continue; }
                for (const char *p = VTTS_HI_FOLD[c - 0xC0]; *p; p++) if (f < x->cap) x->b[f++] = (uint8_t)*p;
            }
            int m = vtts_en_normalize(x->b, f, x->a, x->a + half, half, x->out, x->out_cap);
            if (m < 0) { d->err = 1; return; }
            put(d, ' ');
            for (int k = 0; k < m; k++) put(d, (uint8_t)x->out[k]);
            put(d, ' ');
            i = e;
            continue;
        }
        put(d, s[i++]);
    }
}

/* SYMBOLS (in order; no reading holds a key), then - and – -> space */
static void p_symbols(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n; i++) {
        const char *r = letter_of(VTTS_EL_SYMBOLS, VTTS_EL_N_SYMBOLS, s[i]);
        if (r) puts8(d, r);
        else put(d, s[i] == '-' || s[i] == 0x2013 ? ' ' : s[i]);
    }
}

static int is_mark(uint32_t c) { return c == ',' || c == '.' || c == '?' || c == '!' || c == ';' || c == ':'; }
static int comb(uint32_t c) { return c >= 0x300 && c <= 0x36F; }

/* lower(t), then findall([^\W\d_](?:[^\W\d_]|[̀-ͯ])*(?:'[^\W\d_]+)*|[,.?!;:]) joined by
 * spaces, a mark after a mark dropped */
static void p_words(const uint32_t *s, int n, lb_t *d) {
    int any = 0, last_mark = 0;
    for (int i = 0; i < n;) {
        if (is_letter(s[i])) {
            int j = i + 1;
            while (IN(j) && (is_letter(s[j]) || comb(s[j]))) j++;
            while (AT(j, '\'') && IN(j + 1) && is_letter(s[j + 1])) { j++; while (IN(j) && is_letter(s[j])) j++; }
            if (any) put(d, ' ');
            putn(d, s + i, j - i);
            any = 1;
            last_mark = 0;
            i = j;
            continue;
        }
        if (is_mark(s[i]) && !(any && last_mark)) {
            if (any) put(d, ' ');
            put(d, s[i]);
            any = last_mark = 1;
        }
        i++;
    }
}

int vtts_el_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, uint32_t *ea, uint32_t *eb,
                      int ecap, char *eout, int eout_cap, const uint32_t **out) {
    lb_t p = {a, 0, cap, 0}, q = {b, 0, cap, 0};
    en_scratch_t ex = {ea, eb, ecap, eout, eout_cap};
    putn(&p, in, n);
    if (p.err) return -1;
#define SWAP() do { if (q.err) return -1; lb_t t_ = p; p = q; q = t_; } while (0)
#define PASS(fn) do { q.n = 0; fn(p.p, p.n, &q); SWAP(); } while (0)
    PASS(p_marks);
    PASS(p_unit);
    for (int k = 0; k < VTTS_EL_N_ABBREV; k++) { q.n = 0; p_abbrev(k, p.p, p.n, &q); SWAP(); }
    PASS(p_drop);
    PASS(p_date_iso);
    PASS(p_date_dmy);
    PASS(p_time);
    PASS(p_phone);
    PASS(p_money_before);
    PASS(p_money_after);
    PASS(p_percent);
    PASS(p_ordinal);
    PASS(p_range);
    PASS(p_pause);
    PASS(p_code);
    PASS(p_number);
    if (!text_in_capitals(p.p, p.n)) PASS(p_greek_caps);
    q.n = 0;
    p_latin(p.p, p.n, &q, &ex);
    SWAP();
    PASS(p_symbols);
    q.n = 0;
    lower_el(p.p, p.n, &q);
    SWAP();
    PASS(p_words);
#undef PASS
#undef SWAP
    *out = p.p;
    return p.n;
}

/* ======================= g2p ======================= */

enum { K_V = 0, K_C = 1, K_G = 2 };
static const char *const PH[] = {"a", "e", "i", "o", "u", "p", "t", "k", "b", "d", "g", "f", "v", "th", "dh", "gh", "s",
                                 "z", "x", "ts", "dz", "m", "n", "ng", "l", "r", "j"};
enum { P_A, P_E, P_I, P_O, P_U, P_P, P_T, P_K, P_B, P_D, P_G, P_F, P_V, P_TH, P_DH, P_GH, P_S, P_Z, P_X, P_TS, P_DZ,
       P_M, P_N, P_NG, P_L, P_R, P_J };

/* segment: kind | phone << 2 | stressed << 8 | i_sound << 9 */
#define SEG(k, ph, st, is) ((uint32_t)(k) | (uint32_t)(ph) << 2 | (uint32_t)(st) << 8 | (uint32_t)(is) << 9)
#define S_KIND(x) ((int)((x) & 3))
#define S_PH(x) ((int)(((x) >> 2) & 63))
#define S_ST(x) ((int)(((x) >> 8) & 1))
#define S_IS(x) ((int)(((x) >> 9) & 1))

static int vowel_ph(uint32_t b) { /* α a, ε e, η ι υ i, ο ω o; -1 not a vowel letter */
    switch (b) {
    case 0x3B1: return P_A;
    case 0x3B5: return P_E;
    case 0x3B7: case 0x3B9: case 0x3C5: return P_I;
    case 0x3BF: case 0x3C9: return P_O;
    default: return -1;
    }
}

static int voiceless(uint32_t c) { return c && in_u8(c, "θκξπσςτφχψ"); }
static int voiced(uint32_t c) { return c && in_u8(c, "βγδζλμνρ"); }

/* letters (base | acc << 24 | dia << 25) of the lower-case word lw[0..n) */
static int letters_of(const uint32_t *lw, int n, uint32_t *lets) {
    int m = 0;
    for (int i = 0; i < n; i++) {
        uint32_t c = lw[i];
        if (comb(c)) {
            if (m) {
                if (c == 0x301 || c == 0x300 || c == 0x342) lets[m - 1] |= 1u << 24;
                if (c == 0x308) lets[m - 1] |= 1u << 25;
            }
            continue;
        }
        int acc, dia;
        uint32_t base = decompose(c, &acc, &dia);
        if (base && m < VTTS_EL_MAXW) lets[m++] = base | (uint32_t)acc << 24 | (uint32_t)dia << 25;
    }
    return m;
}

#define L_B(x) ((x) & 0xFFFFFF)
#define L_ACC(x) ((int)(((x) >> 24) & 1))
#define L_DIA(x) ((int)(((x) >> 25) & 1))

static int segments(const uint32_t *lets, int n, uint32_t *segs) {
    int ns = 0;
    for (int i = 0; i < n;) {
        uint32_t b = L_B(lets[i]), nb = i + 1 < n ? L_B(lets[i + 1]) : 0;
        int acc = L_ACC(lets[i]), nacc = i + 1 < n ? L_ACC(lets[i + 1]) : 0, ndia = i + 1 < n ? L_DIA(lets[i + 1]) : 0;
        int v = vowel_ph(b);
        if (v >= 0) {
            int dg = -1, is = 0;
            if (nb == 0x3B9 && (b == 0x3B1 || b == 0x3B5 || b == 0x3BF || b == 0x3C5)) { /* αι ει οι υι */
                dg = b == 0x3B1 ? P_E : P_I;
                is = b == 0x3B5 || b == 0x3BF;
            } else if (b == 0x3BF && nb == 0x3C5) dg = P_U; /* ου */
            if (dg >= 0 && !ndia && !acc) { segs[ns++] = SEG(K_V, dg, nacc, is); i += 2; continue; }
            if ((b == 0x3B1 || b == 0x3B5 || b == 0x3B7) && nb == 0x3C5 && !ndia && !acc) { /* αυ ευ ηυ */
                uint32_t after = i + 2 < n ? L_B(lets[i + 2]) : 0;
                segs[ns++] = SEG(K_V, v, nacc, b == 0x3B7);
                segs[ns++] = SEG(K_C, !after || voiceless(after) ? P_F : P_V, 0, 0);
                i += after == 0x3B2 || after == 0x3C6 ? 3 : 2;
                continue;
            }
            segs[ns++] = SEG(K_V, v, acc, b == 0x3B9 || b == 0x3B7 || b == 0x3C5);
            i++;
            continue;
        }
        if ((b == 0x3BC && nb == 0x3C0) || (b == 0x3BD && nb == 0x3C4)) { /* μπ ντ */
            segs[ns++] = SEG(K_C, b == 0x3BC ? P_B : P_D, 0, 0);
            i += 2;
            continue;
        }
        if (b == 0x3B3 && nb == 0x3BA) { /* γκ */
            if (i) segs[ns++] = SEG(K_C, P_NG, 0, 0);
            segs[ns++] = SEG(K_C, P_G, 0, 0);
            i += 2;
            continue;
        }
        if (b == 0x3B3 && (nb == 0x3B3 || nb == 0x3C7 || nb == 0x3BE)) { /* γγ γχ γξ */
            segs[ns++] = SEG(K_C, P_NG, 0, 0);
            if (nb == 0x3B3) { segs[ns++] = SEG(K_C, P_G, 0, 0); i += 2; } else i++;
            continue;
        }
        if (b == 0x3C4 && (nb == 0x3C3 || nb == 0x3C2)) { segs[ns++] = SEG(K_C, P_TS, 0, 0); i += 2; continue; }
        if (b == 0x3C4 && nb == 0x3B6) { segs[ns++] = SEG(K_C, P_DZ, 0, 0); i += 2; continue; }
        if ((b == 0x3C3 || b == 0x3C2) && voiced(nb)) segs[ns++] = SEG(K_C, P_Z, 0, 0);
        else switch (b) {
            case 0x3B2: segs[ns++] = SEG(K_C, P_V, 0, 0); break;
            case 0x3B3: segs[ns++] = SEG(K_C, P_GH, 0, 0); break;
            case 0x3B4: segs[ns++] = SEG(K_C, P_DH, 0, 0); break;
            case 0x3B6: segs[ns++] = SEG(K_C, P_Z, 0, 0); break;
            case 0x3B8: segs[ns++] = SEG(K_C, P_TH, 0, 0); break;
            case 0x3BA: segs[ns++] = SEG(K_C, P_K, 0, 0); break;
            case 0x3BB: segs[ns++] = SEG(K_C, P_L, 0, 0); break;
            case 0x3BC: segs[ns++] = SEG(K_C, P_M, 0, 0); break;
            case 0x3BD: segs[ns++] = SEG(K_C, P_N, 0, 0); break;
            case 0x3BE: segs[ns++] = SEG(K_C, P_K, 0, 0); segs[ns++] = SEG(K_C, P_S, 0, 0); break;
            case 0x3C0: segs[ns++] = SEG(K_C, P_P, 0, 0); break;
            case 0x3C1: segs[ns++] = SEG(K_C, P_R, 0, 0); break;
            case 0x3C2: case 0x3C3: segs[ns++] = SEG(K_C, P_S, 0, 0); break;
            case 0x3C4: segs[ns++] = SEG(K_C, P_T, 0, 0); break;
            case 0x3C6: segs[ns++] = SEG(K_C, P_F, 0, 0); break;
            case 0x3C7: segs[ns++] = SEG(K_C, P_X, 0, 0); break;
            case 0x3C8: segs[ns++] = SEG(K_C, P_P, 0, 0); segs[ns++] = SEG(K_C, P_S, 0, 0); break;
            default: break;
            }
        i += nb == b ? 2 : 1;
    }
    return ns;
}

static void glides(uint32_t *segs, int ns, int has_tonos) {
    int first_stress = -1;
    for (int k = 0; k < ns && first_stress < 0; k++) if (S_KIND(segs[k]) == K_V && S_ST(segs[k])) first_stress = k;
    for (int k = 0; k < ns; k++) {
        uint32_t s = segs[k];
        if (S_KIND(s) != K_V) continue; /* the vowels of the list before the loop: none becomes a vowel */
        if (S_ST(s) || S_PH(s) != P_I || !S_IS(s) || k == 0 || S_KIND(segs[k - 1]) != K_C) continue;
        if (k + 1 >= ns || S_KIND(segs[k + 1]) != K_V) continue;
        int after_gh = S_PH(segs[k - 1]) == P_GH;
        int liquid = k >= 2 && S_KIND(segs[k - 2]) == K_C && (S_PH(segs[k - 1]) == P_R || S_PH(segs[k - 1]) == P_L);
        if (S_PH(segs[k + 1]) == P_I) continue;
        if (!has_tonos || after_gh ||
            (!liquid && (S_ST(segs[k + 1]) || (first_stress >= 0 && k > first_stress))))
            segs[k] = SEG(K_G, P_J, 0, 0);
    }
}

static int unstressed(const uint32_t *lets, int n) {
    uint32_t b[16];
    if (n > 16) return 0;
    for (int i = 0; i < n; i++) b[i] = L_B(lets[i]);
    for (int k = 0; k < VTTS_EL_N_UNSTRESSED; k++) if (eq_u8(b, n, VTTS_EL_UNSTRESSED[k])) return 1;
    return 0;
}

typedef struct { uint8_t *out; int n, cap; } emit_t;

static void emit(emit_t *e, const char *name, int stress) {
    char t[8];
    size_t l = strlen(name);
    memcpy(t, name, l);
    if (stress) t[l++] = '1';
    t[l] = 0;
    for (int k = 0; k < VTTS_EL_N_TOKENS; k++)
        if (strcmp(VTTS_EL_TOKENS[k], t) == 0) {
            if (e->n < e->cap) e->out[e->n++] = (uint8_t)(VTTS_EL_TOK0 + k);
            return;
        }
}

int vtts_el_word_ids(const uint32_t *w, int n, uint32_t *scratch, uint8_t *out, int cap) {
    emit_t e = {out, 0, cap};
    uint32_t *lw = scratch, *lets = scratch + VTTS_EL_MAXW, *segs = scratch + 2 * VTTS_EL_MAXW;
    lb_t l = {lw, 0, VTTS_EL_MAXW, 0};
    lower_el(w, n < VTTS_EL_MAXW ? n : VTTS_EL_MAXW, &l);
    for (int k = 0; k < VTTS_EL_N_OVERRIDES; k++)
        if (!l.err && eq_u8(lw, l.n, VTTS_EL_OVERRIDES[k][0])) {
            const char *p = VTTS_EL_OVERRIDES[k][1];
            while (*p) {
                char t[8];
                int m = 0;
                while (*p && *p != ' ' && m < 7) t[m++] = *p++;
                t[m] = 0;
                while (*p == ' ') p++;
                int st = m > 1 && t[m - 1] == '1';
                if (st) t[m - 1] = 0;
                emit(&e, t, st);
            }
            return e.n;
        }
    int nl = letters_of(lw, l.n, lets);
    int ns = segments(lets, nl, segs);
    if (!ns) return 0;
    int has_tonos = 0;
    for (int k = 0; k < ns; k++) has_tonos |= S_KIND(segs[k]) == K_V && S_ST(segs[k]);
    glides(segs, ns, has_tonos);
    if (!has_tonos) {
        int nv = 0, last2 = -1, last = -1, first = -1;
        for (int k = 0; k < ns; k++)
            if (S_KIND(segs[k]) == K_V) { nv++; last2 = last; last = k; if (first < 0) first = k; }
        if (nv >= 2) segs[last2] |= 1u << 8;
        else if (nv == 1 && !unstressed(lets, nl)) segs[first] |= 1u << 8;
    }
    for (int k = 0; k < ns; k++) emit(&e, PH[S_PH(segs[k])], S_KIND(segs[k]) == K_V && S_ST(segs[k]));
    return e.n;
}

#endif /* VTTS_ENABLE_EL */
