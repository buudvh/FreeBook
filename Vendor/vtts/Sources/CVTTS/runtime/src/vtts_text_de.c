/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_de.c -- German front-end of the device (token set de-en). Mirrors
 * src/vtts/frontend/de/normalize_de.py (normalization pass by pass, split_sentences_de),
 * latin.latin_word_lang in mode "de" and de/g2p_de.py (morph split, graphemes, stress, sounds).
 * All tables are generated into vtts_text_de_tables.h by runtime/tools/gen_text_tables.py. */
#include "vtts_langs.h"
#if VTTS_ENABLE_DE /* else an empty unit (vtts_langs.h) */

#include "vtts_text_de.h"

#include <string.h>

#include "vtts_text_de_tables.h"
#include "vtts_text_lt.h"

/* ======================= small helpers ======================= */

static int dec1(const char *s, uint32_t *c) {
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

static int in_list(const char *const *list, int n, const char *w) {
    for (int k = 0; k < n; k++) if (strcmp(list[k], w) == 0) return 1;
    return 0;
}

/* s (len bytes) ends with t */
static int ends(const char *s, int len, const char *t) {
    int tl = (int)strlen(t);
    return tl <= len && memcmp(s + len - tl, t, (size_t)tl) == 0;
}

static int ends_any(const char *s, int len, const char *const *list, int n) {
    for (int k = 0; k < n; k++) if (ends(s, len, list[k])) return 1;
    return 0;
}

static int starts(const char *s, int len, int at, const char *t) {
    int tl = (int)strlen(t);
    return at >= 0 && at + tl <= len && memcmp(s + at, t, (size_t)tl) == 0;
}

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
#define SP(i) (IN(i) && vtts_u_space(s[i]))
#define AT(i, c) (IN(i) && s[i] == (uint32_t)(c))
#define D(i) (IN(i) && s[i] >= '0' && s[i] <= '9')
#define WDC(i) (W(i) || AT(i, '.') || AT(i, ','))
#define SIGN(i) (AT(i, '-') || AT(i, 0x2212))

static int drun(const uint32_t *s, int n, int i) {
    int j = i;
    while (D(j)) j++;
    return j - i;
}

static int val(const uint32_t *s, int i, int len) {
    int v = 0;
    for (int k = 0; k < len; k++) v = v * 10 + (int)(s[i + k] - '0');
    return v;
}

static int key_at(const uint32_t *s, int n, int i, const char *k) {
    int m = 0, l;
    uint32_t c;
    while ((l = dec1(k, &c)) > 0) {
        if (!IN(i + m) || s[i + m] != c) return 0;
        m++;
        k += l;
    }
    return m;
}

/* [A-Za-zÄÖÜäöüß] and its lower case as UTF-8 */
static int de_letter(uint32_t c) {
    return (c < 0x80 && ((c | 32) >= 'a' && (c | 32) <= 'z')) || c == 0xC4 || c == 0xD6 || c == 0xDC ||
           c == 0xE4 || c == 0xF6 || c == 0xFC || c == 0xDF;
}
static uint32_t de_lower(uint32_t c) {
    if (c < 0x80) return c >= 'A' && c <= 'Z' ? c + 32 : c;
    return c == 0xC4 || c == 0xD6 || c == 0xDC ? c + 32 : c;
}

static int u8_put(char *o, int cap, int m, uint32_t c) {
    if (c < 0x80) { if (m + 1 >= cap) return -1; o[m++] = (char)c; }
    else if (c < 0x800) { if (m + 2 >= cap) return -1; o[m++] = (char)(0xC0 | (c >> 6)); o[m++] = (char)(0x80 | (c & 0x3F)); }
    else if (c < 0x10000) {
        if (m + 3 >= cap) return -1;
        o[m++] = (char)(0xE0 | (c >> 12)); o[m++] = (char)(0x80 | ((c >> 6) & 0x3F)); o[m++] = (char)(0x80 | (c & 0x3F));
    } else {
        if (m + 4 >= cap) return -1;
        o[m++] = (char)(0xF0 | (c >> 18)); o[m++] = (char)(0x80 | ((c >> 12) & 0x3F));
        o[m++] = (char)(0x80 | ((c >> 6) & 0x3F)); o[m++] = (char)(0x80 | (c & 0x3F));
    }
    o[m] = 0;
    return m;
}

/* _prev_word(text, pos): ([A-Za-zÄÖÜäöüß]+)\W*$ over s[0..pos), lower case, into o ("" if none) */
static void prev_word(const uint32_t *s, int pos, char *o, int cap) {
    int k = pos, n = pos, m = 0;
    o[0] = 0;
    while (k > 0 && !vtts_u_word(s[k - 1])) k--;
    int e = k;
    while (k > 0 && de_letter(s[k - 1])) k--;
    (void)n;
    for (int i = k; i < e; i++) if ((m = u8_put(o, cap, m, de_lower(s[i]))) < 0) { o[0] = 0; return; }
}

static int ord_en(const char *w) { return in_sorted(VTTS_DE_ORD_EN, VTTS_DE_N_ORD_EN, w); }
static int ord_e(const char *w) { return in_sorted(VTTS_DE_ORD_E, VTTS_DE_N_ORD_E, w); }
static int month_name(const char *w) { return in_sorted(VTTS_DE_MONTH_NAMES, VTTS_DE_N_MONTH_NAMES, w); }

/* ======================= numbers ======================= */

static void below1000(lb_t *d, int n, int final) {
    int h = n / 100, r = n % 100;
    if (h) { if (h != 1) puts8(d, VTTS_DE_ONES[h]); puts8(d, "hundert"); }
    if (r == 1) puts8(d, final ? "eins" : "ein");
    else if (r < 20) puts8(d, VTTS_DE_ONES[r]);
    else {
        if (r % 10) { puts8(d, VTTS_DE_ONES[r % 10]); puts8(d, "und"); }
        puts8(d, VTTS_DE_TENS[r / 10]);
    }
}

static void card_v(lb_t *d, uint64_t n, int final) {
    static const char *const ONE[3] = {"Billion", "Milliarde", "Million"};
    static const char *const MANY[3] = {"Billionen", "Milliarden", "Millionen"};
    static const uint64_t SCALE[3] = {1000000000000ull, 1000000000ull, 1000000ull};
    int any = 0;
    if (n == 0) { puts8(d, "null"); return; }
    for (int k = 0; k < 3; k++) {
        uint64_t q = n / SCALE[k];
        n %= SCALE[k];
        if (!q) continue;
        if (any) put(d, ' ');
        if (q == 1) { puts8(d, "eine "); puts8(d, ONE[k]); }
        else { card_v(d, q, 0); put(d, ' '); puts8(d, MANY[k]); }
        any = 1;
    }
    if (n) {
        if (any) put(d, ' ');
        int th = (int)(n / 1000), r = (int)(n % 1000);
        if (th) { if (th != 1) below1000(d, th, 0); puts8(d, "tausend"); }
        if (r) below1000(d, r, final);
    }
}

/* cardinal(int(digits)) of the ASCII digits in s[0..n) (other code points skipped) */
static void card_s(lb_t *d, const uint32_t *s, int n, int final) {
    char dg[64];
    int m = 0;
    for (int i = 0; i < n; i++) {
        if (s[i] < '0' || s[i] > '9') continue;
        if (!m && s[i] == '0') continue;
        if (m < 63) dg[m] = (char)s[i];
        m++;
    }
    if (m > 15) { /* >= 10**15: digit by digit */
        int first = 1;
        for (int i = 0; i < n; i++) {
            if (s[i] < '0' || s[i] > '9') continue;
            if (first && s[i] == '0') continue;
            if (!first) put(d, ' ');
            puts8(d, VTTS_DE_DIGITS[s[i] - '0']);
            first = 0;
        }
        return;
    }
    uint64_t v = 0;
    for (int i = 0; i < m; i++) v = v * 10 + (uint64_t)(dg[i] - '0');
    card_v(d, v, final);
}

static void year_v(lb_t *d, int v) {
    if (v >= 1100 && v <= 1999) {
        puts8(d, VTTS_DE_ONES[v / 100]);
        puts8(d, "hundert");
        if (v % 100) below1000(d, v % 100, 1);
        return;
    }
    card_v(d, (uint64_t)v, 1);
}

static void ordinal_stem(lb_t *d, int v) {
    if (v <= 0) { card_v(d, 0, 1); put(d, 't'); return; }
    int r = v % 100;
    if (v >= 100) {
        card_v(d, (uint64_t)(v - r), 0);
        if (!r) { puts8(d, "st"); return; }
    }
    if (r < 20 && VTTS_DE_ORD_IRREGULAR[r][0]) { puts8(d, VTTS_DE_ORD_IRREGULAR[r]); return; }
    card_v(d, (uint64_t)r, 0);
    puts8(d, r < 20 ? "t" : "st");
}

/* latin_norm.parse_number of an ASCII number s[0..n): integer part [0, *ie), decimals [*f0, n) or -1 */
static int groups_full(const uint32_t *s, int n, uint32_t g, uint32_t dm, int *ie, int *f0) {
    int r = drun(s, n, 0), i, groups = 0;
    if (r < 1 || r > 3) return 0;
    for (i = r; AT(i, g) && D(i + 1) && D(i + 2) && D(i + 3); i += 4) groups++;
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

/* value of the integer part (digits only), saturating; *nd: significant digits */
static uint64_t int_value(const uint32_t *s, int n, int *nd) {
    uint64_t v = 0;
    int m = 0;
    for (int i = 0; i < n; i++) {
        if (s[i] < '0' || s[i] > '9') continue;
        if (!m && s[i] == '0') continue;
        m++;
        if (m <= 18) v = v * 10 + (uint64_t)(s[i] - '0');
    }
    *nd = m;
    return v;
}

/* strip the leading - and − of s */
static int unsign(const uint32_t **s, int n) {
    while (n > 0 && ((*s)[0] == '-' || (*s)[0] == 0x2212)) { (*s)++; n--; }
    return n;
}

/* number(s) with an optional sign */
static void number(lb_t *d, const uint32_t *s, int n) {
    int neg = n > 0 && (s[0] == '-' || s[0] == 0x2212);
    n = unsign(&s, n);
    int ie, f0, nd;
    parse_number(s, n, &ie, &f0);
    if (neg) puts8(d, "minus ");
    uint64_t v = int_value(s, ie, &nd);
    int four = n == 4;
    for (int i = 0; i < n && four; i++) four = s[i] >= '0' && s[i] <= '9';
    if (f0 < 0 && four && nd == 4 && v >= 1100 && v <= 1999) year_v(d, (int)v);
    else card_s(d, s, ie, 1);
    if (f0 >= 0) {
        puts8(d, " Komma");
        for (int i = f0; i < n; i++)
            if (s[i] >= '0' && s[i] <= '9') { put(d, ' '); puts8(d, VTTS_DE_DIGITS[s[i] - '0']); }
    }
}

static int one(const uint32_t *s, int n) {
    n = unsign(&s, n);
    int ie, f0, nd;
    parse_number(s, n, &ie, &f0);
    return f0 < 0 && int_value(s, ie, &nd) == 1 && nd == 1;
}

static void count(lb_t *d, const uint32_t *s, int n, int fem) {
    if (one(s, n)) {
        if (n > 0 && (s[0] == '-' || s[0] == 0x2212)) puts8(d, "minus ");
        puts8(d, fem ? "eine" : "ein");
        return;
    }
    number(d, s, n);
}

/* ======================= normalization passes ======================= */

typedef int (*end_ok)(const uint32_t *s, int n, int end, void *u);

static int try_dec(const uint32_t *s, int n, int b, end_ok ok, void *u) {
    if ((AT(b, '.') || AT(b, ',')) && D(b + 1))
        for (int k = drun(s, n, b + 1); k >= 1; k--) if (ok(s, n, b + 1 + k, u)) return b + 1 + k;
    return ok(s, n, b, u) ? b : -1;
}

/* NUM at j: the first end, in the regex's order, that ok() accepts */
static int num_match(const uint32_t *s, int n, int j, end_ok ok, void *u) {
    if (!D(j)) return -1;
    int r = drun(s, n, j), e;
    if (r <= 3) {
        int p = j + r, g = 0;
        while ((AT(p, '.') || AT(p, ',')) && D(p + 1) && D(p + 2) && D(p + 3)) { p += 4; g++; }
        for (; g >= 1; g--) if ((e = try_dec(s, n, j + r + 4 * g, ok, u)) >= 0) return e;
    }
    for (int k = r; k >= 1; k--) if ((e = try_dec(s, n, j + k, ok, u)) >= 0) return e;
    return -1;
}

static int ok_nodigit(const uint32_t *s, int n, int e, void *u) { (void)u; return !D(e); }

typedef struct { int key, end; } km_t;

/* (?:,-)?(?![0-9]) */
static int ok_money_before(const uint32_t *s, int n, int e, void *u) {
    km_t *m = u;
    if (AT(e, ',') && AT(e + 1, '-') && !D(e + 2)) { m->end = e + 2; return 1; }
    if (!D(e)) { m->end = e; return 1; }
    return 0;
}

/* (?:,-)?\s?(KEYS)(?![\w]) */
static int ok_money_after(const uint32_t *s, int n, int e, void *u) {
    km_t *m = u;
    for (int c = AT(e, ',') && AT(e + 1, '-'); c >= 0; c--)
        for (int sp = SP(e + 2 * c); sp >= 0; sp--) {
            int p = e + 2 * c + sp;
            for (int k = 0; k < VTTS_DE_N_CURRENCY; k++) {
                int l = key_at(s, n, p, VTTS_DE_CURRENCY[k].key);
                if (l && !W(p + l)) { m->key = k; m->end = p + l; return 1; }
            }
        }
    return 0;
}

/* \s?(%|‰) */
static int ok_pct(const uint32_t *s, int n, int e, void *u) {
    km_t *m = u;
    for (int sp = SP(e); sp >= 0; sp--)
        if (AT(e + sp, '%') || AT(e + sp, 0x2030)) { m->key = s[e + sp] == '%'; m->end = e + sp + 1; return 1; }
    return 0;
}

/* \s?(UNITS)(?![\w²³]) */
static int ok_unit(const uint32_t *s, int n, int e, void *u) {
    km_t *m = u;
    for (int sp = SP(e); sp >= 0; sp--)
        for (int k = 0; k < VTTS_DE_N_UNITS; k++) {
            int p = e + sp, l = key_at(s, n, p, VTTS_DE_UNITS[k].key);
            if (l && !W(p + l) && !AT(p + l, 0xB2) && !AT(p + l, 0xB3)) { m->key = k; m->end = p + l; return 1; }
        }
    return 0;
}

/* apply_abbreviations, one key */
static void p_abbrev(int k, const uint32_t *s, int n, lb_t *d) {
    const char *key = VTTS_DE_ABBREV[k][0];
    int dot = key[strlen(key) - 1] == '.';
    for (int i = 0; i < n;) {
        int m;
        if (!W(i - 1) && (m = key_at(s, n, i, key)) && (dot || !W(i + m))) {
            int end = dot;
            for (int q = i + m; q < n && end; q++) end = vtts_u_space(s[q]);
            put(d, ' ');
            puts8(d, VTTS_DE_ABBREV[k][1]);
            put(d, ' ');
            if (end) put(d, '.');
            i += m;
            continue;
        }
        put(d, s[i++]);
    }
}

static void p_drop(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n; i++) put(d, in_u8(s[i], VTTS_DE_DROP) ? ' ' : s[i]);
}

static void p_parens(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n; i++) put(d, s[i] == '(' || s[i] == ')' ? ' ' : s[i]);
}

/* _date: 0 when the day or month is out of range */
static int date_out(lb_t *d, int dd, int mm, const uint32_t *y, int yl, const char *prev) {
    if (!(dd >= 1 && dd <= 31 && mm >= 1 && mm <= 12)) return 0;
    put(d, ' ');
    ordinal_stem(d, dd);
    puts8(d, ord_en(prev) ? "en" : ord_e(prev) ? "e" : "er");
    put(d, ' ');
    puts8(d, VTTS_DE_MONTHS[mm]);
    if (y) { put(d, ' '); year_v(d, val(y, 0, yl) + (yl == 2 ? 2000 : 0)); }
    put(d, ' ');
    return 1;
}

/* (?<![0-9-])([0-9]{4})-([0-9]{1,2})-([0-9]{1,2})(?![0-9-]) */
static void p_date_iso(const uint32_t *s, int n, lb_t *d) {
    char prev[64];
    for (int i = 0; i < n;) {
        if (D(i) && !D(i - 1) && !AT(i - 1, '-') && D(i + 1) && D(i + 2) && D(i + 3) && AT(i + 4, '-')) {
            int m0 = i + 5, ml = drun(s, n, m0);
            if (ml >= 1 && ml <= 2 && AT(m0 + ml, '-')) {
                int d0 = m0 + ml + 1, dl = drun(s, n, d0);
                if (dl >= 1 && dl <= 2 && !AT(d0 + dl, '-')) {
                    prev_word(s, i, prev, sizeof prev);
                    if (!date_out(d, val(s, d0, dl), val(s, m0, ml), s + i, 4, prev)) putn(d, s + i, d0 + dl - i);
                    i = d0 + dl;
                    continue;
                }
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![0-9.])([0-9]{1,2})\.([0-9]{1,2})\.([0-9]{4}|[0-9]{2})?(?![0-9]), kept unless there is a year
 * or a space (or the end) follows */
static void p_date_dmy(const uint32_t *s, int n, lb_t *d) {
    char prev[64];
    for (int i = 0; i < n;) {
        if (D(i) && !D(i - 1) && !AT(i - 1, '.')) {
            int r1 = drun(s, n, i);
            if (r1 <= 2 && AT(i + r1, '.')) {
                int m0 = i + r1 + 1, r2 = drun(s, n, m0);
                if (r2 >= 1 && r2 <= 2 && AT(m0 + r2, '.')) {
                    int y0 = m0 + r2 + 1, ry = drun(s, n, y0);
                    if (ry == 4 || ry == 2 || ry == 0) {
                        int e = y0 + ry;
                        if (ry || e >= n || vtts_u_space(s[e])) {
                            prev_word(s, i, prev, sizeof prev);
                            if (!date_out(d, val(s, i, r1), val(s, m0, r2), ry ? s + y0 : NULL, ry, prev))
                                putn(d, s + i, e - i);
                        } else putn(d, s + i, e - i);
                        i = e;
                        continue;
                    }
                }
            }
        }
        put(d, s[i++]);
    }
}

static int hours(const uint32_t *s, int n, int i, int hl[3]) {
    int k = 0;
    if ((AT(i, '0') || AT(i, '1')) && D(i + 1)) hl[k++] = 2;
    if (D(i)) hl[k++] = 1;
    if (AT(i, '2') && IN(i + 1) && s[i + 1] >= '0' && s[i + 1] <= '4') hl[k++] = 2;
    return k;
}

static int m05(const uint32_t *s, int n, int j) { return IN(j) && s[j] >= '0' && s[j] <= '5' && D(j + 1); }

/* \s?Uhr\b at k: the end, or -1 */
static int uhr(const uint32_t *s, int n, int k) {
    for (int sp = SP(k); sp >= 0; sp--) {
        int p = k + sp;
        if (key_at(s, n, p, "Uhr") && !W(p + 3)) return p + 3;
    }
    return -1;
}

static void p_time(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        int hl[3], nh = D(i) ? hours(s, n, i, hl) : 0, end = -1, h = 0, mi = 0, sec = 0;
        if (nh && !D(i - 1) && !AT(i - 1, ':') && !AT(i - 1, '.') && !AT(i - 1, ',')) {
            for (int c = 0; c < nh && end < 0; c++) {
                int j = i + hl[c];
                if (AT(j, ':') && m05(s, n, j + 1)) { /* :M(:S)?(\s?Uhr\b)?(?![0-9]) */
                    int k = j + 3, has = AT(k, ':') && m05(s, n, k + 1);
                    for (int sv = has; sv >= 0 && end < 0; sv--) {
                        int k2 = sv ? k + 3 : k, u = uhr(s, n, k2);
                        if (u >= 0 && !D(u)) end = u;
                        else if (!D(k2)) end = k2;
                        if (end >= 0) { h = val(s, i, hl[c]); mi = val(s, j + 1, 2); sec = sv ? val(s, k + 1, 2) : 0; }
                    }
                }
                if (end < 0 && AT(j, '.') && m05(s, n, j + 1)) { /* \.M\s?Uhr\b */
                    int u = uhr(s, n, j + 3);
                    if (u >= 0) { end = u; h = val(s, i, hl[c]); mi = val(s, j + 1, 2); sec = 0; }
                }
            }
        }
        if (end < 0 && nh && !W(i - 1) && !AT(i - 1, ':') && !AT(i - 1, '.') && !AT(i - 1, ',')) {
            for (int c = 0; c < nh && end < 0; c++) { /* H\s?Uhr\b */
                int u = uhr(s, n, i + hl[c]);
                if (u >= 0) { end = u; h = val(s, i, hl[c]); mi = 0; sec = 0; }
            }
        }
        if (end >= 0) {
            put(d, ' ');
            card_v(d, (uint64_t)h, 0);
            puts8(d, " Uhr");
            if (mi) { put(d, ' '); card_v(d, (uint64_t)mi, 1); }
            if (sec) { puts8(d, " und "); card_v(d, (uint64_t)sec, 1); puts8(d, sec == 1 ? " Sekunde" : " Sekunden"); }
            put(d, ' ');
            i = end;
            continue;
        }
        put(d, s[i++]);
    }
}

/* 0?[0-9]{2,5}(?:[\s/-][0-9]{2,8}){1,4}(?![0-9]) at c: the end or -1 */
static int phone_core(const uint32_t *s, int n, int c) {
    int r = drun(s, n, c);
    if (!(r >= 2 && (r <= 5 || (r == 6 && AT(c, '0'))))) return -1;
    int e = c + r, cnt = 0;
    while (cnt < 4 && (SP(e) || AT(e, '/') || AT(e, '-'))) {
        int r2 = drun(s, n, e + 1);
        if (r2 < 2 || r2 > 8) break;
        e += 1 + r2;
        cnt++;
    }
    return cnt ? e : -1;
}

static void p_phone(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        int e = -1;
        if (!D(i - 1)) {
            for (int pre = AT(i, '+'); pre >= 0 && e < 0; pre--) {
                int p = i;
                if (pre) {
                    int r = drun(s, n, i + 1);
                    if (!(r >= 1 && r <= 3 && (SP(i + 1 + r) || AT(i + 1 + r, '-')))) continue;
                    p = i + 2 + r;
                }
                if (AT(p, '(') && AT(p + 1, '0')) {
                    int r = drun(s, n, p + 2);
                    if (r >= 1 && r <= 4 && AT(p + 2 + r, ')')) {
                        int q = p + 3 + r;
                        for (int sp = SP(q); sp >= 0 && e < 0; sp--) e = phone_core(s, n, q + sp);
                    }
                }
                if (e < 0) e = phone_core(s, n, p);
            }
        }
        if (e < 0 && AT(i, '0') && !D(i - 1) && !AT(i - 1, '.') && !AT(i - 1, ',')) {
            int r = drun(s, n, i), q = i + r;
            if (r >= 6 && !((AT(q, '.') || AT(q, ',')) && D(q + 1))) e = q;
        }
        if (e >= 0) {
            int cnt = 0;
            for (int q = i; q < e; q++) cnt += s[q] >= '0' && s[q] <= '9';
            if (cnt < 6 || !(s[i] == '0' || s[i] == '+' || s[i] == '(')) putn(d, s + i, e - i);
            else {
                put(d, ' ');
                if (s[i] == '+') puts8(d, "plus ");
                int first = 1;
                for (int q = i; q < e; q++) {
                    if (s[q] < '0' || s[q] > '9') continue;
                    if (!first) put(d, ' ');
                    puts8(d, VTTS_DE_DIGITS[s[q] - '0']);
                    first = 0;
                }
                put(d, ' ');
            }
            i = e;
            continue;
        }
        put(d, s[i++]);
    }
}

/* _money(sign, num, cur) */
static void money_out(lb_t *d, int neg, const uint32_t *num, int nn, int k) {
    int ie, f0, nd;
    parse_number(num, nn, &ie, &f0);
    uint64_t v = int_value(num, ie, &nd);
    put(d, ' ');
    if (f0 >= 0 && nn - f0 == 2) {
        int cents = val(num, f0, 2);
        if (nd == 0 && cents) {
            if (neg) puts8(d, "minus ");
            card_v(d, (uint64_t)cents, 0);
            put(d, ' ');
            puts8(d, VTTS_DE_CURRENCY[k].cent);
            put(d, ' ');
            return;
        }
        if (neg) puts8(d, "minus ");
        if (v == 1 && nd == 1) puts8(d, "ein"); else card_s(d, num, ie, 1);
        put(d, ' ');
        puts8(d, VTTS_DE_CURRENCY[k].one);
        if (cents) { put(d, ' '); card_v(d, (uint64_t)cents, 1); }
        put(d, ' ');
        return;
    }
    if (neg) puts8(d, "minus ");
    if (f0 >= 0) {
        number(d, num, nn);
        put(d, ' ');
        puts8(d, VTTS_DE_CURRENCY[k].many);
    } else {
        if (v == 1 && nd == 1) puts8(d, "ein"); else card_s(d, num, ie, 1);
        put(d, ' ');
        puts8(d, VTTS_DE_CURRENCY[k].one);
    }
    put(d, ' ');
}

/* (KEYS)\s?(-?)(NUM)(?:,-)?(?![0-9]) */
static void p_money_before(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        int done = 0;
        for (int k = 0; k < VTTS_DE_N_CURRENCY && !done; k++) {
            int l = key_at(s, n, i, VTTS_DE_CURRENCY[k].key);
            if (!l) continue;
            for (int sp = SP(i + l); sp >= 0 && !done; sp--) {
                int p = i + l + sp;
                for (int sg = AT(p, '-'); sg >= 0 && !done; sg--) {
                    km_t m = {0, 0};
                    int e = num_match(s, n, p + sg, ok_money_before, &m);
                    if (e < 0) continue;
                    money_out(d, sg, s + p + sg, e - p - sg, k);
                    i = m.end;
                    done = 1;
                }
            }
        }
        if (!done) put(d, s[i++]);
    }
}

/* (?<![\w.,])(-?)(NUM)(?:,-)?\s?(KEYS)(?![\w]) */
static void p_money_after(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int done = 0;
            for (int sg = AT(i, '-'); sg >= 0 && !done; sg--) {
                km_t m = {0, 0};
                int e = num_match(s, n, i + sg, ok_money_after, &m);
                if (e < 0) continue;
                money_out(d, sg, s + i + sg, e - i - sg, m.key);
                i = m.end;
                done = 1;
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

/* (?<![\w.,])([-−]?)(NUM)\s?(%|‰) */
static void p_percent(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int done = 0;
            for (int sg = SIGN(i); sg >= 0 && !done; sg--) {
                km_t m = {0, 0};
                int e = num_match(s, n, i + sg, ok_pct, &m);
                if (e < 0) continue;
                put(d, ' ');
                number(d, s + i, e - i);
                puts8(d, m.key ? " Prozent " : " Promille ");
                i = m.end;
                done = 1;
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

/* (?<![\w.,])([-−]?)(NUM)\s?(UNITS)(?![\w²³]) */
static void p_unit(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int done = 0;
            for (int sg = SIGN(i); sg >= 0 && !done; sg--) {
                km_t m = {0, 0};
                int e = num_match(s, n, i + sg, ok_unit, &m);
                if (e < 0) continue;
                put(d, ' ');
                count(d, s + i, e - i, VTTS_DE_UNITS[m.key].fem);
                put(d, ' ');
                puts8(d, one(s + i + sg, e - i - sg) ? VTTS_DE_UNITS[m.key].one : VTTS_DE_UNITS[m.key].many);
                put(d, ' ');
                i = m.end;
                done = 1;
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

/* (?<![\w.,])([0-9]{1,4})\.(?=\s+([A-Za-zÄÖÜäöüß]+)) -> _ordinal */
static void p_ordinal(const uint32_t *s, int n, lb_t *d) {
    char prev[64], nl[64];
    for (int i = 0; i < n;) {
        if (D(i) && !WDC(i - 1)) {
            int r = drun(s, n, i), k = i + r + 1;
            if (r <= 4 && AT(i + r, '.') && SP(k)) {
                while (SP(k)) k++;
                int e = k, m = 0;
                while (IN(e) && de_letter(s[e])) e++;
                if (e > k) {
                    nl[0] = 0;
                    for (int q = k; q < e && m >= 0; q++) m = u8_put(nl, sizeof nl, m, de_lower(s[q]));
                    if (m < 0) nl[0] = 0;
                    prev_word(s, i, prev, sizeof prev);
                    int mon = month_name(nl);
                    uint32_t c0 = s[k];
                    int low = c0 < 0x80 ? (c0 >= 'a' && c0 <= 'z') : (c0 == 0xE4 || c0 == 0xF6 || c0 == 0xFC || c0 == 0xDF);
                    if (mon || low || ord_en(prev) || ord_e(prev) || !strcmp(prev, "ein") || !strcmp(prev, "zum")) {
                        put(d, ' ');
                        ordinal_stem(d, val(s, i, r));
                        puts8(d, ord_en(prev) ? "en" : ord_e(prev) ? "e" : (mon || !strcmp(prev, "ein")) ? "er" : "e");
                        put(d, ' ');
                    } else putn(d, s + i, r + 1);
                    i += r + 1;
                    continue;
                }
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![\w.,])([0-9]+)\s?[-–]\s?([0-9]+)(?![\w.,]) */
static void p_range(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (D(i) && !WDC(i - 1)) {
            int r1 = drun(s, n, i), p = i + r1, e = -1, q2 = 0;
            for (int sp = SP(p); sp >= 0 && e < 0; sp--) {
                int q = p + sp;
                if (!(AT(q, '-') || AT(q, 0x2013))) continue;
                for (int sp2 = SP(q + 1); sp2 >= 0 && e < 0; sp2--) {
                    int r2 = drun(s, n, q + 1 + sp2);
                    if (r2 && !WDC(q + 1 + sp2 + r2)) { e = q + 1 + sp2 + r2; q2 = q + 1 + sp2; }
                }
            }
            if (e >= 0) {
                put(d, ' ');
                card_s(d, s + i, r1, 1);
                puts8(d, " bis ");
                card_s(d, s + q2, e - q2, 1);
                put(d, ' ');
                i = e;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int is_dash(uint32_t c) { return c == 0x2014 || c == 0x2013 || c == '-'; }

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

static const char *letter_name(uint32_t c) {
    for (int k = 0; k < VTTS_DE_N_LETTERS; k++) if (VTTS_DE_LETTERS[k].cp == c) return VTTS_DE_LETTERS[k].name;
    return NULL;
}

static int upper_az(uint32_t c) { return c >= 'A' && c <= 'Z'; }

static void p_code(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if ((upper_az(s[i]) || (s[i] >= '0' && s[i] <= '9')) && !W(i - 1)) {
            int j = i, up = 0, dg = 0;
            while (IN(j) && (upper_az(s[j]) || (s[j] >= '0' && s[j] <= '9'))) { up |= upper_az(s[j]); dg |= !upper_az(s[j]); j++; }
            if (up && dg && !W(j)) {
                put(d, ' ');
                for (int k = i; k < j; k++) {
                    if (k > i) put(d, ' ');
                    puts8(d, upper_az(s[k]) ? letter_name(s[k] + 32) : VTTS_DE_DIGITS[s[k] - '0']);
                }
                put(d, ' ');
                i = j;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![\w.,])([-−]?)(NUM)(?![0-9]) -> _number */
static void p_number(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int done = 0;
            for (int sg = SIGN(i); sg >= 0 && !done; sg--) {
                int j = i + sg, e = num_match(s, n, j, ok_nodigit, NULL);
                if (e < 0) continue;
                int k = e;
                while (SP(k)) k++;
                int le = k;
                while (IN(le) && de_letter(s[le])) le++;
                put(d, ' ');
                if (one(s + j, e - j) && le > k && (upper_az(s[k]) || s[k] == 0xC4 || s[k] == 0xD6 || s[k] == 0xDC)) {
                    char w[64];
                    int m = 0, fem = 0;
                    for (int q = k; q < le && m >= 0; q++) m = u8_put(w, sizeof w, m, de_lower(s[q]));
                    if (m >= 0)
                        for (int f = 0; f < VTTS_DE_N_FEMININE_END && !fem; f++) fem = ends(w, m, VTTS_DE_FEMININE_END[f]);
                    else { /* a long word: only its end matters */
                        char t[16];
                        int tm = 0;
                        for (int q = le - 6 > k ? le - 6 : k; q < le && tm >= 0; q++) tm = u8_put(t, sizeof t, tm, de_lower(s[q]));
                        for (int f = 0; f < VTTS_DE_N_FEMININE_END && !fem && tm > 0; f++) fem = ends(t, tm, VTTS_DE_FEMININE_END[f]);
                    }
                    count(d, s + i, e - i, fem);
                } else number(d, s + i, e - i);
                put(d, ' ');
                i = e;
                done = 1;
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

static void p_symbols(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n; i++) {
        const char *r = NULL;
        for (int k = 0; k < VTTS_DE_N_SYMBOLS && !r; k++) if (VTTS_DE_SYMBOLS[k].cp == s[i]) r = VTTS_DE_SYMBOLS[k].text;
        if (r) puts8(d, r);
        else put(d, s[i] == '-' || s[i] == 0x2212 ? ' ' : s[i]);
    }
}

static void p_acronym(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (upper_az(s[i]) && !W(i - 1)) {
            int j = i;
            while (IN(j) && upper_az(s[j])) j++;
            if (j - i >= 2 && j - i <= 5 && !W(j)) {
                char low[8];
                for (int k = i; k < j; k++) low[k - i] = (char)(s[k] + 32);
                low[j - i] = 0;
                if (in_sorted(VTTS_DE_ACRONYM_WORDS, VTTS_DE_N_ACRONYM_WORDS, low)) {
                    for (int k = i; k < j; k++) put(d, s[k] + 32);
                } else {
                    for (int k = i; k < j; k++) {
                        if (k > i) put(d, ' ');
                        puts8(d, letter_name(s[k] + 32));
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
    for (int i = 0; i < n; i++) {
        if (s[i] == 0x130) { put(d, 'i'); put(d, 0x307); }
        else put(d, vtts_u_lower(s[i]));
    }
}

static int is_letter(uint32_t c) { return c != '_' && vtts_u_word(c) && vtts_u_digit(c) < 0; }
static int is_mark(uint32_t c) { return c == ',' || c == '.' || c == '?' || c == '!' || c == ';' || c == ':'; }

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

int vtts_de_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, const uint32_t **out) {
    lb_t p = {a, 0, cap, 0}, q = {b, 0, cap, 0};
    putn(&p, in, n);
    if (p.err) return -1;
#define SWAP() do { if (q.err) return -1; lb_t t_ = p; p = q; q = t_; } while (0)
#define PASS(fn) do { q.n = 0; fn(p.p, p.n, &q); SWAP(); } while (0)
    for (int k = 0; k < VTTS_DE_N_ABBREV; k++) { q.n = 0; p_abbrev(k, p.p, p.n, &q); SWAP(); }
    PASS(p_drop);
    PASS(p_date_iso);
    PASS(p_date_dmy);
    PASS(p_time);
    PASS(p_phone);
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
    PASS(p_acronym);
    PASS(p_lower);
    PASS(p_words);
#undef PASS
#undef SWAP
    *out = p.p;
    return p.n;
}

/* ======================= sentences (split_sentences_de) ======================= */

static int de_upper_cp(uint32_t c) { return upper_az(c) || c == 0xC4 || c == 0xD6 || c == 0xDC; }
static int de_lower_cp(uint32_t c) { return (c >= 'a' && c <= 'z') || c == 0xE4 || c == 0xF6 || c == 0xFC || c == 0xDF; }
static int end_mark(uint32_t c) { return c == '.' || c == '!' || c == '?' || c == ';'; }
static int cjk_end(uint32_t c) {
    return c == 0x3002 || c == 0xFF01 || c == 0xFF1F || c == 0xFF1B || c == 0x0964 || c == 0x0965;
}

/* a dot at t[end-1] (the piece starts at start) that does not end the sentence */
static int keep_dot(const uint32_t *s, int n, int start, int end) {
    int ws = end - 1;
    while (ws > start && !vtts_u_space(s[ws - 1])) ws--;
    int wl = end - 1 - ws; /* w = s[ws .. end-1) */
    int r = end;
    while (r < n && vtts_u_space(s[r])) r++;
    if (r >= n) return 0; /* rest is empty */
    int digits = wl >= 1 && wl <= 4;
    for (int k = ws; k < end - 1 && digits; k++) digits = s[k] >= '0' && s[k] <= '9';
    if (digits) {
        char prev[64], nxt[64];
        int e = r, m = 0;
        while (e < n && !vtts_u_space(s[e])) e++;
        int a = r, z = e;
        while (a < z && in_u8(s[a], ".,;:!?")) a++;
        while (z > a && in_u8(s[z - 1], ".,;:!?")) z--;
        nxt[0] = 0;
        for (int k = a; k < z && m >= 0; k++) m = u8_put(nxt, sizeof nxt, m, vtts_u_lower(s[k]));
        if (m < 0) nxt[0] = 0;
        prev_word(s + start, ws - start, prev, sizeof prev);
        if (de_lower_cp(s[r]) || month_name(nxt) || ord_en(prev) || ord_e(prev)) return 1;
    }
    /* abbreviations: a single letter, w + "." a key, or the text before the dot ends with a key */
    int abbrev = wl == 1 && (s[ws] < 0x80 ? ((s[ws] | 32) >= 'a' && (s[ws] | 32) <= 'z')
                                            : (s[ws] == 0xC4 || s[ws] == 0xD6 || s[ws] == 0xDC));
    char w8[64];
    int m = 0;
    w8[0] = 0;
    for (int k = ws; k < end && m >= 0; k++) m = u8_put(w8, sizeof w8, m, s[k]); /* w + "." */
    if (m < 0) w8[0] = 0;
    for (int k = 0; k < VTTS_DE_N_ABBREV && !abbrev && w8[0]; k++) abbrev = strcmp(VTTS_DE_ABBREV[k][0], w8) == 0;
    for (int k = 0; k < VTTS_DE_N_ABBREV_DOT && !abbrev; k++) {
        uint32_t key[16];
        int kl = 0, l;
        uint32_t c;
        const char *p = VTTS_DE_ABBREV_DOT[k];
        while ((l = dec1(p, &c)) > 0 && kl < 16) { key[kl++] = c; p += l; }
        int b = end - 1 - kl; /* key at s[b .. end-1) */
        if (b < start) continue;
        int ok = 1;
        for (int q = 0; q < kl && ok; q++) ok = s[b + q] == key[q];
        if (ok && (b == start || vtts_u_space(s[b - 1]))) abbrev = 1;
    }
    if (!abbrev) return 0;
    int usw = !strcmp(w8, "usw.") || !strcmp(w8, "etc.");
    return !(usw && de_upper_cp(s[r]));
}

int vtts_de_next_sentence(const uint32_t *s, int n, vtts_de_split *st, int *ps, int *pe) {
    if (!st->init) {
        int a = 0, z = n;
        while (a < z && vtts_u_space(s[a])) a++;
        while (z > a && vtts_u_space(s[z - 1])) z--;
        st->start = st->scan = a;
        st->done = z; /* end of the stripped text */
        st->init = 1;
    }
    int z = st->done;
    while (st->scan < z) {
        int i = st->scan, end = -1;
        if (end_mark(s[i])) {
            int j = i;
            while (j < z && end_mark(s[j])) j++;
            if (j < z && vtts_u_space(s[j])) end = j;
        }
        if (end < 0 && cjk_end(s[i])) end = i + 1;
        if (end < 0) { st->scan = i + 1; continue; }
        st->scan = end;
        if (end - i == 1 && s[i] == '.' && keep_dot(s, z, st->start, end)) continue;
        int a = st->start, b = end;
        st->start = end;
        while (a < b && vtts_u_space(s[a])) a++;
        while (b > a && vtts_u_space(s[b - 1])) b--;
        if (b > a) { *ps = a; *pe = b; return 1; }
    }
    if (st->start < z) {
        int a = st->start, b = z;
        st->start = z;
        while (a < b && vtts_u_space(s[a])) a++;
        while (b > a && vtts_u_space(s[b - 1])) b--;
        if (b > a) { *ps = a; *pe = b; return 1; }
    }
    return 0;
}

/* ======================= tagging (latin.latin_word_lang, mode de) ======================= */

static int de_foreign(const char *w, int n) { /* g2p_de._foreign of a word with sch replaced by S */
    static const char *const STARTS[] = {"sh", "gh", "sl", "sm", "sn", "sw", "tw", "dw", "wr"};
    static const char *const ENDS[] = {"sh", "th", "dge", "gh", "ook", "oot", "aw", "ew", "y", "ead", "eak", "eam", "ay", "ey"};
    static const char *const ANY[] = {"wh", "tch", "ght", "igh", "ou", "oy"};
    for (unsigned k = 0; k < sizeof STARTS / sizeof *STARTS; k++) if (starts(w, n, 0, STARTS[k])) return 1;
    for (unsigned k = 0; k < sizeof ENDS / sizeof *ENDS; k++) if (ends(w, n, ENDS[k])) return 1;
    for (unsigned k = 0; k < sizeof ANY / sizeof *ANY; k++)
        for (int i = 0; i + (int)strlen(ANY[k]) <= n; i++) if (starts(w, n, i, ANY[k])) return 1;
    if (starts(w, n, 0, "th") && (n == 2 || !strchr("aeiouyr", w[2]))) return 1;
    if (starts(w, n, 0, "sc") && (n == 2 || w[2] != 'h')) return 1;
    for (int k = 1; k <= 2; k++) {
        if (n <= k + 1) continue;
        int cons = 1;
        for (int i = 0; i < k; i++) cons &= !strchr("aeiou", w[i]);
        if (!cons || !starts(w, n, k, "oa")) continue;
        int r = k + 2;
        if (starts(w, n, r, "st") || starts(w, n, r, "ch") || starts(w, n, r, "rd") ||
            (n - r == 1 && (w[r] == 't' || w[r] == 'd')))
            return 1;
    }
    for (int k = 0; k < n; k++) {
        char nx = k + 1 < n ? w[k + 1] : 0;
        if (w[k] == 'c' && (k == 0 || w[k - 1] != 's') && nx != 'h' && nx != 'k') return 1;
        if (w[k] == 'q' && nx != 'u') return 1;
    }
    return ends(w, n, "ing") && (n == 3 || w[n - 4] != 'l');
}

static int valid_spelling(const char *p, int n) {
    char w[128], t[128];
    if (n <= 0 || n >= (int)sizeof w) return n > 0 && 0;
    memcpy(w, p, (size_t)n);
    w[n] = 0;
    if (in_sorted(VTTS_DE_ENGLISH, VTTS_DE_N_ENGLISH, w)) return 0;
    int m = 0;
    for (int i = 0; i < n;) {
        if (i + 3 <= n && memcmp(w + i, "sch", 3) == 0) { t[m++] = 'S'; i += 3; }
        else t[m++] = w[i++];
    }
    t[m] = 0;
    return !(de_foreign(t, m) && !in_sorted(VTTS_DE_NATIVE, VTTS_DE_N_NATIVE, w));
}

int vtts_de_word_lang(const uint32_t *w, int n) {
    char low[128];
    if (n <= 0) return -1;
    for (int i = 0; i < n; i++)
        for (int k = 0; k < VTTS_DE_N_OWN; k++) if (w[i] == VTTS_DE_OWN[k]) return 1;
    int alpha = 0;
    for (int i = 0; i < n; i++) {
        uint32_t c = w[i];
        int az = c < 0x80 && (c | 32) >= 'a' && (c | 32) <= 'z';
        if (!(az || c == '-' || c == '\'')) return -1;
        alpha |= az;
    }
    if (!alpha) return -1;
    if (n < (int)sizeof low) {
        for (int i = 0; i < n; i++) low[i] = (char)(w[i] >= 'A' && w[i] <= 'Z' ? w[i] + 32 : w[i]);
        low[n] = 0;
        if (in_sorted(VTTS_DE_NATIVE, VTTS_DE_N_NATIVE, low) || in_sorted(VTTS_DE_TABLE_KEYS, VTTS_DE_N_TABLE_KEYS, low))
            return 1;
        if (vtts_lt_english_word(low)) return 0;
    }
    int all_caps = 1, all_valid = 1;
    for (int a = 0; a < n;) {
        int b = a;
        while (b < n && w[b] != '-' && w[b] != '\'') b++;
        if (b > a) {
            int len = b - a, caps = len >= 2 && len <= 5;
            for (int k = a; k + 1 < b; k++) if (w[k] >= 'a' && w[k] <= 'z' && upper_az(w[k + 1])) return 0;
            for (int k = a; k < b; k++) caps &= upper_az(w[k]);
            all_caps &= caps;
            if (all_valid) {
                char part[128];
                if (len >= (int)sizeof part) all_valid = 0;
                else {
                    for (int k = 0; k < len; k++) part[k] = (char)(w[a + k] | 32);
                    all_valid = valid_spelling(part, len);
                }
            }
        }
        a = b + 1;
    }
    if (n == 1 || all_caps) return 1;
    return all_valid;
}

/* ======================= g2p (g2p_de) ======================= */

enum { K_UP, K_SP, K_STEM, K_UNK, K_SUF, K_INF, K_LNK };
enum { F_L = 1, F_S = 2, F_ST = 4, F_AT = 8 };
#define MAXW VTTS_DE_MAXW
#define VOW VTTS_DE_VOWELS

static int is_v(char c) { return c && strchr(VOW, c) != NULL; }

typedef struct { uint8_t kind, start, len, alen; const char *ann; } piece_t;

/* ---- fold ---- */
static int fold_cp(uint32_t c, char *o) { /* coded letters of fold(chr(c)) into o: count */
    if (c < 0x80) {
        if (c >= 'A' && c <= 'Z') { o[0] = (char)(c + 32); return 1; }
        if (c >= 'a' && c <= 'z') { o[0] = (char)c; return 1; }
        return 0;
    }
    for (int k = 0; k < VTTS_DE_N_FOLD2; k++)
        if (VTTS_DE_FOLD2[k].cp == c) { int l = (int)strlen(VTTS_DE_FOLD2[k].letters); memcpy(o, VTTS_DE_FOLD2[k].letters, (size_t)l); return l; }
    int lo = 0, hi = VTTS_DE_N_FOLD - 1, k = -1;
    while (lo <= hi) {
        int m = (lo + hi) / 2;
        if (VTTS_DE_FOLD[m].start <= c) { k = m; lo = m + 1; } else hi = m - 1;
    }
    if (k < 0 || c - VTTS_DE_FOLD[k].start >= VTTS_DE_FOLD[k].count) return 0;
    o[0] = VTTS_DE_FOLD_LETTERS[VTTS_DE_FOLD[k].first + (int)(c - VTTS_DE_FOLD[k].start) * VTTS_DE_FOLD[k].step];
    return 1;
}

/* ---- tables ---- */
static int stem_find(const char *w, int len) { /* index in VTTS_DE_STEMS or -1 */
    int lo = 0, hi = VTTS_DE_N_STEMS - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2;
        const char *k = VTTS_DE_STEMS[m][0];
        int c = strncmp(k, w, (size_t)len);
        if (!c) c = k[len] ? 1 : 0;
        if (!c) return m;
        if (c < 0) lo = m + 1; else hi = m - 1;
    }
    return -1;
}

static int set_has(const char *const *list, int n, const char *w, int len) {
    for (int k = 0; k < n; k++) if ((int)strlen(list[k]) == len && memcmp(list[k], w, (size_t)len) == 0) return 1;
    return 0;
}

static int prefix_index(const char *t, int len) {
    for (int k = 0; k < VTTS_DE_N_PREFIXES; k++)
        if ((int)strlen(VTTS_DE_PREFIXES[k].text) == len && memcmp(VTTS_DE_PREFIXES[k].text, t, (size_t)len) == 0) return k;
    return -1;
}

static int ph_id(const char *name) {
    for (int k = 0; k < VTTS_DE_N_PH; k++) if (!strcmp(VTTS_DE_PH[k], name)) return VTTS_DE_TOK0 + k;
    return -1;
}

/* ---- 1. morphs ---- */

static int full_vowel(const char *r, int n) {
    int k = n;
    while (k > 0 && strchr(VTTS_DE_FULL_VOWEL_ENDING, r[k - 1])) k--;
    int core = k > 0 && r[k - 1] == 'e' ? k - 1 : n;
    for (int i = 0; i < core; i++) if (is_v(r[i])) return 1;
    return 0;
}

static int prefix_ok(const char *pre, int pl, const char *r, int n) {
    if (n < 3 || !full_vowel(r, n)) return 0;
    int sp = VTTS_DE_PREFIXES[prefix_index(pre, pl)].sp;
    if (ends_any(r, n, VTTS_DE_FOREIGN_ENDS, VTTS_DE_N_FOREIGN_ENDS) ||
        (sp && ends_any(r, n, VTTS_DE_FOREIGN_ENDS_IER, VTTS_DE_N_FOREIGN_ENDS_IER)))
        return 0;
    int on = 0;
    while (on < n && !is_v(r[on])) on++;
    if (!on) {
        int ok = (pl == 2 && (!memcmp(pre, "be", 2) || !memcmp(pre, "ge", 2))) ||
                 (pl == 3 && (!memcmp(pre, "ver", 3) || !memcmp(pre, "zer", 3) || !memcmp(pre, "ent", 3)));
        return ok && strchr("aiouAOU", r[0]) && n >= 4;
    }
    if (pl == 3 && !memcmp(pre, "emp", 3)) return r[0] == 'f';
    int sch = on >= 3 && !memcmp(r, "sch", 3) &&
              (on == 3 || (on == 4 && strchr("lmnrw", r[3])));
    if (on > 1 && !set_has(VTTS_DE_ONSETS, VTTS_DE_N_ONSETS, r, on) && !sch) return 0;
    return pre[pl - 1] != r[0];
}

static int inside_grapheme(const char *w, int n, int i) {
    char a = w[i - 1], b = w[i];
    if (a == b) return !(i + 1 < n && !is_v(w[i + 1]) && !is_v(b));
    if (a == 'n' && b == 'g') return 1;
    if ((a == 'c' && (b == 'h' || b == 'k')) || (a == 'p' && b == 'h') || (a == 't' && (b == 'h' || b == 'z')) ||
        (a == 'q' && b == 'u'))
        return 1;
    if (starts(w, n, i - 1, "sch") || (i >= 2 && starts(w, n, i - 2, "sch"))) return 1;
    for (int k = 0; k < VTTS_DE_N_DIGRAPHS; k++)
        if (VTTS_DE_DIGRAPHS[k][0][0] == a && VTTS_DE_DIGRAPHS[k][0][1] == b) return 1;
    return 0;
}

enum { S_START, S_PRE, S_STEM, S_UNK, S_SUF, S_LNK, N_STATES };

typedef struct {
    uint8_t ok, unk, np, ninf, bi, bs;
    int16_t known; /* letters in known pieces */
    piece_t pc;
    uint8_t root_kind, root_start, root_len, root_is_prev;
} node_t;

static int cost_lt(const node_t *a, int unk, int known, int np, int ninf) { /* (unk,-known,np,ninf) < a's */
    if (unk != a->unk) return unk < a->unk;
    if (known != a->known) return known > a->known;
    if (np != a->np) return np < a->np;
    return ninf < a->ninf;
}

static void push(node_t *nodes, const node_t *from, int i, int s, int j, int state, piece_t pc) {
    node_t *t = &nodes[j * N_STATES + state];
    int unk = from->unk + (pc.kind == K_UNK), known = from->known + (pc.kind == K_UNK ? 0 : pc.len);
    int np = from->np + 1, ninf = from->ninf + (pc.kind == K_INF || pc.kind == K_LNK);
    if (t->ok && !cost_lt(t, unk, known, np, ninf)) return;
    t->ok = 1;
    t->unk = (uint8_t)unk; t->known = (int16_t)known; t->np = (uint8_t)np; t->ninf = (uint8_t)ninf;
    t->bi = (uint8_t)i; t->bs = (uint8_t)s;
    t->pc = pc;
    if (pc.kind == K_STEM || pc.kind == K_UNK) {
        t->root_kind = pc.kind; t->root_start = pc.start; t->root_len = pc.len; t->root_is_prev = 1;
    } else {
        t->root_kind = from->root_kind; t->root_start = from->root_start; t->root_len = from->root_len; t->root_is_prev = 0;
    }
}

static piece_t mk(int kind, int start, int len, const char *ann, int alen) {
    piece_t p = {(uint8_t)kind, (uint8_t)start, (uint8_t)len, (uint8_t)alen, ann};
    return p;
}

/* segment(w): pieces into out, returns their count */
static int segment(const char *w, int n, node_t *nodes, piece_t *out) {
    memset(nodes, 0, sizeof(node_t) * (size_t)(n + 1) * N_STATES);
    nodes[S_START].ok = 1;
    nodes[S_START].root_kind = 255;
    int foreign = ends_any(w, n, VTTS_DE_FOREIGN_ENDS, VTTS_DE_N_FOREIGN_ENDS) ||
                  ends_any(w, n, VTTS_DE_FOREIGN_ENDS_IER, VTTS_DE_N_FOREIGN_ENDS_IER);
    for (int i = 0; i < n; i++) {
        int inside = i > 0 && inside_grapheme(w, n, i);
        for (int st = 0; st < N_STATES; st++) {
            node_t *nd = &nodes[i * N_STATES + st];
            if (!nd->ok) continue;
            if (inside && st != S_PRE && !(st == S_STEM && starts(w, n, i, "chen"))) continue;
            const piece_t *prev = st == S_START ? NULL : &nd->pc;
            const char *pt = prev ? w + prev->start : NULL;
            int pl = prev ? prev->len : 0;
            /* prefixes */
            for (int k = 0; k < VTTS_DE_N_PREFIXES; k++) {
                const char *p = VTTS_DE_PREFIXES[k].text;
                int len = (int)strlen(p), kind = VTTS_DE_PREFIXES[k].sp ? K_SP : K_UP;
                if (kind == K_UP && prev && (prev->kind == K_UP || prev->kind == K_UNK)) continue;
                if (prev && prev->kind == K_UNK && prev->len < 5) continue;
                if (len == 2 && !memcmp(p, "er", 2) && prev &&
                    (prev->kind == K_STEM || prev->kind == K_SUF || prev->kind == K_INF))
                    continue;
                if (starts(w, n, i, p) && n - i > len) push(nodes, nd, i, st, i + len, S_PRE, mk(kind, i, len, w + i, len));
            }
            /* stems */
            for (int j = i + 3; j <= n; j++) {
                int si = stem_find(w + i, j - i);
                if (si < 0) continue;
                const char *sub = w + i;
                if (prev && prev->kind == K_UNK && pt[pl - 1] == sub[0]) continue;
                if (i > 0 && is_v(sub[0]) && (j - i < 4 || prev->kind == K_UNK)) continue;
                if (prev && prev->kind == K_UNK && (prev->len < 5 || foreign || j - i < 4)) continue;
                const char *ann = VTTS_DE_STEMS[si][1];
                push(nodes, nd, i, st, j, S_STEM, mk(K_STEM, i, j - i, ann, (int)strlen(ann)));
            }
            /* unknown stems */
            if (st != S_UNK) {
                for (int j = i + 3; j <= n; j++) {
                    const char *sub = w + i;
                    int len = j - i, v = 0;
                    for (int q = 0; q < len && !v; q++) v = is_v(sub[q]);
                    if (!v) continue;
                    if (i > 0 && (is_v(sub[0]) || len < 4)) continue;
                    if (set_has(VTTS_DE_DERIVATION, VTTS_DE_N_DERIVATION, sub, len) ||
                        set_has(VTTS_DE_VOWEL_SUFFIXES, VTTS_DE_N_VOWEL_SUFFIXES, sub, len) || (i > 0 && sub[0] == sub[1]))
                        continue;
                    if (prev && (prev->kind == K_UP || prev->kind == K_SP) && !prefix_ok(pt, pl, w + i, n - i)) continue;
                    if (prev && pt[pl - 1] == sub[0] && (prev->kind == K_UP || prev->kind == K_SP || prev->kind == K_STEM))
                        continue;
                    push(nodes, nd, i, st, j, S_UNK, mk(K_UNK, i, len, w + i, len));
                }
            }
            /* suffixes and linkers */
            if (st == S_STEM || st == S_UNK || st == S_SUF) {
                for (int k = 0; k < VTTS_DE_N_ALL_SUFFIXES; k++) {
                    const char *sx = VTTS_DE_ALL_SUFFIXES[k];
                    int len = (int)strlen(sx);
                    if (!starts(w, n, i, sx)) continue;
                    int inf = set_has(VTTS_DE_INFLECTION, VTTS_DE_N_INFLECTION, sx, len);
                    if (inf && nd->root_kind == K_UNK) {
                        const char *rt = w + nd->root_start;
                        int rl = nd->root_len;
                        if (!(nd->root_is_prev && rl >= 3 && (rt[rl - 1] == 'b' || rt[rl - 1] == 'g') && (sx[0] == 's' || sx[0] == 't') &&
                              is_v(rt[rl - 2]) && !is_v(rt[rl - 3])))
                            continue;
                    }
                    if (len == 4 && !memcmp(sx, "chen", 4) && (is_v(pt[pl - 1]) || (pt[pl - 1] == 's' && prev->kind != K_STEM)))
                        continue;
                    if (pt[pl - 1] == sx[0] && !is_v(sx[0])) continue;
                    const char *ann = sx;
                    int alen = len;
                    for (int r = 0; r < VTTS_DE_N_SUFFIX_READING; r++)
                        if (!strcmp(VTTS_DE_SUFFIX_READING[r][0], sx)) { ann = VTTS_DE_SUFFIX_READING[r][1]; alen = (int)strlen(ann); }
                    push(nodes, nd, i, st, i + len, S_SUF, mk(inf ? K_INF : K_SUF, i, len, ann, alen));
                }
                if (i > 0 && prev->kind != K_UNK)
                    for (int k = 0; k < VTTS_DE_N_LINKERS; k++) {
                        const char *sx = VTTS_DE_LINKERS[k];
                        int len = (int)strlen(sx);
                        if (starts(w, n, i, sx) && n - i > len) push(nodes, nd, i, st, i + len, S_LNK, mk(K_LNK, i, len, w + i, len));
                    }
            }
        }
    }
    static const int FIN[3] = {S_STEM, S_UNK, S_SUF};
    const node_t *best = NULL;
    int bst = -1;
    for (int k = 0; k < 3; k++) {
        const node_t *c = &nodes[n * N_STATES + FIN[k]];
        if (!c->ok) continue;
        if (!best || cost_lt(best, c->unk, c->known, c->np, c->ninf)) { best = c; bst = FIN[k]; }
    }
    if (!best) { out[0] = mk(K_UNK, 0, n, w, n); return 1; }
    int cnt = best->np, i = n, s = bst;
    for (int k = cnt - 1; k >= 0; k--) {
        const node_t *c = &nodes[i * N_STATES + s];
        out[k] = c->pc;
        i = c->bi;
        s = c->bs;
    }
    return cnt;
}

static int number_word(const char *w, int n) {
    uint8_t ok[MAXW + 1];
    memset(ok, 0, sizeof ok);
    ok[0] = 1;
    for (int i = 0; i < n; i++)
        if (ok[i])
            for (int k = 0; k < VTTS_DE_N_NUMBER_MORPHS; k++)
                if (starts(w, n, i, VTTS_DE_NUMBER_MORPHS[k])) ok[i + strlen(VTTS_DE_NUMBER_MORPHS[k])] = 1;
    if (ok[n]) return 1;
    for (int k = 0; k < VTTS_DE_N_NUMBER_TAILS; k++) {
        int tl = (int)strlen(VTTS_DE_NUMBER_TAILS[k]);
        if (n > tl && ends(w, n, VTTS_DE_NUMBER_TAILS[k]) && ok[n - tl]) return 1;
    }
    return 0;
}

static int number_pieces(const char *w, int n, piece_t *out) {
    if (n < 3 || !number_word(w, n)) return -1;
    int cnt = 0, i = 0;
    while (i < n) {
        int k = 0;
        for (; k < VTTS_DE_N_NUMBER_MORPHS_LONG; k++) if (starts(w, n, i, VTTS_DE_NUMBER_MORPHS_LONG[k])) break;
        if (k == VTTS_DE_N_NUMBER_MORPHS_LONG) { out[cnt++] = mk(K_INF, i, n - i, w + i, n - i); break; }
        int len = (int)strlen(VTTS_DE_NUMBER_MORPHS_LONG[k]), si = stem_find(w + i, len);
        const char *ann = si >= 0 ? VTTS_DE_STEMS[si][1] : w + i;
        out[cnt++] = mk(K_STEM, i, len, ann, si >= 0 ? (int)strlen(ann) : len);
        i += len;
    }
    return cnt;
}

/* _cut_annotated: the annotation without its first m letters */
static void cut_ann(const char *a, int al, int m, const char **o, int *ol) {
    int k = 0, seen = 0;
    while (seen < m) { if (!strchr(":.'", a[k])) seen++; k++; }
    while (k < al && (a[k] == ':' || a[k] == '.')) k++;
    *o = a + k;
    *ol = al - k;
}

static int split_root_prefix(const char *w, piece_t *in, int cnt, piece_t *out) {
    int m = 0, maxl = 0;
    for (int k = 0; k < VTTS_DE_N_PREFIXES; k++) { int l = (int)strlen(VTTS_DE_PREFIXES[k].text); if (l > maxl) maxl = l; }
    for (int k = 0; k < cnt; k++) {
        piece_t p = in[k];
        int kp = k == 0 ? -1 : in[k - 1].kind;
        if ((p.kind == K_STEM || p.kind == K_UNK) &&
            (k == 0 || kp == K_UP || kp == K_SP || kp == K_LNK || kp == K_STEM || kp == K_SUF || kp == K_INF)) {
            int done = 0;
            for (int L = maxl; L >= 1 && !done; L--)
                for (int q = 0; q < VTTS_DE_N_PREFIXES && !done; q++) {
                    const char *pre = VTTS_DE_PREFIXES[q].text;
                    if ((int)strlen(pre) != L) continue;
                    const char *t = w + p.start;
                    int rl = p.len - L;
                    if (!starts(t, p.len, 0, pre) || rl < 3) continue;
                    int si = stem_find(t + L, rl);
                    if (VTTS_DE_PREFIXES[q].sp && si < 0) continue;
                    if (is_v(t[L]) && si < 0) continue;
                    char full[MAXW + 1];
                    int fl = 0;
                    memcpy(full, t + L, (size_t)rl);
                    fl = rl;
                    for (int r = k + 1; r < cnt; r++) { memcpy(full + fl, w + in[r].start, in[r].len); fl += in[r].len; }
                    if (si >= 0 || prefix_ok(pre, L, full, fl)) {
                        out[m++] = mk(VTTS_DE_PREFIXES[q].sp ? K_SP : K_UP, p.start, L, w + p.start, L);
                        const char *a;
                        int al;
                        cut_ann(p.ann, p.alen, L, &a, &al);
                        int plain = al == rl && !memcmp(a, t + L, (size_t)rl);
                        if (si >= 0 && plain) { a = VTTS_DE_STEMS[si][1]; al = (int)strlen(a); }
                        out[m++] = mk(si >= 0 ? K_STEM : p.kind, p.start + L, rl, a, al);
                        done = 1;
                    }
                }
            if (!done) out[m++] = p;
            continue;
        }
        out[m++] = p;
    }
    return m;
}

/* ---- 2.-4. reading ---- */

typedef struct {
    char t[6];
    uint8_t len, v, unit, pos, flags, piece, glide, silent, ts;
} gr_t;

typedef struct { char ch; uint8_t flags, piece, unit; } let_t;

static int graphemes(const let_t *L, int n, gr_t *out) {
    int cnt = 0, k = 0;
#define SAME(a, b) ((b) < n && L[a].unit == L[b].unit)
    while (k < n) {
        gr_t g;
        memset(&g, 0, sizeof g);
        char ch = L[k].ch;
        g.unit = L[k].unit; g.pos = (uint8_t)k; g.piece = L[k].piece;
        if (is_v(ch)) {
            int two = 0;
            if (SAME(k, k + 1))
                for (int d = 0; d < VTTS_DE_N_DIGRAPHS && !two; d++)
                    if (VTTS_DE_DIGRAPHS[d][0][0] == ch && VTTS_DE_DIGRAPHS[d][0][1] == L[k + 1].ch &&
                        !(ch == 'e' && L[k + 1].ch == 'u' && (L[k + 1].flags & F_S)))
                        two = 1;
            if (ch == 'y' && SAME(k, k + 1) && is_v(L[k + 1].ch) && (k == 0 || L[k - 1].unit != g.unit)) {
                g.t[0] = 'y'; g.len = 1; g.flags = L[k].flags;
                out[cnt++] = g;
                k++;
                continue;
            }
            g.v = 1;
            g.len = (uint8_t)(two ? 2 : 1);
            for (int q = 0; q < g.len; q++) { g.t[q] = L[k + q].ch; g.flags |= L[k + q].flags; }
            out[cnt++] = g;
            k += g.len;
            continue;
        }
        int glen = 0;
        for (int c = 0; c < VTTS_DE_N_CONS_GRAPHEMES && !glen; c++) {
            const char *cg = VTTS_DE_CONS_GRAPHEMES[c];
            int cl = (int)strlen(cg);
            if (!strcmp(cg, "chs") && cnt && out[cnt - 1].v && (out[cnt - 1].flags & F_L)) continue;
            int ok = 1;
            for (int j = 0; j < cl && ok; j++) ok = (j == 0 || SAME(k, k + j)) && k + j < n && L[k + j].ch == cg[j];
            if (ok) glen = cl;
        }
        if (!glen) glen = SAME(k, k + 1) && L[k + 1].ch == ch && !is_v(ch) ? 2 : 1;
        for (int q = 0; q < glen; q++) g.t[q] = L[k + q].ch;
        g.len = (uint8_t)glen;
        g.flags = L[k].flags;
        out[cnt++] = g;
        k += glen;
    }
#undef SAME
    for (int j = 1; j < cnt; j++)
        if (!strcmp(out[j].t, "h") && out[j - 1].v && out[j - 1].unit == out[j].unit) out[j].silent = 1;
    return cnt;
}

static int vowel_at(const gr_t *gs, int cnt, int pos) {
    for (int j = 0; j < cnt; j++) if (gs[j].v && gs[j].pos <= pos && pos < gs[j].pos + gs[j].len) return j;
    return -1;
}

static int ie_unstressed(const char *t, int n) {
    int bl = ends(t, n, "ien") ? n - 1 : n;
    if (!ends(t, bl, "ie")) return 0;
    if (ends_any(t, bl, VTTS_DE_UNSTRESSED_IE, VTTS_DE_N_UNSTRESSED_IE)) return 1;
    if (ends(t, n, "ien")) {
        int v = 0;
        for (int i = 0; i < n - 3 && !v; i++) v = is_v(t[i]);
        if (!v) return 0;
        return !ends_any(t, bl, VTTS_DE_STRESSED_IEN, VTTS_DE_N_STRESSED_IEN);
    }
    return 0;
}

static int not_stressed(const char *t, int n) {
    char buf[MAXW + 1];
    memcpy(buf, t, (size_t)n);
    buf[n] = 0;
    if (in_sorted(VTTS_DE_NOT_STRESSED_WORDS, VTTS_DE_N_NOT_STRESSED_WORDS, buf)) return 1;
    for (int e = 0; e < VTTS_DE_N_NOT_STRESSED_ENDS; e++)
        for (int q = 0; q < VTTS_DE_N_NOT_STRESSED_TAILS; q++) {
            char x[32];
            strcpy(x, VTTS_DE_NOT_STRESSED_ENDS[e]);
            strcat(x, VTTS_DE_NOT_STRESSED_TAILS[q]);
            if (ends(t, n, x)) return 1;
        }
    return ends(t, n, "erlei") && (n == 5 || t[n - 6] != 'i');
}

static int suffix_start(const char *t, int n, const char *const *list, int cnt, const char *pre) {
    int best = -1;
    for (int k = 0; k < cnt; k++) {
        char x[32];
        strcpy(x, pre);
        strcat(x, list[k]);
        int l = (int)strlen(x);
        if (ends(t, n, x) && (best < 0 || n - l < best)) best = n - l;
    }
    return best;
}

static int ending_group(const char *t, int n, const vtts_de_rule *r) {
    for (int st = 0; st <= n; st++)
        for (int b = 0; b < r->nb; b++) {
            if (!starts(t, n, st, r->b[b])) continue;
            int g0 = st + (int)strlen(r->b[b]);
            for (int g = 0; g < r->ng; g++) {
                if (!starts(t, n, g0, r->g[g])) continue;
                int bad = 0;
                for (int q = 0; q < r->nna && !bad; q++) bad = ends(t, g0, r->na[q]);
                if (bad) continue;
                int a0 = g0 + (int)strlen(r->g[g]);
                if (!starts(t, n, a0, r->after)) continue;
                int t0 = a0 + (int)strlen(r->after);
                for (int q = 0; q < r->nt; q++)
                    if ((int)strlen(r->t[q]) == n - t0 && !memcmp(t + t0, r->t[q], (size_t)(n - t0))) return g0;
            }
        }
    return -1;
}

static int penult(const char *t, int n, int *vp, int *cp) {
    for (int k = 0; k < 2; k++) {
        int st = k == 0 ? n - 4 : n - 3, tail = k == 0;
        if (st < 0) continue;
        if (tail && t[n - 1] != 'n' && t[n - 1] != 's') continue;
        char v = t[st], c = t[st + 1], e = t[st + 2];
        if (e != 'e' || !strchr(VTTS_DE_PENULT_CONS, c)) continue;
        if (!(strchr(VTTS_DE_PENULT_VOWELS, v) || (v == 'e' && strchr(VTTS_DE_PENULT_E_BEFORE, c)))) continue;
        if (st > 0 && strchr("aeiouAOUy", t[st - 1])) continue;
        *vp = st;
        *cp = st + 1;
        return 1;
    }
    return 0;
}

static int head_of(const gr_t *gs, int cnt, const char *t, int n, int root_end) {
    int vow[MAXW + 8], nv = 0;
    for (int j = 0; j < cnt; j++) if (gs[j].v && !gs[j].glide) vow[nv++] = j;
    if (!nv) return -1;
    for (int k = 0; k < nv; k++) if (gs[vow[k]].flags & F_ST) return vow[k];
    int root0 = -1;
    for (int k = 0; k < nv && root0 < 0; k++) if (gs[vow[k]].pos < root_end) root0 = vow[k];
    if (root0 < 0) root0 = vow[0];
    if (nv >= 2 && !not_stressed(t, n)) {
        if (ends(t, n, "ik")) {
            char buf[MAXW + 1];
            memcpy(buf, t, (size_t)n);
            buf[n] = 0;
            if (in_sorted(VTTS_DE_STRESSED_IK, VTTS_DE_N_STRESSED_IK, buf)) return vow[nv - 1];
        }
        int oren = suffix_start(t, n, VTTS_DE_OREN_TAILS, VTTS_DE_N_OREN_TAILS, "or");
        if (oren >= 0 && nv >= 3) return vowel_at(gs, cnt, oren);
        int be = suffix_start(t, n, VTTS_DE_BEFORE_ENDINGS, VTTS_DE_N_BEFORE_ENDINGS, "");
        if (be < 0 || ((ends(t, n, "ie") || ends(t, n, "ien")) && !ie_unstressed(t, n))) {
            for (int r = 0; r < VTTS_DE_N_STRESSED_ENDINGS; r++) {
                int g0 = ending_group(t, n, &VTTS_DE_STRESSED_ENDINGS[r]);
                if (g0 < 0) continue;
                int j = vowel_at(gs, cnt, g0);
                if (j >= 0 && gs[j].pos < root_end) return j;
                break;
            }
            int vp, cpos;
            if (penult(t, n, &vp, &cpos) && nv >= 3 && !(t[vp] == 'i' && t[cpos] == 'g')) {
                int j = vowel_at(gs, cnt, vp);
                if (j >= 0 && cpos < root_end) return j;
            }
        }
        if (be >= 0) {
            int last = -1, prevl = -1;
            for (int k = 0; k < nv; k++) if (gs[vow[k]].pos < be) { prevl = last; last = vow[k]; }
            if (last >= 0) {
                if (!strcmp(gs[last].t, "e") && prevl >= 0 && strchr("rln", t[be - 1])) return prevl;
                return last;
            }
        }
    }
    return root0;
}

static void mark_special(gr_t *gs, int *pcnt, const char *t, int n) {
    int cnt = *pcnt;
    for (int pos = 0; pos < n; pos++) {
        if (t[pos] != 't') continue;
        int hit = 0;
        for (int e = 0; e < VTTS_DE_N_TI_ENDS && !hit; e++) {
            char x[16] = "i";
            strcat(x, VTTS_DE_TI_ENDS[e]);
            hit = starts(t, n, pos + 1, x);
        }
        if (!hit) continue;
        for (int j = 0; j < cnt; j++) {
            if (!gs[j].v && !strcmp(gs[j].t, "t") && gs[j].pos == pos) gs[j].ts = 1;
            if (gs[j].v && !strcmp(gs[j].t, "i") && gs[j].pos == pos + 1) gs[j].glide = 1;
        }
    }
    for (int pos = 1; pos + 1 < n;) {
        int ok = t[pos] == 'i' && t[pos + 1] == 'e' && !strchr("aeiouAOUd", t[pos - 1]);
        if (ok) {
            int hz = starts(t, n, pos + 2, "ll");
            for (int e = 0; e < VTTS_DE_N_IE_HIATUS_ENDS && !hz; e++)
                hz = (int)strlen(VTTS_DE_IE_HIATUS_ENDS[e]) == n - pos - 2 && starts(t, n, pos + 2, VTTS_DE_IE_HIATUS_ENDS[e]);
            ok = hz;
        }
        if (!ok) { pos++; continue; }
        for (int k = 0; k < cnt; k++) {
            if (gs[k].v && !strcmp(gs[k].t, "ie") && gs[k].pos == pos) {
                memmove(gs + k + 1, gs + k, sizeof(gr_t) * (size_t)(cnt - k));
                cnt++;
                gs[k].t[1] = 0; gs[k].len = 1; gs[k].glide = 1;
                gs[k + 1].t[0] = 'e'; gs[k + 1].t[1] = 0; gs[k + 1].len = 1; gs[k + 1].pos = (uint8_t)(pos + 1);
                gs[k + 1].glide = 0;
                break;
            }
        }
        pos += 2;
    }
    if (ie_unstressed(t, n)) {
        int end = n - (ends(t, n, "ien") ? 1 : 0);
        for (int k = 0; k < cnt; k++) {
            if (gs[k].v && !strcmp(gs[k].t, "ie") && gs[k].pos == end - 2) {
                memmove(gs + k + 1, gs + k, sizeof(gr_t) * (size_t)(cnt - k));
                cnt++;
                gs[k].t[1] = 0; gs[k].len = 1; gs[k].glide = 1;
                gs[k + 1].t[0] = 'e'; gs[k + 1].t[1] = 0; gs[k + 1].len = 1; gs[k + 1].pos = (uint8_t)(end - 1);
                gs[k + 1].glide = 0; gs[k + 1].flags |= F_AT;
                break;
            }
        }
    }
    *pcnt = cnt;
}

static void mark_glides(gr_t *gs, int cnt, int head) {
    for (int j = 0; j < cnt; j++) {
        gr_t *g = &gs[j];
        if (!g->v || strcmp(g->t, "i") || j == head || g->glide || (g->flags & F_L)) continue;
        if (j + 1 >= cnt || !gs[j + 1].v || gs[j + 1].unit != g->unit) continue;
        if (j == 0 || gs[j - 1].v) continue;
        int later = 0;
        for (int k = j + 2; k < cnt && !later; k++) later = gs[k].v && gs[k].unit == g->unit;
        if (!later || j + 1 == head) g->glide = 1;
    }
}

static const char *long_of(char v) {
    for (int k = 0; k < VTTS_DE_N_LONG_SHORT; k++) if (VTTS_DE_LONG_SHORT[k][0][0] == v) return VTTS_DE_LONG_SHORT[k][1];
    return "";
}
static const char *short_of(char v) {
    for (int k = 0; k < VTTS_DE_N_LONG_SHORT; k++) if (VTTS_DE_LONG_SHORT[k][0][0] == v) return VTTS_DE_LONG_SHORT[k][2];
    return "";
}

static const char *vowel_ph(const gr_t *gs, int cnt, int j, int head) {
    const gr_t *g = &gs[j];
    if (g->glide) return "j";
    if (g->len == 2) {
        if (!strcmp(g->t, "ie") && (g->flags & F_AT)) return "@";
        const gr_t *nx = j + 1 < cnt && gs[j + 1].unit == g->unit ? &gs[j + 1] : NULL;
        if (!strcmp(g->t, "eu") && nx && !strcmp(nx->t, "r") && (j + 2 >= cnt || gs[j + 2].v || gs[j + 2].unit != g->unit))
            return "2:";
        for (int d = 0; d < VTTS_DE_N_DIGRAPHS; d++) if (!strcmp(VTTS_DE_DIGRAPHS[d][0], g->t)) return VTTS_DE_DIGRAPHS[d][1];
    }
    char v = g->t[0];
    if (g->flags & F_S) return short_of(v);
    if (g->flags & F_L) return long_of(v);
    if (g->flags & F_AT) return "@";
    int cons[MAXW + 8], nc = 0, after = 0, va = 0;
    for (int k = j + 1; k < cnt; k++) {
        if (gs[k].unit != g->unit) continue;
        after++;
        if (gs[k].v) { va = 1; break; }
        cons[nc++] = k;
    }
    (void)after;
    if (v == 'e' && j != head && (g->piece == K_SUF || g->piece == K_INF || g->piece == K_LNK || (head >= 0 && j > head))) {
        if (!nc && va) return "e:";
        if (j > 0 && gs[j - 1].v && !strcmp(gs[j - 1].t, "a") && gs[j - 1].unit == g->unit) return "e:";
        char coda[32];
        int cl = 0;
        coda[0] = 0;
        for (int k = 0; k < nc && cl < 28; k++) { memcpy(coda + cl, gs[cons[k]].t, gs[cons[k]].len); cl += gs[cons[k]].len; }
        coda[cl] = 0;
        if (va || (g->piece != K_STEM && g->piece != K_UNK) || in_list(VTTS_DE_REDUCE_CODA, VTTS_DE_N_REDUCE_CODA, coda))
            return "@";
        return "E";
    }
    if (j != head && head >= 0) {
        if (v == 'a' && j < head) return "a";
        if (v == 'i' && nc && (!strcmp(gs[cons[0]].t, "g") || !strcmp(gs[cons[0]].t, "k") || !strcmp(gs[cons[0]].t, "ck")))
            return "I";
        if (nc == 1 && (!strcmp(gs[cons[0]].t, "r") || !strcmp(gs[cons[0]].t, "rr")) && !va && v != 'e') return long_of(v);
    }
    if (nc && gs[cons[0]].silent) return long_of(v);
    if (!nc) {
        if (!va && v == 'y') return "i:";
        return long_of(v);
    }
    const char *c0 = gs[cons[0]].t;
    if (!strcmp(c0, "Z")) return long_of(v);
    if (nc == 2 && va && gs[cons[0]].len == 1 && strchr("bdgkptf", c0[0]) &&
        (!strcmp(gs[cons[1]].t, "l") || !strcmp(gs[cons[1]].t, "r")))
        return long_of(v);
    if (nc == 1 && (gs[cons[0]].len == 1 || !strcmp(c0, "ph") || !strcmp(c0, "th")) && strcmp(c0, "x")) {
        if (va) return long_of(v);
        return j == head ? long_of(v) : short_of(v);
    }
    return short_of(v);
}

typedef struct { const char *ph[3]; int n; } cph_t;

static int native_v(const char *w, int n) {
    if (n < 1 || w[0] != 'v') return 0;
    for (int k = 0; k < VTTS_DE_N_NATIVE_V_START; k++) if (starts(w, n, 1, VTTS_DE_NATIVE_V_START[k])) return 1;
    for (int k = 0; k < VTTS_DE_N_NATIVE_V_WORD; k++)
        if ((int)strlen(VTTS_DE_NATIVE_V_WORD[k]) == n - 1 && starts(w, n, 1, VTTS_DE_NATIVE_V_WORD[k])) return 1;
    return 0;
}

static int join_from(const gr_t *gs, int cnt, int j, int same_unit, char *o, int cap) {
    int m = 0;
    for (int k = j; k < cnt; k++) {
        if (same_unit && gs[k].unit != gs[j - 1 >= 0 ? j - 1 : 0].unit) continue;
        if (m + gs[k].len >= cap) break;
        memcpy(o + m, gs[k].t, gs[k].len);
        m += gs[k].len;
    }
    o[m] = 0;
    return m;
}

static cph_t C1(const char *a) { cph_t r = {{a, NULL, NULL}, 1}; return r; }
static cph_t C2(const char *a, const char *b) { cph_t r = {{a, b, NULL}, 2}; return r; }

static cph_t consonant(const gr_t *gs, int cnt, int j, int head, const char *next_text) {
    const gr_t *g = &gs[j];
    const char *t = g->t;
    const gr_t *nx = j + 1 < cnt && gs[j + 1].unit == g->unit ? &gs[j + 1] : NULL;
    const gr_t *pv = j > 0 && gs[j - 1].unit == g->unit ? &gs[j - 1] : NULL;
    int nv = nx && nx->v, stem_start = j == 0;
    if (!strcmp(t, "sch")) return C1("S");
    if (!strcmp(t, "tsch")) return C2("t", "S");
    if (!strcmp(t, "chs")) return C2("k", "s");
    if (!strcmp(t, "ch")) {
        if ((g->piece == K_SUF || g->piece == K_INF) && !pv) return C1("C");
        if (!pv && stem_start) {
            char word[MAXW + 8];
            int wl = join_from(gs, cnt, j, 0, word, sizeof word);
            if (!starts(word, wl, 0, "chor"))
                for (int k = 0; k < VTTS_DE_N_INITIAL_CH_S; k++) if (starts(word, wl, 0, VTTS_DE_INITIAL_CH_S[k])) return C1("S");
            if (nx && strchr(VTTS_DE_FRONT, nx->t[0])) return C1("C");
            return C1("k");
        }
        if (pv && pv->v && !pv->glide)
            for (int k = 0; k < VTTS_DE_N_BACK; k++) if (!strcmp(pv->t, VTTS_DE_BACK[k])) return C1("x");
        return C1("C");
    }
    if (!strcmp(t, "ck")) return C1("k");
    if (!strcmp(t, "ph")) return C1("f");
    if (!strcmp(t, "th")) return C1("t");
    if (!strcmp(t, "qu")) return C2("k", "v");
    if (!strcmp(t, "ng")) return C1("N");
    if (!strcmp(t, "tz") || !strcmp(t, "zz") || !strcmp(t, "z")) return C2("t", "s");
    if (!strcmp(t, "dt")) return C1("t");
    if (!strcmp(t, "x")) return C2("k", "s");
    if (!strcmp(t, "Z") || !strcmp(t, "ss")) return C1("s");
    if (!strcmp(t, "c")) return nx && strchr("eiAy", nx->t[0]) ? C2("t", "s") : C1("k");
    if (!strcmp(t, "h")) return C1("h");
    if (!strcmp(t, "j") || !strcmp(t, "y")) return C1("j");
    if (!strcmp(t, "w")) return C1("v");
    if (!strcmp(t, "t") && g->ts) return C2("t", "s");
    if (!strcmp(t, "r") || !strcmp(t, "rr")) {
        if (nv || (pv && !pv->v && nx)) return C1("R");
        if (!pv && nx) return C1("R");
        return C1("6");
    }
    if (!strcmp(t, "s")) {
        if (!pv && stem_start && nx && (nx->t[0] == 'p' || nx->t[0] == 't') && g->piece != K_SUF && g->piece != K_INF)
            return C1("S");
        if (nv && (!pv || pv->v || !strcmp(pv->t, "l") || !strcmp(pv->t, "m") || !strcmp(pv->t, "n") || !strcmp(pv->t, "r") ||
                   !strcmp(pv->t, "ng") || !strcmp(pv->t, "rr") || !strcmp(pv->t, "ll") || !strcmp(pv->t, "mm") || !strcmp(pv->t, "nn")))
            return C1("z");
        return C1("s");
    }
    if (!strcmp(t, "n") && nx && (!strcmp(nx->t, "k") || !strcmp(nx->t, "ck"))) return C1("N");
    if (!strcmp(t, "g") && (!nx || !nv)) {
        /* _ig_g */
        if (j > 0 && gs[j - 1].v && !strcmp(gs[j - 1].t, "i") && j - 1 != head) {
            char rest[MAXW + 8];
            int m = 0;
            for (int k = j + 1; k < cnt; k++)
                if (gs[k].unit == g->unit && m + gs[k].len < (int)sizeof rest) { memcpy(rest + m, gs[k].t, gs[k].len); m += gs[k].len; }
            rest[m] = 0;
            if (in_list(VTTS_DE_IG_REST, VTTS_DE_N_IG_REST, rest)) {
                if (!m) {
                    char later[MAXW + 8];
                    int lm = 0;
                    for (int k = j + 1; k < cnt && lm + gs[k].len < (int)sizeof later; k++) { memcpy(later + lm, gs[k].t, gs[k].len); lm += gs[k].len; }
                    later[lm] = 0;
                    const char *l = lm ? later : next_text;
                    if (!strncmp(l, "lich", 4)) return C1("k");
                }
                return C1("C");
            }
        }
    }
    if (!strcmp(t, "v") || !strcmp(t, "vv")) {
        if (!pv) {
            char word[MAXW + 8];
            int wl = join_from(gs, cnt, j, 0, word, sizeof word);
            return native_v(word, wl) ? C1("f") : C1("v");
        }
        if (pv->v && nv) return C1("v");
        return C1("f");
    }
    char b = t[0];
    if (b == 'b' || b == 'd' || b == 'g') {
        int voiced = nx && (nv || !strcmp(nx->t, "l") || !strcmp(nx->t, "r") || !strcmp(nx->t, "n") || !strcmp(nx->t, "j") ||
                            !strcmp(nx->t, "w") || !strcmp(nx->t, "ll") || !strcmp(nx->t, "rr") || !strcmp(nx->t, "nn"));
        if (!voiced) return C1(b == 'b' ? "p" : b == 'd' ? "t" : "k");
        return C1(b == 'b' ? "b" : b == 'd' ? "d" : "g");
    }
    static const char *const ONE[] = {"l", "m", "n", "k", "p", "t", "f", "h", "j"};
    for (int k = 0; k < 9; k++) if (b == ONE[k][0]) return C1(ONE[k]);
    for (int k = 0; k < VTTS_DE_N_OTHER_CONSONANTS; k++)
        if (VTTS_DE_OTHER_CONSONANTS[k][0][0] == b) {
            const char *o = VTTS_DE_OTHER_CONSONANTS[k][1];
            if (!strcmp(o, "k s")) return C2("k", "s");
            static char one_buf[8][2];
            one_buf[k][0] = o[0];
            one_buf[k][1] = 0;
            return C1(one_buf[k]);
        }
    cph_t z = {{NULL, NULL, NULL}, 0};
    return z;
}

typedef struct { uint8_t *o; int n, cap; } ob_t;

static void emit_id(ob_t *o, int id) { if (id >= 0 && o->n < o->cap) o->o[o->n++] = (uint8_t)id; }

/* a phone name, with "1" when stressed */
static int name_id(const char *name, int stressed) {
    char b[8];
    strcpy(b, name);
    if (stressed) strcat(b, "1");
    return ph_id(b);
}

static int is_vowel_id(int id) { return id >= VTTS_DE_TOK0 && id < VTTS_DE_TOK0 + 2 * VTTS_DE_N_VOWELS + 2; }
static int is_unstressed_vowel_id(int id) {
    return (id >= VTTS_DE_TOK0 && id < VTTS_DE_TOK0 + VTTS_DE_N_VOWELS) ||
           id == VTTS_DE_TOK0 + 2 * VTTS_DE_N_VOWELS || id == VTTS_DE_TOK0 + 2 * VTTS_DE_N_VOWELS + 1;
}

static void read_group(gr_t *gs, int cnt, int head, int primary, const char *next_text, ob_t *o) {
    int at = ph_id("@"), six = ph_id("6");
    for (int j = 0; j < cnt; j++) {
        if (gs[j].v) {
            if (j == 0) emit_id(o, ph_id("?"));
            int id = name_id(vowel_ph(gs, cnt, j, head), primary && j == head);
            emit_id(o, id);
            continue;
        }
        if (gs[j].silent) continue;
        cph_t c = consonant(gs, cnt, j, head, next_text);
        for (int k = 0; k < c.n; k++) {
            int id = ph_id(c.ph[k]);
            if (id == six && o->n && o->o[o->n - 1] == at) { o->o[o->n - 1] = (uint8_t)six; continue; }
            emit_id(o, id);
        }
    }
}

typedef struct {
    node_t nodes[(MAXW + 1) * N_STATES];
    piece_t p1[MAXW + 2], p2[2 * MAXW + 4];
    let_t L[2 * MAXW + 8];
    gr_t gs[2 * MAXW + 16];
} scratch_t;

static int phonemes(const char *w, int n, scratch_t *S, ob_t *o) {
    int start = o->n;
    if (!n) return 0;
    {
        char key[MAXW + 1];
        memcpy(key, w, (size_t)n);
        key[n] = 0;
        int lo = 0, hi = VTTS_DE_N_OVERRIDES - 1;
        while (lo <= hi) {
            int m = (lo + hi) / 2, c = strcmp(VTTS_DE_OVERRIDES[m][0], key);
            if (!c) {
                for (const unsigned char *p = (const unsigned char *)VTTS_DE_OVERRIDES[m][1]; *p; p++) emit_id(o, *p);
                return o->n - start;
            }
            if (c < 0) lo = m + 1; else hi = m - 1;
        }
    }
    int cnt = number_pieces(w, n, S->p1);
    if (cnt < 0) {
        int si = stem_find(w, n);
        if (si >= 0) { S->p1[0] = mk(K_STEM, 0, n, VTTS_DE_STEMS[si][1], (int)strlen(VTTS_DE_STEMS[si][1])); cnt = 1; }
        else cnt = segment(w, n, S->nodes, S->p1);
    }
    piece_t *P = S->p2;
    cnt = split_root_prefix(w, S->p1, cnt, P);
    if (cnt > 1 && P[0].kind == K_SP && set_has(VTTS_DE_INSEPARABLE, VTTS_DE_N_INSEPARABLE, w + P[0].start, P[0].len)) {
        const piece_t *last = &P[cnt - 1];
        int ending = (last->kind == K_SUF || last->kind == K_INF) &&
                     set_has(VTTS_DE_VERB_ENDINGS, VTTS_DE_N_VERB_ENDINGS, w + last->start, last->len);
        int ge = P[1].len == 2 && !memcmp(w + P[1].start, "ge", 2);
        if (!ge && (ends(w, n, "ung") || ends(w, n, "ungen") || ending)) P[0].kind = K_UP;
    }
    /* groups */
    int gstart[2 * MAXW + 4], gend[2 * MAXW + 4], gpre[2 * MAXW + 4], ng = 0;
    for (int k = 0; k < cnt; k++) {
        int kind = P[k].kind;
        if (kind == K_UP || kind == K_SP) { gstart[ng] = k; gend[ng] = k + 1; gpre[ng++] = 1; }
        else if (kind == K_STEM || kind == K_UNK || !ng || gpre[ng - 1]) { gstart[ng] = k; gend[ng] = k + 1; gpre[ng++] = 0; }
        else gend[ng - 1] = k + 1;
    }
    int primary = -1;
    for (int g = 0; g < ng && primary < 0; g++) if (!gpre[g] || P[gstart[g]].kind == K_SP) primary = g;
    if (ng > 1 && primary == 0 && ((P[0].len == 4 && !memcmp(w + P[0].start, "nord", 4)) ||
                                   (P[0].len == 3 && !memcmp(w + P[0].start, "sUd", 3)))) {
        const piece_t *q = &P[gstart[1]];
        if (starts(w + q->start, q->len, 0, "ost") || starts(w + q->start, q->len, 0, "Ost") ||
            starts(w + q->start, q->len, 0, "west"))
            primary = 1;
    }
    for (int g = 0; g < ng; g++) {
        int prim = g == primary;
        if (gpre[g]) {
            const piece_t *p = &P[gstart[g]];
            int pi = prefix_index(w + p->start, p->len);
            const unsigned char *ids = (const unsigned char *)VTTS_DE_PREFIXES[pi].ids;
            int len = (int)strlen((const char *)ids), marked = 0, first_v = -1;
            for (int k = 0; k < len; k++) {
                if (ids[k] >= VTTS_DE_TOK0 + VTTS_DE_N_VOWELS && ids[k] < VTTS_DE_TOK0 + 2 * VTTS_DE_N_VOWELS) marked = 1;
                if (first_v < 0 && is_unstressed_vowel_id(ids[k])) first_v = k;
            }
            int i0 = ids[0];
            if (i0 >= VTTS_DE_TOK0 + VTTS_DE_N_VOWELS && i0 < VTTS_DE_TOK0 + 2 * VTTS_DE_N_VOWELS) i0 -= VTTS_DE_N_VOWELS;
            if (is_unstressed_vowel_id(i0)) emit_id(o, ph_id("?"));
            for (int k = 0; k < len; k++) {
                int id = ids[k];
                int str = id >= VTTS_DE_TOK0 + VTTS_DE_N_VOWELS && id < VTTS_DE_TOK0 + 2 * VTTS_DE_N_VOWELS;
                if (!prim || p->kind == K_UP) { if (str) id -= VTTS_DE_N_VOWELS; }
                else if (!marked && k == first_v) id += VTTS_DE_N_VOWELS;
                emit_id(o, id);
            }
            continue;
        }
        /* letters of the group */
        let_t *L = S->L;
        int nl = 0, unit = 0, root_end = 0;
        for (int k = gstart[g]; k < gend[g]; k++) {
            const piece_t *p = &P[k];
            if (k > gstart[g]) {
                const piece_t *pp = &P[k - 1];
                char f = w[p->start], lastc = w[pp->start + pp->len - 1];
                int joined = is_v(f) || (is_v(lastc) && f != 's');
                if (!joined) unit++;
            }
            int pend = 0;
            for (int a = 0; a < p->alen; a++) {
                char ch = p->ann[a];
                if (ch == '\'') { pend = F_ST; continue; }
                if (ch == ':') { if (nl) L[nl - 1].flags |= F_L; continue; }
                if (ch == '.') { if (nl) L[nl - 1].flags |= F_S; continue; }
                L[nl].ch = ch; L[nl].flags = (uint8_t)pend; L[nl].piece = p->kind; L[nl].unit = (uint8_t)unit;
                nl++;
                pend = 0;
            }
            if (k == gstart[g]) root_end = nl;
        }
        if (P[gstart[g]].kind == K_UNK) {
            root_end = nl;
            int pos = 0;
            for (int k = gstart[g]; k < gend[g]; k++) {
                if (P[k].kind == K_SUF && set_has(VTTS_DE_DERIVATION, VTTS_DE_N_DERIVATION, w + P[k].start, P[k].len)) {
                    root_end = pos;
                    break;
                }
                pos += P[k].len;
            }
        }
        char text[2 * MAXW + 8];
        for (int k = 0; k < nl; k++) text[k] = L[k].ch;
        text[nl] = 0;
        int gc = graphemes(L, nl, S->gs);
        mark_special(S->gs, &gc, text, nl);
        int rl = nl;
        const piece_t *last = &P[gend[g] - 1];
        if (gend[g] - gstart[g] > 1 && (last->kind == K_LNK || (last->kind == K_INF && last->len == 1 && w[last->start] == 's')))
            rl = nl - last->len;
        int head = head_of(S->gs, gc, text, rl, root_end < rl ? root_end : rl);
        mark_glides(S->gs, gc, head);
        char next_text[MAXW + 1] = "";
        if (g + 1 < ng) {
            const piece_t *q = &P[gstart[g + 1]];
            memcpy(next_text, w + q->start, q->len);
            next_text[q->len] = 0;
        }
        read_group(S->gs, gc, head, prim, next_text, o);
    }
    /* _merge_doubles */
    int t = ph_id("t"), s = ph_id("s"), gl = ph_id("?"), m = start;
    for (int k = start; k < o->n; k++) {
        int p = o->o[k];
        if (m > start && p == o->o[m - 1] && !is_unstressed_vowel_id(p) && p != gl &&
            !(p == t && k + 1 < o->n && o->o[k + 1] == s))
            continue;
        o->o[m++] = (uint8_t)p;
    }
    o->n = m;
    (void)is_vowel_id;
    return o->n - start;
}

static int fold_word(const uint32_t *w, int n, char *o) {
    int m = 0;
    for (int i = 0; i < n; i++) {
        if (w[i] == '\'') continue;
        char f[4];
        int l = fold_cp(w[i], f);
        for (int k = 0; k < l && m < MAXW; k++) o[m++] = f[k];
    }
    o[m] = 0;
    return m;
}

static int override_has(const char *w) {
    int lo = 0, hi = VTTS_DE_N_OVERRIDES - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2, c = strcmp(VTTS_DE_OVERRIDES[m][0], w);
        if (!c) return 1;
        if (c < 0) lo = m + 1; else hi = m - 1;
    }
    return 0;
}

static void word_tokens(const char *w, int n, scratch_t *S, ob_t *o) {
    int vow = 0;
    for (int i = 0; i < n && !vow; i++) vow = is_v(w[i]);
    if (n && !vow && !override_has(w)) {
        for (int i = 0; i < n; i++) {
            static const char CODED[] = "abcdefghijklmnopqrstuvwxyzAOUZ";
            static const uint32_t CPS[4] = {0xE4, 0xF6, 0xFC, 0xDF};
            const char *pos = strchr(CODED, w[i]);
            if (!pos) continue;
            int ix = (int)(pos - CODED);
            const char *name = letter_name(ix < 26 ? (uint32_t)('a' + ix) : CPS[ix - 26]);
            if (!name) continue;
            /* each space-separated part of the name, folded */
            uint32_t cp[32];
            int cn = 0, l;
            uint32_t c;
            const char *p = name;
            for (;;) {
                l = dec1(p, &c);
                if (l == 0 || c == ' ') {
                    if (cn) {
                        char f[MAXW + 1];
                        int fl = fold_word(cp, cn, f);
                        word_tokens(f, fl, S, o);
                    }
                    cn = 0;
                    if (!l) break;
                } else if (cn < 32) cp[cn++] = c;
                p += l ? l : 0;
                if (!l) break;
            }
        }
        return;
    }
    phonemes(w, n, S, o);
}

int vtts_de_word_ids(const uint32_t *w, int n, void *scratch, uint8_t *out, int cap) {
    char f[MAXW + 1];
    int fl = fold_word(w, n, f);
    ob_t o = {out, 0, cap};
    uintptr_t base = ((uintptr_t)scratch + 7u) & ~(uintptr_t)7u; /* scratch_t holds pointers */
    if (sizeof(scratch_t) + 8 > VTTS_DE_SCRATCH) return 0;
    word_tokens(f, fl, (scratch_t *)base, &o);
    return o.n;
}

#endif /* VTTS_ENABLE_DE */
