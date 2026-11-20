/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_sw.c -- Swahili (sw-en) of the device front-end. Mirrors src/vtts/frontend/latin.py
 * (tagging of plain Latin words in the sw pair: word lists, CamelCase, acronyms, valid_spelling),
 * latin_norm.py and sw/normalize_sw.py (normalization, pass by pass, with the regexes' backtracking
 * order) and sw/g2p_sw.py (fold, digraphs, syllabic nasals, penultimate stress). Tables are generated
 * into vtts_text_sw_tables.h; no blob is needed. */
#include "vtts_langs.h"
#if VTTS_ENABLE_SW /* else an empty unit (vtts_langs.h) */

#include "vtts_text_sw.h"

#include <string.h>

#include "vtts_text_lt.h"
#include "vtts_text_sw_tables.h"

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

static int in_sorted(const char *const *list, int n, const char *w) {
    int lo = 0, hi = n - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2, c = strcmp(list[m], w);
        if (!c) return 1;
        if (c < 0) lo = m + 1; else hi = m - 1;
    }
    return 0;
}

static int is_letter(uint32_t c) { return c != '_' && vtts_u_word(c) && vtts_u_digit(c) < 0; } /* [^\W\d_] */
static int upper_az(uint32_t c) { return c >= 'A' && c <= 'Z'; }
static int vowel(int c) { return c == 'a' || c == 'e' || c == 'i' || c == 'o' || c == 'u'; }

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

/* the ASCII word k at s[i] under re.IGNORECASE: its length or 0 */
static int icase_at(const uint32_t *s, int n, int i, const char *k) {
    int m = 0;
    for (; k[m]; m++) {
        if (!IN(i + m)) return 0;
        int ok = 0;
        for (int r = 0; r < VTTS_SW_N_ICASE && !ok; r++) {
            if (VTTS_SW_ICASE[r][1] != (uint32_t)k[m]) continue;
            for (int v = 0; VTTS_SW_ICASE[r][v] && !ok; v++) ok = VTTS_SW_ICASE[r][v] == s[i + m];
        }
        if (!ok) return 0;
    }
    return m;
}

/* (?:(?<![\w])WORD\s+)? (re.IGNORECASE) at i: the position after the spaces, or -1 */
static int prefix_at(const uint32_t *s, int n, int i, const char *word) {
    if (W(i - 1)) return -1;
    int l = icase_at(s, n, i, word);
    if (!l || !SP(i + l)) return -1;
    int j = i + l;
    while (SP(j)) j++;
    return j;
}

/* ======================= numbers ======================= */

static int sig(const uint32_t *s, int n, int *st) { /* significant digits of s[0..n): count, *st the first */
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

static void digit_words(lb_t *d, const uint32_t *s, int n, int from) { /* digit names joined by spaces */
    int first = 1;
    for (int i = from; i < n; i++) {
        int v = vtts_u_digit(s[i]);
        if (v < 0) continue;
        if (!first) put(d, ' ');
        puts8(d, VTTS_SW_ONES[v]);
        first = 0;
    }
}

static void below_100(lb_t *d, int v) {
    if (v < 10) { puts8(d, VTTS_SW_ONES[v]); return; }
    puts8(d, VTTS_SW_TENS[v / 10]);
    if (v % 10) { puts8(d, " na "); puts8(d, VTTS_SW_ONES[v % 10]); }
}

static void below_1000(lb_t *d, int v) {
    int h = v / 100, r = v % 100;
    if (!h) { below_100(d, r); return; }
    puts8(d, "mia ");
    puts8(d, VTTS_SW_ONES[h]);
    if (r) { puts8(d, r < 10 ? " na " : " "); below_100(d, r); }
}

/* cardinal(v), 0 <= v < 10^15 */
static void card_v(lb_t *d, uint64_t v) {
    static const uint64_t SC[3] = {1000000000000ull, 1000000000ull, 1000000ull};
    int any = 0;
    if (!v) { puts8(d, VTTS_SW_ONES[0]); return; }
    for (int k = 0; k < 3; k++) {
        uint64_t q = v / SC[k];
        v %= SC[k];
        if (!q) continue;
        if (any) put(d, ' ');
        puts8(d, VTTS_SW_SCALES[k]);
        put(d, ' ');
        card_v(d, q);
        any = 1;
    }
    int q = (int)(v / 1000), r = (int)(v % 1000);
    if (q) { /* _thousands: laki for hundreds of thousands */
        int lakh = q / 100, rest = q % 100;
        if (any) put(d, ' ');
        if (lakh) { puts8(d, "laki "); below_100(d, lakh); }
        if (rest) { if (lakh) puts8(d, " na "); puts8(d, "elfu "); below_100(d, rest); }
        any = 1;
    }
    if (r) {
        if (any) { put(d, ' '); if (r < 100) puts8(d, "na "); }
        below_1000(d, r);
    }
}

/* cardinal(int(digits of s[0..n))): from 10^15 digit by digit */
static void card(lb_t *d, const uint32_t *s, int n) {
    int st, nd = sig(s, n, &st);
    if (!nd) { puts8(d, VTTS_SW_ONES[0]); return; }
    if (nd > 15) { digit_words(d, s, n, st); return; }
    uint64_t v = 0;
    for (int i = st; i < n; i++) { int x = vtts_u_digit(s[i]); if (x >= 0) v = v * 10 + (uint64_t)x; }
    card_v(d, v);
}

/* normalize_sw.parse_number: integer part [0, *ie) (separators skipped), decimals [*f0, n) or -1.
 * 1,250.50 and 1.000.000 group thousands; any other number splits at its first . or , */
static void parse_number(const uint32_t *s, int n, int *ie, int *f0) {
    int r = drun(s, n, 0), i, g = 0;
    if (r >= 1 && r <= 3) {
        for (i = r; AT(i, ',') && DG(i + 1) && DG(i + 2) && DG(i + 3); i += 4) g++;
        if (g && i == n) { *ie = n; *f0 = -1; return; }
        if (g && AT(i, '.') && i + 1 < n && drun(s, n, i + 1) == n - i - 1) { *ie = i; *f0 = i + 1; return; }
        for (g = 0, i = r; AT(i, '.') && DG(i + 1) && DG(i + 2) && DG(i + 3); i += 4) g++;
        if (g >= 2 && i == n) { *ie = n; *f0 = -1; return; }
    }
    for (int m = 0; m < 2; m++)
        for (i = 0; i < n; i++)
            if (s[i] == (m ? ',' : '.')) { *ie = i; *f0 = i + 1; return; }
    *ie = n;
    *f0 = -1;
}

/* number(sign + s): cardinal, then nukta and the decimals digit by digit */
static void number(lb_t *d, const uint32_t *s, int n, int neg) {
    int ie, f0;
    if (neg) puts8(d, "hasi ");
    parse_number(s, n, &ie, &f0);
    card(d, s, ie);
    if (f0 >= 0 && f0 < n) { puts8(d, " nukta "); digit_words(d, s, n, f0); }
}

/* _money(name, num): shilingi with cents as senti, any other amount as a number */
static void money_out(lb_t *d, const char *name, const uint32_t *s, int n) {
    int ie, f0, cents = 0;
    parse_number(s, n, &ie, &f0);
    if (f0 >= 0 && f0 < n) {
        int a = vtts_u_digit(s[f0]), b = f0 + 1 < n ? vtts_u_digit(s[f0 + 1]) : 0;
        cents = (a < 0 ? 0 : a) * 10 + (b < 0 ? 0 : b);
    }
    put(d, ' ');
    puts8(d, name);
    put(d, ' ');
    if (!strcmp(name, "shilingi") && cents) {
        card(d, s, ie);
        puts8(d, " na senti ");
        card_v(d, (uint64_t)cents);
    } else {
        number(d, s, n, 0);
    }
    put(d, ' ');
}

/* ======================= normalization passes =======================
 * Each regex pass of normalize_sw is one function from s (n code points) to d; matches are found left
 * to right without overlap, like re.sub, and lookarounds look at the pass's input. Where
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
        for (int k = 0; k < VTTS_SW_N_UNITS; k++) {
            int l = key_at(s, n, e + sp, VTTS_SW_UNITS[k].key);
            if (l && !W(e + sp + l)) { m->key = k; m->end = e + sp + l; return 1; }
        }
    return 0;
}

typedef struct { const char *sym; int end; } after_m;

/* \s?(?:/=|(€|£|¥|\$)|\s?(?:shilingi|Sh|TSh|KSh)(?![\w])) */
static int ok_after(const uint32_t *s, int n, int e, void *u) {
    after_m *m = u;
    for (int sp = SP(e); sp >= 0; sp--) {
        int p = e + sp, l;
        if (AT(p, '/') && AT(p + 1, '=')) { m->sym = NULL; m->end = p + 2; return 1; }
        for (int k = 0; k < VTTS_SW_N_CUR_AFTER; k++)
            if ((l = key_at(s, n, p, VTTS_SW_CUR_AFTER[k]))) { m->sym = VTTS_SW_CUR_AFTER[k]; m->end = p + l; return 1; }
        for (int sp2 = SP(p); sp2 >= 0; sp2--)
            for (int k = 0; k < VTTS_SW_N_CUR_WORDS; k++)
                if ((l = key_at(s, n, p + sp2, VTTS_SW_CUR_WORDS[k])) && !W(p + sp2 + l)) {
                    m->sym = NULL;
                    m->end = p + sp2 + l;
                    return 1;
                }
    }
    return 0;
}

/* apply_abbreviations, one key: (?<![\w])KEY[(?![\w])] -> " reading " (+ "." at the end of the text) */
static void p_abbrev(int k, const uint32_t *s, int n, lb_t *d) {
    const char *key = VTTS_SW_ABBREV[k][0];
    int dot = key[strlen(key) - 1] == '.';
    for (int i = 0; i < n;) {
        int m;
        if (!W(i - 1) && (m = key_at(s, n, i, key)) && (dot || !W(i + m))) {
            int end = dot;
            for (int q = i + m; q < n && end; q++) end = vtts_u_space(s[q]);
            put(d, ' ');
            puts8(d, VTTS_SW_ABBREV[k][1]);
            put(d, ' ');
            if (end) put(d, '.');
            i += m;
            continue;
        }
        put(d, s[i++]);
    }
}

static void p_drop(const uint32_t *s, int n, lb_t *d) { /* ’ -> ', then DROP -> space */
    for (int i = 0; i < n; i++) put(d, s[i] == 0x2019 ? '\'' : in_u8(s[i], VTTS_SW_DROP) ? ' ' : s[i]);
}

/* _date(d, m, y): " tarehe ... " or the original text when the day or month is out of range */
static void date_out(lb_t *d, int dd, int mm, const uint32_t *y, int yl, const uint32_t *orig, int on) {
    if (!(dd >= 1 && dd <= 31 && mm >= 1 && mm <= 12)) { putn(d, orig, on); return; }
    puts8(d, " tarehe ");
    card_v(d, (uint64_t)dd);
    put(d, ' ');
    puts8(d, VTTS_SW_MONTHS[mm]);
    if (y) { put(d, ' '); card_v(d, (uint64_t)(val(y, 0, yl) + (yl == 2 ? 2000 : 0))); }
    put(d, ' ');
}

/* (?<![\d-])(\d{4})-(\d{1,2})-(\d{1,2})(?![\d-]) at p: the end or -1 */
static int iso_at(const uint32_t *s, int n, int p, int *m0, int *ml, int *d0, int *dl) {
    if (!(DG(p) && !DG(p - 1) && !AT(p - 1, '-') && DG(p + 1) && DG(p + 2) && DG(p + 3) && AT(p + 4, '-'))) return -1;
    *m0 = p + 5;
    *ml = drun(s, n, *m0);
    if (*ml < 1 || *ml > 2 || !AT(*m0 + *ml, '-')) return -1;
    *d0 = *m0 + *ml + 1;
    *dl = drun(s, n, *d0);
    if (*dl < 1 || *dl > 2 || AT(*d0 + *dl, '-')) return -1;
    return *d0 + *dl;
}

/* DATE_ISO with the optional (?:(?<![\w])tarehe\s+)? before it */
static void p_date_iso(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        int m0, ml, d0, dl, p = prefix_at(s, n, i, "tarehe"), e = -1;
        if (p >= 0) e = iso_at(s, n, p, &m0, &ml, &d0, &dl);
        if (e < 0) e = iso_at(s, n, p = i, &m0, &ml, &d0, &dl);
        if (e >= 0) {
            date_out(d, val(s, d0, dl), val(s, m0, ml), s + p, 4, s + i, e - i);
            i = e;
            continue;
        }
        put(d, s[i++]);
    }
}

/* (?<![\d/])(\d{1,2})/(\d{1,2})/(\d{4}|\d{2})(?![\d/]) at p: the end or -1 */
static int dmy_at(const uint32_t *s, int n, int p, int *r1, int *m0, int *r2, int *y0, int *ry) {
    if (!DG(p) || DG(p - 1) || AT(p - 1, '/')) return -1;
    *r1 = drun(s, n, p);
    if (*r1 > 2 || !AT(p + *r1, '/')) return -1;
    *m0 = p + *r1 + 1;
    *r2 = drun(s, n, *m0);
    if (*r2 < 1 || *r2 > 2 || !AT(*m0 + *r2, '/')) return -1;
    *y0 = *m0 + *r2 + 1;
    *ry = drun(s, n, *y0);
    if ((*ry != 4 && *ry != 2) || AT(*y0 + *ry, '/')) return -1;
    return *y0 + *ry;
}

static void p_date_dmy(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        int r1, m0, r2, y0, ry, p = prefix_at(s, n, i, "tarehe"), e = -1;
        if (p >= 0) e = dmy_at(s, n, p, &r1, &m0, &r2, &y0, &ry);
        if (e < 0) e = dmy_at(s, n, p = i, &r1, &m0, &r2, &y0, &ry);
        if (e >= 0) {
            date_out(d, val(s, p, r1), val(s, m0, r2), s + y0, ry, s + i, e - i);
            i = e;
            continue;
        }
        put(d, s[i++]);
    }
}

static int m05(const uint32_t *s, int n, int j) { return IN(j) && s[j] >= '0' && s[j] <= '5' && DG(j + 1); } /* [0-5]\d */

/* (?<![\d:.])([01]?\d|2[0-4]):([0-5]\d)(?::[0-5]\d)?(?![\d:]) at p: the end or -1 */
static int time_at(const uint32_t *s, int n, int p, int *h, int *mi) {
    int hl[3], nh = 0;
    if (!DG(p) || DG(p - 1) || AT(p - 1, ':') || AT(p - 1, '.')) return -1;
    if ((AT(p, '0') || AT(p, '1')) && DG(p + 1)) hl[nh++] = 2; /* the hour lengths in the regex's order */
    hl[nh++] = 1;
    if (AT(p, '2') && IN(p + 1) && s[p + 1] >= '0' && s[p + 1] <= '4') hl[nh++] = 2;
    for (int c = 0; c < nh; c++) {
        int j = p + hl[c];
        if (!(AT(j, ':') && m05(s, n, j + 1))) continue;
        int k = j + 3, has = AT(k, ':') && m05(s, n, k + 1);
        for (int sv = has; sv >= 0; sv--) {
            int e = sv ? k + 3 : k;
            if (!DG(e) && !AT(e, ':')) { *h = val(s, p, hl[c]); *mi = val(s, j + 1, 2); return e; }
        }
    }
    return -1;
}

/* TIME with the optional (?:(?<![\w])saa\s+)? -> " saa H [na robo | na nusu | na dakika M] " */
static void p_time(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        int h = 0, mi = 0, p = prefix_at(s, n, i, "saa"), e = -1;
        if (p >= 0) e = time_at(s, n, p, &h, &mi);
        if (e < 0) e = time_at(s, n, i, &h, &mi);
        if (e >= 0) {
            puts8(d, " saa ");
            card_v(d, (uint64_t)h);
            if (mi == 15) puts8(d, " na robo");
            else if (mi == 30) puts8(d, " na nusu");
            else if (mi) { puts8(d, " na dakika "); card_v(d, (uint64_t)mi); }
            put(d, ' ');
            i = e;
            continue;
        }
        put(d, s[i++]);
    }
}

/* \d{2,4}(?:[\s-]\d{2,4}){2,4}(?![\d]) at q: the end or -1 */
static int phone_core(const uint32_t *s, int n, int q) {
    int r = drun(s, n, q), e = q + r, cnt = 0;
    if (r < 2 || r > 4) return -1;
    while (cnt < 4 && SPD(e)) {
        int r2 = drun(s, n, e + 1);
        if (r2 < 2 || r2 > 4) break;
        e += 1 + r2;
        cnt++;
    }
    return cnt >= 2 ? e : -1;
}

/* PHONE: (?<![\d])(?:\+\d{1,3}[\s-])?CORE | (?<![\d.,])0\d{2,}(?![\d]|[.,]\d) -> phone_digits */
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
                e = phone_core(s, n, p);
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
                if (s[i] == '+') puts8(d, "jumlisha ");
                digit_words(d, s, e, i);
                put(d, ' ');
            }
            i = e;
            continue;
        }
        put(d, s[i++]);
    }
}

/* (?<![\w])(CUR)\s?(NUM)(?:/=)? -> _money */
static void p_money_before(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        int e = -1, j = 0, k = 0;
        if (!W(i - 1))
            for (k = 0; k < VTTS_SW_N_CURRENCY && e < 0; k++) {
                int l = key_at(s, n, i, VTTS_SW_CURRENCY[k][0]);
                if (!l) continue;
                for (int sp = SP(i + l); sp >= 0 && e < 0; sp--) e = num_match(s, n, j = i + l + sp, ok_always, NULL);
            }
        if (e >= 0) {
            money_out(d, VTTS_SW_CURRENCY[k - 1][1], s + j, e - j);
            i = AT(e, '/') && AT(e + 1, '=') ? e + 2 : e;
            continue;
        }
        put(d, s[i++]);
    }
}

/* (?<![\w.,])(NUM)\s?(?:/=|(€|£|¥|\$)|\s?(?:shilingi|Sh|TSh|KSh)(?![\w])) -> _money */
static void p_money_after(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        after_m m = {NULL, 0};
        int e = WDC(i - 1) ? -1 : num_match(s, n, i, ok_after, &m);
        if (e >= 0) {
            const char *name = "shilingi";
            if (m.sym)
                for (int k = 0; k < VTTS_SW_N_CURRENCY; k++)
                    if (!strcmp(VTTS_SW_CURRENCY[k][0], m.sym)) name = VTTS_SW_CURRENCY[k][1];
            money_out(d, name, s + i, e - i);
            i = m.end;
            continue;
        }
        put(d, s[i++]);
    }
}

/* (?<![\w.,])(-?)(NUM)\s?% at p: the start of NUM or -1 */
static int pct_at(const uint32_t *s, int n, int p, int *e, int *end) {
    if (WDC(p - 1)) return -1;
    int j = p + AT(p, '-');
    *e = num_match(s, n, j, ok_pct, end);
    return *e >= 0 ? j : -1;
}

/* PERCENT with the optional (?:(?<![\w])asilimia\s+)? -> " asilimia number " */
static void p_percent(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        int e = -1, end = 0, p = prefix_at(s, n, i, "asilimia"), j = -1;
        if (p >= 0) j = pct_at(s, n, p, &e, &end);
        if (j < 0) j = pct_at(s, n, p = i, &e, &end);
        if (j >= 0) {
            puts8(d, " asilimia ");
            number(d, s + j, e - j, j > p);
            put(d, ' ');
            i = end;
            continue;
        }
        put(d, s[i++]);
    }
}

/* (?<![\w.,])(-?)(NUM)\s?(UNITS)(?![\w]) -> " unit number " */
static void p_unit(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            unit_m m = {0, 0};
            int j = i + AT(i, '-'), e = num_match(s, n, j, ok_unit, &m);
            if (e >= 0) {
                put(d, ' ');
                puts8(d, VTTS_SW_UNITS[m.key].reading);
                put(d, ' ');
                number(d, s + j, e - j, j > i);
                put(d, ' ');
                i = m.end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![\w.,])(UNIT_WORDS)\s+(NUM)(?![\d]) -> " unit number " */
static void p_unit_before(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        int e = -1, j = 0, k = 0;
        if (!WDC(i - 1))
            for (k = 0; k < VTTS_SW_N_UNITS && e < 0; k++) {
                int l = VTTS_SW_UNITS[k].before ? key_at(s, n, i, VTTS_SW_UNITS[k].key) : 0;
                if (!l || !SP(i + l)) continue;
                for (j = i + l; SP(j); j++) {}
                e = num_match(s, n, j, ok_nodigit, NULL);
            }
        if (e >= 0) {
            put(d, ' ');
            puts8(d, VTTS_SW_UNITS[k - 1].reading);
            put(d, ' ');
            number(d, s + j, e - j, 0);
            put(d, ' ');
            i = e;
            continue;
        }
        put(d, s[i++]);
    }
}

/* (?<![\w])(CONCORDS)\s+([12])(?![\d.,:/\w]) (re.IGNORECASE) -> " concord kwanza|pili " */
static void p_ordinal(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        int done = 0;
        if (!W(i - 1))
            for (int k = 0; k < VTTS_SW_N_CONCORDS && !done; k++) {
                int l = icase_at(s, n, i, VTTS_SW_CONCORDS[k]), j;
                if (!l || !SP(i + l)) continue;
                for (j = i + l; SP(j); j++) {}
                if (!(AT(j, '1') || AT(j, '2')) || W(j + 1) || AT(j + 1, '.') || AT(j + 1, ',') || AT(j + 1, ':') ||
                    AT(j + 1, '/'))
                    continue;
                put(d, ' ');
                putn(d, s + i, l);
                puts8(d, AT(j, '1') ? " kwanza " : " pili ");
                i = j + 1;
                done = 1;
            }
        if (!done) put(d, s[i++]);
    }
}

/* (?<![\w.,])(\d+)\s?[-–]\s?(\d+)(?![\w]) -> " a hadi b " */
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
                        puts8(d, " hadi ");
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

/* PRODUCT_CODE (?<![\w])(?=..[A-Z])(?=..[0-9])[A-Z0-9]+(?![\w]) -> letters by name, digits one by one */
static void p_code(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if ((upper_az(s[i]) || (s[i] >= '0' && s[i] <= '9')) && !W(i - 1)) {
            int j = i, up = 0, dg = 0;
            while (IN(j) && (upper_az(s[j]) || (s[j] >= '0' && s[j] <= '9'))) { up |= upper_az(s[j]); dg |= !upper_az(s[j]); j++; }
            if (up && dg && !W(j)) {
                put(d, ' ');
                for (int k = i; k < j; k++) {
                    if (k > i) put(d, ' ');
                    puts8(d, upper_az(s[k]) ? VTTS_SW_LETTERS[s[k] - 'A'] : VTTS_SW_ONES[s[k] - '0']);
                }
                put(d, ' ');
                i = j;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![\w.,])(-?)(NUM)(?![\d]) -> " number " */
static void p_number(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int j = i + AT(i, '-'), e = num_match(s, n, j, ok_nodigit, NULL);
            if (e >= 0) {
                put(d, ' ');
                number(d, s + j, e - j, j > i);
                put(d, ' ');
                i = e;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* SYMBOLS (in order; no reading holds a key), then "-" -> " " */
static void p_symbols(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n; i++) {
        const char *r = NULL;
        for (int k = 0; k < VTTS_SW_N_SYMBOLS && !r; k++) if (VTTS_SW_SYMBOLS[k].cp == s[i]) r = VTTS_SW_SYMBOLS[k].text;
        if (r) puts8(d, r);
        else put(d, s[i] == '-' ? ' ' : s[i]);
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
                if (in_sorted(VTTS_SW_ACRONYM_WORDS, VTTS_SW_N_ACRONYM_WORDS, low)) {
                    for (int k = i; k < j; k++) put(d, s[k] + 32);
                } else {
                    for (int k = i; k < j; k++) {
                        if (k > i) put(d, ' ');
                        puts8(d, VTTS_SW_LETTERS[s[k] - 'A']);
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

int vtts_sw_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, const uint32_t **out) {
    lb_t p = {a, 0, cap, 0}, q = {b, 0, cap, 0};
    putn(&p, in, n);
    if (p.err) return -1;
#define SWAP() do { if (q.err) return -1; lb_t t_ = p; p = q; q = t_; } while (0)
#define PASS(fn) do { q.n = 0; fn(p.p, p.n, &q); SWAP(); } while (0)
    for (int k = 0; k < VTTS_SW_N_ABBREV; k++) { q.n = 0; p_abbrev(k, p.p, p.n, &q); SWAP(); }
    PASS(p_drop);
    PASS(p_date_iso);
    PASS(p_date_dmy);
    PASS(p_time);
    PASS(p_phone);
    PASS(p_money_before);
    PASS(p_money_after);
    PASS(p_percent);
    PASS(p_unit);
    PASS(p_unit_before);
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

/* ======================= tagging (latin.latin_word_lang, code "sw") ======================= */

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

static int camel(const uint32_t *w, int n) {
    for (int i = 0; i + 1 < n; i++)
        if (w[i] >= 'a' && w[i] <= 'z' && upper_az(w[i + 1])) return 1;
    return 0;
}

/* run of consonant codes ok: at most three, no h after the first, no doubled letter (after a leading
 * mm or nn) */
static int run_ok(const char *r, int len) {
    if (len > 3) return 0;
    for (int k = 1; k < len; k++) if (r[k] == 'h') return 0;
    int from = len >= 2 && r[0] == r[1] && (r[0] == 'm' || r[0] == 'n');
    for (int k = from; k + 1 < len; k++) if (r[k] == r[k + 1]) return 0;
    return 1;
}

/* g2p_sw.valid_spelling of the lower case of w[0..n) (ASCII letters and ') */
static int valid_spelling(const uint32_t *w, int n) {
#define LOW(k) ((char)(w[k] | 32 * (w[k] != '\'')))
    if (n < 1 || !vowel(LOW(n - 1))) return 0;
    if (n >= 3 && LOW(n - 1) == 'e' && LOW(n - 2) == 'l' && !vowel(LOW(n - 3)) && LOW(n - 3) != '\'') return 0; /* [^aeiou']le$ */
    char run[4];
    int rl = 0;
    for (int i = 0; i < n;) {
        char c = LOW(i);
        int step = 1;
        for (int k = 0; k < VTTS_SW_N_CODES; k++) { /* digraphs as one code (they do not overlap) */
            const char *dg = VTTS_SW_CODES[k][0];
            int l = (int)strlen(dg), m = 0;
            while (m < l && i + m < n && LOW(i + m) == dg[m]) m++;
            if (m == l) { c = VTTS_SW_CODES[k][1][0]; step = l; break; }
        }
        i += step;
        if (c == '\'' || c == 'c' || c == 'q' || c == 'x') return 0;
        if (vowel(c)) {
            if (rl && !run_ok(run, rl)) return 0;
            rl = 0;
            continue;
        }
        if (rl == 4) return 0;
        run[rl++] = c;
    }
    return !rl || run_ok(run, rl);
#undef LOW
}

int vtts_sw_word_lang(const uint32_t *w, int n) {
    char low[128];
    if (n <= 0 || !plain_latin(w, n)) return -1;
    if (n < (int)sizeof low) {
        for (int i = 0; i < n; i++) low[i] = (char)(upper_az(w[i]) ? w[i] + 32 : w[i]);
        low[n] = 0;
        if (in_sorted(VTTS_SW_NATIVE, VTTS_SW_N_NATIVE, low) || in_sorted(VTTS_SW_TABLE_KEYS, VTTS_SW_N_TABLE_KEYS, low))
            return 1;
        if (vtts_lt_english_word(low)) return 0;
    }
    int all_caps = 1, all_valid = 1;
    for (int a = 0; a < n;) { /* parts: split at '-' only (the apostrophe of ng' is a letter) */
        int b = a;
        while (b < n && w[b] != '-') b++;
        if (b > a) {
            int len = b - a, up = 0, lo = 0;
            if (camel(w + a, len)) return 0;
            for (int k = a; k < b; k++) { up |= upper_az(w[k]); lo |= w[k] >= 'a' && w[k] <= 'z'; }
            all_caps &= up && !lo && len >= 2 && len <= 5; /* str.isupper() */
            if (all_valid) all_valid = valid_spelling(w + a, len);
        }
        a = b + 1;
    }
    if (n == 1 || all_caps) return 1;
    return all_valid;
}

/* ======================= g2p ======================= */

#define ACUTE 1 /* the acute accent kept by fold() (a stress mark) */

typedef struct { char kind, mark, ph[4]; } seg_t; /* kind 'C', 'V' or 'N' (syllabic nasal) */

/* fold() of one code point: the letter (0: none) and whether an acute accent follows it */
static int fold1(uint32_t c, int *acute) {
    *acute = 0;
    if (c < 0x80) {
        if (c >= 'A' && c <= 'Z') return (int)c + 32;
        return (c >= 'a' && c <= 'z') || c == '\'' ? (int)c : 0;
    }
    int lo = 0, hi = VTTS_SW_N_FOLD - 1, k = -1;
    while (lo <= hi) {
        int m = (lo + hi) / 2;
        if (VTTS_SW_FOLD[m].start <= c) { k = m; lo = m + 1; } else hi = m - 1;
    }
    if (k < 0 || c - VTTS_SW_FOLD[k].start >= VTTS_SW_FOLD[k].count) return 0;
    const vtts_sw_fold *r = &VTTS_SW_FOLD[k];
    *acute = r->acute;
    return r->first ? (int)(r->first + (c - r->start) * r->step) : 0;
}

/* fold(word) into o (at most cap chars, ACUTE for a kept acute accent); returns the length */
static int fold_word(const uint32_t *w, int n, char *o, int cap) {
    int m = 0;
    for (int i = 0; i < n && m < cap; i++) {
        int ac, f = fold1(w[i], &ac);
        if (f) o[m++] = (char)f;
        if (ac && m && m < cap && vowel(o[m - 1])) o[m++] = ACUTE;
    }
    return m;
}

typedef struct { uint8_t *out; int n, cap; } emit_t;

static void emit(emit_t *e, const char *ph, int stress) {
    char b[8];
    size_t l = strlen(ph);
    memcpy(b, ph, l);
    if (stress) b[l++] = '1';
    b[l] = 0;
    for (int k = 0; k < VTTS_SW_N_TOKENS; k++)
        if (!strcmp(VTTS_SW_TOKENS[k], b)) {
            if (e->n < e->cap) e->out[e->n++] = (uint8_t)(VTTS_SW_TOK0 + k);
            return;
        }
}

typedef struct { char w[VTTS_SW_MAXW + 8], plain[VTTS_SW_MAXW + 8]; seg_t S[VTTS_SW_MAXW]; } sw_scratch;

static void add_seg(seg_t *S, int *ns, char kind, const char *ph, int mark) {
    seg_t *s = &S[(*ns)++];
    memset(s, 0, sizeof *s);
    s->kind = kind;
    s->mark = (char)mark;
    for (int k = 0; k < 3 && ph[k]; k++) s->ph[k] = ph[k];
}

/* g2p_sw.phonemes of the n code points w */
static void phonemes(emit_t *e, const uint32_t *word, int wn, sw_scratch *x) {
    char *w = x->w, *plain = x->plain;
    seg_t *S = x->S;
    int n = fold_word(word, wn, w, VTTS_SW_MAXW), pn = 0, ns = 0;
    for (int i = 0; i < n; i++) if (w[i] != ACUTE) plain[pn++] = w[i];
    plain[pn] = 0;
    for (int k = 0; k < VTTS_SW_N_STRESS; k++)
        if (!strcmp(plain, VTTS_SW_STRESS[k][0])) {
            uint32_t r[64];
            int rn = 0, l;
            for (const char *p = VTTS_SW_STRESS[k][1]; rn < 64 && (l = dec1(p, &r[rn])) > 0; p += l) rn++;
            n = fold_word(r, rn, w, VTTS_SW_MAXW);
            break;
        }
    for (int i = 0; i < n;) { /* _segments */
        char c = w[i], one[2] = {c, 0};
        if (vowel(c)) {
            int marked = i + 1 < n && w[i + 1] == ACUTE;
            add_seg(S, &ns, 'V', one, marked);
            i += marked ? 2 : 1;
            continue;
        }
        if (c == '\'' || c == ACUTE) { i++; continue; }
        if ((c == 'm' || c == 'n') && i == 0 && n > 1 && !vowel(w[1]) && w[1] != '\'') {
            char nx = w[1];
            if ((c == 'm' && !strchr("bwy", nx)) || (c == 'n' && !strchr("djgyz", nx))) {
                add_seg(S, &ns, 'N', one, 0);
                i++;
                continue;
            }
        }
        int dg = -1;
        for (int k = 0; k < VTTS_SW_N_DIGRAPHS && dg < 0; k++) {
            const char *p = VTTS_SW_DIGRAPHS[k][0];
            int l = (int)strlen(p);
            if (i + l <= n && !memcmp(w + i, p, (size_t)l)) dg = k;
        }
        if (dg >= 0) {
            add_seg(S, &ns, 'C', VTTS_SW_DIGRAPHS[dg][1], 0);
            i += (int)strlen(VTTS_SW_DIGRAPHS[dg][0]);
            continue;
        }
        if (i && c == w[i - 1] && c != 'm' && c != 'n' && ns && S[ns - 1].kind == 'C') { i++; continue; } /* doubled letter */
        if (c == 'x') { add_seg(S, &ns, 'C', "k", 0); add_seg(S, &ns, 'C', "s", 0); }
        else { if (c == 'c' || c == 'q') one[0] = 'k'; add_seg(S, &ns, 'C', one, 0); }
        i++;
    }
    int stress = -1, last = -1, prev = -1;
    for (int k = 0; k < ns; k++) {
        if (S[k].kind == 'V' && S[k].mark && stress < 0) stress = k;
        if (S[k].kind != 'C') { prev = last; last = k; }
    }
    if (stress < 0 && last >= 0 && !in_sorted(VTTS_SW_UNSTRESSED, VTTS_SW_N_UNSTRESSED, plain)) {
        int k = prev >= 0 ? prev : last;
        if (S[k].kind == 'V') stress = k;
    }
    for (int k = 0; k < ns; k++) emit(e, S[k].ph, k == stress);
}

int vtts_sw_word_ids(const uint32_t *w, int n, void *scratch, size_t scratch_bytes, uint8_t *out, int cap) {
    sw_scratch *x = scratch;
    emit_t e = {out, 0, cap};
    if (scratch_bytes < sizeof *x) return 0;
    if (n > VTTS_SW_MAXW / 2) n = VTTS_SW_MAXW / 2; /* a letter and an accent per code point; x reads as two sounds */
    int m = fold_word(w, n, x->w, VTTS_SW_MAXW), letters = 0, vow = 0;
    for (int i = 0; i < m; i++) { letters |= x->w[i] != ACUTE; vow |= vowel(x->w[i]); }
    if (letters && !vow) { /* a word without a vowel (km, kg) is spelled letter by letter */
        char sp[VTTS_SW_MAXW];
        int k = 0;
        for (int i = 0; i < m; i++) if (x->w[i] >= 'a' && x->w[i] <= 'z') sp[k++] = x->w[i];
        for (int i = 0; i < k; i++) {
            uint32_t name[16];
            int nn = 0;
            for (const char *p = VTTS_SW_LETTERS[sp[i] - 'a']; *p && nn < 16; p++) name[nn++] = (uint32_t)(unsigned char)*p;
            phonemes(&e, name, nn, x);
        }
        return e.n;
    }
    phonemes(&e, w, n, x);
    return e.n;
}

#endif /* VTTS_ENABLE_SW */
