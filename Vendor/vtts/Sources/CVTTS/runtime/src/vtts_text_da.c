/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_da.c -- Danish front-end of the device (token set da-en): tagging of plain Latin words
 * (latin.py with the Danish word lists and spelling check), normalization pass by pass
 * (da/normalize_da.py and latin_norm.py) and word readings (da/g2p_da.py: the NST lexicon of the
 * frequent words, compounds of known words, the spelling rules with stress, vowel length and stød).
 * All tables are in the generated vtts_text_da_tables.h; no blob is needed. Compiled only with
 * VTTS_ENABLE_DA (vtts_text_da.h). */
#include "vtts_text_da.h"

#if VTTS_ENABLE_DA

#include <string.h>

#include "vtts_text_da_tables.h"
#include "vtts_text_lt.h"

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

static int in_list(const char *const *list, int n, const char *s) {
    for (int k = 0; k < n; k++) if (strcmp(list[k], s) == 0) return 1;
    return 0;
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
#define RG(i, lo, hi) (IN(i) && s[i] >= (uint32_t)(lo) && s[i] <= (uint32_t)(hi))
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

/* ======================= numbers (normalize_da) ======================= */

static void below_100(lb_t *d, int v) {
    if (v < 20) { puts8(d, VTTS_DA_ONES[v]); return; }
    if (v % 10) { puts8(d, VTTS_DA_ONES[v % 10]); puts8(d, "og"); }
    puts8(d, VTTS_DA_TENS[v / 10]);
}

static void below_1000(lb_t *d, int v) {
    int h = v / 100, r = v % 100;
    if (h) {
        if (h == 1) puts8(d, "hundrede");
        else { puts8(d, VTTS_DA_ONES[h]); puts8(d, " hundrede"); }
    }
    if (r) {
        if (h) puts8(d, " og ");
        below_100(d, r);
    }
}

/* cardinal(v) for 0 < v < 10**15 */
static void card_v(lb_t *d, uint64_t v) {
    static const uint64_t SC[2] = {1000000000ull, 1000000ull};
    static const char *const ONE[2] = {"milliard", "million"}, *const MANY[2] = {"milliarder", "millioner"};
    int any = 0;
    for (int k = 0; k < 2; k++) {
        uint64_t q = v / SC[k];
        v %= SC[k];
        if (!q) continue;
        if (any) put(d, ' ');
        if (q == 1) { puts8(d, "en "); puts8(d, ONE[k]); }
        else { card_v(d, q); put(d, ' '); puts8(d, MANY[k]); }
        any = 1;
    }
    int q = (int)(v / 1000), r = (int)(v % 1000);
    if (q) {
        if (any) put(d, ' ');
        if (q == 1) puts8(d, "tusind");
        else { below_1000(d, q); puts8(d, " tusind"); }
        any = 1;
    }
    if (r) {
        if (any) { put(d, ' '); if (r < 100) puts8(d, "og "); }
        below_1000(d, r);
    }
}

/* cardinal(int(s)) of the digits of s[0..n) */
static void card(lb_t *d, const uint32_t *s, int n) {
    int st, nd = sig(s, n, &st);
    if (!nd) { puts8(d, VTTS_DA_ONES[0]); return; }
    if (nd > 15) { /* " ".join(DIGITS[int(c)] for c in str(n)) */
        int first = 1;
        for (int i = st; i < n; i++) {
            int v = vtts_u_digit(s[i]);
            if (v < 0) continue;
            if (!first) put(d, ' ');
            puts8(d, VTTS_DA_ONES[v]);
            first = 0;
        }
        return;
    }
    card_v(d, value(s, n, st));
}

static void card_i(lb_t *d, int v) {
    if (!v) { puts8(d, VTTS_DA_ONES[0]); return; }
    card_v(d, (uint64_t)v);
}

static void year(lb_t *d, int v) {
    if (v >= 1100 && v <= 1999) {
        puts8(d, VTTS_DA_ONES[v / 100]);
        puts8(d, " hundrede");
        if (v % 100) { puts8(d, " og "); below_100(d, v % 100); }
        return;
    }
    card_i(d, v);
}

/* latin_norm.parse_number: integer part [0, *ie) (separators skipped), decimals [*f0, n) or -1 */
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

static int is_one(const uint32_t *s, int n) { /* int(s) == 1 */
    int st, nd = sig(s, n, &st);
    return nd == 1 && vtts_u_digit(s[st]) == 1;
}

/* number(sign + s): "minus " for a sign, cardinal, then komma/punktum and the decimals */
static void number(lb_t *d, const uint32_t *s, int n, int neg) {
    int ie, f0;
    uint32_t mark;
    if (neg) puts8(d, "minus ");
    parse_number(s, n, &ie, &f0, &mark);
    card(d, s, ie);
    if (f0 < 0) return;
    put(d, ' ');
    puts8(d, mark == ',' ? VTTS_DA_COMMA : VTTS_DA_PERIOD);
    put(d, ' ');
    if (f0 < n && n - f0 <= 2 && s[f0] != '0') { card(d, s + f0, n - f0); return; }
    int first = 1;
    for (int i = f0; i < n; i++) {
        int v = vtts_u_digit(s[i]);
        if (v < 0) continue;
        if (!first) put(d, ' ');
        puts8(d, VTTS_DA_ONES[v]);
        first = 0;
    }
}

/* ======================= normalization passes =======================
 * Each regex pass of the Python normalizer is one function from s (n code points) to d; matches
 * are found left to right without overlap, like re.sub, and lookarounds look at the pass's input.
 * Where backtracking can change a match, the candidate ends are tried in the regex's order. */

typedef int (*end_ok)(const uint32_t *s, int n, int end, void *u);

static int try_dec(const uint32_t *s, int n, int b, end_ok ok, void *u) { /* (?:[.,]\d+)? then ok() */
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

/* apply_abbreviations, one key: (?<![\w])KEY[(?![\w])] -> " reading " (+ "." at the end of the text) */
static void p_abbrev(int k, const uint32_t *s, int n, lb_t *d) {
    const char *key = VTTS_DA_ABBREV[k][0];
    int dot = key[strlen(key) - 1] == '.';
    for (int i = 0; i < n;) {
        int m;
        if (!W(i - 1) && (m = key_at(s, n, i, key)) && (dot || !W(i + m))) {
            int end = dot;
            for (int q = i + m; q < n && end; q++) end = vtts_u_space(s[q]);
            put(d, ' ');
            puts8(d, VTTS_DA_ABBREV[k][1]);
            put(d, ' ');
            if (end) put(d, '.');
            i += m;
            continue;
        }
        put(d, s[i++]);
    }
}

static void p_drop(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n; i++) put(d, in_u8(s[i], VTTS_DA_DROP) ? ' ' : s[i]);
}

/* _date(d, m, y): " ordinal month [year] " or the original text when the day or month is out of range */
static void date_out(lb_t *d, int dd, int mm, int yy, const uint32_t *orig, int on) {
    if (!(dd >= 1 && dd <= 31 && mm >= 1 && mm <= 12)) { putn(d, orig, on); return; }
    put(d, ' ');
    puts8(d, VTTS_DA_ORDINALS[dd]);
    put(d, ' ');
    puts8(d, VTTS_DA_MONTHS[mm]);
    put(d, ' ');
    year(d, yy);
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
                    date_out(d, val(s, d0, dl), val(s, m0, ml), val(s, i, 4), s + i, d0 + dl - i);
                    i = d0 + dl;
                    continue;
                }
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![\d/.])(\d{1,2})([/.])(\d{1,2})\2(\d{4})(?![\d/]|\.\d) */
static void p_date_dmy(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !DG(i - 1) && !AT(i - 1, '/') && !AT(i - 1, '.')) {
            int r1 = drun(s, n, i), p = i + r1;
            if (r1 <= 2 && (AT(p, '/') || AT(p, '.'))) {
                uint32_t sep = s[p];
                int m0 = p + 1, r2 = drun(s, n, m0);
                if (r2 >= 1 && r2 <= 2 && AT(m0 + r2, sep)) {
                    int y0 = m0 + r2 + 1, e = y0 + 4;
                    if (drun(s, n, y0) == 4 && !AT(e, '/') && !(AT(e, '.') && DG(e + 1))) {
                        date_out(d, val(s, i, r1), val(s, m0, r2), val(s, y0, 4), s + i, e - i);
                        i = e;
                        continue;
                    }
                }
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![\d.,])(\d{1,2})\.\s?(months)(?:\s(\d{4}))?(?![\w]) */
static void p_date_named(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !DG(i - 1) && !AT(i - 1, '.') && !AT(i - 1, ',')) {
            int r = drun(s, n, i), done = 0;
            if (r <= 2 && AT(i + r, '.')) {
                int p = i + r + 1;
                for (int sp = SP(p); sp >= 0 && !done; sp--) {
                    int q = p + sp;
                    for (int k = 0; k < VTTS_DA_N_MONTH_KEYS && !done; k++) {
                        int l = key_at(s, n, q, VTTS_DA_MONTH_KEYS[k]);
                        if (!l) continue;
                        int e = q + l, end = -1, y = -1;
                        if (SP(e) && DG(e + 1) && DG(e + 2) && DG(e + 3) && DG(e + 4) && !W(e + 5)) {
                            end = e + 5;
                            y = val(s, e + 1, 4);
                        } else if (!W(e)) {
                            end = e;
                        }
                        if (end < 0) continue;
                        int dd = val(s, i, r);
                        if (dd < 1 || dd > 31) putn(d, s + i, end - i);
                        else {
                            put(d, ' ');
                            puts8(d, VTTS_DA_ORDINALS[dd]);
                            put(d, ' ');
                            for (int c = q; c < e; c++) put(d, s[c] >= 'A' && s[c] <= 'Z' ? s[c] + 32 : s[c]);
                            if (y >= 0) { put(d, ' '); year(d, y); }
                            put(d, ' ');
                        }
                        i = end;
                        done = 1;
                    }
                }
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

/* _clock(h, mi) */
static void clock_words(lb_t *d, int h, int mi) {
    card_i(d, h);
    if (!mi) return;
    put(d, ' ');
    if (mi < 10) { puts8(d, "nul "); puts8(d, VTTS_DA_ONES[mi]); }
    else below_100(d, mi);
}

/* ([Kk]lokken)\s+(\d{1,2})(?:[.:]([0-5]\d))?(?![\d]) -> "\1 clock " */
static void p_time_kl(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if ((AT(i, 'K') || AT(i, 'k')) && key_at(s, n, i + 1, "lokken") && SP(i + 7)) {
            int p = i + 7, done = 0;
            while (SP(p)) p++;
            int r = drun(s, n, p);
            for (int hl = r >= 2 ? 2 : r; hl >= 1 && !done; hl--) {
                int q = p + hl, end = -1, mi = 0;
                if ((AT(q, '.') || AT(q, ':')) && RG(q + 1, '0', '5') && DG(q + 2) && !DG(q + 3)) {
                    end = q + 3;
                    mi = val(s, q + 1, 2);
                } else if (!DG(q)) {
                    end = q;
                }
                if (end < 0) continue;
                putn(d, s + i, 7);
                put(d, ' ');
                clock_words(d, val(s, p, hl), mi);
                put(d, ' ');
                i = end;
                done = 1;
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

/* ([01]?\d|2[0-4]) at i: the hour lengths in the order the regex tries them */
static int hours(const uint32_t *s, int n, int i, int hl[3]) {
    int k = 0;
    if ((AT(i, '0') || AT(i, '1')) && DG(i + 1)) hl[k++] = 2;
    if (DG(i)) hl[k++] = 1;
    if (AT(i, '2') && RG(i + 1, '0', '4')) hl[k++] = 2;
    return k;
}

/* (?<![\d:.,])([01]?\d|2[0-4])[:.]([0-5]\d)(?![\d:]|[.,]\d) -> " clock " */
static void p_time(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !DG(i - 1) && !AT(i - 1, ':') && !AT(i - 1, '.') && !AT(i - 1, ',')) {
            int hl[3], nh = hours(s, n, i, hl), done = 0;
            for (int c = 0; c < nh && !done; c++) {
                int j = i + hl[c], e = j + 3;
                if (!((AT(j, ':') || AT(j, '.')) && RG(j + 1, '0', '5') && DG(j + 2))) continue;
                if (DG(e) || AT(e, ':') || ((AT(e, '.') || AT(e, ',')) && DG(e + 1))) continue;
                put(d, ' ');
                clock_words(d, val(s, i, hl[c]), val(s, j + 1, 2));
                put(d, ' ');
                i = e;
                done = 1;
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

/* PHONE: (?<![\d])(?:\+\d{2}\s)?\d{2}(?:\s\d{2}){3}(?![\d]) | (?<![\d])\+\d{2}\s?\d{8}(?![\d]) */
static int pairs4(const uint32_t *s, int n, int p) { /* \d{2}(?:\s\d{2}){3}(?![\d]) at p: end or -1 */
    if (!(DG(p) && DG(p + 1))) return -1;
    int q = p + 2;
    for (int g = 0; g < 3; g++) {
        if (!(SP(q) && DG(q + 1) && DG(q + 2))) return -1;
        q += 3;
    }
    return DG(q) ? -1 : q;
}

static void p_phone(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        int e = -1;
        if (!DG(i - 1)) {
            int pre = AT(i, '+') && DG(i + 1) && DG(i + 2) && SP(i + 3);
            for (int k = pre; k >= 0 && e < 0; k--) e = pairs4(s, n, k ? i + 4 : i);
            if (e < 0 && AT(i, '+') && DG(i + 1) && DG(i + 2))
                for (int sp = SP(i + 3); sp >= 0 && e < 0; sp--) {
                    int q = i + 3 + sp;
                    if (drun(s, n, q) >= 8 && !DG(q + 8)) e = q + 8;
                }
        }
        if (e >= 0) { /* _phone: groups split at white space; "+dd" read as plus and a number; pairs */
            int first = 1;
            put(d, ' ');
            for (int a = i; a < e;) {
                while (a < e && vtts_u_space(s[a])) a++;
                int b = a;
                while (b < e && !vtts_u_space(s[b])) b++;
                if (b == a) break;
                int g = a;
                if (s[g] == '+') {
                    if (!first) put(d, ' ');
                    puts8(d, "plus ");
                    card(d, s + g + 1, 2);
                    first = 0;
                    g += 3;
                }
                for (; g < b; g += 2) {
                    int l = b - g < 2 ? b - g : 2;
                    if (!first) put(d, ' ');
                    first = 0;
                    if (s[g] == '0') {
                        for (int c = 0; c < l; c++) {
                            if (c) put(d, ' ');
                            puts8(d, VTTS_DA_ONES[vtts_u_digit(s[g + c])]);
                        }
                    } else card(d, s + g, l);
                }
                a = b;
            }
            put(d, ' ');
            i = e;
            continue;
        }
        put(d, s[i++]);
    }
}

/* _money(num, cur) */
static void money_out(lb_t *d, const uint32_t *num, int nn, const char *const *cur) {
    int ie, f0;
    uint32_t mark;
    parse_number(num, nn, &ie, &f0, &mark);
    put(d, ' ');
    int krone = strcmp(cur[1], "krone") == 0;
    if (f0 >= 0 && krone && nn - f0 == 2) {
        card(d, num, ie);
        put(d, ' ');
        puts8(d, is_one(num, ie) ? cur[1] : cur[2]);
        int cents = val(num, f0, 2);
        if (cents) { puts8(d, " og "); card_i(d, cents); puts8(d, " øre"); }
        put(d, ' ');
        return;
    }
    number(d, num, nn, 0);
    put(d, ' ');
    puts8(d, is_one(num, ie) && f0 < 0 ? cur[1] : cur[2]);
    put(d, ' ');
}

/* (DKK|EUR|USD|€|\$|£)\s?(NUM)(?:,-)? */
static void p_money_before(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        int done = 0;
        for (int k = 0; k < VTTS_DA_N_CUR_BEFORE && !done; k++) {
            int l = key_at(s, n, i, VTTS_DA_CUR_BEFORE[k][0]);
            if (!l) continue;
            for (int sp = SP(i + l); sp >= 0 && !done; sp--) {
                int j = i + l + sp, e = num_match(s, n, j, ok_always, NULL);
                if (e < 0) continue;
                int end = AT(e, ',') && AT(e + 1, '-') ? e + 2 : e;
                money_out(d, s + j, e - j, VTTS_DA_CUR_BEFORE[k]);
                i = end;
                done = 1;
            }
        }
        if (done) continue;
        put(d, s[i++]);
    }
}

typedef struct { int key, end; } cur_m;

static int ok_cur_after(const uint32_t *s, int n, int e, void *u) { /* (?:,-)?\s?(KEYS)(?![\w]) */
    cur_m *m = u;
    for (int dash = AT(e, ',') && AT(e + 1, '-'); dash >= 0; dash--) {
        int p = e + 2 * dash;
        for (int sp = SP(p); sp >= 0; sp--)
            for (int k = 0; k < VTTS_DA_N_CUR_AFTER; k++) {
                int l = key_at(s, n, p + sp, VTTS_DA_CUR_AFTER[k][0]);
                if (l && !W(p + sp + l)) { m->key = k; m->end = p + sp + l; return 1; }
            }
    }
    return 0;
}

/* (?<![\w.,])(NUM)(?:,-)?\s?(CUR)(?![\w]) -> _money (+ "." after "kr." at the end of the text) */
static void p_money_after(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            cur_m m = {0, 0};
            int e = num_match(s, n, i, ok_cur_after, &m);
            if (e >= 0) {
                money_out(d, s + i, e - i, VTTS_DA_CUR_AFTER[m.key]);
                if (strcmp(VTTS_DA_CUR_AFTER[m.key][0], "kr.") == 0) {
                    int end = 1;
                    for (int q = m.end; q < n && end; q++) end = vtts_u_space(s[q]);
                    if (end) put(d, '.');
                }
                i = m.end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![\w.,])(\d+)\s?øre(?![\w]) */
static void p_ore(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !WDC(i - 1)) {
            int r = drun(s, n, i), p = i + r, done = 0;
            for (int sp = SP(p); sp >= 0 && !done; sp--) {
                int q = p + sp, l = key_at(s, n, q, "øre");
                if (!l || W(q + l)) continue;
                put(d, ' ');
                card(d, s + i, r);
                puts8(d, " øre ");
                i = q + l;
                done = 1;
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

/* (?<![\w.,])(-?)(NUM)\s?% -> " number procent " */
static void p_percent(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int j = i + AT(i, '-'), end = 0, e = num_match(s, n, j, ok_pct, &end);
            if (e >= 0) {
                put(d, ' ');
                number(d, s + j, e - j, j > i);
                puts8(d, " procent ");
                i = end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

typedef struct { int key, end; } unit_m;

static int ok_unit(const uint32_t *s, int n, int e, void *u) { /* \s?(UNITS)(?![\w]) */
    unit_m *m = u;
    for (int sp = SP(e); sp >= 0; sp--)
        for (int k = 0; k < VTTS_DA_N_UNITS; k++) {
            int l = key_at(s, n, e + sp, VTTS_DA_UNITS[k][0]);
            if (l && !W(e + sp + l)) { m->key = k; m->end = e + sp + l; return 1; }
        }
    return 0;
}

/* (?<![\w.,])(-?)(NUM)\s?(UNITS)(?![\w]) */
static void p_unit(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            unit_m m = {0, 0};
            int j = i + AT(i, '-'), e = num_match(s, n, j, ok_unit, &m);
            if (e >= 0) {
                int ie, f0;
                uint32_t mark;
                parse_number(s + j, e - j, &ie, &f0, &mark);
                put(d, ' ');
                if (j > i) puts8(d, "minus ");
                number(d, s + j, e - j, 0);
                put(d, ' ');
                puts8(d, VTTS_DA_UNITS[m.key][is_one(s + j, ie) && f0 < 0 ? 1 : 2]);
                put(d, ' ');
                i = m.end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int da_lower_letter(uint32_t c) { return (c >= 'a' && c <= 'z') || c == 0xE6 || c == 0xF8 || c == 0xE5; }

/* (?<![\w.,])(\d{1,2})\.(?=\s[a-zæøå]) -> " ordinal " */
static void p_ordinal(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !WDC(i - 1)) {
            int r = drun(s, n, i);
            if (r <= 2 && AT(i + r, '.') && SP(i + r + 1) && IN(i + r + 2) && da_lower_letter(s[i + r + 2])) {
                int v = val(s, i, r);
                put(d, ' ');
                if (v >= 1 && v <= 31) puts8(d, VTTS_DA_ORDINALS[v]);
                else card_i(d, v);
                put(d, ' ');
                i += r + 1;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![\w.,])(\d+)\s?[-–]\s?(\d+)(?![\w]) -> " a til b " */
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
                        puts8(d, " til ");
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

/* PRODUCT_CODE -> letters by name, digits one by one */
static void p_code(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if ((upper_az(s[i]) || (s[i] >= '0' && s[i] <= '9')) && !W(i - 1)) {
            int j = i, up = 0, dg = 0;
            while (IN(j) && (upper_az(s[j]) || (s[j] >= '0' && s[j] <= '9'))) { up |= upper_az(s[j]); dg |= !upper_az(s[j]); j++; }
            if (up && dg && !W(j)) {
                put(d, ' ');
                for (int k = i; k < j; k++) {
                    if (k > i) put(d, ' ');
                    puts8(d, upper_az(s[k]) ? VTTS_DA_LETTERS[s[k] - 'A'] : VTTS_DA_ONES[s[k] - '0']);
                }
                put(d, ' ');
                i = j;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![\w.,])(1[1-9]\d\d)(?![\w]|[.,]\d) -> " year " */
static void p_year(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (AT(i, '1') && !WDC(i - 1) && RG(i + 1, '1', '9') && DG(i + 2) && DG(i + 3) && !W(i + 4) &&
            !((AT(i + 4, '.') || AT(i + 4, ',')) && DG(i + 5))) {
            put(d, ' ');
            year(d, 1000 + (int)(s[i + 1] - '0') * 100 + val(s, i + 2, 2));
            put(d, ' ');
            i += 4;
            continue;
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
        for (int k = 0; k < VTTS_DA_N_SYMBOLS && !r; k++) if (VTTS_DA_SYMBOLS[k].cp == s[i]) r = VTTS_DA_SYMBOLS[k].text;
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
                if (in_sorted(VTTS_DA_ACRONYM_WORDS, VTTS_DA_N_ACRONYM_WORDS, low)) {
                    for (int k = i; k < j; k++) put(d, s[k] + 32);
                } else {
                    for (int k = i; k < j; k++) {
                        if (k > i) put(d, ' ');
                        puts8(d, VTTS_DA_LETTERS[s[k] - 'A']);
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

int vtts_da_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, const uint32_t **out) {
    lb_t p = {a, 0, cap, 0}, q = {b, 0, cap, 0};
    putn(&p, in, n);
    if (p.err) return -1;
#define SWAP() do { if (q.err) return -1; lb_t t_ = p; p = q; q = t_; } while (0)
#define PASS(fn) do { q.n = 0; fn(p.p, p.n, &q); SWAP(); } while (0)
    for (int k = 0; k < VTTS_DA_N_ABBREV; k++) { q.n = 0; p_abbrev(k, p.p, p.n, &q); SWAP(); }
    PASS(p_drop);
    PASS(p_date_iso);
    PASS(p_date_dmy);
    PASS(p_date_named);
    PASS(p_time_kl);
    PASS(p_time);
    PASS(p_phone);
    PASS(p_money_before);
    PASS(p_money_after);
    PASS(p_ore);
    PASS(p_percent);
    PASS(p_unit);
    PASS(p_ordinal);
    PASS(p_range);
    PASS(p_pause);
    PASS(p_code);
    PASS(p_year);
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

#undef IN
#undef W
#undef DG
#undef SP
#undef AT
#undef RG
#undef WDC

/* ======================= words: lexicon, compounds, rules (g2p_da.py) =======================
 * A folded word is a byte string: a-z, and { | } ~ for å æ é ø. Units are bytes too: a vowel letter,
 * a consonant letter, an upper-case letter for a doubled consonant ("tt" -> 'T'), '$' for the sj
 * sound (sj sch ch -tion -sion) and '#' for ng (ng, the n of nk). */

#define SJ '$'
#define NG '#'

static int vowel_b(char c) { return c && strchr(VTTS_DA_VOWEL_LETTERS, c) != NULL; }
static int vow_index(char c) { return (int)(strchr(VTTS_DA_VOWEL_LETTERS, c) - VTTS_DA_VOWEL_LETTERS); }
static int doubled(char u) { return u >= 'A' && u <= 'Z'; }
static char base(char u) { return doubled(u) ? (char)(u + 32) : u; }

/* ---- known words (front coded with the lexicon readings) ---- */

static int cmp_bytes(const uint8_t *a, int la, const uint8_t *b, int lb) {
    int m = la < lb ? la : lb;
    for (int i = 0; i < m; i++) if (a[i] != b[i]) return a[i] < b[i] ? -1 : 1;
    return la < lb ? -1 : la > lb ? 1 : 0;
}

/* the word at off into buf (holding the previous word); *toks: its readings (or -1); next offset */
static int decode_word(int off, uint8_t *buf, int *len, int *toks) {
    int p = VTTS_DA_WORDS[off++] & 0x7F;
    while (VTTS_DA_WORDS[off] >= 0x61 && VTTS_DA_WORDS[off] < 0x80) buf[p++] = VTTS_DA_WORDS[off++];
    *len = p;
    *toks = -1;
    if (VTTS_DA_WORDS[off] == 0x40) {
        *toks = ++off;
        while (VTTS_DA_WORDS[off] < 0x40) off++;
    }
    return off;
}

/* the known word w: 1 and *toks (offset of the readings, -1 when the rules read it), else 0 */
static int find_word(const char *w, int n, int *toks) {
    uint8_t buf[VTTS_DA_MAX_WORD + 1];
    int lo = 0, hi = VTTS_DA_N_BLOCKS - 1, b = -1, len, t;
    if (n > VTTS_DA_MAX_WORD || n <= 0) return 0;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        decode_word((int)VTTS_DA_BLOCKS[mid], buf, &len, &t);
        if (cmp_bytes(buf, len, (const uint8_t *)w, n) <= 0) { b = mid; lo = mid + 1; } else hi = mid - 1;
    }
    if (b < 0) return 0;
    int off = (int)VTTS_DA_BLOCKS[b];
    int end = b + 1 < VTTS_DA_N_BLOCKS ? (int)VTTS_DA_BLOCKS[b + 1] : VTTS_DA_WORDS_BYTES - 1;
    while (off < end) {
        off = decode_word(off, buf, &len, &t);
        int c = cmp_bytes(buf, len, (const uint8_t *)w, n);
        if (!c) { if (toks) *toks = t; return 1; }
        if (c > 0) return 0;
    }
    return 0;
}

/* ---- token output ---- */

typedef struct { uint8_t *p; int n, cap; } tk_t;
static void tk(tk_t *o, int t) { if (o->n < o->cap) o->p[o->n++] = (uint8_t)t; }

/* ---- spelling -> units ---- */

#define MAXU (2 * VTTS_DA_MAXW + 2) /* units of a word (x gives two) */
typedef struct {
    char w[VTTS_DA_MAXW + 1];
    int nw;
    char u[MAXU];  /* unit codes */
    int16_t pos[MAXU];
    int nu;
    int16_t na[MAXU], nb[MAXU];
    int nn;
    char rkind[MAXU]; /* 'v', 'o', 'c' */
    int16_t rk[MAXU];
    uint8_t out[MAXU][6];
    uint8_t nout[MAXU];
    uint8_t skip[MAXU];
    uint8_t long_syl[MAXU];
} rs_t;

static int starts(const char *w, int n, int i, const char *k) {
    int l = (int)strlen(k);
    return i + l <= n && memcmp(w + i, k, (size_t)l) == 0;
}

static void unit(rs_t *r, char c, int pos) {
    if (r->nu >= MAXU) return;
    r->u[r->nu] = c;
    r->pos[r->nu] = (int16_t)pos;
    r->nu++;
}

static void units(rs_t *r) {
    const char *w = r->w;
    int n = r->nw;
    r->nu = 0;
    for (int i = 0; i < n;) {
        char c = w[i];
        if (i > 0 && (starts(w, n, i, "tion") || starts(w, n, i, "sion"))) { unit(r, SJ, i); i += 2; }
        else if (starts(w, n, i, "sch")) { unit(r, SJ, i); i += 3; }
        else if (starts(w, n, i, "sj") || starts(w, n, i, "ch") || (i == 0 && starts(w, n, 0, "sh"))) { unit(r, SJ, i); i += 2; }
        else if (starts(w, n, i, "ph") || starts(w, n, i, "th")) { unit(r, c == 'p' ? 'f' : 't', i); i += 2; }
        else if (starts(w, n, i, "ck")) { unit(r, 'K', i); i += 2; }
        else if (starts(w, n, i, "ng")) { unit(r, NG, i); i += 2; }
        else if (starts(w, n, i, "nk")) { unit(r, NG, i); unit(r, 'k', i + 1); i += 2; }
        else if (i == 0 && (starts(w, n, 0, "hv") || starts(w, n, 0, "hj"))) { unit(r, w[1], 0); i += 2; }
        else if (c == 'x') { unit(r, 'k', i); unit(r, 's', i); i += 1; }
        else if (starts(w, n, i, "qu")) { unit(r, 'k', i); unit(r, 'v', i + 1); i += 2; }
        else if (strchr("ptkbdgfslmnrv", c) && i + 1 < n && w[i + 1] == c) { unit(r, (char)(c - 32), i); i += 2; }
        else {
            if (c == 'c') c = i + 1 < n && strchr("eiy|~", w[i + 1]) ? 's' : 'k';
            if (c == 'z') c = 's';
            else if (c == 'w') c = 'v';
            else if (c == 'q') c = 'k';
            unit(r, c, i);
            i += 1;
        }
    }
}

static int pair_nucleus(char a, char b, int *k) {
    for (int q = 0; q < VTTS_DA_N_PAIRS; q++)
        if (VTTS_DA_PAIRS[q].a == a && VTTS_DA_PAIRS[q].b == b) { if (k) *k = q; return 1; }
    return 0;
}

static void nuclei(rs_t *r) {
    r->nn = 0;
    for (int k = 0; k < r->nu; k++) {
        if (!vowel_b(r->u[k])) continue;
        if (r->nn && r->na[r->nn - 1] == k - 1 && r->nb[r->nn - 1] == k - 1 && pair_nucleus(r->u[k - 1], r->u[k], NULL)) {
            r->nb[r->nn - 1] = (int16_t)k;
            continue;
        }
        r->na[r->nn] = (int16_t)k;
        r->nb[r->nn] = (int16_t)k;
        r->nn++;
    }
}

static int ends_with(const char *w, int n, const char *e) {
    int l = (int)strlen(e);
    return l <= n && memcmp(w + n - l, e, (size_t)l) == 0;
}

static int in_endings(const char *w, int a, int b) { /* w[a:b] in STRESSED_ENDINGS */
    char t[16];
    if (b - a >= (int)sizeof t) return 0;
    memcpy(t, w + a, (size_t)(b - a));
    t[b - a] = 0;
    return in_sorted(VTTS_DA_STRESSED_ENDINGS, VTTS_DA_N_STRESSED_ENDINGS, t);
}

/* stressed_syllable: index of the stressed nucleus, *foreign */
static int stressed_syllable(const rs_t *r, int *foreign) {
    const char *w = r->w;
    int n = r->nw;
    *foreign = 0;
    for (int k = 0; k < r->nn; k++)
        if (r->u[r->na[k]] == '}') { *foreign = 1; return k; }
    if (r->nn >= 2) {
        for (int e = 0; e < VTTS_DA_N_PRE_STRESSED_ENDINGS; e++)
            if (ends_with(w, n, VTTS_DA_PRE_STRESSED_ENDINGS[e]) && r->nn >= 3) return r->nn - 2;
        for (int L = (n - 1 < 9 ? n - 1 : 9); L > 1; L--) {
            if (!in_endings(w, n - L, n)) continue;
            int start = n - L, k = r->nn;
            for (int q = 0; q < r->nn; q++) if (r->pos[r->na[q]] >= start) { k = q; break; }
            if (k > 0 && k < r->nn) { *foreign = 1; return k; }
            break;
        }
        for (int q = 0; q < VTTS_DA_N_UNSTRESSED_PREFIXES; q++) {
            const char *p = VTTS_DA_UNSTRESSED_PREFIXES[q];
            int lp = (int)strlen(p);
            if (starts(w, n, 0, p) && n > lp + 2 && !vowel_b(w[lp]) && r->pos[r->na[1]] >= lp &&
                (r->nn >= 3 || r->u[r->na[1]] != 'e'))
                return 1;
        }
    }
    return 0;
}

static int is_onset(const char *seq) { return in_sorted(VTTS_DA_ONSETS, VTTS_DA_N_ONSETS, seq); }

/* _split: role of each unit */
static void split_roles(rs_t *r) {
    for (int i = 0; i < r->nu; i++) { r->rkind[i] = 'o'; r->rk[i] = 0; }
    for (int k = 0; k < r->nn; k++) {
        int a = r->na[k], b = r->nb[k];
        for (int i = a; i <= b; i++) { r->rkind[i] = 'v'; r->rk[i] = (int16_t)k; }
        int end = k + 1 < r->nn ? r->na[k + 1] : r->nu, c0 = b + 1, nc = end - c0;
        if (k + 1 == r->nn) {
            for (int i = c0; i < end; i++) { r->rkind[i] = 'c'; r->rk[i] = (int16_t)k; }
            continue;
        }
        int first = nc >= 1 && (r->u[c0] == 'j' || r->u[c0] == 'g');
        int rs = c0 + first, nr = end - rs, take = 0;
        for (int L = nr < 3 ? nr : 3; L > 0; L--) {
            if (L == 1 && r->u[end - 1] != NG) { take = 1; break; }
            char seq[4];
            int dbl = 0;
            for (int q = 0; q < L; q++) { seq[q] = base(r->u[end - L + q]); dbl |= doubled(r->u[end - L + q]); }
            seq[L] = 0;
            if (L > 1 && is_onset(seq) && !dbl) { take = L; break; }
        }
        for (int i = c0; i < end - take; i++) { r->rkind[i] = 'c'; r->rk[i] = (int16_t)k; }
        for (int i = end - take; i < end; i++) { r->rkind[i] = 'o'; r->rk[i] = (int16_t)(k + 1); }
    }
}

static int role_is(const rs_t *r, int i, char kind, int k) { return r->rkind[i] == kind && r->rk[i] == k; }

static void set_out(rs_t *r, int i, int t) { r->out[i][0] = (uint8_t)t; r->nout[i] = 1; }

/* _onset_sound */
static int onset_sound(char u0, int strong) {
    char u = base(u0);
    if (u == SJ) return VTTS_DA_T_sj;
    if (!strong && (u == 'p' || u == 't' || u == 'k')) return u == 'p' ? VTTS_DA_T_b : u == 't' ? VTTS_DA_T_d : VTTS_DA_T_g;
    switch (u) {
    case 'r': return VTTS_DA_T_R;
    case 'c': return VTTS_DA_T_k;
    case NG: return VTTS_DA_T_N;
    case 'p': return VTTS_DA_T_p;
    case 't': return VTTS_DA_T_t;
    case 'k': return VTTS_DA_T_k;
    case 'b': return VTTS_DA_T_b;
    case 'd': return VTTS_DA_T_d;
    case 'g': return VTTS_DA_T_g;
    case 'f': return VTTS_DA_T_f;
    case 'v': return VTTS_DA_T_v;
    case 's': return VTTS_DA_T_s;
    case 'h': return VTTS_DA_T_h;
    case 'm': return VTTS_DA_T_m;
    case 'n': return VTTS_DA_T_n;
    case 'l': return VTTS_DA_T_l;
    case 'j': return VTTS_DA_T_j;
    default: return -1;
    }
}

/* _consonant: sounds of the consonant unit i (0..1 tokens) */
static int consonant(const rs_t *r, int i, int s) {
    char u = r->u[i], c = base(u), kind = r->rkind[i];
    int k = r->rk[i], dbl = doubled(u);
    char prev = i > 0 ? r->u[i - 1] : 0, nxt = i + 1 < r->nu ? r->u[i + 1] : 0;
    if (c == SJ) return VTTS_DA_T_sj;
    if (c == NG) return VTTS_DA_T_N;
    if (kind == 'o') {
        if (c == 'p' || c == 't' || c == 'k') {
            int strong = ((i == 0 || (k == s && !dbl)) && base(prev) != 's') || i == 0;
            if (prev == 's' && r->rkind[i - 1] == 'o') strong = 0;
            return onset_sound(u, strong);
        }
        if (c == 'd') {
            if (dbl || (i > 0 && vowel_b(prev) && k != s)) return VTTS_DA_T_D;
            if ((base(prev) == 'n' || base(prev) == 'l' || base(prev) == 'r') && r->rkind[i - 1] == 'c' && k != s) return -1;
            return VTTS_DA_T_d;
        }
        if (c == 'g' && i > 0 && vowel_b(prev) && !dbl) return -1;
        if (c == 'h' || strchr("bfvslmnj", c)) return onset_sound(c, 1);
        if (c == 'r') return VTTS_DA_T_R;
        return onset_sound(u, 0);
    }
    if (c == 'p' || c == 't' || c == 'k') {
        if (c == 't' && prev == 'e' && i == r->nu - 1 && k != s) return VTTS_DA_T_D;
        if (c == 't' && prev == 'd' && role_is(r, i - 1, 'c', k)) return VTTS_DA_T_d;
        return c == 'p' ? VTTS_DA_T_b : c == 't' ? VTTS_DA_T_d : VTTS_DA_T_g;
    }
    if (c == 'd') {
        char bp = base(prev);
        if (bp == 'n' || bp == 'l' || bp == 'r' || nxt == 't' || nxt == 's' || nxt == 'T' || nxt == 'S') return -1;
        return vowel_b(prev) || dbl ? VTTS_DA_T_D : VTTS_DA_T_d;
    }
    if (c == 'g') {
        if (vowel_b(prev)) {
            if (prev == 'o' || prev == '{') return VTTS_DA_T_w;
            if (prev == 'e' || prev == '|' || prev == '~' || prev == '}') return VTTS_DA_T_jG;
            return -1;
        }
        if (base(prev) == 'r') return VTTS_DA_T_w;
        return VTTS_DA_T_g;
    }
    if (c == 'v') {
        if (vowel_b(prev)) return VTTS_DA_T_w;
        if (base(prev) == 'l') return -1;
        if (base(prev) == 'r') return VTTS_DA_T_w;
        return VTTS_DA_T_v;
    }
    if (c == 'j') return vowel_b(prev) ? VTTS_DA_T_jG : VTTS_DA_T_j;
    if (c == 'r') return vowel_b(prev) ? VTTS_DA_T_6G : VTTS_DA_T_R;
    if (c == 'h') return -1;
    if (strchr("bfslmn", c)) return onset_sound(c, 1);
    return -1;
}

static int is_long_tok(int t) { return t >= VTTS_DA_T_iL && t <= VTTS_DA_T_QL; }

static int stod_ending(const char *w, int a, int n) {
    char t[16];
    if (n - a >= (int)sizeof t) return 0;
    memcpy(t, w + a, (size_t)(n - a));
    t[n - a] = 0;
    return in_list(VTTS_DA_STOD_ENDINGS, VTTS_DA_N_STOD_ENDINGS, t);
}

/* rules(): tokens of the folded word r->w (token indices) */
static void rules(rs_t *r, tk_t *o) {
    units(r);
    nuclei(r);
    int n = r->nu;
    if (!r->nn) {
        for (int i = 0; i < n; i++) { int t = onset_sound(r->u[i], 1); if (t >= 0) tk(o, t); }
        return;
    }
    int foreign, s = stressed_syllable(r, &foreign);
    split_roles(r);
    for (int i = 0; i < n; i++) { r->nout[i] = 0; r->skip[i] = 0; }
    for (int k = 0; k < r->nn; k++) {
        int a = r->na[k], b = r->nb[k];
        int coda0 = -1, ncoda = 0, on0 = -1, non = 0;
        for (int i = b + 1; i < n; i++) {
            if (role_is(r, i, 'c', k)) { if (coda0 < 0) coda0 = i; ncoda++; }
            if (role_is(r, i, 'o', k + 1)) { if (on0 < 0) on0 = i; non++; }
        }
        int nxt = coda0 >= 0 ? coda0 : on0;
        char c1 = nxt >= 0 ? r->u[nxt] : 0;
        char prev = a > 0 && role_is(r, a - 1, 'o', k) ? r->u[a - 1] : 0;
        int last = k + 1 == r->nn, stressed = k == s;
        r->long_syl[k] = 0;
        if (a != b) {
            int q = 0;
            pair_nucleus(r->u[a], r->u[b], &q);
            r->out[a][0] = VTTS_DA_PAIRS[q].t0;
            r->nout[a] = 1;
            if (VTTS_DA_PAIRS[q].t1 != 255) r->out[a][r->nout[a]++] = VTTS_DA_PAIRS[q].t1;
            r->long_syl[k] = (uint8_t)is_long_tok(r->out[a][0]);
            continue;
        }
        char v = r->u[a];
        int vi = vow_index(v);
        if (!stressed) {
            int coda_r = coda0 >= 0 && r->u[coda0] == 'r';
            if (v == 'e' && ((prev == 'r' && a > 0) || coda_r)) {
                set_out(r, a, VTTS_DA_T_6);
                if (coda_r) r->skip[coda0] = 1;
                if (prev == 'r' && a >= 2 && vowel_b(r->u[a - 2])) r->skip[a - 1] = 1;
            } else if (v == 'e' && r->pos[a] == 0) {
                set_out(r, a, VTTS_DA_T_E);
            } else if (k == 0 && s == 1 && (starts(r->w, r->nw, 0, "be") || starts(r->w, r->nw, 0, "ge")) && v == 'e') {
                set_out(r, a, VTTS_DA_T_e);
            } else if (k == 0 && s == 1 && starts(r->w, r->nw, 0, "for") && v == 'o') {
                set_out(r, a, VTTS_DA_T_Q);
                if (a + 1 < n) r->skip[a + 1] = 1;
            } else {
                set_out(r, a, VTTS_DA_UNSTRESSED_OF[vi]);
            }
            if (v == 'i' && coda0 >= 0 && r->u[coda0] == 'g') r->skip[coda0] = 1;
            continue;
        }
        int lng;
        if (last) lng = ncoda == 0 || (ncoda == 1 && strchr(VTTS_DA_LONG_FINAL, r->u[coda0]) && r->u[coda0]);
        else lng = ncoda == 0 && non <= 1 && !(non && doubled(r->u[on0]));
        if (foreign && last && ncoda == 1 && r->u[coda0] != 'k' && r->u[coda0] != 'K' && r->u[coda0] != NG) lng = 1;
        if (foreign && v == 'o' && prev == SJ) lng = 1;
        int q = lng ? VTTS_DA_LONG_OF[vi] : VTTS_DA_SHORT_OF[vi];
        int coda_first = coda0 >= 0 && coda0 == nxt;
        if (c1 == 'r' && coda_first) {
            char after_r = nxt + 1 < n ? r->u[nxt + 1] : 0;
            if (v == 'a' || v == '{' || (v == 'o' && after_r && after_r != 'd' && after_r != 'D')) {
                q = v == 'a' ? VTTS_DA_T_AL : VTTS_DA_T_QL;
                r->skip[nxt] = 1;
            } else {
                q = v == 'e' || v == '|' ? VTTS_DA_T_E : v == '~' ? VTTS_DA_T_9 : v == 'o' ? VTTS_DA_T_o
                                                                                     : VTTS_DA_SHORT_OF[vi];
            }
        } else if (c1 == NG) {
            q = v == 'a' ? VTTS_DA_T_A : v == 'i' ? VTTS_DA_T_e : v == 'y' ? VTTS_DA_T_2 : v == 'u' ? VTTS_DA_T_O
                : v == 'o' ? VTTS_DA_T_O : v == 'e' ? VTTS_DA_T_E : VTTS_DA_SHORT_OF[vi];
        } else if (c1 == 'j' && coda0 >= 0) {
            q = v == 'e' || v == '|' || v == 'a' ? VTTS_DA_T_A : v == '~' ? VTTS_DA_T_O : VTTS_DA_SHORT_OF[vi];
        } else if (c1 == 'g' && coda_first) {
            if (v == 'a' || v == 'i' || v == 'u' || v == 'y') { q = VTTS_DA_LONG_OF[vi]; r->skip[nxt] = 1; }
            else q = v == 'o' || v == '{' || v == '~' ? VTTS_DA_T_O : VTTS_DA_T_A; /* o å ø: O; e æ é: A */
        } else if (c1 == 'v' && coda_first) {
            q = v == 'a' ? VTTS_DA_T_A : v == 'o' || v == '{' ? VTTS_DA_T_O : v == 'e' ? VTTS_DA_T_E
                : v == '~' ? VTTS_DA_T_2 : VTTS_DA_SHORT_OF[vi];
        } else if (!lng) {
            char nxt2 = nxt >= 0 && nxt < n - 1 ? r->u[nxt + 1] : 0;
            if (v == 'i' && (c1 == 'k' || c1 == 'K' || c1 == 'N' || c1 == 'M' || (c1 == 'n' && nxt2 == 'd'))) q = VTTS_DA_T_e;
            else if (v == 'u' && (c1 == 'm' || c1 == 'M' || c1 == 'N' || c1 == 'n')) q = VTTS_DA_T_O;
            else if (v == 'y' && (c1 == 'N' || (c1 == 'n' && nxt2 == 'd'))) q = VTTS_DA_T_2;
            else if (v == 'a' && (c1 == 'm' || c1 == 'M')) q = VTTS_DA_T_A;
        }
        if (v == 'a' && (prev == 'r' || prev == 'R') && (q == VTTS_DA_T_a || q == VTTS_DA_T_aL))
            q = q == VTTS_DA_T_a ? VTTS_DA_T_A : VTTS_DA_T_AL;
        set_out(r, a, q);
        r->long_syl[k] = (uint8_t)is_long_tok(q);
    }
    for (int i = 0; i < n; i++) {
        if (r->skip[i] || r->rkind[i] == 'v') continue;
        int t = consonant(r, i, s);
        if (t >= 0) set_out(r, i, t);
    }
    /* stress and stød */
    int a = r->na[s], b = r->nb[s];
    uint8_t *oa = r->out[a];
    for (int q = r->nout[a]; q > 1; q--) oa[q] = oa[q - 1];
    oa[1] = VTTS_DA_T_PRI;
    r->nout[a]++;
    int has_tail = s + 1 < r->nn, tail = has_tail ? r->pos[r->na[s + 1]] : r->nw;
    if (!has_tail || foreign || stod_ending(r->w, tail, r->nw)) {
        if (r->long_syl[s]) { /* after the vowel and the stress mark */
            for (int q = r->nout[a]; q > 2; q--) oa[q] = oa[q - 1];
            oa[2] = VTTS_DA_T_STOD;
            r->nout[a]++;
        } else if (r->nout[a] > 2 && ((VTTS_DA_VOICED_CODA >> oa[2]) & 1)) {
            oa[r->nout[a]++] = VTTS_DA_T_STOD;
        } else {
            for (int i = b + 1; i < n; i++) {
                if (!role_is(r, i, 'c', s)) break;
                if (!r->nout[i]) continue;
                if ((VTTS_DA_VOICED_CODA >> r->out[i][0]) & 1) r->out[i][r->nout[i]++] = VTTS_DA_T_STOD;
                break;
            }
        }
    }
    for (int i = 0; i < n; i++) for (int q = 0; q < r->nout[i]; q++) tk(o, r->out[i][q]);
}

/* ---- words ---- */

static void put_rules(rs_t *r, const char *w, int n, tk_t *o) {
    memcpy(r->w, w, (size_t)n);
    r->w[n] = 0;
    r->nw = n;
    rules(r, o);
}

/* simple_word: the lexicon reading, else the rules */
static void simple_word(rs_t *r, const char *w, int n, tk_t *o) {
    int t;
    if (find_word(w, n, &t) && t >= 0) {
        for (int q = t; VTTS_DA_WORDS[q] < 0x40; q++) tk(o, VTTS_DA_WORDS[q] - 1);
        return;
    }
    put_rules(r, w, n, o);
}

typedef struct { int start[5], end[5], link[5], np; } split_t;

typedef struct {
    const char *w;
    int n, have, key[3];
    split_t cur, best;
} search_t;

/* split_compound's search(i, parts) */
static void search(search_t *x, int i) {
    if (x->cur.np > 3) return;
    for (int j = x->n; j >= i + 3; j--) {
        if (!find_word(x->w + i, j - i, NULL)) continue;
        int np = x->cur.np;
        x->cur.start[np] = i; x->cur.end[np] = j; x->cur.link[np] = 0;
        if (j == x->n) {
            if (np) {
                int links = 0;
                for (int q = 0; q <= np; q++) links += x->cur.link[q] != 0;
                int key[3] = {np + 1, links, -(x->cur.end[0] - x->cur.start[0])};
                if (!x->have || key[0] < x->key[0] || (key[0] == x->key[0] && (key[1] < x->key[1] ||
                    (key[1] == x->key[1] && key[2] < x->key[2])))) {
                    x->have = 1;
                    memcpy(x->key, key, sizeof key);
                    x->best = x->cur;
                    x->best.np = np + 1;
                }
            }
            continue;
        }
        if (x->n - j >= 3) { x->cur.np = np + 1; search(x, j); x->cur.np = np; }
        if (j < x->n && (x->w[j] == 's' || x->w[j] == 'e') && x->n - j - 1 >= 3) {
            x->cur.start[np] = i; x->cur.end[np] = j; x->cur.link[np] = x->w[j];
            x->cur.np = np + 1;
            search(x, j + 1);
            x->cur.np = np;
        }
    }
}

static int split_compound(const char *w, int n, split_t *out) {
    search_t x;
    memset(&x, 0, sizeof x);
    x.w = w;
    x.n = n;
    search(&x, 0);
    if (x.have) *out = x.best;
    return x.have;
}

static int unstressed_word(const char *w, int n) {
    char t[16];
    if (n >= (int)sizeof t) return 0;
    memcpy(t, w, (size_t)n);
    t[n] = 0;
    return in_sorted(VTTS_DA_UNSTRESSED, VTTS_DA_N_UNSTRESSED, t);
}

/* word_tokens_names of the folded word w */
static void word_tokens(rs_t *r, const char *w, int n, tk_t *o) {
    int t, any_vowel = 0, known, start = o->n;
    if (n <= 0) return;
    for (int i = 0; i < n; i++) any_vowel |= vowel_b(w[i]);
    known = find_word(w, n, &t);
    if (!any_vowel && !(known && t >= 0)) {
        if (n <= 6) {
            for (int i = 0; i < n; i++) {
                const char *name = VTTS_DA_LETTER_NAMES[w[i] - 'a'];
                word_tokens(r, name, (int)strlen(name), o);
            }
        } else put_rules(r, w, n, o);
        return;
    }
    if (known && t >= 0) {
        for (int q = t; VTTS_DA_WORDS[q] < 0x40; q++) tk(o, VTTS_DA_WORDS[q] - 1);
    } else {
        split_t sp;
        if (!known && split_compound(w, n, &sp)) {
            for (int k = 0; k < sp.np; k++) {
                int s0 = o->n;
                simple_word(r, w + sp.start[k], sp.end[k] - sp.start[k], o);
                int m = s0;
                for (int q = s0; q < o->n; q++) {
                    int tok = o->p[q];
                    if (k > 0 && tok == VTTS_DA_T_PRI) tok = VTTS_DA_T_SEC;
                    if (k + 1 < sp.np && tok == VTTS_DA_T_STOD) continue;
                    o->p[m++] = (uint8_t)tok;
                }
                o->n = m;
                if (sp.link[k]) tk(o, sp.link[k] == 's' ? VTTS_DA_T_s : VTTS_DA_T_AT);
            }
        } else put_rules(r, w, n, o);
    }
    if (unstressed_word(w, n)) {
        int m = start;
        for (int q = start; q < o->n; q++)
            if (o->p[q] != VTTS_DA_T_PRI && o->p[q] != VTTS_DA_T_SEC) o->p[m++] = o->p[q];
        o->n = m;
    }
}

/* fold(): lower case; a-z å æ é ø kept, FOLD letters folded, everything else dropped */
static int fold(const uint32_t *w, int n, char *out, int cap) {
    int m = 0;
    for (int i = 0; i < n && m < cap; i++) {
        uint32_t c = w[i] == 0x130 ? 'i' : vtts_u_lower(w[i]);
        char b = 0;
        if (c >= 'a' && c <= 'z') b = (char)c;
        else if (c == 0xE5) b = '{';
        else if (c == 0xE6) b = '|';
        else if (c == 0xE9) b = '}';
        else if (c == 0xF8) b = '~';
        else
            for (int k = 0; k < VTTS_DA_N_FOLD; k++) if (VTTS_DA_FOLD[k].cp == c) { b = VTTS_DA_FOLD[k].to; break; }
        if (b) out[m++] = b;
    }
    return m;
}

int vtts_da_word_ids(const uint32_t *w, int n, void *scratch, size_t ns, uint8_t *out, int cap) {
    if (!scratch || ns < sizeof(rs_t) + 2 * (VTTS_DA_MAXW + 1) || ns > (size_t)1 << 30) return 0;
    rs_t *r = scratch;
    char *word = (char *)(r + 1);
    int m = fold(w, n, word, VTTS_DA_MAXW);
    uint8_t toks[2048];
    tk_t o = {toks, 0, (int)sizeof toks};
    word_tokens(r, word, m, &o);
    int k = 0;
    for (int i = 0; i < o.n && k < cap; i++) out[k++] = (uint8_t)(VTTS_DAEN_T0 + toks[i]);
    return k;
}

/* ======================= tagging (latin.latin_word_lang, mode da) ======================= */

static int camel(const uint32_t *w, int n) {
    for (int i = 0; i + 1 < n; i++)
        if (w[i] >= 'a' && w[i] <= 'z' && upper_az(w[i + 1])) return 1;
    return 0;
}

static int has_sub(const char *w, int n, const char *f) {
    int fl = (int)strlen(f);
    for (int i = 0; i + fl <= n; i++) if (memcmp(w + i, f, (size_t)fl) == 0) return 1;
    return 0;
}

/* valid_spelling of a lower-case ASCII word */
static int valid_spelling(const char *w, int n) {
    static const char *const FOREIGN[] = {"th", "ph", "sh", "ea", "oa", "ee", "oo", "ou", "ay", "ey", "oy", "aw",
                                          "ow", "gh", "wh", "tch", "dge"};
    split_t sp;
    if (n <= 0) return 0;
    if (find_word(w, n, NULL) || split_compound(w, n, &sp)) return 1;
    for (int i = 0; i < n; i++) if (strchr("wqxz", w[i])) return 0;
    char t[VTTS_DA_MAXW + 1], t2[VTTS_DA_MAXW + 1]; /* "c" in w.replace("ck", "").replace("ch", "") */
    int m = 0, m2 = 0;
    for (int i = 0; i < n;) { if (i + 1 < n && w[i] == 'c' && w[i + 1] == 'k') i += 2; else t[m++] = w[i++]; }
    for (int i = 0; i < m;) { if (i + 1 < m && t[i] == 'c' && t[i + 1] == 'h') i += 2; else t2[m2++] = t[i++]; }
    for (int i = 0; i < m2; i++) if (t2[i] == 'c') return 0;
    for (int k = 0; k < (int)(sizeof FOREIGN / sizeof *FOREIGN); k++) if (has_sub(w, n, FOREIGN[k])) return 0;
    return !strchr("aiouy", w[n - 1]) || n <= 3;
}

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

int vtts_da_word_lang(const uint32_t *w, int n) {
    char low[128];
    if (n <= 0) return -1;
    for (int i = 0; i < n; i++) if (in_u8(w[i], VTTS_DA_OWN)) return 1;
    if (!plain_latin(w, n)) return -1;
    if (n < (int)sizeof low) {
        for (int i = 0; i < n; i++) low[i] = (char)(w[i] >= 'A' && w[i] <= 'Z' ? w[i] + 32 : w[i]);
        low[n] = 0;
        if (in_sorted(VTTS_DA_NATIVE, VTTS_DA_N_NATIVE, low) || in_sorted(VTTS_DA_TABLE_KEYS, VTTS_DA_N_TABLE_KEYS, low))
            return 1;
        if (vtts_lt_english_word(low)) return 0;
    }
    int all_caps = 1, all_valid = 1;
    for (int a = 0; a < n;) {
        int b = a;
        while (b < n && w[b] != '-' && w[b] != '\'') b++;
        if (b > a) {
            int len = b - a, caps = len >= 2 && len <= 5;
            if (camel(w + a, len)) return 0;
            for (int k = a; k < b; k++) caps &= upper_az(w[k]);
            all_caps &= caps;
            if (all_valid) {
                char part[VTTS_DA_MAXW + 1];
                if (len > VTTS_DA_MAXW) all_valid = 0;
                else {
                    for (int k = 0; k < len; k++) part[k] = (char)(w[a + k] | 32);
                    part[len] = 0;
                    all_valid = valid_spelling(part, len);
                }
            }
        }
        a = b + 1;
    }
    if (n == 1 || all_caps) return 1;
    return all_valid ? 1 : 0;
}

#endif /* VTTS_ENABLE_DA */
