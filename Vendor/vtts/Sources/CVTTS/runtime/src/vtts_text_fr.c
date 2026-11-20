/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_fr.c -- French (fr-en) language module of the device front-end. Mirrors
 * src/vtts/frontend/fr/normalize_fr.py (normalization pass by pass, then liaison), fr/g2p_fr.py
 * (silent letters, endings, letter rules, e muet, mid vowels) and the fr rules of lang.py and
 * latin.py (tagging). All tables are generated into vtts_text_fr_tables.h by
 * runtime/tools/gen_text_tables.py; no blob is needed. Compiled only when VTTS_ENABLE_FR is 1. */
#include "vtts_langs.h"
#if VTTS_ENABLE_FR /* else an empty unit (vtts_langs.h) */

#include "vtts_text_fr.h"

#include <string.h>

#include "vtts_text_fr_tables.h"
#include "vtts_text_lt.h" /* vtts_u_word / digit / space / lower, vtts_lt_english_word */

/* ======================= small helpers ======================= */

static int is_letter(uint32_t c) { return c != '_' && vtts_u_word(c) && vtts_u_digit(c) < 0; } /* [^\W\d_] */

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

static int in_u8(uint32_t c, const char *set) { /* c is one of the code points of the UTF-8 set */
    uint32_t x;
    int l;
    if (!c) return 0;
    while ((l = dec1(set, &x)) > 0) { if (x == c) return 1; set += l; }
    return 0;
}

static int u8_len(const char *s) { /* code points */
    uint32_t x;
    int l, n = 0;
    while ((l = dec1(s, &x)) > 0) { n++; s += l; }
    return n;
}

/* code points -> UTF-8 (NUL-terminated); 0 when it does not fit */
static int to_u8(const uint32_t *w, int n, char *o, int cap) {
    int m = 0;
    for (int i = 0; i < n; i++) {
        uint32_t c = w[i];
        if (m + 5 > cap) return 0;
        if (c < 0x80) o[m++] = (char)c;
        else if (c < 0x800) { o[m++] = (char)(0xC0 | (c >> 6)); o[m++] = (char)(0x80 | (c & 0x3F)); }
        else if (c < 0x10000) {
            o[m++] = (char)(0xE0 | (c >> 12)); o[m++] = (char)(0x80 | ((c >> 6) & 0x3F)); o[m++] = (char)(0x80 | (c & 0x3F));
        } else {
            o[m++] = (char)(0xF0 | (c >> 18)); o[m++] = (char)(0x80 | ((c >> 12) & 0x3F));
            o[m++] = (char)(0x80 | ((c >> 6) & 0x3F)); o[m++] = (char)(0x80 | (c & 0x3F));
        }
    }
    o[m] = 0;
    return 1;
}

static int find_sorted(const char *const *list, int n, const char *w) { /* index or -1 */
    int lo = 0, hi = n - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2, c = strcmp(list[m], w);
        if (!c) return m;
        if (c < 0) lo = m + 1; else hi = m - 1;
    }
    return -1;
}

/* the code points w equal the UTF-8 string k */
static int eq_u8(const uint32_t *w, int n, const char *k) {
    uint32_t x;
    int l, i = 0;
    while ((l = dec1(k, &x)) > 0) { if (i >= n || w[i] != x) return 0; i++; k += l; }
    return i == n;
}

/* w[pos..] starts with the UTF-8 string k */
static int starts_u8(const uint32_t *w, int n, int pos, const char *k) {
    uint32_t x;
    int l, i = pos;
    if (pos < 0) return 0;
    while ((l = dec1(k, &x)) > 0) { if (i >= n || w[i] != x) return 0; i++; k += l; }
    return 1;
}

static int ends_u8(const uint32_t *w, int n, const char *k) {
    int m = u8_len(k);
    return n >= m && starts_u8(w, n, n - m, k);
}

static int starts_any(const uint32_t *w, int n, const char *const *list, int nl) {
    for (int k = 0; k < nl; k++) if (starts_u8(w, n, 0, list[k])) return 1;
    return 0;
}

/* ======================= output buffer ======================= */

typedef struct { uint32_t *p; int n, cap, err; } lb_t;

static void put(lb_t *d, uint32_t c) { if (d->n < d->cap) d->p[d->n++] = c; else d->err = 1; }
static void puts8(lb_t *d, const char *s) {
    uint32_t c;
    int l;
    while ((l = dec1(s, &c)) > 0) { put(d, c); s += l; }
}
static void putn(lb_t *d, const uint32_t *s, int n) { for (int i = 0; i < n; i++) put(d, s[i]); }

/* the text written since start ends with the UTF-8 string k */
static int tail_is(const lb_t *d, int start, const char *k) {
    int m = u8_len(k);
    return d->n - start >= m && starts_u8(d->p, d->n, d->n - m, k);
}

#define IN(i) ((i) >= 0 && (i) < n)
#define W(i) (IN(i) && vtts_u_word(s[i]))
#define DG(i) (IN(i) && vtts_u_digit(s[i]) >= 0)
#define SP(i) (IN(i) && vtts_u_space(s[i]))
#define AT(i, c) (IN(i) && s[i] == (uint32_t)(c))
#define WDC(i) (W(i) || AT(i, '.') || AT(i, ','))

static int drun(const uint32_t *s, int n, int i) {
    int j = i;
    while (IN(j) && vtts_u_digit(s[j]) >= 0) j++;
    return j - i;
}

static int val(const uint32_t *s, int i, int len) { /* small values (dates, times) */
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

/* re.IGNORECASE match of code point c with the ASCII letter ch */
static int icase(uint32_t c, char ch) {
    for (int r = 0; r < VTTS_FR_N_ICASE; r++) {
        if (VTTS_FR_ICASE[r][1] != (uint32_t)ch) continue;
        for (int v = 0; VTTS_FR_ICASE[r][v]; v++) if (VTTS_FR_ICASE[r][v] == c) return 1;
        return 0;
    }
    return c == (uint32_t)(unsigned char)ch;
}

static int icase_at(const uint32_t *s, int n, int i, const char *k) { /* ASCII k at s[i], re.I */
    int m = (int)strlen(k);
    for (int q = 0; q < m; q++) if (!IN(i + q) || !icase(s[i + q], k[q])) return 0;
    return m;
}

/* significant digits of s[0..n) (other code points are separators): count, *st the first */
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

static void digit_words(lb_t *d, const uint32_t *s, int n, int from) { /* latin_norm.digits */
    int first = 1;
    for (int i = from; i < n; i++) {
        int v = vtts_u_digit(s[i]);
        if (v < 0) continue;
        if (!first) put(d, ' ');
        puts8(d, VTTS_FR_ONES[v]);
        first = 0;
    }
}

static uint64_t value(const uint32_t *s, int n, int st) {
    uint64_t v = 0;
    for (int i = st; i < n; i++) { int x = vtts_u_digit(s[i]); if (x >= 0) v = v * 10 + (uint64_t)x; }
    return v;
}

/* ======================= numbers (normalize_fr) ======================= */

static void below_100(lb_t *d, int v) {
    if (v <= 16) { puts8(d, VTTS_FR_ONES[v]); return; }
    if (v < 20) { puts8(d, "dix-"); puts8(d, VTTS_FR_ONES[v - 10]); return; }
    int t = v / 10, u = v % 10;
    if (t == 7 || t == 9) {
        int rest = v - (t - 1) * 10;
        puts8(d, VTTS_FR_TENS[t]);
        if (rest == 11 && t == 7) puts8(d, " et onze");
        else { put(d, '-'); below_100(d, rest); }
        return;
    }
    if (t == 8) {
        if (!u) puts8(d, "quatre-vingts");
        else { puts8(d, "quatre-vingt-"); puts8(d, VTTS_FR_ONES[u]); }
        return;
    }
    puts8(d, VTTS_FR_TENS[t]);
    if (u == 1) puts8(d, " et un");
    else if (u) { put(d, '-'); puts8(d, VTTS_FR_ONES[u]); }
}

static void below_1000(lb_t *d, int v, int last) {
    int st = d->n, h = v / 100, r = v % 100;
    if (!h) below_100(d, r);
    else {
        if (h == 1) puts8(d, "cent");
        else { puts8(d, VTTS_FR_ONES[h]); puts8(d, " cent"); }
        if (r) { put(d, ' '); below_100(d, r); }
        else if (h > 1 && last) put(d, 's');
    }
    if (!last && tail_is(d, st, "quatre-vingts")) d->n--;
}

static void card_v(lb_t *d, uint64_t v) {
    static const uint64_t SC[3] = {1000000000000ull, 1000000000ull, 1000000ull};
    static const char *const NAME[3] = {"billion", "milliard", "million"};
    int any = 0;
    if (!v) { puts8(d, VTTS_FR_ONES[0]); return; }
    for (int k = 0; k < 3; k++) {
        uint64_t q = v / SC[k];
        v %= SC[k];
        if (!q) continue;
        if (any) put(d, ' ');
        below_1000(d, (int)q, 1);
        put(d, ' ');
        puts8(d, NAME[k]);
        if (q > 1) put(d, 's');
        any = 1;
    }
    int q = (int)(v / 1000), r = (int)(v % 1000);
    if (q) {
        if (any) put(d, ' ');
        if (q == 1) puts8(d, "mille");
        else { below_1000(d, q, 0); puts8(d, " mille"); }
        any = 1;
    }
    if (r) { if (any) put(d, ' '); below_1000(d, r, 1); }
}

/* cardinal(int(s)) of the digits of s[0..n) */
static void card(lb_t *d, const uint32_t *s, int n) {
    int st, nd = sig(s, n, &st);
    if (nd > 15) { digit_words(d, s, n, st); return; }
    card_v(d, value(s, n, st));
}

/* feminine(): un -> une at the end (after a non-word code point or the start) */
static void feminine(lb_t *d, int start) {
    if (tail_is(d, start, "un") && (d->n - start == 2 || !vtts_u_word(d->p[d->n - 3]))) put(d, 'e');
}

/* ordinal(n, fem) of the digits of s[0..n) */
static void ordinal(lb_t *d, const uint32_t *s, int n, int fem) {
    int st, nd = sig(s, n, &st);
    if (nd == 1 && vtts_u_digit(s[st]) == 1) { puts8(d, fem ? "première" : "premier"); return; }
    int s0 = d->n;
    card(d, s, n);
    int a = d->n;
    while (a > s0 && d->p[a - 1] != ' ' && d->p[a - 1] != '-') a--; /* the last piece */
    int len = d->n - a;
    if (len == 4 && starts_u8(d->p, d->n, a, "cinq")) puts8(d, "uième");
    else if (len == 4 && starts_u8(d->p, d->n, a, "neuf")) { d->n--; puts8(d, "vième"); }
    else if ((len == 5 && starts_u8(d->p, d->n, a, "cents")) || (len == 6 && starts_u8(d->p, d->n, a, "vingts"))) {
        d->n--;
        puts8(d, "ième");
    } else if (len && d->p[d->n - 1] == 'e') { d->n--; puts8(d, "ième"); }
    else puts8(d, "ième");
}

/* latin_norm.parse_number: integer part [0, *ie), decimal part [*f0, n) or *f0 = -1 */
static int groups_full(const uint32_t *s, int n, uint32_t g, uint32_t dm, int *ie, int *f0) {
    int r = drun(s, n, 0), i, groups = 0;
    if (r < 1 || r > 3) return 0;
    for (i = r; AT(i, g) && DG(i + 1) && DG(i + 2) && DG(i + 3); i += 4) groups++;
    if (!groups) return 0;
    if (i == n) { *ie = n; *f0 = -1; return 1; }
    if (AT(i, dm) && i + 1 < n && drun(s, n, i + 1) == n - i - 1) { *ie = i; *f0 = i + 1; return 1; }
    return 0;
}

static void parse_number(const uint32_t *s, int n, int *ie, int *f0, uint32_t *mark) {
    if (groups_full(s, n, '.', ',', ie, f0)) { *mark = ','; return; }
    if (groups_full(s, n, ',', '.', ie, f0)) { *mark = '.'; return; }
    for (int m = 0; m < 2; m++) {
        uint32_t c = m ? '.' : ',';
        for (int i = 0; i < n; i++)
            if (s[i] == c) { *ie = i; *f0 = i + 1; *mark = c; return; }
    }
    *ie = n;
    *f0 = -1;
    *mark = 0;
}

/* number(s) without sign (read_number); *small: the integer part is 0 or 1 and there is no
 * decimal part (_count). Returns 1 when there is a decimal part. */
static int read_number(lb_t *d, const uint32_t *s, int n, int *small) {
    int ie, f0, st;
    uint32_t mark;
    parse_number(s, n, &ie, &f0, &mark);
    card(d, s, ie);
    int nd = sig(s, ie, &st);
    if (small) *small = f0 < 0 && (nd == 0 || (nd == 1 && vtts_u_digit(s[st]) == 1));
    if (f0 < 0) return 0;
    put(d, ' ');
    puts8(d, mark == ',' ? VTTS_FR_COMMA : VTTS_FR_PERIOD);
    put(d, ' ');
    if (f0 < n && n - f0 <= 2 && s[f0] != '0') card(d, s + f0, n - f0);
    else digit_words(d, s, n, f0);
    return 1;
}

static int number(lb_t *d, const uint32_t *s, int n, int neg, int *small) {
    if (neg) puts8(d, "moins ");
    return read_number(d, s, n, small);
}

/* ======================= normalization passes =======================
 * Each regex pass of normalize_fr is one function from s (n code points) to d; matches are found
 * left to right without overlap, like re.sub, and lookarounds look at the pass's input. Where
 * backtracking can change a match, the candidate ends are tried in the regex's order. */

typedef int (*end_ok)(const uint32_t *s, int n, int end, void *u);

static int try_dec(const uint32_t *s, int n, int b, end_ok ok, void *u) { /* (?:[.,]\d+)? at b */
    if ((AT(b, '.') || AT(b, ',')) && DG(b + 1))
        for (int k = drun(s, n, b + 1); k >= 1; k--) if (ok(s, n, b + 1 + k, u)) return b + 1 + k;
    return ok(s, n, b, u) ? b : -1;
}

/* NUM = \d{1,3}(?:[.,]\d{3})+(?:[.,]\d+)?|\d+(?:[.,]\d+)? at j: the first end ok() accepts */
static int num_match(const uint32_t *s, int n, int j, end_ok ok, void *u) {
    if (!DG(j)) return -1;
    int r = drun(s, n, j), e;
    if (r <= 3) {
        int p = j + r, g = 0;
        while ((AT(p, '.') || AT(p, ',')) && DG(p + 1) && DG(p + 2) && DG(p + 3)) { p += 4; g++; }
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

typedef struct { int key, end; } unit_m;

static int ok_unit(const uint32_t *s, int n, int e, void *u) { /* \s?(UNITS)(?![\w²³]) */
    unit_m *m = u;
    for (int sp = SP(e); sp >= 0; sp--)
        for (int k = 0; k < VTTS_FR_N_UNITS; k++) {
            int l = key_at(s, n, e + sp, VTTS_FR_UNITS[k].key);
            if (l && !W(e + sp + l) && !AT(e + sp + l, 0xB2) && !AT(e + sp + l, 0xB3)) {
                m->key = k;
                m->end = e + sp + l;
                return 1;
            }
        }
    return 0;
}

/* \s?(€|EUR|CHF|£|¥|\$)(?![\w]) at e: the currency index, the end */
static int cur_after(const uint32_t *s, int n, int e, int *cur, int *end) {
    for (int sp = SP(e); sp >= 0; sp--)
        for (int k = 0; k < VTTS_FR_N_MONEY_AFTER; k++) {
            int l = key_at(s, n, e + sp, VTTS_FR_MONEY_AFTER[k]);
            if (l && !W(e + sp + l)) {
                for (int c = 0; c < VTTS_FR_N_CURRENCY; c++)
                    if (strcmp(VTTS_FR_CURRENCY[c].key, VTTS_FR_MONEY_AFTER[k]) == 0) *cur = c;
                *end = e + sp + l;
                return 1;
            }
        }
    return 0;
}

typedef struct { int cur, end, sc0, sl; } money_m;

/* (\s?(?:millions?|milliards?|mille)(?![\w]))?\s?(CUR)(?![\w]) at e */
static int ok_money_after(const uint32_t *s, int n, int e, void *u) {
    money_m *m = u;
    for (int sp = SP(e); sp >= 0; sp--)
        for (int a = 0; a < VTTS_FR_N_SCALES_AFTER; a++) {
            int l = key_at(s, n, e + sp, VTTS_FR_SCALES_AFTER[a]);
            if (l && !W(e + sp + l) && cur_after(s, n, e + sp + l, &m->cur, &m->end)) {
                m->sc0 = e + sp;
                m->sl = l;
                return 1;
            }
        }
    m->sc0 = -1;
    m->sl = 0;
    return cur_after(s, n, e, &m->cur, &m->end);
}

/* _apply_abbreviations, one key: (?<![\w'])KEY[(?![\w])] -> " reading " (+ "." at the end) */
static void p_abbrev(int k, const uint32_t *s, int n, lb_t *d) {
    const char *key = VTTS_FR_ABBREV[k][0];
    int dot = key[strlen(key) - 1] == '.';
    for (int i = 0; i < n;) {
        int m;
        if (!W(i - 1) && !AT(i - 1, '\'') && (m = key_at(s, n, i, key)) && (dot || !W(i + m))) {
            int end = dot;
            for (int q = i + m; q < n && end; q++) end = vtts_u_space(s[q]);
            put(d, ' ');
            puts8(d, VTTS_FR_ABBREV[k][1]);
            put(d, ' ');
            if (end) put(d, '.');
            i += m;
            continue;
        }
        put(d, s[i++]);
    }
}

/* the typographic apostrophes, no-break spaces and superscript ordinal letters */
static void p_prep(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n; i++) {
        uint32_t c = s[i];
        put(d, c == 0x2019 || c == 0x2BC ? '\'' : c == 0xA0 || c == 0x202F ? ' ' : c);
    }
}

/* str.replace(a, b) of code points (a of 1 or 2, b of 1 or 2) */
static void p_repl(const uint32_t *s, int n, lb_t *d, uint32_t a0, uint32_t a1, uint32_t b0, uint32_t b1) {
    for (int i = 0; i < n;) {
        if (s[i] == a0 && (!a1 || AT(i + 1, a1))) {
            put(d, b0);
            if (b1) put(d, b1);
            i += a1 ? 2 : 1;
            continue;
        }
        put(d, s[i++]);
    }
}

static void p_drop(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n; i++) put(d, in_u8(s[i], VTTS_FR_DROP) ? ' ' : s[i]);
}

static int roman_letter(uint32_t c) { return c == 'I' || c == 'V' || c == 'X' || c == 'L' || c == 'C'; }

static uint64_t roman_value(const uint32_t *s, int n) {
    uint64_t total = 0;
    for (int k = 0; k < n; k++) {
        int v = s[k] == 'I' ? 1 : s[k] == 'V' ? 5 : s[k] == 'X' ? 10 : s[k] == 'L' ? 50 : 100;
        int nx = k + 1 < n ? (s[k + 1] == 'I' ? 1 : s[k + 1] == 'V' ? 5 : s[k + 1] == 'X' ? 10 : s[k + 1] == 'L' ? 50 : 100) : 0;
        if (nx > v) total -= (uint64_t)v; else total += (uint64_t)v;
    }
    return total;
}

static void card_u64(lb_t *d, uint64_t v) {
    uint32_t b[24];
    int k = 0;
    char t[24];
    int m = 0;
    do { t[m++] = (char)('0' + v % 10); v /= 10; } while (v && m < 23);
    while (m) b[k++] = (uint32_t)t[--m];
    card(d, b, k);
}

static void ordinal_u64(lb_t *d, uint64_t v, int fem) {
    uint32_t b[24];
    int k = 0;
    char t[24];
    int m = 0;
    do { t[m++] = (char)('0' + v % 10); v /= 10; } while (v && m < 23);
    while (m) b[k++] = (uint32_t)t[--m];
    ordinal(d, b, k, fem);
}

/* ROMAN_ORDINAL (?<![\w])([IVXLC]+)(er|re|e|ème)(?![\w]) */
static void p_roman_ordinal(const uint32_t *s, int n, lb_t *d) {
    static const char *const SUF[4] = {"er", "re", "e", "ème"};
    for (int i = 0; i < n;) {
        if (roman_letter(s[i]) && !W(i - 1)) {
            int j = i;
            while (IN(j) && roman_letter(s[j])) j++;
            int done = 0;
            for (int a = 0; a < 4 && !done; a++) {
                int l = key_at(s, n, j, SUF[a]);
                if (!l || W(j + l)) continue;
                int r = j - i;
                int keep = a == 2 && ((r == 1 && (s[i] == 'L' || s[i] == 'C')) ||
                                      (r == 2 && s[i + 1] == 'I' && (s[i] == 'L' || s[i] == 'C' || s[i] == 'V')));
                if (keep) putn(d, s + i, j + l - i);
                else { put(d, ' '); ordinal_u64(d, roman_value(s + i, r), a == 1); put(d, ' '); }
                i = j + l;
                done = 1;
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

static int lower_fr(uint32_t c) { return in_u8(c, "abcdefghijklmnopqrstuvwxyzàâçéèêëîïôûùüÿ"); }

/* ROMAN_NAME (?<![\w'])([A-ZÉ][a-zàâçéèêëîïôûùüÿ]+) ([IVX]{2,5}|V|X)(?![\w']) */
static void p_roman_name(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (((s[i] >= 'A' && s[i] <= 'Z') || s[i] == 0xC9) && !W(i - 1) && !AT(i - 1, '\'')) {
            int k = i + 1;
            while (IN(k) && lower_fr(s[k])) k++;
            if (k > i + 1 && AT(k, ' ')) {
                int r0 = k + 1, r = r0;
                while (IN(r) && (s[r] == 'I' || s[r] == 'V' || s[r] == 'X')) r++;
                int len = r - r0;
                if (((len >= 2 && len <= 5) || (len == 1 && (s[r0] == 'V' || s[r0] == 'X'))) && !W(r) && !AT(r, '\'')) {
                    putn(d, s + i, k - i);
                    put(d, ' ');
                    card_u64(d, roman_value(s + r0, len));
                    put(d, ' ');
                    i = r;
                    continue;
                }
            }
        }
        put(d, s[i++]);
    }
}

/* _date(d, m, y): " out " or the original text */
static void date_out(lb_t *d, int dd, int mm, const uint32_t *y, int yl, const uint32_t *orig, int on) {
    if (!(dd >= 1 && dd <= 31 && mm >= 1 && mm <= 12)) { putn(d, orig, on); return; }
    put(d, ' ');
    if (dd == 1) puts8(d, "premier"); else card_u64(d, (uint64_t)dd);
    put(d, ' ');
    puts8(d, VTTS_FR_MONTHS[mm]);
    if (y) { put(d, ' '); card_u64(d, (uint64_t)(val(y, 0, yl) + (yl == 2 ? 2000 : 0))); }
    put(d, ' ');
}

/* (?<![\d-])(\d{4})-(\d{1,2})-(\d{1,2})(?![\d-]) */
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

/* (?<![\d/.])(\d{1,2})[/.](\d{1,2})[/.](\d{4}|\d{2})(?![\d/]) */
static void p_date_dmy(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !DG(i - 1) && !AT(i - 1, '/') && !AT(i - 1, '.')) {
            int r1 = drun(s, n, i);
            if (r1 <= 2 && (AT(i + r1, '/') || AT(i + r1, '.'))) {
                int m0 = i + r1 + 1, r2 = drun(s, n, m0);
                if (r2 >= 1 && r2 <= 2 && (AT(m0 + r2, '/') || AT(m0 + r2, '.'))) {
                    int y0 = m0 + r2 + 1, ry = drun(s, n, y0);
                    if ((ry == 4 || ry == 2) && !AT(y0 + ry, '/')) {
                        date_out(d, val(s, i, r1), val(s, m0, r2), s + y0, ry, s + i, y0 + ry - i);
                        i = y0 + ry;
                        continue;
                    }
                }
            }
        }
        put(d, s[i++]);
    }
}

static int phone_sep(const uint32_t *s, int n, int i) { return SP(i) || AT(i, '.') || AT(i, '-'); }

/* [1-9](?:[\s.-]?\d{2}){4}(?![\d]) at c: the end or -1 */
static int phone_core(const uint32_t *s, int n, int c) {
    if (!IN(c) || s[c] < '1' || s[c] > '9') return -1;
    int e = c + 1;
    for (int g = 0; g < 4; g++) {
        if (phone_sep(s, n, e) && DG(e + 1) && DG(e + 2)) e += 3;
        else if (DG(e) && DG(e + 1)) e += 2;
        else return -1;
    }
    return DG(e) ? -1 : e;
}

static void phone_pair(lb_t *d, const uint32_t *p, int len) {
    if (len == 2 && p[0] == '0') { puts8(d, "zéro "); puts8(d, VTTS_FR_ONES[vtts_u_digit(p[1])]); }
    else card(d, p, len);
}

/* PHONE (?<![\d+])(?:\+33\s?(?:\(0\)\s?)?|0033\s?|0)[1-9](?:[\s.-]?\d{2}){4}(?![\d]) -> pairs */
static void p_phone(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        int e = -1;
        if (!DG(i - 1) && !AT(i - 1, '+')) {
            if (key_at(s, n, i, "+33"))
                for (int sp = SP(i + 3); sp >= 0 && e < 0; sp--) {
                    int q = i + 3 + sp;
                    if (key_at(s, n, q, "(0)"))
                        for (int sp2 = SP(q + 3); sp2 >= 0 && e < 0; sp2--) e = phone_core(s, n, q + 3 + sp2);
                    if (e < 0) e = phone_core(s, n, q);
                }
            if (e < 0 && key_at(s, n, i, "0033"))
                for (int sp = SP(i + 4); sp >= 0 && e < 0; sp--) e = phone_core(s, n, i + 4 + sp);
            if (e < 0 && AT(i, '0')) e = phone_core(s, n, i + 1);
        }
        if (e >= 0) {
            uint32_t ds[64];
            int nd = 0;
            for (int q = i; q < e && nd < 64; q++) if (vtts_u_digit(s[q]) >= 0) ds[nd++] = s[q];
            int a = 0;
            put(d, ' ');
            if (key_at(s, n, i, "+33") || key_at(s, n, i, "0033")) {
                puts8(d, "plus trente-trois ");
                a = s[i] == '+' ? 2 : 4;
                if (a < nd && ds[a] == '0') a++;
                puts8(d, VTTS_FR_ONES[vtts_u_digit(ds[a])]);
                a++;
                if (a < nd) put(d, ' ');
            }
            for (int k = a; k < nd; k += 2) {
                if (k > a) put(d, ' ');
                phone_pair(d, ds + k, nd - k >= 2 ? 2 : 1);
            }
            put(d, ' ');
            i = e;
            continue;
        }
        put(d, s[i++]);
    }
}

/* PHONE_OTHER (?<![\d])\+\d{1,3}(?:[\s.-]?\d){6,}(?![\d]) -> " plus d i g i t s " */
static void p_phone_other(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (AT(i, '+') && !DG(i - 1) && DG(i + 1)) {
            int e = i + 1, cnt = 0;
            for (;;) {
                if (DG(e)) { e++; cnt++; }
                else if (phone_sep(s, n, e) && DG(e + 1)) { e += 2; cnt++; }
                else break;
            }
            if (cnt - 1 >= 6) {
                puts8(d, " plus ");
                digit_words(d, s, e, i);
                put(d, ' ');
                i = e;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* ([01]?\d|2[0-4]) at i: the hour lengths in the order the regex tries them */
static int hours(const uint32_t *s, int n, int i, int hl[3]) {
    int k = 0;
    if ((AT(i, '0') || AT(i, '1')) && DG(i + 1)) hl[k++] = 2;
    if (DG(i)) hl[k++] = 1;
    if (AT(i, '2') && IN(i + 1) && s[i + 1] >= '0' && s[i + 1] <= '4') hl[k++] = 2;
    return k;
}

static int m05(const uint32_t *s, int n, int j) { return IN(j) && s[j] >= '0' && s[j] <= '5' && DG(j + 1); }
static int no_dc(const uint32_t *s, int n, int e) { return !DG(e) && !AT(e, ':'); }

static void time_out(lb_t *d, int h, int mi, int sec) {
    put(d, ' ');
    int st = d->n;
    card_u64(d, (uint64_t)h);
    feminine(d, st);
    puts8(d, h <= 1 ? " heure" : " heures");
    if (mi) { put(d, ' '); st = d->n; card_u64(d, (uint64_t)mi); feminine(d, st); }
    if (sec) {
        puts8(d, " et ");
        st = d->n;
        card_u64(d, (uint64_t)sec);
        feminine(d, st);
        puts8(d, sec == 1 ? " seconde" : " secondes");
    }
    put(d, ' ');
}

/* TIME (?<![\d:,.])H\s?(?:h|:)\s?M(?::S)?(?:\s?min(?![\w]))?(?![\d:]) | (?<![\w:.,])H\s?h(?![\w]) */
static void p_time(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        int hl[3], nh = DG(i) ? hours(s, n, i, hl) : 0, end = -1, h = 0, mi = 0, sec = 0;
        if (nh && !DG(i - 1) && !AT(i - 1, ':') && !AT(i - 1, ',') && !AT(i - 1, '.')) {
            for (int c = 0; c < nh && end < 0; c++) {
                int j = i + hl[c];
                for (int s1 = SP(j); s1 >= 0 && end < 0; s1--) {
                    int p = j + s1;
                    if (!(AT(p, 'h') || AT(p, ':'))) continue;
                    for (int s2 = SP(p + 1); s2 >= 0 && end < 0; s2--) {
                        int q = p + 1 + s2;
                        if (!m05(s, n, q)) continue;
                        int k = q + 2, has = AT(k, ':') && m05(s, n, k + 1);
                        for (int sv = has; sv >= 0 && end < 0; sv--) {
                            int k2 = sv ? k + 3 : k;
                            for (int s3 = SP(k2); s3 >= 0 && end < 0; s3--) {
                                int r = k2 + s3, l = key_at(s, n, r, "min");
                                if (l && !W(r + l) && no_dc(s, n, r + l)) end = r + l;
                            }
                            if (end < 0 && no_dc(s, n, k2)) end = k2;
                            if (end >= 0) { h = val(s, i, hl[c]); mi = val(s, q, 2); sec = sv ? val(s, k + 1, 2) : 0; }
                        }
                    }
                }
            }
        }
        if (end < 0 && nh && !W(i - 1) && !AT(i - 1, ':') && !AT(i - 1, '.') && !AT(i - 1, ','))
            for (int c = 0; c < nh && end < 0; c++) {
                int j = i + hl[c];
                for (int s1 = SP(j); s1 >= 0 && end < 0; s1--)
                    if (AT(j + s1, 'h') && !W(j + s1 + 1)) { end = j + s1 + 1; h = val(s, i, hl[c]); mi = sec = 0; }
            }
        if (end >= 0) {
            time_out(d, h, mi, sec);
            i = end;
            continue;
        }
        put(d, s[i++]);
    }
}

static int group_sp(const uint32_t *s, int n, int i) { return IN(i) && in_u8(s[i], VTTS_FR_GROUP_SPACES); }

/* GROUPED (?<![\d.,])\d{1,3}(?:[ NBSP NNBSP]\d{3})+(?![\d]) -> the digits without the spaces */
static void p_grouped(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !DG(i - 1) && !AT(i - 1, '.') && !AT(i - 1, ',')) {
            int r = drun(s, n, i);
            if (r <= 3) {
                int p = i + r, g = 0;
                while (group_sp(s, n, p) && DG(p + 1) && DG(p + 2) && DG(p + 3)) { p += 4; g++; }
                if (g && DG(p)) { p -= 4; g--; }
                if (g) {
                    for (int q = i; q < p; q++) if (!group_sp(s, n, q)) put(d, s[q]);
                    i = p;
                    continue;
                }
            }
        }
        put(d, s[i++]);
    }
}

static void p_parens(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n; i++) put(d, s[i] == '(' || s[i] == ')' ? ' ' : s[i]);
}

static void put_de(lb_t *d, const char *noun) { /* _de(): d'euros, de dollars */
    uint32_t c0;
    dec1(noun, &c0);
    if (in_u8(c0, "aeiouyé")) { puts8(d, "d'"); puts8(d, noun); }
    else { puts8(d, "de "); puts8(d, noun); }
}

/* _money(num, cur, scale) */
static void money_out(lb_t *d, const uint32_t *num, int nn, int cur, const uint32_t *scale, int sn) {
    const vtts_fr_currency *C = &VTTS_FR_CURRENCY[cur];
    int small, ie, f0, st;
    uint32_t mark;
    put(d, ' ');
    if (scale) {
        number(d, num, nn, 0, NULL);
        put(d, ' ');
        if (sn == 5 && key_at(scale, sn, 0, "mille")) { puts8(d, "mille "); puts8(d, C->many); }
        else { putn(d, scale, sn); put(d, ' '); put_de(d, C->many); }
        put(d, ' ');
        return;
    }
    parse_number(num, nn, &ie, &f0, &mark);
    int nd = sig(num, ie, &st), one = nd == 1 && vtts_u_digit(num[st]) == 1;
    if (f0 >= 0 && nn - f0 == 2 && C->cent1[0]) {
        int c = val(num, f0, 2);
        if (!nd) { card_u64(d, (uint64_t)c); put(d, ' '); puts8(d, c == 1 ? C->cent1 : C->cents); }
        else {
            card(d, num, ie);
            put(d, ' ');
            puts8(d, one ? C->one : C->many);
            if (c) { put(d, ' '); card_u64(d, (uint64_t)c); }
        }
        put(d, ' ');
        return;
    }
    if (f0 < 0 && nd >= 7) { /* n >= 10**6 and n % 10**6 == 0 */
        int zeros = 1;
        for (int k = 0, q = ie - 1; k < 6; q--) {
            if (vtts_u_digit(num[q]) < 0) continue;
            zeros &= num[q] == '0' || vtts_u_digit(num[q]) == 0;
            k++;
        }
        if (zeros) {
            number(d, num, nn, 0, NULL);
            put(d, ' ');
            put_de(d, C->many);
            put(d, ' ');
            return;
        }
    }
    number(d, num, nn, 0, &small);
    put(d, ' ');
    puts8(d, small ? C->one : C->many);
    put(d, ' ');
}

/* MONEY_BEFORE (CUR)\s?(NUM)(\s?(?:millions?|milliards?)(?![\w]))? */
static void p_money_before(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        int e = -1, j = 0, k;
        for (k = 0; k < VTTS_FR_N_CURRENCY && e < 0; k++) {
            int l = key_at(s, n, i, VTTS_FR_CURRENCY[k].key);
            if (!l) continue;
            for (int sp = SP(i + l); sp >= 0 && e < 0; sp--) {
                j = i + l + sp;
                e = num_match(s, n, j, ok_always, NULL);
            }
        }
        if (e >= 0) {
            int sc0 = -1, sl = 0, end = e;
            for (int sp = SP(e); sp >= 0 && sc0 < 0; sp--)
                for (int a = 0; a < VTTS_FR_N_SCALES_BEFORE && sc0 < 0; a++) {
                    int l = key_at(s, n, e + sp, VTTS_FR_SCALES_AFTER[a]);
                    if (l && !W(e + sp + l)) { sc0 = e + sp; sl = l; end = sc0 + l; }
                }
            money_out(d, s + j, e - j, k - 1, sc0 >= 0 ? s + sc0 : NULL, sl);
            i = end;
            continue;
        }
        put(d, s[i++]);
    }
}

/* MONEY_AFTER (?<![\w.,])(NUM)(\s?(?:millions?|milliards?|mille)(?![\w]))?\s?(CUR)(?![\w]) */
static void p_money_after(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            money_m m = {0, 0, -1, 0};
            int e = num_match(s, n, i, ok_money_after, &m);
            if (e >= 0) {
                money_out(d, s + i, e - i, m.cur, m.sc0 >= 0 ? s + m.sc0 : NULL, m.sl);
                i = m.end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* PERCENT (?<![\w.,])(-?)(NUM)\s?% -> " number pour cent " */
static void p_percent(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int end = 0, j = i + AT(i, '-'), e = num_match(s, n, j, ok_pct, &end);
            if (e < 0 && j > i) { j = i; e = num_match(s, n, j, ok_pct, &end); }
            if (e >= 0) {
                put(d, ' ');
                number(d, s + j, e - j, j > i, NULL);
                puts8(d, " pour cent ");
                i = end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* UNIT (?<![\w.,])(-?)(NUM)\s?(UNITS)(?![\w²³]) -> _unit */
static void p_unit(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            unit_m m = {0, 0};
            int j = i + AT(i, '-'), e = num_match(s, n, j, ok_unit, &m);
            if (e < 0 && j > i) { j = i; e = num_match(s, n, j, ok_unit, &m); }
            if (e >= 0) {
                int small, st;
                const vtts_fr_unit *U = &VTTS_FR_UNITS[m.key];
                put(d, ' ');
                if (j > i) puts8(d, "moins ");
                st = d->n;
                number(d, s + j, e - j, 0, &small);
                if (U->fem && small) feminine(d, st);
                put(d, ' ');
                puts8(d, small ? U->one : U->many);
                put(d, ' ');
                i = m.end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* ORDINAL (?<![\w.,])(\d+)(er|re|ère|ers|res|ères|e|es|ème|èmes|nd|nde|nds|ndes|d|de)(?![\w]) */
static void p_ordinal(const uint32_t *s, int n, lb_t *d) {
    static const char *const SUF[16] = {"er", "re", "ère", "ers", "res", "ères", "e", "es", "ème", "èmes",
                                        "nd", "nde", "nds", "ndes", "d", "de"};
    for (int i = 0; i < n;) {
        if (DG(i) && !WDC(i - 1)) {
            int r = drun(s, n, i), p = i + r, done = 0;
            for (int a = 0; a < 16 && !done; a++) {
                int l = key_at(s, n, p, SUF[a]);
                if (!l || W(p + l)) continue;
                const char *suf = SUF[a];
                int st, nd = sig(s + i, r, &st);
                put(d, ' ');
                if (suf[0] == 'n' || a >= 14 || (suf[0] == 'd')) {
                    if (nd == 1 && vtts_u_digit(s[i + st]) == 2) puts8(d, strchr(suf, 'e') ? "seconde" : "second");
                    else ordinal(d, s + i, r, 0);
                } else ordinal(d, s + i, r, suf[0] == 'r' || (unsigned char)suf[0] == 0xC3);
                put(d, ' ');
                i = p + l;
                done = 1;
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

/* RANGE (?<![\w.,])(\d+)\s?[-–]\s?(\d+)(?![\w]) -> " a à b " */
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
                        card(d, s + i, r1);
                        puts8(d, " à ");
                        card(d, s + b0, r2);
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

static int upper_az(uint32_t c) { return c >= 'A' && c <= 'Z'; }

/* PRODUCT_CODE -> letters by French name, digits one by one */
static void p_code(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if ((upper_az(s[i]) || (s[i] >= '0' && s[i] <= '9')) && !W(i - 1)) {
            int j = i, up = 0, dg = 0;
            while (IN(j) && (upper_az(s[j]) || (s[j] >= '0' && s[j] <= '9'))) { up |= upper_az(s[j]); dg |= !upper_az(s[j]); j++; }
            if (up && dg && !W(j)) {
                put(d, ' ');
                for (int k = i; k < j; k++) {
                    if (k > i) put(d, ' ');
                    if (upper_az(s[k])) puts8(d, VTTS_FR_LETTER_NAMES[s[k] - 'A']);
                    else puts8(d, VTTS_FR_ONES[s[k] - '0']);
                }
                put(d, ' ');
                i = j;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* the lower-cased code points w are a word of the sorted list */
static int lower_in(const uint32_t *w, int n, const char *const *list, int nl) {
    char b[128];
    uint32_t t[40];
    int m = 0;
    for (int i = 0; i < n; i++) {
        if (m + 2 > 40) return 0;
        if (w[i] == 0x130) { t[m++] = 'i'; t[m++] = 0x307; }
        else t[m++] = vtts_u_lower(w[i]);
    }
    return to_u8(t, m, b, (int)sizeof b) && find_sorted(list, nl, b) >= 0;
}

/* NUMBER (?<![\w.,])(-?)(NUM)(?![\d])(?:\s+([^\W\d_]+))? -> " words noun " */
static void p_number(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int j = i + AT(i, '-'), e = num_match(s, n, j, ok_nodigit, NULL);
            if (e < 0 && j > i) { j = i; e = num_match(s, n, j, ok_nodigit, NULL); }
            if (e >= 0) {
                int f = e, g, st;
                while (SP(f)) f++;
                g = f;
                if (f > e) while (IN(g) && is_letter(s[g])) g++;
                put(d, ' ');
                st = d->n;
                int frac = number(d, s + j, e - j, j > i, NULL);
                if (g > f && !frac && lower_in(s + f, g - f, VTTS_FR_FEMININE, VTTS_FR_N_FEMININE)) feminine(d, st);
                put(d, ' ');
                if (g > f) { putn(d, s + f, g - f); put(d, ' '); i = g; }
                else { put(d, ' '); i = e; }
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static void p_symbols(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n; i++) {
        const char *r = NULL;
        for (int k = 0; k < VTTS_FR_N_SYMBOLS && !r; k++) if (VTTS_FR_SYMBOLS[k].cp == s[i]) r = VTTS_FR_SYMBOLS[k].text;
        if (r) puts8(d, r); else put(d, s[i]);
    }
}

/* (?=(?:il|elle|on|ils|elles)(?![\w])) at i, re.I */
static int pronoun_after(const uint32_t *s, int n, int i) {
    static const char *const P[5] = {"il", "elle", "on", "ils", "elles"};
    for (int k = 0; k < 5; k++) {
        int l = icase_at(s, n, i, P[k]);
        if (l && !W(i + l)) return 1;
    }
    return 0;
}

/* INVERSION_T -t-(?=PRONOUN) -> " t'"; INVERSION (?<=[tdTD])-(?=PRONOUN) -> " t'";
 * IMPERATIVE (?<=[sz])-(?=(?:y|en)(?![\w])) -> " z'" (all re.I), then "-" -> " " */
static void p_inversion_t(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (s[i] == '-' && IN(i + 1) && icase(s[i + 1], 't') && AT(i + 2, '-') && pronoun_after(s, n, i + 3)) {
            puts8(d, " t'");
            i += 3;
            continue;
        }
        put(d, s[i++]);
    }
}

static void p_inversion(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n; i++) {
        if (s[i] == '-' && i > 0 && (icase(s[i - 1], 't') || icase(s[i - 1], 'd')) && pronoun_after(s, n, i + 1))
            puts8(d, " t'");
        else put(d, s[i]);
    }
}

static void p_imperative(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n; i++) {
        int ok = 0;
        if (s[i] == '-' && i > 0 && (icase(s[i - 1], 's') || icase(s[i - 1], 'z'))) {
            int l = icase_at(s, n, i + 1, "y");
            if (l && !W(i + 1 + l)) ok = 1;
            l = icase_at(s, n, i + 1, "en");
            if (!ok && l && !W(i + 1 + l)) ok = 1;
        }
        if (ok) puts8(d, " z'"); else put(d, s[i]);
    }
}

static void p_hyphen(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n; i++) put(d, s[i] == '-' ? ' ' : s[i]);
}

/* ACRONYM (?<![\w'])[A-Z]{2,5}(?![\w']): the lower-case word, or spelled */
static void p_acronym(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (upper_az(s[i]) && !W(i - 1) && !AT(i - 1, '\'')) {
            int j = i;
            while (IN(j) && upper_az(s[j])) j++;
            if (j - i >= 2 && j - i <= 5 && !W(j) && !AT(j, '\'')) {
                char low[8];
                for (int k = i; k < j; k++) low[k - i] = (char)(s[k] + 32);
                low[j - i] = 0;
                if (find_sorted(VTTS_FR_ACRONYM_WORDS, VTTS_FR_N_ACRONYM_WORDS, low) >= 0) {
                    for (int k = i; k < j; k++) put(d, s[k] + 32);
                } else {
                    put(d, ' ');
                    for (int k = i; k < j; k++) {
                        if (k > i) put(d, ' ');
                        puts8(d, VTTS_FR_LETTER_NAMES[s[k] - 'A']);
                    }
                    put(d, ' ');
                }
                i = j;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static void p_lower(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n; i++) {
        if (s[i] == 0x130) { put(d, 'i'); put(d, 0x307); }
        else put(d, vtts_u_lower(s[i]));
    }
}

static int is_mark(uint32_t c) { return c == ',' || c == '.' || c == '?' || c == '!' || c == ';' || c == ':'; }

/* finish_fr: findall([^\W\d_]+(?:'[^\W\d_]+)*'?|[,.?!;:]), a mark after a mark dropped; the words
 * are written separated by single spaces */
static void p_words(const uint32_t *s, int n, lb_t *d) {
    int any = 0, last_mark = 0;
    for (int i = 0; i < n;) {
        if (is_letter(s[i])) {
            int j = i;
            while (IN(j) && is_letter(s[j])) j++;
            while (AT(j, '\'') && IN(j + 1) && is_letter(s[j + 1])) { j++; while (IN(j) && is_letter(s[j])) j++; }
            if (AT(j, '\'')) j++;
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

/* ======================= liaison (_sandhi) =======================
 * Streamed over the words: the current word is written to d and changed there; a liaison consonant
 * for the next word is kept as a pending prefix; prev is the last word written (final). */

/* compare code points with a UTF-8 string (code point order = UTF-8 byte order) */
static int cmp32(const uint32_t *w, int n, const char *k) {
    uint32_t x;
    int l, i = 0;
    while ((l = dec1(k, &x)) > 0) {
        if (i >= n) return -1;
        if (w[i] != x) return w[i] < x ? -1 : 1;
        i++;
        k += l;
    }
    return i < n ? 1 : 0;
}

static int find32(const uint32_t *w, int n, const char *const *list, int nl) {
    int lo = 0, hi = nl - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2, c = cmp32(w, n, list[m]);
        if (!c) return m;
        if (c > 0) lo = m + 1; else hi = m - 1;
    }
    return -1;
}

static int find32_pairs(const uint32_t *w, int n, const char *const (*list)[2], int nl) {
    int lo = 0, hi = nl - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2, c = cmp32(w, n, list[m][0]);
        if (!c) return m;
        if (c > 0) lo = m + 1; else hi = m - 1;
    }
    return -1;
}

#define IN32(w, n, L) (find32(w, n, VTTS_FR_##L, VTTS_FR_N_##L) >= 0)

static int vowel_start(const uint32_t *w, int n) { /* _vowel_start */
    int m = n, inner = 0;
    while (m > 0 && w[m - 1] == '\'') m--;
    for (int i = 0; i < m; i++) inner |= w[i] == '\'';
    if (inner) return starts_u8(w, n, 0, "aujourd'");
    int r = n;
    while (r > 0 && w[r - 1] == 's') r--;
    if (IN32(w, n, NO_LIAISON) || IN32(w, n, H_ASPIRE) || IN32(w, r, H_ASPIRE)) return 0;
    if (n && w[0] == 'y' && !eq_u8(w, n, "y") && !eq_u8(w, n, "yeux") && !eq_u8(w, n, "ypérite")) return 0;
    if (!n) return 0;
    if (in_u8(w[0], "aeiouyàâæéèêëîïôœùûüÿ")) return 1;
    return w[0] == 'h' && n > 1 && in_u8(w[1], "aeiouyàâæéèêëîïôœùûü");
}

static int next_word(const uint32_t *s, int n, int i, int *a) { /* the word at or after i: length, *a start */
    while (i < n && s[i] == ' ') i++;
    *a = i;
    int j = i;
    while (j < n && s[j] != ' ') j++;
    return j - i;
}

static int eq_any(const uint32_t *w, int n, const char *const *k, int nk) {
    for (int i = 0; i < nk; i++) if (eq_u8(w, n, k[i])) return 1;
    return 0;
}

static void sandhi(const uint32_t *s, int n, lb_t *d) {
    static const char *const SIX_KEEP[7] = {"sept", "septième", "à", "et", "ou", "au", "aux"};
    static const char *const DIX_Z[4] = {"huit", "neuf", "huitième", "neuvième"};
    static const char *const NEUF_V[3] = {"ans", "heures", "hommes"};
    static const char *const EST_PREV[4] = {"l'", "nord", "sud", "à"};
    int a, len = next_word(s, n, 0, &a), first = 1, prev_s = 0, prev_n = 0;
    uint32_t pending = 0;
    while (len > 0) {
        int na, nl = next_word(s, n, a + len, &na);
        if (!first) put(d, ' ');
        first = 0;
        int ws = d->n;
        if (pending) { put(d, pending); put(d, '\''); }
        pending = 0;
        putn(d, s + a, len);
        if (d->err) return;
        uint32_t *w = d->p + ws;
        int wn = d->n - ws;
        const uint32_t *nx = s + na;
        int nxn = nl;
        if (nl == 1 && is_mark(nx[0])) nxn = 0;
        const uint32_t *pv = d->p + prev_s;
        int pvn = prev_n;
        int b0 = wn;
        while (b0 > 0 && w[b0 - 1] != '\'') b0--;
        const uint32_t *base = w + b0;
        int bn = wn - b0;
#define BASE(k) eq_u8(base, bn, k)
#define NXT(k) eq_u8(nx, nxn, k)
        do {
            if (BASE("six") || BASE("dix")) {
                if (BASE("dix") && eq_any(nx, nxn, DIX_Z, 4)) { d->n--; pending = 'z'; break; }
                if (eq_any(nx, nxn, SIX_KEEP, 7) || !nxn) break;
                d->n--;
                if (vowel_start(nx, nxn)) pending = 'z';
                break;
            }
            if (BASE("huit") && nxn && !vowel_start(nx, nxn) && !NXT("et")) { d->n--; break; }
            if (BASE("vingt") && (NXT("et") || IN32(nx, nxn, UNIT_WORDS)) && !eq_u8(pv, pvn, "quatre")) {
                pending = 't';
                break;
            }
            if (BASE("neuf") && eq_any(nx, nxn, NEUF_V, 3)) { pending = 'v'; break; }
            if (BASE("tous") && !nxn) { d->n--; puts8(d, "sse"); break; }
            if ((BASE("est") && eq_any(pv, pvn, EST_PREV, 4)) || eq_u8(w, wn, "l'est")) { d->n -= 3; puts8(d, "èst"); break; }
            if (!nxn) break;
            {
                int m = nxn, ap = -1;
                while (m > 0 && nx[m - 1] == '\'') m--;
                for (int i = 0; i < m && ap < 0; i++) if (nx[i] == '\'') ap = i;
                if (ap == 1 && in_u8(nx[0], "ztnvr")) break; /* nxt.split("'")[0] in (z t n v r) */
            }
            if (!vowel_start(nx, nxn)) break;
            if (IN32(base, bn, NUMBER_WORDS) && (NXT("un") || NXT("une") || NXT("onze"))) break;
            int dn = find32_pairs(base, bn, VTTS_FR_DENASAL, VTTS_FR_N_DENASAL);
            if (dn >= 0) { d->n -= bn; puts8(d, VTTS_FR_DENASAL[dn][1]); break; }
            if ((BASE("nous") || BASE("vous")) && IN32(pv, pvn, PREPOSITIONS)) break;
            if (eq_u8(w, wn, "quelqu'un") || eq_u8(w, wn, "chacun")) break;
            int li = find32_pairs(base, bn, VTTS_FR_LIAISON, VTTS_FR_N_LIAISON);
            if (li >= 0) pending = (uint32_t)(unsigned char)VTTS_FR_LIAISON[li][1][0];
        } while (0);
#undef BASE
#undef NXT
        prev_s = ws;
        prev_n = d->n - ws;
        a = na;
        len = nl;
    }
}

int vtts_fr_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, const uint32_t **out) {
    lb_t p = {a, 0, cap, 0}, q = {b, 0, cap, 0};
    putn(&p, in, n);
    if (p.err) return -1;
#define SWAP() do { if (q.err) return -1; lb_t t_ = p; p = q; q = t_; q.n = 0; } while (0)
#define PASS(fn) do { q.n = 0; fn(p.p, p.n, &q); SWAP(); } while (0)
    PASS(p_prep);
    q.n = 0; p_repl(p.p, p.n, &q, 0x1D49, 0x2B3, 'e', 'r'); SWAP();
    q.n = 0; p_repl(p.p, p.n, &q, 0x2B3, 0x1D49, 'r', 'e'); SWAP();
    q.n = 0; p_repl(p.p, p.n, &q, 0x1D49, 0, 'e', 0); SWAP();
    q.n = 0; p_repl(p.p, p.n, &q, 0x1D48, 0, 'd', 0); SWAP();
    for (int k = 0; k < VTTS_FR_N_ABBREV; k++) { q.n = 0; p_abbrev(k, p.p, p.n, &q); SWAP(); }
    PASS(p_drop);
    PASS(p_roman_ordinal);
    PASS(p_roman_name);
    PASS(p_date_iso);
    PASS(p_date_dmy);
    PASS(p_phone);
    PASS(p_phone_other);
    PASS(p_time);
    PASS(p_grouped);
    PASS(p_parens);
    PASS(p_money_before);
    PASS(p_money_after);
    PASS(p_percent);
    PASS(p_unit);
    PASS(p_ordinal);
    PASS(p_range);
    PASS(p_pause);
    PASS(p_code);
    PASS(p_number);
    PASS(p_symbols);
    PASS(p_inversion_t);
    PASS(p_inversion);
    PASS(p_imperative);
    PASS(p_hyphen);
    PASS(p_acronym);
    PASS(p_lower);
    PASS(p_words);
    PASS(sandhi);
#undef PASS
#undef SWAP
    *out = p.p;
    return p.n;
}

/* ======================= tagging (lang._fr_tags, latin.latin_word_lang) ======================= */

static int plain_latin(const uint32_t *w, int n) {
    int alpha = 0;
    for (int i = 0; i < n; i++) {
        uint32_t c = w[i];
        int az = (c | 32) >= 'a' && (c | 32) <= 'z' && c < 0x80;
        if (!(az || c == '-' || c == '\'')) return 0;
        alpha |= az;
    }
    return n > 0 && alpha;
}

static int is_v_ascii(char c) { return c == 'a' || c == 'e' || c == 'i' || c == 'o' || c == 'u'; }

static int in_list_n(const char *const *list, int nl, const char *r, int len) {
    char b[16];
    if (len <= 0 || len >= (int)sizeof b) return 0;
    memcpy(b, r, (size_t)len);
    b[len] = 0;
    return find_sorted(list, nl, b) >= 0;
}

static int onset_ok(const char *r, int len) { return len == 1 || in_list_n(VTTS_FR_ONSETS, VTTS_FR_N_ONSETS, r, len); }

/* valid_spelling of a lower-case ASCII word of len n (< 120) */
static int valid_spelling(const char *w0, int n) {
    char w[128], t[128], m[128];
    int tn = 0;
    if (n <= 0 || n >= 120) return 0;
    memcpy(w, w0, (size_t)n);
    w[n] = 0;
    for (int i = 0; i < n;) { /* re.sub(r"eau|(?<=[gj])ea", "o", w) */
        if (i + 3 <= n && !memcmp(w + i, "eau", 3)) { t[tn++] = 'o'; i += 3; }
        else if (i + 2 <= n && !memcmp(w + i, "ea", 2) && i > 0 && (w[i - 1] == 'g' || w[i - 1] == 'j')) { t[tn++] = 'o'; i += 2; }
        else t[tn++] = w[i++];
    }
    t[tn] = 0;
    for (int k = 0; k < VTTS_FR_N_FOREIGN; k++) if (strstr(t, VTTS_FR_FOREIGN[k])) return 0;
    for (int i = 0; i + 1 < n; i++)
        if (w[i] == w[i + 1] && !in_list_n(VTTS_FR_DOUBLES, VTTS_FR_N_DOUBLES, w + i, 2)) return 0;
    if ((n >= 3 && !memcmp(w + n - 3, "ing", 3)) || (w[n - 1] == 'y' && n > 2 && !is_v_ascii(w[n - 2]))) return 0;
    for (int k = 0; k < VTTS_FR_N_DIGRAPHS; k++) { /* str.replace in order */
        const char *f = VTTS_FR_DIGRAPHS[k][0], *r = VTTS_FR_DIGRAPHS[k][1];
        int fl = (int)strlen(f), rl = (int)strlen(r), o = 0;
        for (int i = 0; i < n;) {
            if (i + fl <= n && !memcmp(w + i, f, (size_t)fl)) { memcpy(m + o, r, (size_t)rl); o += rl; i += fl; }
            else m[o++] = w[i++];
        }
        memcpy(w, m, (size_t)o);
        n = o;
        w[n] = 0;
    }
#define ISV(k) (is_v_ascii(w[k]) || (w[k] == 'y' && !((k) + 1 < n && is_v_ascii(w[(k) + 1]))))
    int any = 0;
    for (int k = 0; k < n; k++) any |= ISV(k);
    if (!any) return 0;
    for (int k = 0; k < n;) {
        if (ISV(k)) { k++; continue; }
        int j = k;
        while (j < n && !ISV(j)) j++;
        char r[64];
        int len = 0;
        for (int q = k; q < j && len < 60; q++) { /* map the digraph codes back */
            const char *e = w[q] == 'C' ? "ch" : w[q] == 'F' ? "ph" : w[q] == 'T' ? "th" : w[q] == 'N' ? "gn"
                          : w[q] == 'K' ? "q" : w[q] == 'G' ? "g" : NULL;
            if (e) { while (*e) r[len++] = *e++; } else r[len++] = w[q];
        }
        int start = k == 0, end = j == n;
        if (start && !onset_ok(r, len)) return 0;
        if (end && !in_list_n(VTTS_FR_FINALS, VTTS_FR_N_FINALS, r, len)) return 0;
        if (!start && !end) {
            int okc = 0;
            for (int sp = 0; sp < len && !okc; sp++)
                okc = (sp == 0 || in_list_n(VTTS_FR_CODAS, VTTS_FR_N_CODAS, r, sp)) && onset_ok(r + sp, len - sp);
            if (!okc) return 0;
        }
        k = j;
    }
#undef ISV
    return 1;
}

static int camel(const uint32_t *w, int n) {
    for (int i = 0; i + 1 < n; i++) if (w[i] >= 'a' && w[i] <= 'z' && upper_az(w[i + 1])) return 1;
    return 0;
}

/* word_lang(core, "fr"): 1 fr, 0 en, -1 neutral */
static int word_lang(const uint32_t *w, int n) {
    char low[128], part[128];
    if (n <= 0) return -1;
    for (int i = 0; i < n; i++) if (in_u8(w[i], VTTS_FR_OWN)) return 1;
    if (!plain_latin(w, n)) return -1;
    if (n < (int)sizeof low) {
        for (int i = 0; i < n; i++) low[i] = (char)(w[i] >= 'A' && w[i] <= 'Z' ? w[i] + 32 : w[i]);
        low[n] = 0;
        if (find_sorted(VTTS_FR_NATIVE, VTTS_FR_N_NATIVE, low) >= 0 || find_sorted(VTTS_FR_TABLE_KEYS, VTTS_FR_N_TABLE_KEYS, low) >= 0)
            return 1;
        if (vtts_lt_english_word(low)) return 0;
    }
    int all_caps = 1, all_valid = 1;
    for (int a = 0; a <= n;) {
        int b = a;
        while (b < n && w[b] != '-' && w[b] != '\'') b++;
        if (b > a) {
            int len = b - a, caps = len >= 2 && len <= 5;
            if (camel(w + a, len)) return 0;
            for (int k = a; k < b; k++) caps &= upper_az(w[k]);
            all_caps &= caps;
            if (all_valid) {
                if (len >= 120) all_valid = 0;
                else {
                    for (int k = 0; k < len; k++) part[k] = (char)(w[a + k] | 32);
                    all_valid = valid_spelling(part, len);
                }
            }
        }
        a = b + 1;
    }
    if (n == 1 || all_caps) return 1;
    return all_valid ? 1 : 0;
}

static int is_edge(uint32_t c) { return c < 0x80 ? strchr(".,;:!?\"'()[]{}", (int)c) != NULL && c : in_u8(c, "…“”‘’«»–—"); }

static int core_of(const uint32_t *c, int n, int *a) { /* _core: strip EDGE; returns the length */
    int i = 0, j = n;
    while (i < j && is_edge(c[i])) i++;
    while (j > i && is_edge(c[j - 1])) j--;
    *a = i;
    return j - i;
}

static int roman_ordinal_core(const uint32_t *w, int n) { /* [IVXLC]+(?:e|er|re|ème) fullmatch */
    int j = 0;
    while (j < n && roman_letter(w[j])) j++;
    if (!j) return 0;
    return eq_u8(w + j, n - j, "e") || eq_u8(w + j, n - j, "er") || eq_u8(w + j, n - j, "re") || eq_u8(w + j, n - j, "ème");
}

int vtts_fr_chunk_tag(const uint32_t *ch, int n, int *split) {
    *split = 0;
    /* FR_ELISION ^([\"“«(]*(?:clitics)['’])(.+)$ (re.I), not aujourd'hui */
    int q = 0;
    while (q < n && (ch[q] == '"' || ch[q] == 0x201C || ch[q] == 0xAB || ch[q] == '(')) q++;
    static const char AUJ[] = "aujourd'hui";
    int auj = n >= 11;
    for (int k = 0; k < 11 && auj; k++) {
        uint32_t c = ch[k] == 0x130 ? 'i' : vtts_u_lower(ch[k]);
        auj = c == (uint32_t)AUJ[k] || (k == 7 && c == 0x2019);
    }
    if (!auj)
        for (int k = 0; k < VTTS_FR_N_CLITICS; k++) {
            int l = icase_at(ch, n, q, VTTS_FR_CLITICS[k]);
            if (!l || q + l >= n || !(ch[q + l] == '\'' || ch[q + l] == 0x2019) || q + l + 1 >= n) continue;
            int r0 = q + l + 1, a, cl = core_of(ch + r0, n - r0, &a);
            int rest = cl ? word_lang(ch + r0 + a, cl) : -1;
            if (rest == 0) { *split = r0; return 0; }
            return rest;
        }
    int a, cl = core_of(ch, n, &a);
    const uint32_t *c = ch + a;
    if (cl && roman_ordinal_core(c, cl)) return -1;
    int tag = cl ? word_lang(c, cl) : -1;
    if (tag == 0) {
        int dash = 0, parts = 0, english = 0;
        for (int i = 0; i < cl; i++) dash |= c[i] == '-';
        if (dash)
            for (int x = 0; x <= cl;) {
                int y = x;
                while (y < cl && c[y] != '-') y++;
                if (y - x > 1) {
                    parts++;
                    int p0 = 0, pl = y - x;
                    (void)p0;
                    if (word_lang(c + x, pl) == 0) english = 1;
                }
                x = y + 1;
            }
        if (dash && parts && !english) return 1;
    }
    return tag;
}

/* ======================= g2p (g2p_fr) ======================= */

/* fold() of one code point into o (0, 1 or 2 letters) */
static int fold1(uint32_t c, uint32_t *o) {
    if (c < 0x80) {
        if (c >= 'A' && c <= 'Z') { o[0] = c + 32; return 1; }
        if ((c >= 'a' && c <= 'z') || c == '\'') { o[0] = c; return 1; }
        return 0;
    }
    for (int k = 0; k < VTTS_FR_N_FOLD_MULTI; k++)
        if (VTTS_FR_FOLD_MULTI[k].cp == c) {
            const char *t = VTTS_FR_FOLD_MULTI[k].text;
            int m = 0;
            uint32_t x;
            int l;
            while ((l = dec1(t, &x)) > 0) { o[m++] = x; t += l; }
            return m;
        }
    int lo = 0, hi = VTTS_FR_N_FOLD - 1, k = -1;
    while (lo <= hi) {
        int m = (lo + hi) / 2;
        if (VTTS_FR_FOLD[m].start <= c) { k = m; lo = m + 1; } else hi = m - 1;
    }
    if (k < 0 || c - VTTS_FR_FOLD[k].start >= VTTS_FR_FOLD[k].count) return 0;
    o[0] = VTTS_FR_FOLD[k].first + (c - VTTS_FR_FOLD[k].start) * VTTS_FR_FOLD[k].step;
    return 1;
}

static int fold_word(const uint32_t *w, int n, uint32_t *o) {
    int m = 0;
    for (int i = 0; i < n && m + 2 <= VTTS_FR_MAXW; i++) m += fold1(w[i], o + m);
    return m;
}

#define NASAL_E ((uint32_t)VTTS_FR_NASAL_E)

static int vowel(uint32_t c) { return c == NASAL_E || in_u8(c, VTTS_FR_VOWELS); }
static int front(uint32_t c) { return c == NASAL_E || in_u8(c, VTTS_FR_FRONT); }

static int word_in(const uint32_t *w, int n, const char *const *list, int nl) {
    return find32(w, n, list, nl) >= 0;
}

static int vowel_groups(const uint32_t *w, int n) {
    int g = 0;
    for (int i = 0; i < n; i++) if (in_u8(w[i], VTTS_FR_VOWELS) && (i == 0 || !in_u8(w[i - 1], VTTS_FR_VOWELS))) g++;
    return g;
}

static void set_tail(uint32_t *w, int *n, int cut, const char *add) { /* w = w[:-cut] + add */
    *n -= cut;
    uint32_t x;
    int l;
    while ((l = dec1(add, &x)) > 0) { w[(*n)++] = x; add += l; }
}

static int ent_read(const uint32_t *w, int n) {
    if (word_in(w, n, VTTS_FR_W_ENT, VTTS_FR_N_W_ENT)) return 1;
    if (vowel_groups(w, n - 3) == 0) return 1;
    return ends_u8(w, n, "ment") && !word_in(w, n, VTTS_FR_W_MENT_VERBS, VTTS_FR_N_W_MENT_VERBS);
}

/* _respell_end in place */
static void respell_end(uint32_t *w, int *pn) {
    int n = *pn;
#define FIN(len) word_in(w, len, VTTS_FR_W_FINAL, VTTS_FR_N_W_FINAL)
    if (FIN(n)) return;
    int plural = 0;
    if (n > 2 && w[n - 1] == 's' && w[n - 2] != 's') {
        n--;
        plural = 1;
        *pn = n;
        if (FIN(n)) return;
        w[n] = 's';
        if (FIN(n + 1)) return;
    } else if (n > 2 && w[n - 1] == 'x') {
        if ((ends_u8(w, n, "ex") || ends_u8(w, n, "ax") || ends_u8(w, n, "yx") || ends_u8(w, n, "ox") ||
             ends_u8(w, n, "ynx")) && !ends_u8(w, n, "aux") && !ends_u8(w, n, "eaux"))
            return;
        n--;
    } else if (n > 2 && w[n - 1] == 'z') {
        if (w[n - 2] == 'e') { set_tail(w, &n, 2, "é"); *pn = n; return; }
        n--;
    }
    *pn = n;
    if (ends_u8(w, n, "em") && n > 2) { set_tail(w, &n, 2, "èm"); *pn = n; return; }
    if (ends_u8(w, n, "ent") && n > 3) {
        if (plural || ent_read(w, n)) {
            if (ends_u8(w, n, "emment")) { set_tail(w, &n, 6, "am"); w[n++] = NASAL_E; }
            else { n -= 3; w[n++] = NASAL_E; }
            *pn = n;
            return;
        } else if (ends_u8(w, n, "ient") && (w[n - 5] == 'v' || w[n - 5] == 't')) {
        } else {
            *pn = n - 2;
            return;
        }
    }
    if (ends_u8(w, n, "er") && n > 2) {
        int keep = word_in(w, n, VTTS_FR_W_ER, VTTS_FR_N_W_ER) || vowel_groups(w, n - 2) == 0;
        if (!keep && plural) { w[n] = 's'; keep = word_in(w, n + 1, VTTS_FR_W_ER, VTTS_FR_N_W_ER); }
        set_tail(w, &n, 2, keep ? "èr" : "é");
        *pn = n;
        return;
    }
    if (ends_u8(w, n, "ed") && n > 2) { set_tail(w, &n, 2, "é"); *pn = n; return; }
    if (ends_u8(w, n, "et") && n > 2) { set_tail(w, &n, 2, "è"); *pn = n; return; }
    while (n > 1) {
        uint32_t last = w[n - 1], prev = w[n - 2];
        if (last == 't') {
            if (ends_u8(w, n, "ct") || ends_u8(w, n, "pt") || ends_u8(w, n, "st")) break;
            n--;
        } else if (last == 'd' || last == 'p') n--;
        else if (last == 'g' && (!vowel(prev) || (prev == 'i' && n >= 3 && vowel(w[n - 3])))) n--;
        else if (last == 'c' && (prev == 'n' || word_in(w, n, VTTS_FR_W_C_SILENT, VTTS_FR_N_W_C_SILENT))) n--;
        else if (last == 'b' && prev == 'm') n--;
        else if (last == 'l' && word_in(w, n, VTTS_FR_W_L_SILENT, VTTS_FR_N_W_L_SILENT)) n--;
        else if (last == 'f' && word_in(w, n, VTTS_FR_W_F_SILENT, VTTS_FR_N_W_F_SILENT)) n--;
        else break;
    }
    *pn = n;
#undef FIN
}

/* segments: kind V vowel, C consonant, G glide, O and U (eu) mid vowels, S schwa candidate, F final
 * e, X deleted; ph a token index (into VTTS_FR_TOKENS) */
typedef struct { char kind; uint8_t ph; } fseg_t;

static int tok(const char *name) {
    for (int k = 0; k < VTTS_FR_N_TOKENS; k++) if (!strcmp(VTTS_FR_TOKENS[k], name)) return k;
    return 0;
}

typedef struct { fseg_t *s; int n, cap; } segs_t;

static void add(segs_t *S, char kind, const char *ph) {
    if (S->n < S->cap) { S->s[S->n].kind = kind; S->s[S->n].ph = (uint8_t)tok(ph); S->n++; }
}

static int nasal(const uint32_t *w, int n, int k) { /* _nasal */
    if (k >= n || (w[k] != 'm' && w[k] != 'n')) return 0;
    return k + 1 == n || (!vowel(w[k + 1]) && w[k + 1] != 'm' && w[k + 1] != 'n' && w[k + 1] != 'h');
}

static int cluster_before(const uint32_t *w, int i) {
    return i >= 2 && (w[i - 1] == 'l' || w[i - 1] == 'r') && in_u8(w[i - 2], "pbtdkgfvc");
}

static int silent_e(const uint32_t *w, int n, int k) {
    return k < n && w[k] == 'e' && k + 2 < n && !vowel(w[k + 1]) && vowel(w[k + 2]);
}

static int ti_is_s(const uint32_t *w, int n, int i) {
    if (i == 0 || w[i - 1] == 's' || w[i - 1] == 'x') return 0;
    const uint32_t *r = w + i + 1;
    int rn = n - i - 1;
    if (rn < 2 || r[0] != 'i') return 0;
    if (rn == 2 && r[1] == 'e') return ends_u8(w, n, "atie");
    if (starts_u8(r, rn, 0, "ié") || starts_u8(r, rn, 0, "ier") || starts_u8(r, rn, 0, "iè") ||
        starts_u8(r, rn, 0, "iez") || starts_u8(r, rn, 0, "ien"))
        return starts_u8(r, rn, 0, "ience");
    return r[1] == NASAL_E || in_u8(r[1], "aeouâ");
}

static void e_before_consonants(segs_t *S, const uint32_t *w, int n, int i) {
    int j = i + 1;
    while (j < n && !vowel(w[j])) j++;
    const uint32_t *run = w + i + 1;
    int rl = j - i - 1;
    if (j == n || run[0] == 'x') { add(S, 'V', "E"); return; }
    if (rl >= 2 && run[0] == run[1]) {
        if (rl == 2 && run[0] == 's' && i <= 1 &&
            (starts_u8(w, n, 0, "ress") || starts_u8(w, n, 0, "dessus") || starts_u8(w, n, 0, "dessous")))
            add(S, 'S', "@");
        else add(S, 'V', "E");
        return;
    }
    int dig = rl >= 2 && (starts_u8(run, rl, 0, "ch") || starts_u8(run, rl, 0, "ph") || starts_u8(run, rl, 0, "th") ||
                          starts_u8(run, rl, 0, "gn") || starts_u8(run, rl, 0, "qu"));
    int single = rl == 1 || (rl == 2 && dig);
    int onset2 = word_in(run, rl, VTTS_FR_ONSET2, VTTS_FR_N_ONSET2);
    int chl = rl >= 2 && (starts_u8(run, rl, 0, "ch") || starts_u8(run, rl, 0, "ph") || starts_u8(run, rl, 0, "th")) &&
              (rl == 2 || eq_u8(run + 2, rl - 2, "l") || eq_u8(run + 2, rl - 2, "r") || eq_u8(run + 2, rl - 2, "lr"));
    if (single || onset2 || chl) add(S, 'S', "@"); else add(S, 'V', "E");
}

static void scan(segs_t *S, const uint32_t *w, int n) {
#define AT_(k) ((k) >= 0 && (k) < n ? w[k] : (uint32_t)'#')
#define ISV(k) vowel(AT_(k))
#define IS(c, set) in_u8(c, set)
    int i = 0;
    while (i < n) {
        uint32_t c = AT_(i), n1 = AT_(i + 1), n2 = AT_(i + 2), n3 = AT_(i + 3);
        int step = 1;
        if (IS(c, "aàâä")) {
            if (c == 'a' && IS(n1, "iî")) {
                if ((n2 == 'm' || n2 == 'n') && nasal(w, n, i + 2)) { add(S, 'V', "in"); step = 3; }
                else if (n2 == 'l' && (n3 == 'l' || i + 3 == n)) { add(S, 'V', "a"); add(S, 'G', "j"); step = n3 == 'l' ? 4 : 3; }
                else { add(S, 'V', "E"); step = 2; }
            } else if (c == 'a' && n1 == 'y') {
                add(S, 'V', "E");
                if (ISV(i + 2)) add(S, 'G', "j");
                step = 2;
            } else if (c == 'a' && n1 == 'u') { add(S, 'V', n2 == 'r' ? "O" : "o"); step = 2; }
            else if (c == 'a' && (n1 == 'm' || n1 == 'n') && nasal(w, n, i + 1)) { add(S, 'V', "an"); step = 2; }
            else add(S, 'V', "a");
        } else if (c == 'e') {
            if (n1 == 'a' && n2 == 'u') { add(S, 'V', "o"); step = 3; }
            else if (IS(n1, "uûœ")) {
                if (n2 == 'i' && n3 == 'l' && (AT_(i + 4) == 'l' || i + 4 == n)) {
                    add(S, 'V', "oe"); add(S, 'G', "j"); step = AT_(i + 4) == 'l' ? 5 : 4;
                } else { add(S, 'U', "eu"); step = 2; }
            } else if (IS(n1, "iî")) {
                if ((n2 == 'm' || n2 == 'n') && nasal(w, n, i + 2)) { add(S, 'V', "in"); step = 3; }
                else if (n2 == 'l' && (n3 == 'l' || i + 3 == n)) { add(S, 'V', "E"); add(S, 'G', "j"); step = n3 == 'l' ? 4 : 3; }
                else { add(S, 'V', "E"); step = 2; }
            } else if (n1 == 'y') {
                add(S, 'V', "E");
                if (ISV(i + 2)) add(S, 'G', "j");
                step = 2;
            } else if ((n1 == 'm' || n1 == 'n') && nasal(w, n, i + 1)) {
                int sc = i >= 3 && w[i - 3] == 's' && w[i - 2] == 'c';
                int ien = IS(AT_(i - 1), "iyé") && n1 == 'n' && !starts_u8(w, n, i + 2, "ce") &&
                          !(n2 == 't' && (sc || (ISV(i + 3) && !IS(AT_(i - 2), "bvt"))));
                add(S, 'V', ien ? "in" : "an");
                step = 2;
            } else if ((n1 == 'm' || n1 == 'n') && n2 == n1 && i == 0) {
                add(S, 'V', "an");
                add(S, 'C', n1 == 'm' ? "m" : "n");
                step = 3;
            } else if (n1 == 'm' && n2 == 'm' && starts_u8(w, n, i + 3, "ent") ) add(S, 'V', "a");
            else if (i == n - 1) add(S, 'F', "@");
            else if (ISV(i + 1)) { if (AT_(i - 1) != 'g') add(S, 'V', "E"); }
            else if (ISV(i - 1) && !IS(AT_(i - 1), "éè") && !(AT_(i - 1) == 'u' && IS(AT_(i - 2), "qg")) &&
                     i + 2 < n && !IS(w[i + 1], VTTS_FR_SILENT_E_VOWELS) &&
                     (w[i + 2] == NASAL_E || IS(w[i + 2], VTTS_FR_SILENT_E_VOWELS))) {
            } else e_before_consonants(S, w, n, i);
        } else if (c == 0xE9) add(S, 'V', "e");          /* é */
        else if (IS(c, "èêë")) add(S, 'V', "E");
        else if (IS(c, "iîï")) {
            if (c == 'i' && (n1 == 'm' || n1 == 'n') && nasal(w, n, i + 1)) { add(S, 'V', "in"); step = 2; }
            else if (c == 'i' && n1 == 'l' && n2 == 'l') {
                int vill = i >= 1 && i + 3 <= n && w[i - 1] == 'v' && w[i + 1] == 'l' && w[i + 2] == 'l';
                if (ISV(i - 1) && !(AT_(i - 1) == 'u' && IS(AT_(i - 2), "gq"))) add(S, 'G', "j");
                else if (i == 0 || vill || starts_any(w, n, VTTS_FR_ILL_L, VTTS_FR_N_ILL_L)) { add(S, 'V', "i"); add(S, 'C', "l"); }
                else { add(S, 'V', "i"); add(S, 'G', "j"); }
                step = 3;
            } else if (c == 'i' && n1 == 'l' && i + 2 == n && ISV(i - 1)) { add(S, 'G', "j"); step = 2; }
            else if (IS(c, "iî") && ISV(i + 1) && !(i + 2 == n && n1 == 'e') && !silent_e(w, n, i + 1)) {
                if (cluster_before(w, i)) add(S, 'V', "i");
                add(S, 'G', "j");
            } else add(S, 'V', "i");
        } else if (IS(c, "oôö")) {
            if (c == 'o' && IS(n1, "iî")) {
                if (n2 == 'n' && nasal(w, n, i + 2)) { add(S, 'G', "w"); add(S, 'V', "in"); step = 3; }
                else { add(S, 'G', "w"); add(S, 'V', "a"); step = 2; }
            } else if (c == 'o' && n1 == 'y') {
                add(S, 'G', "w"); add(S, 'V', "a");
                if (ISV(i + 2)) add(S, 'G', "j");
                step = 2;
            } else if (c == 'o' && IS(n1, "uùû")) {
                if (n2 == 'i' && n3 == 'l' && (AT_(i + 4) == 'l' || i + 4 == n)) {
                    add(S, 'V', "u"); add(S, 'G', "j"); step = AT_(i + 4) == 'l' ? 5 : 4;
                } else if (ISV(i + 2) && !(i + 3 == n && n2 == 'e') && !cluster_before(w, i) && !silent_e(w, n, i + 2)) {
                    add(S, 'G', "w"); step = 2;
                } else { add(S, 'V', "u"); step = 2; }
            } else if (c == 'o' && (n1 == 'm' || n1 == 'n') && nasal(w, n, i + 1)) { add(S, 'V', "on"); step = 2; }
            else if (c == 'o' && IS(n1, "eê")) { add(S, 'G', "w"); add(S, 'V', "a"); step = 2; }
            else if (c == 0xF4) add(S, 'V', "o");          /* ô */
            else add(S, 'O', "O");
        } else if (c == 0x153) {                           /* œ */
            if (n1 == 'u') { add(S, 'U', "eu"); step = 2; }
            else if (n1 == 'i' && n2 == 'l') { add(S, 'V', "oe"); add(S, 'G', "j"); step = 3; }
            else add(S, 'V', "e");
        } else if (c == 0xE6) add(S, 'V', "e");          /* æ */
        else if (c == NASAL_E) add(S, 'V', "an");
        else if (IS(c, "uùûü")) {
            if (c == 'u' && IS(AT_(i - 1), "cg") && starts_u8(w, n, i + 1, "eil")) {
                add(S, 'V', "oe"); add(S, 'G', "j"); step = AT_(i + 4) == 'l' ? 5 : 4;
            } else if (c == 'u' && (n1 == 'm' || n1 == 'n') && nasal(w, n, i + 1)) {
                if (n1 == 'm' && i + 2 == n && i > 0) { add(S, 'V', "O"); add(S, 'C', "m"); }
                else add(S, 'V', "un");
                step = 2;
            } else if (IS(c, "uü") && ISV(i + 1) && !(i + 2 == n && n1 == 'e') && !silent_e(w, n, i + 1)) {
                if (cluster_before(w, i)) add(S, 'V', "y"); else add(S, 'G', "H");
            } else add(S, 'V', "y");
        } else if (IS(c, "yÿ")) {
            if ((n1 == 'm' || n1 == 'n') && nasal(w, n, i + 1)) { add(S, 'V', "in"); step = 2; }
            else if (ISV(i + 1) && !(i + 2 == n && n1 == 'e')) add(S, 'G', "j");
            else add(S, 'V', "i");
        } else if (c == 'c') {
            if (n1 == 'h') {
                int hard = (n2 != '#' && !vowel(n2)) || starts_any(w, n, VTTS_FR_CH_HARD, VTTS_FR_N_CH_HARD);
                add(S, 'C', hard ? "k" : "sh");
                step = 2;
            } else if (front(n1)) add(S, 'C', "s");
            else if (n1 == 'c' && front(n2)) { add(S, 'C', "k"); add(S, 'C', "s"); step = 2; }
            else if (n1 == 'c' || n1 == 'q' || n1 == 'k') { add(S, 'C', "k"); step = n1 == 'q' && n2 == 'u' ? 3 : 2; }
            else add(S, 'C', "k");
        } else if (c == 0xE7) add(S, 'C', "s");          /* ç */
        else if (c == 'g') {
            if (AT_(i - 1) == 'n' && !vowel(n1) && n1 != 'r' && n1 != 'l' && n1 != '#') {
            } else if (n1 == 'n') {
                if (starts_any(w, n, VTTS_FR_GN_SPLIT, VTTS_FR_N_GN_SPLIT)) { add(S, 'C', "g"); add(S, 'C', "n"); }
                else add(S, 'C', "gn");
                step = 2;
            } else if (n1 == 'u' && front(n2)) { add(S, 'C', "g"); step = 2; }
            else if (front(n1)) {
                add(S, 'C', "zh");
                if (n1 == 'e' && IS(n2, "aoâô")) step = 2;
            } else if (n1 == 'g' && front(n2)) { add(S, 'C', "g"); add(S, 'C', "zh"); step = 2; }
            else if (n1 == 'g') { add(S, 'C', "g"); step = 2; }
            else add(S, 'C', "g");
        } else if (c == 'h') {
        } else if (c == 'j') add(S, 'C', "zh");
        else if (c == 'k') add(S, 'C', "k");
        else if (c == 'p') {
            if (n1 == 'h') { add(S, 'C', "f"); step = 2; }
            else if (n1 == 'p') { add(S, 'C', "p"); step = 2; }
            else if (AT_(i - 1) == 'm' && n1 == 't') {
            } else add(S, 'C', "p");
        } else if (c == 'q') {
            add(S, 'C', "k");
            if (n1 == 'u') step = 2;
        } else if (c == 's') {
            if (n1 == 's' || (n1 == 'c' && front(n2))) { add(S, 'C', "s"); step = 2; }
            else if (n1 == 'h') { add(S, 'C', "sh"); step = 2; }
            else if (ISV(i - 1) && ISV(i + 1)) add(S, 'C', "z");
            else add(S, 'C', "s");
        } else if (c == 't') {
            if (n1 == 'h' || n1 == 't') { add(S, 'C', "t"); step = 2; }
            else if (ti_is_s(w, n, i)) add(S, 'C', "s");
            else add(S, 'C', "t");
        } else if (c == 'w') add(S, 'G', "w");
        else if (c == 'x') {
            int heads = 0;
            if (i >= 2)
                for (int k = 0; k < VTTS_FR_N_EX_GZ_HEADS && !heads; k++) heads = eq_u8(w, i - 1, VTTS_FR_EX_GZ_HEADS[k]);
            if (i == 0) {
                if (starts_u8(w, n, 0, "xavier")) { add(S, 'C', "g"); add(S, 'C', "z"); }
                else { add(S, 'C', "k"); add(S, 'C', "s"); }
            } else if (starts_any(w, n, VTTS_FR_X_Z, VTTS_FR_N_X_Z)) add(S, 'C', "z");
            else if (starts_any(w, n, VTTS_FR_X_S, VTTS_FR_N_X_S)) add(S, 'C', "s");
            else if (AT_(i - 1) == 'e' && ISV(i + 1) && (i == 1 || heads)) { add(S, 'C', "g"); add(S, 'C', "z"); }
            else if (n1 == 'c' && front(n2)) { add(S, 'C', "k"); add(S, 'C', "s"); step = 2; }
            else { add(S, 'C', "k"); add(S, 'C', "s"); }
        } else if (IS(c, "bdfjlmnrvz")) {
            char nm[2] = {(char)c, 0};
            add(S, 'C', nm);
            if (n1 == c) step = 2;
        }
        i += step;
    }
#undef AT_
#undef ISV
#undef IS
}

static int seg_vowel(const fseg_t *s) { return s->kind == 'V' || s->kind == 'O' || s->kind == 'U' || s->kind == 'S'; }

/* _resolve: final e, e muet, mid vowels; appends token ids */
static void resolve(segs_t *S, uint8_t *out, int *no, int cap) {
    fseg_t *s = S->s;
    int n = S->n, nv = 0;
    for (int k = 0; k < n; k++) nv += s[k].kind == 'V' || s[k].kind == 'O' || s[k].kind == 'U' || s[k].kind == 'S';
    for (int k = 0; k < n; k++)
        if (s[k].kind == 'F') { if (nv == 0) s[k].kind = 'S'; else s[k].kind = 'X'; }
    for (int k = 0; k < n; k++) {
        if (s[k].kind != 'S') continue;
        int before = 0, prev_v = 0, after_v = 0;
        for (int t = k - 1; t >= 0; t--) {
            if (s[t].kind == 'X') continue;
            if (seg_vowel(&s[t])) { prev_v = 1; break; }
            before++;
        }
        for (int t = k + 1; t < n && !after_v; t++) after_v = seg_vowel(&s[t]);
        if (prev_v && before == 1 && after_v) s[k].kind = 'X';
    }
    static const char OBS[] = "pbtdkgfv";
    for (int k = 0; k < n; k++) {
        if (s[k].kind == 'X') continue;
        int ph = s[k].ph;
        if (s[k].kind == 'O' || s[k].kind == 'U') {
            int cons[64], nc = 0, nxt_v = 0;
            for (int t = k + 1; t < n; t++) {
                if (s[t].kind == 'X') continue;
                if (seg_vowel(&s[t])) { nxt_v = 1; break; }
                if (nc < 64) cons[nc++] = s[t].ph;
            }
            if (nxt_v)
                while (nc && (cons[nc - 1] == tok("j") || cons[nc - 1] == tok("w") || cons[nc - 1] == tok("H"))) nc--;
            if (s[k].kind == 'O') ph = (!nxt_v && !nc) || (nc && cons[0] == tok("z")) ? tok("o") : tok("O");
            else {
                const char *c0 = nc ? VTTS_FR_TOKENS[cons[0]] : "", *c1 = nc > 1 ? VTTS_FR_TOKENS[cons[1]] : "";
                int closed = (nc >= 1 && !nxt_v && !(nc == 1 && cons[0] == tok("z"))) ||
                             (nc >= 2 && !(nc == 2 && strlen(c0) == 1 && strchr(OBS, c0[0]) &&
                                           (!strcmp(c1, "l") || !strcmp(c1, "r"))));
                ph = closed ? tok("oe") : tok("eu");
            }
        }
        if (*no < cap) out[(*no)++] = (uint8_t)(VTTS_FR_TOK0 + ph);
    }
}

typedef struct {
    uint8_t *out;
    int n, cap;
    uint32_t *B, *H;  /* scratch words: the rules' copy, a head + "e" */
    fseg_t *seg;
    int seg_cap;
} g2p_t;

static void emit_names(g2p_t *G, const char *names) { /* "m @ s j eu" */
    char b[8];
    while (*names) {
        int l = 0;
        while (names[l] && names[l] != ' ' && l < 7) { b[l] = names[l]; l++; }
        b[l] = 0;
        if (G->n < G->cap) G->out[G->n++] = (uint8_t)(VTTS_FR_TOK0 + tok(b));
        names += l;
        while (*names == ' ') names++;
    }
}

/* _rules(w) of folded code points */
static void rules(g2p_t *G, const uint32_t *w, int n) {
    if (n > VTTS_FR_MAXW) n = VTTS_FR_MAXW;
    if (G->B != w) memmove(G->B, w, (size_t)n * sizeof *w);
    segs_t S = {G->seg, 0, G->seg_cap};
    respell_end(G->B, &n);
    scan(&S, G->B, n);
    resolve(&S, G->out, &G->n, G->cap);
}

static void read_table(g2p_t *G, const char *reading) {
    if (strchr(reading, ' ')) { emit_names(G, reading); return; }
    uint32_t x;
    int l, n = 0;
    while ((l = dec1(reading, &x)) > 0 && n < VTTS_FR_MAXW) { G->B[n++] = x; reading += l; }
    rules(G, G->B, n);
}

static int table_of(const uint32_t *w, int n) { return find32_pairs(w, n, VTTS_FR_OVERRIDES, VTTS_FR_N_OVERRIDES); }
static int prefix_of(const uint32_t *w, int n) { return find32_pairs(w, n, VTTS_FR_PREFIX, VTTS_FR_N_PREFIX); }

/* phonemes() of a word without an apostrophe: the table, the table without a plural s, the rules */
static void phon_plain(g2p_t *G, const uint32_t *w, int n) {
    if (!n) return;
    int t = table_of(w, n);
    if (t >= 0) { read_table(G, VTTS_FR_OVERRIDES[t][1]); return; }
    if (w[n - 1] == 's') {
        t = table_of(w, n - 1);
        if (t >= 0 && !word_in(w, n - 1, VTTS_FR_W_FINAL, VTTS_FR_N_W_FINAL)) { read_table(G, VTTS_FR_OVERRIDES[t][1]); return; }
    }
    rules(G, w, n);
}

/* phonemes(head + "e") of a head ending in qu (jusqu', lorsqu') */
static void phon_que(g2p_t *G, const uint32_t *w, int h) {
    if (h > VTTS_FR_MAXW) h = VTTS_FR_MAXW;
    memmove(G->H, w, (size_t)h * sizeof *w);
    G->H[h] = 'e';
    phon_plain(G, G->H, h + 1);
}

/* phonemes() of a folded word (apostrophes may remain); the apostrophe parts are read in a loop */
static void phon(g2p_t *G, const uint32_t *w, int n) {
    for (;;) {
        while (n > 0 && w[0] == '\'') { w++; n--; } /* lstrip */
        int m = n, inner = -1;
        while (m > 0 && w[m - 1] == '\'') m--;     /* rstrip */
        if (!m) return;
        for (int i = 0; i < m && inner < 0; i++) if (w[i] == '\'') inner = i;
        if (m < n && inner < 0) { /* an elided clitic before an English word: l' */
            int p = prefix_of(w, m);
            if (p >= 0) { emit_names(G, VTTS_FR_PREFIX[p][1]); return; }
            if (m >= 2 && w[m - 2] == 'q' && w[m - 1] == 'u') { phon_que(G, w, m); return; }
        }
        n = m;
        int t = table_of(w, n);
        if (t >= 0) { read_table(G, VTTS_FR_OVERRIDES[t][1]); return; }
        if (inner < 0) { phon_plain(G, w, n); return; }
        int h = inner, p = prefix_of(w, h);
        if (p >= 0) emit_names(G, VTTS_FR_PREFIX[p][1]);
        else if (h >= 2 && w[h - 2] == 'q' && w[h - 1] == 'u') phon_que(G, w, h);
        else phon_plain(G, w, h);
        w += h + 1;
        n -= h + 1;
    }
}

/* word_tokens_fr: a word without a vowel is spelled letter by letter */
static void word_ids(g2p_t *G, const uint32_t *w, int n) {
    int a = 0, apo = 0, vow = 0;
    while (a < n && w[a] == '\'') a++;
    for (int i = a; i < n; i++) { apo |= w[i] == '\''; vow |= vowel(w[i]); }
    if (n > a && !apo && !vow && table_of(w + a, n - a) < 0) {
        for (int i = a; i < n; i++) {
            if (w[i] < 'a' || w[i] > 'z') continue;
            const char *nm = VTTS_FR_LETTER_NAMES[w[i] - 'a'];
            while (*nm) { /* each space-separated part of the name is read as a word */
                uint32_t part[16], x;
                int pl = 0, l;
                while (*nm && *nm != ' ' && (l = dec1(nm, &x)) > 0) { if (pl < 16) part[pl++] = x; nm += l; }
                phon(G, part, pl);
                while (*nm == ' ') nm++;
            }
        }
        return;
    }
    phon(G, w, n);
}

int vtts_fr_word_ids(const uint32_t *word, int wn, uint32_t *scratch, uint8_t *out, int cap) {
    const int W = VTTS_FR_MAXW + 4;
    uint32_t *f = scratch;
    g2p_t G = {out, 0, cap, scratch + W, scratch + 2 * W, (fseg_t *)(void *)(scratch + 3 * W),
               (int)((VTTS_FR_SCRATCH - 3 * W) * sizeof(uint32_t) / sizeof(fseg_t))};
    int n = fold_word(word, wn, f);
    word_ids(&G, f, n);
    return G.n;
}

#endif /* VTTS_ENABLE_FR */
