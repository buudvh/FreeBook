/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_tl.c -- Tagalog (Filipino) pair language of the device front-end, token set tl-en.
 * Mirrors src/vtts/frontend/latin.py (tagging of plain Latin words in mode tl), latin_norm.py and
 * tl/normalize_tl.py (normalization, pass by pass, with the regexes' backtracking order) and
 * tl/g2p_tl.py (spelling rules, glottal stops, stress table with affixes and clitics). Tables are
 * generated into vtts_text_tl_tables.h; Python's \w, \d, \s and lower() and the English word list
 * come from vtts_text_lt.c. Compiled only with VTTS_ENABLE_TL. */
#include "vtts_langs.h"
#if VTTS_ENABLE_TL /* else an empty unit (vtts_langs.h) */

#include "vtts_text_tl.h"

#include <string.h>

#include "vtts_text_lt.h"
#include "vtts_text_tl_tables.h"

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

static int in_u8(uint32_t c, const char *set) { /* c is a code point of the UTF-8 string set */
    uint32_t x;
    int l;
    if (!c) return 0;
    while ((l = dec1(set, &x)) > 0) { if (x == c) return 1; set += l; }
    return 0;
}

static int in_sorted(const char *const *list, int n, const char *w) {
    int lo = 0, hi = n - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2, c = strcmp(list[m], w);
        if (!c) return 1;
        if (c < 0) lo = m + 1; else hi = m - 1;
    }
    return 0;
}

static int in_list(const char *const *list, int n, const char *s, int len) {
    for (int k = 0; k < n; k++) if ((int)strlen(list[k]) == len && memcmp(list[k], s, (size_t)len) == 0) return 1;
    return 0;
}

static int in_u16(const uint16_t *a, int n, uint32_t c) { /* sorted */
    int lo = 0, hi = n - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2;
        if (a[m] == c) return 1;
        if (a[m] < c) lo = m + 1; else hi = m - 1;
    }
    return 0;
}

static int is_letter(uint32_t c) { return c != '_' && vtts_u_word(c) && vtts_u_digit(c) < 0; } /* [^\W\d_] */
static int upper_az(uint32_t c) { return c >= 'A' && c <= 'Z'; }
static int vowel(uint32_t c) { return c == 'a' || c == 'e' || c == 'i' || c == 'o' || c == 'u'; }

/* re.IGNORECASE: c matches the lower-case ASCII letter l */
static int icase(uint32_t c, char l) {
    for (const uint32_t *v = VTTS_TL_ICASE[l - 'a']; *v; v++) if (*v == c) return 1;
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

/* str.lower() of one code point (U+0130 lowers to i U+0307) */
static void put_lower(lb_t *d, uint32_t c) {
    if (c == 0x130) { put(d, 'i'); put(d, 0x307); }
    else put(d, vtts_u_lower(c));
}

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

static int skip_sp(const uint32_t *s, int n, int i) {
    while (SP(i)) i++;
    return i;
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

/* ASCII key (lower-case letters match re.IGNORECASE, other characters exactly) at s[i]: its length or 0 */
static int key_icase(const uint32_t *s, int n, int i, const char *k) {
    int m = 0;
    for (; k[m]; m++) {
        if (!IN(i + m)) return 0;
        if (k[m] >= 'a' && k[m] <= 'z' ? !icase(s[i + m], k[m]) : s[i + m] != (uint32_t)k[m]) return 0;
    }
    return m;
}

/* ======================= numbers ======================= */

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

static uint64_t value(const uint32_t *s, int n, int st) {
    uint64_t v = 0;
    for (int i = st; i < n; i++) { int x = vtts_u_digit(s[i]); if (x >= 0) v = v * 10 + (uint64_t)x; }
    return v;
}

/* the names of the digits of s[from..n), joined by spaces */
static void digit_words(lb_t *d, const uint32_t *s, int n, int from) {
    int first = 1;
    for (int i = from; i < n; i++) {
        int v = vtts_u_digit(s[i]);
        if (v < 0) continue;
        if (!first) put(d, ' ');
        puts8(d, VTTS_TL_ONES[v]);
        first = 0;
    }
}

/* linked() of the text written so far: isa -> isang, milyon -> milyong, apat -> apat na */
static void linked(lb_t *d) {
    uint32_t c = d->n ? d->p[d->n - 1] : 0;
    if (vowel(c)) puts8(d, "ng");
    else if (c == 'n') put(d, 'g');
    else puts8(d, " na");
}

static int ends_vowel(const char *s) { size_t l = strlen(s); return l && vowel((uint32_t)(unsigned char)s[l - 1]); }

static void below_100(lb_t *d, int v) {
    if (v < 10) puts8(d, VTTS_TL_ONES[v]);
    else if (v < 20) puts8(d, VTTS_TL_TEENS[v - 10]);
    else {
        puts8(d, VTTS_TL_TENS[v / 10]);
        if (v % 10) { puts8(d, "'t "); puts8(d, VTTS_TL_ONES[v % 10]); }
    }
}

static void below_1000(lb_t *d, int v) {
    int h = v / 100, r = v % 100;
    if (h) {
        puts8(d, VTTS_TL_ONES[h]);
        linked(d);
        puts8(d, ends_vowel(VTTS_TL_ONES[h]) ? " daan" : " raan");
    }
    if (r) { if (h) puts8(d, " at "); below_100(d, r); }
}

static void card_v(lb_t *d, uint64_t v) { /* cardinal(v), 0 < v < 10^15 */
    static const uint64_t SC[4] = {1000000000000ull, 1000000000ull, 1000000ull, 1000ull};
    int any = 0;
    for (int k = 0; k < 4; k++) {
        uint64_t q = v / SC[k];
        v %= SC[k];
        if (!q) continue;
        if (any) puts8(d, " at ");
        below_1000(d, (int)q);
        linked(d);
        put(d, ' ');
        puts8(d, VTTS_TL_SCALES[k]);
        any = 1;
    }
    if (v) { if (any) puts8(d, " at "); below_1000(d, (int)v); }
}

/* cardinal(int(digits of s[0..n))) */
static void card(lb_t *d, const uint32_t *s, int n) {
    int st, nd = sig(s, n, &st);
    if (!nd) puts8(d, VTTS_TL_ONES[0]);
    else if (nd > 15) digit_words(d, s, n, st);
    else card_v(d, value(s, n, st));
}

static void card_i(lb_t *d, int v) {
    if (v <= 0) { puts8(d, VTTS_TL_ONES[0]); return; }
    card_v(d, (uint64_t)v);
}

/* ordinal(int(digits)): 1 una, 2 ikalawa, 3 ikatlo, else ika + cardinal */
static void ordinal(lb_t *d, const uint32_t *s, int n) {
    int st, nd = sig(s, n, &st);
    int v = nd == 1 ? vtts_u_digit(s[st]) : 0;
    if (v == 1) puts8(d, "una");
    else if (v == 2) puts8(d, "ikalawa");
    else if (v == 3) puts8(d, "ikatlo");
    else { puts8(d, "ika"); card(d, s, n); }
}

static void ordinal_i(lb_t *d, int v) {
    uint32_t b[12];
    int k = 0;
    char t[12];
    int m = 0;
    do { t[m++] = (char)('0' + v % 10); v /= 10; } while (v && m < 11);
    while (m) b[k++] = (uint32_t)t[--m];
    ordinal(d, b, k);
}

/* spanish(v), 1 <= v <= 999: prices and clock minutes */
static void spanish(lb_t *d, int v) {
    int h = v / 100, r = v % 100, any = 0;
    if (h) { puts8(d, h == 1 && !r ? "siyen" : VTTS_TL_ES_HUNDREDS[h]); any = 1; }
    if (!r) return;
    if (any) put(d, ' ');
    if (r < 20) { puts8(d, VTTS_TL_ES_ONES[r]); return; }
    puts8(d, VTTS_TL_ES_TENS[r / 10]);
    if (r % 10) { puts8(d, r / 10 == 2 ? " " : "'y "); puts8(d, VTTS_TL_ES_ONES[r % 10]); }
}

/* \d{1,3}(<g>\d{3})+ from 0, then the end or what follows: the end of the groups, or -1 */
static int groups(const uint32_t *s, int n, uint32_t g, int min_groups) {
    int r = drun(s, n, 0), i, cnt = 0;
    if (r < 1 || r > 3) return -1;
    for (i = r; AT(i, g) && drun(s, n, i + 1) >= 3 && !DG(i + 4); i += 4) cnt++;
    return cnt >= min_groups ? i : -1;
}

/* normalize_tl.parse_number of s[0..n): integer part [0, *ie) (commas, points skipped), decimals
 * [*f0, n) or *f0 = -1 */
static void parse_number(const uint32_t *s, int n, int *ie, int *f0) {
    int e = groups(s, n, ',', 1); /* \d{1,3}(,\d{3})+(\.\d+)? */
    if (e == n) { *ie = n; *f0 = -1; return; }
    if (e >= 0 && AT(e, '.') && e + 1 < n && drun(s, n, e + 1) == n - e - 1) { *ie = e; *f0 = e + 1; return; }
    if (groups(s, n, '.', 2) == n) { *ie = n; *f0 = -1; return; } /* \d{1,3}(\.\d{3}){2,} */
    for (int m = 0; m < 2; m++) {
        uint32_t c = m ? ',' : '.';
        for (int i = 0; i < n; i++)
            if (s[i] == c) { *ie = i; *f0 = i + 1; return; }
    }
    *ie = n;
    *f0 = -1;
}

/* number(sign + s); returns 1 when there are decimals */
static int number(lb_t *d, const uint32_t *s, int n, int neg) {
    int ie, f0;
    parse_number(s, n, &ie, &f0);
    if (neg) puts8(d, "minus ");
    card(d, s, ie);
    if (f0 < 0) return 0;
    if (f0 < n) { puts8(d, " punto "); digit_words(d, s, n, f0); }
    return 1;
}

/* ======================= normalization passes =======================
 * Each regex pass of normalize_tl is one function from s (n code points) to d; matches are found
 * left to right without overlap, like re.sub, and lookarounds look at the pass's input. Where
 * backtracking can change a match, the candidate ends are tried in the regex's order. */

typedef int (*end_ok)(const uint32_t *s, int n, int end, void *u);

static int try_dec(const uint32_t *s, int n, int b, end_ok ok, void *u) { /* (?:[.,]\d+)? at b, then ok() */
    if ((AT(b, '.') || AT(b, ',')) && DG(b + 1))
        for (int k = drun(s, n, b + 1); k >= 1; k--) if (ok(s, n, b + 1 + k, u)) return b + 1 + k;
    return ok(s, n, b, u) ? b : -1;
}

/* NUM = \d{1,3}(?:[.,]\d{3})+(?:[.,]\d+)?|\d+(?:[.,]\d+)? at j: the first end, in the regex's order,
 * that ok() accepts; -1 if none */
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

static int ok_unit(const uint32_t *s, int n, int e, void *u) { /* \s?(UNITS)(?![\w]) */
    unit_m *m = u;
    for (int sp = SP(e); sp >= 0; sp--)
        for (int k = 0; k < VTTS_TL_N_UNITS; k++) {
            int l = key_at(s, n, e + sp, VTTS_TL_UNITS[k][0]);
            if (l && !W(e + sp + l)) { m->key = k; m->end = e + sp + l; return 1; }
        }
    return 0;
}

/* NEXT_WORD = \s+([a-zñ']+) matches at e and its word is not in NO_LINKER: a noun follows */
static int noun_after(const uint32_t *s, int n, int e) {
    char w[16];
    int q = skip_sp(s, n, e), a = q, len = 0, listed = 1;
    if (q == e) return 0;
    while (IN(q) && ((s[q] >= 'a' && s[q] <= 'z') || s[q] == 0xF1 || s[q] == '\'')) {
        if (s[q] < 0x80 && len < (int)sizeof w - 1) w[len++] = (char)s[q];
        else listed = 0;
        q++;
    }
    if (q == a) return 0;
    w[len] = 0;
    return !(listed && in_sorted(VTTS_TL_NO_LINKER, VTTS_TL_N_NO_LINKER, w));
}

/* apply_abbreviations, one key: (?<![\w])KEY[(?![\w])] -> " reading " (+ "." at the end of the text) */
static void p_abbrev(int k, const uint32_t *s, int n, lb_t *d) {
    const char *key = VTTS_TL_ABBREV[k][0];
    int dot = key[strlen(key) - 1] == '.';
    for (int i = 0; i < n;) {
        int m;
        if (!W(i - 1) && (m = key_at(s, n, i, key)) && (dot || !W(i + m))) {
            int end = dot;
            for (int q = i + m; q < n && end; q++) end = vtts_u_space(s[q]);
            put(d, ' ');
            puts8(d, VTTS_TL_ABBREV[k][1]);
            put(d, ' ');
            if (end) put(d, '.');
            i += m;
            continue;
        }
        put(d, s[i++]);
    }
}

static void p_drop(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n; i++) put(d, in_u8(s[i], VTTS_TL_DROP) ? ' ' : s[i]);
}

/* _date(m, d, y) or "" (*ok = 0) */
static int date_out(lb_t *d, int mm, int dd, const uint32_t *y, int yl) {
    if (!(dd >= 1 && dd <= 31 && mm >= 1 && mm <= 12)) return 0;
    put(d, ' ');
    ordinal_i(d, dd);
    puts8(d, " ng ");
    puts8(d, VTTS_TL_MONTHS[mm]);
    if (y) { puts8(d, " , "); card_i(d, val(y, 0, yl) + (yl == 2 ? 2000 : 0)); }
    put(d, ' ');
    return 1;
}

/* (?<![\d-])(\d{4})-(\d{1,2})-(\d{1,2})(?![\d-]) -> _date(m, d, y) */
static void p_date_iso(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !DG(i - 1) && !AT(i - 1, '-') && DG(i + 1) && DG(i + 2) && DG(i + 3) && AT(i + 4, '-')) {
            int m0 = i + 5, ml = drun(s, n, m0);
            if (ml >= 1 && ml <= 2 && AT(m0 + ml, '-')) {
                int d0 = m0 + ml + 1, dl = drun(s, n, d0);
                if (dl >= 1 && dl <= 2 && !AT(d0 + dl, '-')) {
                    if (!date_out(d, val(s, m0, ml), val(s, d0, dl), s + i, 4)) putn(d, s + i, d0 + dl - i);
                    i = d0 + dl;
                    continue;
                }
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![\d/])(\d{1,2})/(\d{1,2})/(\d{4}|\d{2})(?![\d/]) -> month first, else day first */
static void p_date_mdy(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !DG(i - 1) && !AT(i - 1, '/')) {
            int r1 = drun(s, n, i);
            if (r1 <= 2 && AT(i + r1, '/')) {
                int m0 = i + r1 + 1, r2 = drun(s, n, m0);
                if (r2 >= 1 && r2 <= 2 && AT(m0 + r2, '/')) {
                    int y0 = m0 + r2 + 1, ry = drun(s, n, y0);
                    if ((ry == 4 || ry == 2) && !AT(y0 + ry, '/')) {
                        int a = val(s, i, r1), b = val(s, m0, r2);
                        if (!date_out(d, a, b, s + y0, ry) && !date_out(d, b, a, s + y0, ry)) putn(d, s + i, y0 + ry - i);
                        i = y0 + ry;
                        continue;
                    }
                }
            }
        }
        put(d, s[i++]);
    }
}

/* (?:,?\s+(\d{4}))? at e: the year's start or -1; tail_ok: (?![\d]) (word = 0) or (?![\w]) (word = 1) */
static int year_at(const uint32_t *s, int n, int e, int word) {
    int p = e + AT(e, ',');
    if (!SP(p)) return -1;
    int q = skip_sp(s, n, p);
    if (drun(s, n, q) < 4) return -1;
    if (word ? W(q + 4) : DG(q + 4)) return -1;
    return q;
}

/* (?<![\w])(MONTH)\s+(\d{1,2})(?:,?\s+(\d{4}))?(?![\d]) (re.IGNORECASE) -> _date(month, day, year) */
static void p_date_month_day(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!W(i - 1)) {
            int done = 0;
            for (int k = 0; k < VTTS_TL_N_MONTH_KEYS && !done; k++) {
                int l = key_icase(s, n, i, VTTS_TL_MONTH_KEYS[k].key);
                if (!l || !SP(i + l)) continue;
                int j = skip_sp(s, n, i + l), r = drun(s, n, j);
                if (r < 1 || r > 2) continue;
                int y = year_at(s, n, j + r, 0), end = y >= 0 ? y + 4 : j + r;
                if (!date_out(d, VTTS_TL_MONTH_KEYS[k].month, val(s, j, r), y >= 0 ? s + y : NULL, 4)) putn(d, s + i, end - i);
                i = end;
                done = 1;
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

/* (?<![\w.,])(\d{1,2})\s+(MONTH)(?:,?\s+(\d{4}))?(?![\w]) (re.IGNORECASE) */
static void p_date_day_month(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !WDC(i - 1)) {
            int r = drun(s, n, i), done = 0;
            if (r <= 2 && SP(i + r)) {
                int j = skip_sp(s, n, i + r);
                for (int k = 0; k < VTTS_TL_N_MONTH_KEYS && !done; k++) {
                    int l = key_icase(s, n, j, VTTS_TL_MONTH_KEYS[k].key);
                    if (!l) continue;
                    int e = j + l, y = year_at(s, n, e, 1), end = y >= 0 ? y + 4 : e;
                    if (y < 0 && W(e)) continue;
                    if (!date_out(d, VTTS_TL_MONTH_KEYS[k].month, val(s, i, r), y >= 0 ? s + y : NULL, 4))
                        putn(d, s + i, end - i);
                    i = end;
                    done = 1;
                }
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

static int m05(const uint32_t *s, int n, int j) { return IN(j) && s[j] >= '0' && s[j] <= '5' && DG(j + 1); } /* [0-5]\d */
static int no_dc(const uint32_t *s, int n, int e) { return !DG(e) && !AT(e, ':'); }

/* (?<![\d:.])([01]?\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?(?![\d:]) at p: the end or -1 */
static int clock_at(const uint32_t *s, int n, int p, int *h, int *mi) {
    int hl[3], nh = 0;
    if (!DG(p) || DG(p - 1) || AT(p - 1, ':') || AT(p - 1, '.')) return -1;
    if ((AT(p, '0') || AT(p, '1')) && DG(p + 1)) hl[nh++] = 2;
    hl[nh++] = 1;
    if (AT(p, '2') && IN(p + 1) && s[p + 1] >= '0' && s[p + 1] <= '3') hl[nh++] = 2;
    for (int c = 0; c < nh; c++) {
        int j = p + hl[c];
        if (!(AT(j, ':') && m05(s, n, j + 1))) continue;
        int k = j + 3, e = AT(k, ':') && m05(s, n, k + 1) ? k + 3 : k;
        if (!no_dc(s, n, e)) continue;
        *h = val(s, p, hl[c]);
        *mi = val(s, j + 1, 2);
        return e;
    }
    return -1;
}

/* (\s+(?:ng\s+(?:umaga|tanghali|hapon|gabi|madaling\s+araw|hatinggabi)|[ap]\.?m\.?(?![\w])))? at e:
 * the end of the part of the day, *w the start of its words; -1 if none */
static int day_part(const uint32_t *s, int n, int e, int *w) {
    static const char *const WORDS[] = {"umaga", "tanghali", "hapon", "gabi", "madaling", "hatinggabi"};
    if (!SP(e)) return -1;
    int q = skip_sp(s, n, e);
    *w = q;
    if (key_icase(s, n, q, "ng") && SP(q + 2)) {
        int r = skip_sp(s, n, q + 2);
        for (int k = 0; k < 6; k++) {
            int l = key_icase(s, n, r, WORDS[k]);
            if (!l) continue;
            if (k != 4) return r + l;
            if (SP(r + l)) { int t = skip_sp(s, n, r + l), l2 = key_icase(s, n, t, "araw"); if (l2) return t + l2; }
        }
    }
    if (IN(q) && (icase(s[q], 'a') || icase(s[q], 'p')))
        for (int d1 = AT(q + 1, '.'); d1 >= 0; d1--) {
            int mp = q + 1 + d1;
            if (!(IN(mp) && icase(s[mp], 'm'))) continue;
            for (int d2 = AT(mp + 1, '.'); d2 >= 0; d2--)
                if (!W(mp + 1 + d2)) return mp + 1 + d2;
        }
    return -1;
}

/* TIME: (?:(?<![\w])(?:alas|ala)[\s-]+)?CLOCK(PART)? (re.IGNORECASE) -> _time() */
static void p_time(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        int h = 0, mi = 0, end = -1;
        if (!W(i - 1))
            for (int a = 0; a < 2 && end < 0; a++) {
                int l = key_icase(s, n, i, a ? "ala" : "alas");
                if (!l || !SPD(i + l)) continue;
                int p = i + l;
                while (SPD(p)) p++;
                end = clock_at(s, n, p, &h, &mi);
            }
        if (end < 0) end = clock_at(s, n, i, &h, &mi);
        if (end < 0) { put(d, s[i++]); continue; }
        int h12 = h % 12 ? h % 12 : 12, w0 = 0, pe = day_part(s, n, end, &w0);
        put(d, ' ');
        if (h12 == 1) puts8(d, "ala una");
        else { puts8(d, "alas "); puts8(d, VTTS_TL_ES_ONES[h12]); }
        if (mi == 30) puts8(d, " i medya");
        else if (mi) { puts8(d, " i "); spanish(d, mi); }
        if (pe >= 0) {
            if (icase(s[w0], 'n')) { /* ng ...: the words as written, lower-cased */
                put(d, ' ');
                for (int q = w0; q < pe; q++) put_lower(d, s[q]);
            } else if (icase(s[w0], 'a')) puts8(d, " ng umaga");
            else puts8(d, h12 < 6 || h12 == 12 ? " ng hapon" : " ng gabi");
            end = pe;
        } else if (h == 0) puts8(d, " ng hatinggabi");
        else if (h >= 13 && h <= 17) puts8(d, " ng hapon");
        else if (h >= 18) puts8(d, " ng gabi");
        put(d, ' ');
        i = end;
    }
}

/* \d{lo,hi}(?:[\s-]\d{lo,hi}){gmin,gmax}(?![\d]) at q: the end or -1 */
static int phone_core(const uint32_t *s, int n, int q, int lo, int hi, int gmin, int gmax) {
    int r = drun(s, n, q), e = q + r, cnt = 0;
    if (r < lo || r > hi) return -1;
    while (cnt < gmax && SPD(e)) {
        int r2 = drun(s, n, e + 1);
        if (r2 < lo || r2 > hi) break;
        e += 1 + r2;
        cnt++;
    }
    return cnt >= gmin ? e : -1;
}

/* PHONE: (?<![\d])(?:\+\d{1,3}[\s-])?\d{2,4}(?:[\s-]\d{2,4}){2,4}(?![\d]) | (?<![\d.,])0\d{2,}(?![\d]|[.,]\d)
 * -> phone_digits(m, ONES, "plus") */
static void p_phone(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        int e = -1;
        if (!DG(i - 1) && (AT(i, '+') || DG(i))) {
            for (int pre = AT(i, '+'); pre >= 0 && e < 0; pre--) {
                int p = i;
                if (pre) {
                    int r = drun(s, n, i + 1);
                    if (!(r >= 1 && r <= 3 && SPD(i + 1 + r))) continue;
                    p = i + 2 + r;
                }
                e = phone_core(s, n, p, 2, 4, 2, 4);
            }
        }
        if (e < 0 && AT(i, '0') && !DG(i - 1) && !AT(i - 1, '.') && !AT(i - 1, ',')) {
            int r = drun(s, n, i), q = i + r;
            if (r >= 3 && !((AT(q, '.') || AT(q, ',')) && DG(q + 1))) e = q;
        }
        if (e >= 0) {
            int cnt = 0;
            for (int q = i; q < e; q++) cnt += vtts_u_digit(s[q]) >= 0;
            if (cnt < 7 && s[i] != '0') putn(d, s + i, e - i);
            else {
                put(d, ' ');
                if (s[i] == '+') puts8(d, "plus ");
                digit_words(d, s, e, i);
                put(d, ' ');
            }
            i = e;
            continue;
        }
        put(d, s[i++]);
    }
}

/* _money(cur, num, scale) */
static void money_out(lb_t *d, const uint32_t *num, int nn, const char *name, const char *scale) {
    put(d, ' ');
    if (scale) {
        number(d, num, nn, 0);
        put(d, ' ');
        puts8(d, scale);
        put(d, ' ');
        puts8(d, name);
        put(d, ' ');
        return;
    }
    int ie, f0, st, piso = strcmp(name, "piso") == 0;
    parse_number(num, nn, &ie, &f0);
    int nd = sig(num, ie, &st), cents = 0;
    if (f0 >= 0) { /* int(frac[:2].ljust(2, "0")) */
        int a = f0 < nn ? vtts_u_digit(num[f0]) : 0, b = f0 + 1 < nn ? vtts_u_digit(num[f0 + 1]) : 0;
        cents = a * 10 + b;
    }
    uint64_t v = nd <= 15 ? value(num, ie, st) : 1000;
    if (piso && !cents && v >= 2 && v <= 999) {
        spanish(d, (int)v);
        puts8(d, " pesos ");
        return;
    }
    if (cents && !piso) { /* number(num) + name */
        number(d, num, nn, 0);
        put(d, ' ');
        puts8(d, name);
    } else {
        if (nd || !cents) { /* linked(cardinal(n)) + name when n or not cents */
            card(d, num, ie);
            linked(d);
            put(d, ' ');
            puts8(d, name);
            if (cents) puts8(d, " at ");
        }
        if (cents) {
            card_i(d, cents);
            linked(d);
            puts8(d, " sentimo");
        }
    }
    put(d, ' ');
}

/* (CUR)\s?(NUM)(\s?(?:libo|milyon|bilyon|trilyon))? */
static void p_money_before(const uint32_t *s, int n, lb_t *d) {
    static const char *const SCALES[] = {"libo", "milyon", "bilyon", "trilyon"};
    for (int i = 0; i < n;) {
        int e = -1, j = 0, k;
        for (k = 0; k < VTTS_TL_N_CURRENCY && e < 0; k++) {
            int l = key_at(s, n, i, VTTS_TL_CURRENCY[k][0]);
            if (!l) continue;
            for (int sp = SP(i + l); sp >= 0 && e < 0; sp--) {
                j = i + l + sp;
                e = num_match(s, n, j, ok_always, NULL);
            }
        }
        if (e < 0) { put(d, s[i++]); continue; }
        const char *name = VTTS_TL_CURRENCY[k - 1][1], *scale = NULL;
        int end = e;
        for (int sp = SP(e); sp >= 0 && !scale; sp--)
            for (int a = 0; a < 4 && !scale; a++) {
                int l = key_at(s, n, e + sp, SCALES[a]);
                if (l) { scale = SCALES[a]; end = e + sp + l; }
            }
        money_out(d, s + j, e - j, name, scale);
        i = end;
    }
}

/* (?<![\w.,])(-?)(NUM)\s?% -> " linked(number) porsiyento " */
static void p_percent(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int j = i + AT(i, '-'), end = 0, e = num_match(s, n, j, ok_pct, &end);
            if (e >= 0) {
                put(d, ' ');
                number(d, s + j, e - j, j > i);
                linked(d);
                puts8(d, " porsiyento ");
                i = end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![\w.,])(-?)(NUM)\s?(UNITS)(?![\w]) -> " linked(number) UNIT " */
static void p_unit(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            unit_m m = {0, 0};
            int j = i + AT(i, '-'), e = num_match(s, n, j, ok_unit, &m);
            if (e >= 0) {
                put(d, ' ');
                number(d, s + j, e - j, j > i);
                linked(d);
                put(d, ' ');
                puts8(d, VTTS_TL_UNITS[m.key][1]);
                put(d, ' ');
                i = m.end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![\w])([Ii]ka)-?(\d+)(?![\d]) -> ordinal, linked before a noun */
static void p_ordinal(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!W(i - 1) && (AT(i, 'I') || AT(i, 'i')) && AT(i + 1, 'k') && AT(i + 2, 'a')) {
            int q = AT(i + 3, '-') && DG(i + 4) ? i + 4 : i + 3;
            if (DG(q)) {
                int r = drun(s, n, q);
                put(d, ' ');
                ordinal(d, s + q, r);
                if (noun_after(s, n, q + r)) linked(d);
                put(d, ' ');
                i = q + r;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![\w.,])(\d+)\s?[-–]\s?(\d+)(?![\w]) -> " a hanggang b " */
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
                        puts8(d, " hanggang ");
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

/* PRODUCT_CODE: (?<![\w])(?=..[A-Z])(?=..[0-9])[A-Z0-9]+(?![\w]) -> letters by name, digits one by one */
static void p_code(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if ((upper_az(s[i]) || (s[i] >= '0' && s[i] <= '9')) && !W(i - 1)) {
            int j = i, up = 0, dg = 0;
            while (IN(j) && (upper_az(s[j]) || (s[j] >= '0' && s[j] <= '9'))) { up |= upper_az(s[j]); dg |= !upper_az(s[j]); j++; }
            if (up && dg && !W(j)) {
                put(d, ' ');
                for (int k = i; k < j; k++) {
                    if (k > i) put(d, ' ');
                    puts8(d, upper_az(s[k]) ? VTTS_TL_LETTERS[s[k] - 'A'] : VTTS_TL_ONES[s[k] - '0']);
                }
                put(d, ' ');
                i = j;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![\w.,])(-?)(NUM)(?![\d]) -> " number " (linked when a whole number precedes a noun) */
static void p_number(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int j = i + AT(i, '-'), e = num_match(s, n, j, ok_nodigit, NULL);
            if (e >= 0) {
                put(d, ' ');
                int frac = number(d, s + j, e - j, j > i);
                if (!frac && noun_after(s, n, e)) linked(d);
                put(d, ' ');
                i = e;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* SYMBOLS (in order; no reading holds a key) */
static void p_symbols(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n; i++) {
        const char *r = NULL;
        for (int k = 0; k < VTTS_TL_N_SYMBOLS && !r; k++) if (VTTS_TL_SYMBOLS[k].cp == s[i]) r = VTTS_TL_SYMBOLS[k].name;
        if (r) puts8(d, r);
        else put(d, s[i]);
    }
}

/* REDUPLICATION (?<![\w'])([^\W\d_]+)-\1(?![\w']) (re.IGNORECASE) -> \1 \1 */
static void p_redup(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (is_letter(s[i]) && !W(i - 1) && !AT(i - 1, '\'')) {
            int j = i;
            while (IN(j) && is_letter(s[j])) j++;
            int l = j - i, ok = AT(j, '-') && j + 1 + l <= n;
            for (int k = 0; ok && k < l; k++) ok = vtts_u_lower(s[j + 1 + k]) == vtts_u_lower(s[i + k]);
            if (ok && !W(j + 1 + l) && !AT(j + 1 + l, '\'')) {
                putn(d, s + i, l);
                put(d, ' ');
                putn(d, s + i, l);
                i = j + 1 + l;
                continue;
            }
            putn(d, s + i, l); /* no match can start inside the run */
            i = j;
            continue;
        }
        put(d, s[i++]);
    }
}

/* GLOTTAL_HYPHEN (?<=[b-df-hj-np-tv-zñ])-(?=[aeiouáéíóúàèìòùâêîôû]) (re.IGNORECASE) -> ', then - -> space */
static void p_glottal(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n; i++) {
        if (s[i] != '-') { put(d, s[i]); continue; }
        int g = i > 0 && i + 1 < n && in_u16(VTTS_TL_GLOTTAL_BEFORE, VTTS_TL_N_GLOTTAL_BEFORE, s[i - 1]) &&
                in_u16(VTTS_TL_GLOTTAL_AFTER, VTTS_TL_N_GLOTTAL_AFTER, s[i + 1]);
        put(d, g ? '\'' : ' ');
    }
}

/* ACRONYM (?<![\w])[A-Z]{2,5}(?![\w]): spelled, or the lower-case word when it is read as a word */
static void p_acronym(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (upper_az(s[i]) && !W(i - 1)) {
            int j = i;
            while (IN(j) && upper_az(s[j])) j++;
            if (j - i >= 2 && j - i <= 5 && !W(j)) {
                char low[8];
                for (int k = i; k < j; k++) low[k - i] = (char)(s[k] + 32);
                low[j - i] = 0;
                if (in_sorted(VTTS_TL_ACRONYM_WORDS, VTTS_TL_N_ACRONYM_WORDS, low)) {
                    for (int k = i; k < j; k++) put(d, s[k] + 32);
                } else {
                    for (int k = i; k < j; k++) {
                        if (k > i) put(d, ' ');
                        puts8(d, VTTS_TL_LETTERS[s[k] - 'A']);
                    }
                }
                i = j;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static void p_lower(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n; i++) put_lower(d, s[i]);
}

static int is_mark(uint32_t c) { return c == ',' || c == '.' || c == '?' || c == '!' || c == ';' || c == ':'; }

/* finish(): findall([^\W\d_]+(?:'[^\W\d_]+)*|[,.?!;:]) joined by spaces, a mark after a mark dropped */
static void p_words(const uint32_t *s, int n, lb_t *d) {
    int any = 0, last_mark = 0;
    for (int i = 0; i < n;) {
        if (is_letter(s[i])) {
            int j = i;
            while (IN(j) && is_letter(s[j])) j++;
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

int vtts_tl_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, const uint32_t **out) {
    lb_t p = {a, 0, cap, 0}, q = {b, 0, cap, 0};
    putn(&p, in, n);
    if (p.err) return -1;
#define SWAP() do { if (q.err) return -1; lb_t t_ = p; p = q; q = t_; } while (0)
#define PASS(fn) do { q.n = 0; fn(p.p, p.n, &q); SWAP(); } while (0)
    for (int k = 0; k < VTTS_TL_N_ABBREV; k++) { q.n = 0; p_abbrev(k, p.p, p.n, &q); SWAP(); }
    PASS(p_drop);
    PASS(p_date_iso);
    PASS(p_date_mdy);
    PASS(p_date_month_day);
    PASS(p_date_day_month);
    PASS(p_time);
    PASS(p_phone);
    PASS(p_money_before);
    PASS(p_percent);
    PASS(p_unit);
    PASS(p_ordinal);
    PASS(p_range);
    PASS(p_pause);
    PASS(p_code);
    PASS(p_number);
    PASS(p_symbols);
    PASS(p_redup);
    PASS(p_glottal);
    PASS(p_acronym);
    PASS(p_lower);
    PASS(p_words);
#undef PASS
#undef SWAP
    *out = p.p;
    return p.n;
}

/* ======================= tagging (latin.latin_word_lang, mode tl) ======================= */

static int camel(const uint32_t *w, int n) {
    for (int i = 0; i + 1 < n; i++)
        if (w[i] >= 'a' && w[i] <= 'z' && upper_az(w[i + 1])) return 1;
    return 0;
}

/* in-place str.replace(from, to) with len(to) <= len(from) */
static int replace_all(char *w, int n, const char *from, const char *to) {
    int fl = (int)strlen(from), tl = (int)strlen(to), m = 0;
    for (int i = 0; i < n;) {
        if (i + fl <= n && memcmp(w + i, from, (size_t)fl) == 0) { memcpy(w + m, to, (size_t)tl); m += tl; i += fl; }
        else w[m++] = w[i++];
    }
    w[m] = 0;
    return m;
}

static int onset_ok(const char *r, int len) { return len == 1 || in_list(VTTS_TL_ONSETS, VTTS_TL_N_ONSETS, r, len); }

/* consonant_runs(w, y_vowel=False) + clusters_fit */
static int clusters(const char *w, int n) {
    int any = 0;
    for (int k = 0; k < n; k++) any |= vowel((uint32_t)w[k]);
    if (!any) return 0;
    for (int k = 0; k < n;) {
        if (vowel((uint32_t)w[k])) { k++; continue; }
        int j = k;
        while (j < n && !vowel((uint32_t)w[j])) j++;
        const char *r = w + k;
        int len = j - k, start = k == 0, end = j == n;
        if (start && !onset_ok(r, len)) return 0;
        if (end && !in_list(VTTS_TL_FINALS, VTTS_TL_N_FINALS, r, len)) return 0;
        if (!start && !end) {
            int ok = 0;
            for (int sp = 0; sp < len && !ok; sp++)
                ok = (sp == 0 || in_list(VTTS_TL_CODAS, VTTS_TL_N_CODAS, r, sp)) && onset_ok(r + sp, len - sp);
            if (!ok) return 0;
        }
        k = j;
    }
    return 1;
}

/* g2p_tl.valid_spelling of a lower-case ASCII word of letters (w is modified, t: n + 1 chars) */
static int valid_spelling(char *w, int n, char *t) {
    if (n == 1 && (w[0] == 't' || w[0] == 'y')) return 1;
    for (int k = 0; k < VTTS_TL_N_NATIVE_OO; k++) {
        char to[16];
        int l = (int)strlen(VTTS_TL_NATIVE_OO[k]);
        memcpy(to, VTTS_TL_NATIVE_OO[k], (size_t)l + 1);
        replace_all(to, l, "oo", "o");
        n = replace_all(w, n, VTTS_TL_NATIVE_OO[k], to);
    }
    for (int k = 0; k < VTTS_TL_N_FOREIGN; k++) {
        int fl = (int)strlen(VTTS_TL_FOREIGN[k]);
        for (int i = 0; i + fl <= n; i++) if (memcmp(w + i, VTTS_TL_FOREIGN[k], (size_t)fl) == 0) return 0;
    }
    memcpy(t, w, (size_t)n + 1);
    int tn = replace_all(t, n, "ngg", "ng");
    for (int i = 0; i + 1 < tn; i++)
        if (t[i] == t[i + 1] && !in_list(VTTS_TL_DOUBLES, VTTS_TL_N_DOUBLES, t + i, 2)) return 0;
    n = replace_all(w, n, "ng", "N");
    return clusters(w, n);
}

static int plain_latin(const uint32_t *w, int n) {
    int alpha = 0;
    for (int i = 0; i < n; i++) {
        uint32_t c = w[i];
        int az = c < 0x80 && (c | 32) >= 'a' && (c | 32) <= 'z';
        if (!(az || c == '-' || c == '\'')) return 0;
        alpha |= az;
    }
    return n > 0 && alpha;
}

int vtts_tl_word_lang(const uint32_t *w, int n) {
    char low[128], part[128], t[128];
    int hyphen = 0;
    if (n <= 0) return -1;
    for (int i = 0; i < n; i++) if (in_u8(w[i], VTTS_TL_OWN)) return 1;
    if (!plain_latin(w, n)) return -1;
    if (n < (int)sizeof low) {
        for (int i = 0; i < n; i++) low[i] = (char)(w[i] | (w[i] >= 'A' && w[i] <= 'Z' ? 32 : 0));
        low[n] = 0;
        if (in_sorted(VTTS_TL_NATIVE, VTTS_TL_N_NATIVE, low) || in_sorted(VTTS_TL_TABLE_KEYS, VTTS_TL_N_TABLE_KEYS, low))
            return 1;
        if (vtts_lt_english_word(low)) return 0;
    }
    for (int i = 0; i < n; i++) hyphen |= w[i] == '-';
    int all_caps = 1, all_valid = 1;
    for (int pass = 0; pass < 2; pass++) /* HYPHEN_ENGLISH first (any part English), then the rest */
        for (int a = 0; a < n;) {
            int b = a;
            while (b < n && w[b] != '-' && w[b] != '\'') b++;
            int len = b - a;
            if (len > 0 && len < (int)sizeof part) {
                for (int k = 0; k < len; k++) part[k] = (char)(w[a + k] | 32);
                part[len] = 0;
            }
            if (len > 0 && pass == 0) {
                if (hyphen && len < (int)sizeof part && vtts_lt_english_word(part)) return 0;
            } else if (len > 0) {
                int caps = len >= 2 && len <= 5;
                if (camel(w + a, len)) return 0;
                for (int k = a; k < b; k++) caps &= upper_az(w[k]);
                all_caps &= caps;
                if (all_valid) all_valid = len < (int)sizeof part && valid_spelling(part, len, t);
            }
            a = b + 1;
        }
    if (n == 1 || all_caps) return 1;
    return all_valid ? 1 : 0;
}

/* ======================= g2p (g2p_tl.word_tokens_tl) ======================= */

#define ACUTE 0x301u
#define GRAVE 0x300u
#define CIRC 0x302u
#define ENYE 0xF1u

static int is_mark3(uint32_t c) { return c == ACUTE || c == GRAVE || c == CIRC; }

static const vtts_tl_fold *fold_row(uint32_t c) {
    int lo = 0, hi = VTTS_TL_N_FOLD - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2;
        if (VTTS_TL_FOLD[m].cp == c) return &VTTS_TL_FOLD[m];
        if (VTTS_TL_FOLD[m].cp < c) lo = m + 1; else hi = m - 1;
    }
    return NULL;
}

static void fold_mark(uint32_t *o, int *m, int code) {
    static const uint32_t MARKS[4] = {ACUTE, GRAVE, CIRC, 0};
    if (code == 4) { if (*m && o[*m - 1] == 'n') o[*m - 1] = ENYE; }
    else if (code >= 1 && code <= 3 && *m && vowel(o[*m - 1]) && *m < VTTS_TL_MAXW) o[(*m)++] = MARKS[code - 1];
}

/* g2p_tl.fold: lower case, NFD, a-z ' - kept, acute/grave/circumflex after a vowel kept, n + tilde
 * -> ñ, the rest dropped; then strip("-") */
static int fold(const uint32_t *in, int n, uint32_t *o) {
    int m = 0;
    for (int i = 0; i < n; i++) {
        uint32_t c = in[i];
        if (c < 0x80) {
            if (c >= 'A' && c <= 'Z') c += 32;
            if (((c >= 'a' && c <= 'z') || c == '\'' || c == '-') && m < VTTS_TL_MAXW) o[m++] = c;
            continue;
        }
        const vtts_tl_fold *r = c < 0x10000 ? fold_row(c) : NULL;
        if (!r) continue;
        if (r->base && m < VTTS_TL_MAXW) o[m++] = (uint32_t)(unsigned char)r->base;
        fold_mark(o, &m, r->marks & 7);
        fold_mark(o, &m, r->marks >> 3);
    }
    int a = 0;
    while (a < m && o[a] == '-') a++;
    while (m > a && o[m - 1] == '-') m--;
    if (a) memmove(o, o + a, (size_t)(m - a) * sizeof *o);
    return m - a;
}

static int fold_u8(const char *s, uint32_t *o) {
    uint32_t c, buf[64];
    int l, k = 0;
    while ((l = dec1(s, &c)) > 0 && k < 64) { buf[k++] = c; s += l; }
    return fold(buf, k, o);
}

static int plain(const uint32_t *w, int n, uint32_t *o) {
    int m = 0;
    for (int i = 0; i < n; i++) if (!is_mark3(w[i])) o[m++] = w[i];
    return m;
}

static int eq_ascii(const uint32_t *w, int n, const char *k) {
    int i = 0;
    for (; k[i]; i++) if (i >= n || w[i] != (uint32_t)(unsigned char)k[i]) return 0;
    return i == n;
}

static int ends_ascii(const uint32_t *w, int n, const char *k) {
    int m = (int)strlen(k);
    return n >= m && eq_ascii(w + n - m, m, k);
}

/* the stress table entry of c0 + w[0..n) (c0 = 0: none), or -1 */
static int table_find(uint32_t c0, const uint32_t *w, int n) {
    char k[48];
    int m = 0;
    if (c0) { if (c0 >= 0x80) return -1; k[m++] = (char)c0; }
    if (m + n >= (int)sizeof k) return -1;
    for (int i = 0; i < n; i++) { if (w[i] >= 0x80) return -1; k[m++] = (char)w[i]; }
    k[m] = 0;
    int lo = 0, hi = VTTS_TL_N_STRESS - 1;
    while (lo <= hi) {
        int md = (lo + hi) / 2, c = strcmp(VTTS_TL_STRESS[md].key, k);
        if (!c) return md;
        if (c < 0) lo = md + 1; else hi = md - 1;
    }
    return -1;
}

static int starts_ascii(const uint32_t *w, int n, const char *k) {
    int m = (int)strlen(k);
    return n >= m && eq_ascii(w, m, k);
}

typedef struct { uint32_t c0; int off; } stem_t;

/* _lookup(plain word): 1 and the pattern (stress from the end, 0 = default; glottal) or 0 */
static int lookup(const uint32_t *w, int n, int *st, int *gl) {
    int clear = 0;
    for (;;) {
        int k = table_find(0, w, n);
        if (k >= 0) { *st = VTTS_TL_STRESS[k].stress; *gl = clear ? 0 : VTTS_TL_STRESS[k].glottal; return 1; }
        static const char *const CL[3] = {"ng", "'t", "'y"};
        int c;
        for (c = 0; c < 3; c++) {
            int cl = (int)strlen(CL[c]);
            if (ends_ascii(w, n, CL[c]) && n > cl + 1 && (c != 0 || vowel(w[n - cl - 1]))) break;
        }
        if (c == 3) break;
        n -= (int)strlen(CL[c]);
        clear = 1;
    }
    /* _roots: stems without up to two prefixes (in order, without duplicates), then the infixes */
    stem_t S[3 * 48];
    int ns = 1;
    S[0].c0 = 0;
    S[0].off = 0;
    for (int round = 0; round < 2; round++) {
        int lim = ns;
        for (int a = 0; a < lim; a++)
            for (int p = 0; p < VTTS_TL_N_PREFIXES; p++) {
                int off = S[a].off, len = n - off, pl = (int)strlen(VTTS_TL_PREFIXES[p]), dup = 0;
                if (!(starts_ascii(w + off, len, VTTS_TL_PREFIXES[p]) && len - pl >= 3)) continue;
                for (int q = 0; q < ns && !dup; q++) dup = S[q].off == off + pl;
                if (!dup && ns < 48) { S[ns].c0 = 0; S[ns].off = off + pl; ns++; }
            }
    }
    for (int a = 0, lim = ns; a < lim; a++) {
        const uint32_t *x = w + S[a].off;
        int len = n - S[a].off;
        if (len > 4 && !vowel(x[0]) && ((x[1] == 'u' && x[2] == 'm') || (x[1] == 'i' && x[2] == 'n')) && vowel(x[3])) {
            S[ns].c0 = x[0];
            S[ns].off = S[a].off + 3;
            ns++;
        }
        if (len > 4 && ((x[0] == 'u' && x[1] == 'm') || (x[0] == 'i' && x[1] == 'n')) && vowel(x[2])) {
            S[ns].c0 = 0;
            S[ns].off = S[a].off + 2;
            ns++;
        }
    }
    for (int a = 0; a < ns; a++) {
        const uint32_t *x = w + S[a].off;
        int len = n - S[a].off, full = len + (S[a].c0 != 0), k;
        if (a && (k = table_find(S[a].c0, x, len)) >= 0) { *st = VTTS_TL_STRESS[k].stress; *gl = clear ? 0 : VTTS_TL_STRESS[k].glottal; return 1; }
        for (int f = 0; f < VTTS_TL_N_SUFFIXES; f++) {
            int fl = (int)strlen(VTTS_TL_SUFFIXES[f]);
            if (!(full >= fl && ends_ascii(x, len, VTTS_TL_SUFFIXES[f]) && full - fl >= 2)) continue;
            if (len < fl) continue; /* the suffix would reach into c0 */
            if ((k = table_find(S[a].c0, x, len - fl)) >= 0) {
                *st = VTTS_TL_STRESS[k].stress == 1 ? 1 : 0;
                *gl = 0;
                return 1;
            }
        }
    }
    return 0;
}

/* _pattern of a spelling with marks */
static void pattern(const uint32_t *w, int n, int *st, int *gl) {
    int nuc = 0, k = 0;
    for (int i = 0; i < n; i++) nuc += vowel(w[i]);
    *st = 0;
    *gl = 0;
    for (int i = 0; i < n; i++) {
        if (!vowel(w[i])) continue;
        uint32_t mk = i + 1 < n ? w[i + 1] : 0;
        if (mk == ACUTE) *st = nuc - k;
        else if (mk == CIRC) { *st = nuc - k; *gl = 1; }
        else if (mk == GRAVE && k == nuc - 1) *gl = 1;
        k++;
    }
}

static int count_vowels(const uint32_t *w, int n) {
    int c = 0;
    for (int i = 0; i < n; i++) c += vowel(w[i]);
    return c;
}

/* SPANISH_FINAL.search(plain) */
static int spanish_final(const uint32_t *w, int n) {
    if ((ends_ascii(w, n, "yon") || ends_ascii(w, n, "yal") || ends_ascii(w, n, "nal") || ends_ascii(w, n, "tal")) &&
        count_vowels(w, n - 3) >= 2)
        return 1;
    if (ends_ascii(w, n, "dad")) return 1;
    return (ends_ascii(w, n, "ar") || ends_ascii(w, n, "el") || ends_ascii(w, n, "or")) && count_vowels(w, n - 2) >= 1;
}

typedef struct { char kind, ph[3]; } seg_t; /* kind 'C' or 'V' */

typedef struct { uint8_t *out; int n, cap; } emit_t;

static void emit(emit_t *e, const char *name) {
    for (int k = 0; k < VTTS_TL_N_TOKENS; k++)
        if (strcmp(VTTS_TL_TOKENS[k], name) == 0) {
            if (e->n < e->cap) e->out[e->n++] = (uint8_t)(VTTS_TLEN_TOK0 + k);
            return;
        }
}

static void seg(seg_t *S, int *ns, char kind, const char *ph) {
    seg_t *s = &S[(*ns)++];
    s->kind = kind;
    s->ph[0] = ph[0];
    s->ph[1] = ph[0] ? ph[1] : 0;
    s->ph[2] = 0;
}

/* _segments of a folded word */
static int segments(const uint32_t *w, int n, seg_t *S) {
    int ns = 0;
    for (int i = 0; i < n;) {
        uint32_t c = w[i], nx = i + 1 < n ? w[i + 1] : 0, nx2 = i + 2 < n ? w[i + 2] : 0;
        char one[2] = {(char)c, 0};
        if (vowel(c)) {
            int mk = is_mark3(nx);
            if (ns && S[ns - 1].kind == 'V') seg(S, &ns, 'C', "?");
            seg(S, &ns, 'V', one);
            i += mk ? 2 : 1;
            continue;
        }
        if (c == '\'' || c == '-') {
            if (ns && vowel(nx)) seg(S, &ns, 'C', "?");
            i++;
            continue;
        }
        if (c == 'n' && nx == 'g') { seg(S, &ns, 'C', "ng"); i += 2; continue; }
        if ((c == 'c' && nx == 'h') || (c == 't' && nx == 's')) { seg(S, &ns, 'C', "ch"); i += 2; continue; }
        if (c == 's' && nx == 'h') { seg(S, &ns, 'C', "sh"); i += 2; continue; }
        if (c == 'l' && nx == 'l') { seg(S, &ns, 'C', "l"); seg(S, &ns, 'C', "y"); i += 2; continue; }
        if (c == 'q' && nx == 'u' && (nx2 == 'e' || nx2 == 'i')) { seg(S, &ns, 'C', "k"); i += 2; continue; }
        if (i && c == w[i - 1] && !(i >= 2 && w[i - 2] == 'n' && w[i - 1] == 'g')) { i++; continue; }
        if (c == 'c') seg(S, &ns, 'C', nx == 'e' || nx == 'i' ? "s" : "k");
        else if (c == 'q') seg(S, &ns, 'C', "k");
        else if (c == 'x') { seg(S, &ns, 'C', "k"); seg(S, &ns, 'C', "s"); }
        else if (c == ENYE) { seg(S, &ns, 'C', "n"); seg(S, &ns, 'C', "y"); }
        else seg(S, &ns, 'C', c < 0x80 ? one : "");
        i++;
    }
    return ns;
}

static int unstressed(const uint32_t *p, int n) {
    char k[16];
    if (n >= (int)sizeof k) return 0;
    for (int i = 0; i < n; i++) { if (p[i] >= 0x80) return 0; k[i] = (char)p[i]; }
    k[n] = 0;
    return in_sorted(VTTS_TL_UNSTRESSED, VTTS_TL_N_UNSTRESSED, k);
}

/* phonemes(word); w, p: VTTS_TL_MAXW each, S: 2 * VTTS_TL_MAXW + 4 segments */
static void phonemes(emit_t *e, const uint32_t *word, int wn, uint32_t *w, uint32_t *p, seg_t *S) {
    int n = fold(word, wn, w), pn = plain(w, n, p), letters = 0;
    if (eq_ascii(p, pn, "ng")) { emit(e, "n"); emit(e, "a"); emit(e, "ng"); return; }
    if (eq_ascii(p, pn, "mga")) { emit(e, "m"); emit(e, "a"); emit(e, "ng"); emit(e, "a"); return; }
    for (int i = 0; i < pn; i++) letters |= p[i] != '\'' && p[i] != '-';
    if (!letters) return;
    if (n == pn) { /* whole-word entry: its letters and marks */
        int k = table_find(0, p, pn);
        if (k >= 0) n = fold_u8(VTTS_TL_STRESS[k].spelled, w);
    }
    int marked = n != pn, st = 0, gl = 0, found = 1;
    for (int i = 0; i < n && !marked; i++) marked = w[i] != p[i];
    if (marked) pattern(w, n, &st, &gl);
    else found = lookup(p, pn, &st, &gl);
    int ns = marked ? segments(w, n, S) : segments(p, pn, S), nuc = 0, last = -1, stress = -1;
    for (int k = 0; k < ns; k++) if (S[k].kind == 'V') nuc++;
    if (nuc && !unstressed(p, pn)) {
        int back = st ? st : nuc > 1 && !found && spanish_final(p, pn) ? 1 : nuc > 1 ? 2 : 1;
        int target = nuc - back < 0 ? 0 : nuc - back;
        for (int k = 0, v = 0; k < ns; k++)
            if (S[k].kind == 'V') { if (v == target) stress = k; v++; }
    }
    for (int k = 0; k < ns; k++) {
        char b[4] = {S[k].ph[0], S[k].ph[1], 0, 0};
        if (k == stress) b[1] = '1';
        emit(e, b);
        last = k;
    }
    if (gl && last >= 0 && S[last].kind == 'V') emit(e, "?");
}

int vtts_tl_word_ids(const uint32_t *word, int n, uint32_t *scratch, uint8_t *out, int cap) {
    uint32_t *w = scratch, *p = scratch + VTTS_TL_MAXW, *sp = scratch + 2 * VTTS_TL_MAXW;
    seg_t *S = (seg_t *)(void *)(scratch + 3 * VTTS_TL_MAXW);
    emit_t e = {out, 0, cap};
    if (n > VTTS_TL_MAXW / 2) n = VTTS_TL_MAXW / 2; /* a folded letter keeps at most one mark */
    int fn = fold(word, n, w), pn = plain(w, fn, sp), vow = 0;
    for (int i = 0; i < pn; i++) vow |= vowel(sp[i]);
    if (pn && !vow && !eq_ascii(sp, pn, "ng") && !eq_ascii(sp, pn, "mga")) { /* spelled letter by letter */
        for (int i = 0; i < pn; i++) {
            if (!(sp[i] >= 'a' && sp[i] <= 'z')) continue;
            uint32_t name[16];
            int l = 0;
            for (const char *c = VTTS_TL_LETTERS[sp[i] - 'a']; *c && l < 16; c++) name[l++] = (uint32_t)(unsigned char)*c;
            phonemes(&e, name, l, w, p, S);
        }
        return e.n;
    }
    phonemes(&e, word, n, w, p, S);
    return e.n;
}

#endif /* VTTS_ENABLE_TL */
