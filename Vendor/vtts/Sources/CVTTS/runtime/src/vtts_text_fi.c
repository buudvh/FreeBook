/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_fi.c -- Finnish front-end of the device (token set fi-en). Mirrors
 * src/vtts/frontend/fi/normalize_fi.py (normalization, pass by pass, with the helpers of
 * latin_norm.py), fi/g2p_fi.py (spelling, length, stress) and the fi rules of latin.py. All tables
 * are in the generated vtts_text_fi_tables.h. */
#include "vtts_langs.h"
#if VTTS_ENABLE_FI /* else an empty unit (vtts_langs.h) */

#include "vtts_text_fi.h"

#include <string.h>

#include "vtts_text_fi_tables.h"
#include "vtts_text_lt.h" /* vtts_u_word, vtts_u_digit, vtts_u_space, vtts_u_lower */

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

static int u8_decode(const char *k, uint32_t *o, int cap) {
    uint32_t x;
    int l, n = 0;
    while ((l = dec1(k, &x)) > 0 && n < cap) { o[n++] = x; k += l; }
    return n;
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

/* significant digits of s[0..n): count, *st the first */
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

/* digits(): the name of every digit of s[from..n), joined by spaces */
static void digit_words(lb_t *d, const uint32_t *s, int n, int from) {
    int first = 1;
    for (int i = from; i < n; i++) {
        int v = vtts_u_digit(s[i]);
        if (v < 0) continue;
        if (!first) put(d, ' ');
        puts8(d, VTTS_FI_ONES[v]);
        first = 0;
    }
}

/* ======================= numbers ======================= */

enum { NOM = 0, ELA = 1, ILL = 2 };

static void part(lb_t *d, const char *p, int mode) {
    if (mode)
        for (int k = 0; k < VTTS_FI_N_CASES; k++)
            if (strcmp(VTTS_FI_CASES[k][0], p) == 0) { puts8(d, VTTS_FI_CASES[k][mode]); return; }
    puts8(d, p);
}

static void below_100(lb_t *d, int v, int mode) {
    if (v < 10) { part(d, VTTS_FI_ONES[v], mode); return; }
    if (v == 10) { part(d, "kymmenen", mode); return; }
    int t = v / 10, u = v % 10;
    if (t == 1) { part(d, VTTS_FI_ONES[u], mode); part(d, "toista", mode); return; }
    part(d, VTTS_FI_ONES[t], mode);
    part(d, "kymmentä", mode);
    if (u) part(d, VTTS_FI_ONES[u], mode);
}

static void below_1000(lb_t *d, int v, int mode) {
    int h = v / 100, r = v % 100;
    if (h == 1) part(d, "sata", mode);
    else if (h) { part(d, VTTS_FI_ONES[h], mode); part(d, "sataa", mode); }
    if (r || !h) below_100(d, r, mode);
}

static void below_million(lb_t *d, int v, int mode) {
    int th = v / 1000, r = v % 1000;
    if (th == 1) part(d, "tuhat", mode);
    else if (th) { below_1000(d, th, mode); part(d, "tuhatta", mode); }
    if (r || !th) below_1000(d, r, mode);
}

/* cardinal_groups(v) (v < 10^15), groups separated by spaces; mode: case of every part */
static void card_u64(lb_t *d, uint64_t v, int mode) {
    static const uint64_t SC[2] = {1000000000ull, 1000000ull};
    int first = 1;
    if (!v) { part(d, "nolla", mode); return; }
    for (int k = 0; k < 2; k++) {
        uint64_t q = v / SC[k];
        v %= SC[k];
        if (!q) continue;
        if (!first) put(d, ' ');
        first = 0;
        if (q == 1) { part(d, VTTS_FI_SCALES[k][0], mode); continue; }
        below_million(d, (int)q, mode);
        put(d, ' ');
        part(d, VTTS_FI_SCALES[k][1], mode);
    }
    if (v) {
        if (!first) put(d, ' ');
        below_million(d, (int)v, mode);
    }
}

/* cardinal(int(s)) / inflect(int(s), table) of the digits s[0..n) (16+ significant digits: digit by digit) */
static void card(lb_t *d, const uint32_t *s, int n, int mode) {
    int st, nd = sig(s, n, &st);
    if (nd > 15) { digit_words(d, s, n, st); return; }
    card_u64(d, nd ? value(s, n, st) : 0, mode);
}

static void card_i(lb_t *d, int v) { card_u64(d, (uint64_t)v, NOM); }

static void ordinal_below_1000(lb_t *d, int v, int final) {
    int h = v / 100, r = v % 100, t = r / 10, u = r % 10;
    if (h == 1) puts8(d, "sadas");
    else if (h) { puts8(d, VTTS_FI_ORD_PARTS[h]); puts8(d, "sadas"); }
    if (r == 10) { puts8(d, "kymmenes"); return; }
    if (t == 1) { puts8(d, VTTS_FI_ORD_PARTS[u]); puts8(d, "toista"); return; }
    if (t) { puts8(d, VTTS_FI_ORD_PARTS[t]); puts8(d, "kymmenes"); }
    if (u) puts8(d, final ? VTTS_FI_ORD_ONES[u] : VTTS_FI_ORD_PARTS[u]);
}

/* ordinal(int(s)): 1..9999 by parts, else the cardinal */
static void ordinal(lb_t *d, const uint32_t *s, int n) {
    int st, nd = sig(s, n, &st);
    if (nd < 1 || nd > 4) { card(d, s, n, NOM); return; }
    int v = (int)value(s, n, st), th = v / 1000, r = v % 1000;
    if (th == 1) puts8(d, "tuhannes");
    else if (th) { puts8(d, VTTS_FI_ORD_PARTS[th]); puts8(d, "tuhannes"); }
    if (r) ordinal_below_1000(d, r, 1);
}

/* latin_norm.parse_number of a written number s[0..n) (no sign): integer part [0, *ie) (separators
 * skipped), decimal part [*f0, n) or *f0 = -1, decimal mark *mark */
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
    if (AT(0, '+')) { s++; n--; } /* s.lstrip("+") (never reached: NUM has no sign) */
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

/* _is_one(s): the integer part is 1 and there is no decimal part */
static int is_one(const uint32_t *s, int n) {
    int ie, f0, st;
    uint32_t mark;
    parse_number(s, n, &ie, &f0, &mark);
    return f0 < 0 && sig(s, ie, &st) == 1 && vtts_u_digit(s[st]) == 1;
}

/* number(sign + s) */
static void number(lb_t *d, const uint32_t *s, int n, int neg) {
    int ie, f0;
    uint32_t mark;
    if (neg) puts8(d, "miinus ");
    parse_number(s, n, &ie, &f0, &mark);
    card(d, s, ie, NOM);
    if (f0 < 0) return;
    put(d, ' ');
    puts8(d, mark == ',' ? VTTS_FI_COMMA : VTTS_FI_PERIOD);
    put(d, ' ');
    if (f0 < n && n - f0 <= 2 && s[f0] != '0') card(d, s + f0, n - f0, NOM);
    else digit_words(d, s, n, f0);
}

/* ======================= normalization passes =======================
 * Each regex pass of normalize_fi is one function from s (n code points) to d; matches are found
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

typedef struct { const vtts_fi_reading *keys; int nk, word_end, key, end; } keys_m;

static int ok_keys(const uint32_t *s, int n, int e, void *u) { /* \s?(k1|k2|...)[(?![\w])] */
    keys_m *m = u;
    for (int sp = SP(e); sp >= 0; sp--)
        for (int k = 0; k < m->nk; k++) {
            int l = key_at(s, n, e + sp, m->keys[k].key);
            if (l && !(m->word_end && W(e + sp + l))) { m->key = k; m->end = e + sp + l; return 1; }
        }
    return 0;
}

/* apply_abbreviations, one key: (?<![\w])KEY[(?![\w])] -> " reading " (+ "." at the end of the text) */
static void p_abbrev(int k, const uint32_t *s, int n, lb_t *d) {
    const char *key = VTTS_FI_ABBREV[k][0];
    int dot = key[strlen(key) - 1] == '.';
    for (int i = 0; i < n;) {
        int m;
        if (!W(i - 1) && (m = key_at(s, n, i, key)) && (dot || !W(i + m))) {
            int end = dot;
            for (int q = i + m; q < n && end; q++) end = vtts_u_space(s[q]);
            put(d, ' ');
            puts8(d, VTTS_FI_ABBREV[k][1]);
            put(d, ' ');
            if (end) put(d, '.');
            i += m;
            continue;
        }
        put(d, s[i++]);
    }
}

static void p_drop(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n; i++) put(d, in_u8(s[i], VTTS_FI_DROP) ? ' ' : s[i]);
}

/* phone_digits(text, DIGITS, "plus"): fewer than 7 digits (not starting with 0) stay as written */
static void phone_out(const uint32_t *s, int i, int e, lb_t *d) {
    int cnt = 0;
    for (int q = i; q < e; q++) cnt += vtts_u_digit(s[q]) >= 0;
    if (cnt < 7 && s[i] != '0') { putn(d, s + i, e - i); return; }
    put(d, ' ');
    if (s[i] == '+') puts8(d, "plus ");
    digit_words(d, s, e, i);
    put(d, ' ');
}

/* (?:[\s-]\d{lo,hi}){gmin,4}(?![\d]) at p: the end or -1 */
static int phone_groups(const uint32_t *s, int n, int p, int lo, int hi, int gmin) {
    int e = p, cnt = 0;
    while (cnt < 4 && SPD(e)) {
        int r = drun(s, n, e + 1);
        if (r < lo || r > hi) break;
        e += 1 + r;
        cnt++;
    }
    return cnt >= gmin ? e : -1;
}

/* PHONE_FIRST (?<![\d])(?<!\d\s)(?:\+\d{1,3}|0\d{1,3})(?:[\s-]\d{2,7}){1,4}(?![\d]) */
static void p_phone_first(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        int e = -1;
        if (!DG(i - 1) && !(SP(i - 1) && DG(i - 2)) && (AT(i, '+') || AT(i, '0'))) {
            int r = drun(s, n, i + 1);
            if (r >= 1 && r <= 3) e = phone_groups(s, n, i + 1 + r, 2, 7, 1);
        }
        if (e >= 0) { phone_out(s, i, e, d); i = e; continue; }
        put(d, s[i++]);
    }
}

static int thousands_sep(uint32_t c) { return c == ' ' || c == 0xA0 || c == 0x202F; }

/* SPACE_THOUSANDS (?<![\d,.])[1-9]\d{0,2}(?:[   ]\d{3})+(?![\d]) -> the digits */
static void p_space_thousands(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (IN(i) && s[i] >= '1' && s[i] <= '9' && !DG(i - 1) && !AT(i - 1, ',') && !AT(i - 1, '.')) {
            int r = drun(s, n, i), e = i + r, g = 0;
            if (r <= 3)
                while (IN(e) && thousands_sep(s[e]) && drun(s, n, e + 1) == 3) { e += 4; g++; }
            if (r <= 3 && g) {
                for (int q = i; q < e; q++) if (!thousands_sep(s[q])) put(d, s[q]);
                i = e;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* _date(d, m, y): " ordinal(d) month [cardinal(y)] " or the original text when out of range */
static void date_out(lb_t *d, int dd, int mm, const uint32_t *y, int yl, const uint32_t *orig, int on) {
    if (!(dd >= 1 && dd <= 31 && mm >= 1 && mm <= 12)) { putn(d, orig, on); return; }
    uint32_t b[2];
    int k = 0;
    if (dd >= 10) b[k++] = '0' + (uint32_t)(dd / 10);
    b[k++] = '0' + (uint32_t)(dd % 10);
    put(d, ' ');
    ordinal(d, b, k);
    put(d, ' ');
    puts8(d, VTTS_FI_MONTHS[mm]);
    if (y) {
        put(d, ' ');
        card_i(d, val(y, 0, yl) + (yl == 2 ? 2000 : 0));
    }
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

/* DATE_SLASH (?<![\d/])(\d{1,2})/(\d{1,2})/(\d{4}|\d{2})(?![\d/]) */
static void p_date_slash(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !DG(i - 1) && !AT(i - 1, '/')) {
            int r1 = drun(s, n, i);
            if (r1 <= 2 && AT(i + r1, '/')) {
                int m0 = i + r1 + 1, r2 = drun(s, n, m0);
                if (r2 >= 1 && r2 <= 2 && AT(m0 + r2, '/')) {
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

/* DATE_DOT (?<![\d.])(\d{1,2})\.(\d{1,2})\.(\d{4}|\d{2})?(?![\d]) */
static void p_date_dot(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !DG(i - 1) && !AT(i - 1, '.')) {
            int r1 = drun(s, n, i);
            if (r1 <= 2 && AT(i + r1, '.')) {
                int m0 = i + r1 + 1, r2 = drun(s, n, m0);
                if (r2 >= 1 && r2 <= 2 && AT(m0 + r2, '.')) {
                    int y0 = m0 + r2 + 1, ry = drun(s, n, y0);
                    if (ry == 4 || ry == 2 || ry == 0) {
                        date_out(d, val(s, i, r1), val(s, m0, r2), ry ? s + y0 : NULL, ry, s + i, y0 + ry - i);
                        i = y0 + ry;
                        continue;
                    }
                }
            }
        }
        put(d, s[i++]);
    }
}

/* ([01]?\d|2[0-max]) at i: the hour lengths in the order the regex tries them */
static int hours(const uint32_t *s, int n, int i, char max, int hl[3]) {
    int k = 0;
    if ((AT(i, '0') || AT(i, '1')) && DG(i + 1)) hl[k++] = 2;
    if (DG(i)) hl[k++] = 1;
    if (AT(i, '2') && IN(i + 1) && s[i + 1] >= '0' && s[i + 1] <= (uint32_t)max) hl[k++] = 2;
    return k;
}

static int m05(const uint32_t *s, int n, int j) { return IN(j) && s[j] >= '0' && s[j] <= '5' && DG(j + 1); } /* [0-5]\d */
static int no_num(const uint32_t *s, int n, int e) { return !DG(e) && !((AT(e, '.') || AT(e, ',')) && DG(e + 1)); } /* (?![\d]|[.,]\d) */

/* _clock(h, mi) */
static void clock_out(lb_t *d, int h, int mi) {
    put(d, ' ');
    card_i(d, h);
    if (mi) {
        put(d, ' ');
        if (mi < 10) { puts8(d, "nolla "); puts8(d, VTTS_FI_ONES[mi]); }
        else card_i(d, mi);
    }
    put(d, ' ');
}

/* TIME_DOT (?<=kello)(\s+)([01]?\d|2[0-4])(?:[.:]([0-5]\d))?(?![\d]|[.,]\d) */
static void p_time_dot(const uint32_t *s, int n, lb_t *d) {
    static const uint32_t K[5] = {'k', 'e', 'l', 'l', 'o'};
    for (int i = 0; i < n;) {
        if (SP(i) && i >= 5 && memcmp(s + i - 5, K, sizeof K) == 0) {
            int j = i;
            while (SP(j)) j++;
            int hl[3], nh = hours(s, n, j, '4', hl), end = -1, h = 0, mi = 0;
            for (int c = 0; c < nh && end < 0; c++) {
                int e = j + hl[c];
                if ((AT(e, '.') || AT(e, ':')) && m05(s, n, e + 1) && no_num(s, n, e + 3)) {
                    end = e + 3;
                    mi = val(s, e + 1, 2);
                } else if (no_num(s, n, e)) {
                    end = e;
                    mi = 0;
                }
                if (end >= 0) h = val(s, j, hl[c]);
            }
            if (end >= 0) { clock_out(d, h, mi); i = end; continue; }
        }
        put(d, s[i++]);
    }
}

/* TIME_HM (?<![\d.,:])([01]?\d|2[0-3])\.([0-5]\d)(?![\d]|[.,]\d) */
static void p_time_hm(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !DG(i - 1) && !AT(i - 1, '.') && !AT(i - 1, ',') && !AT(i - 1, ':')) {
            int hl[3], nh = hours(s, n, i, '3', hl), end = -1;
            for (int c = 0; c < nh && end < 0; c++) {
                int e = i + hl[c];
                if (AT(e, '.') && m05(s, n, e + 1) && no_num(s, n, e + 3)) {
                    end = e + 3;
                    clock_out(d, val(s, i, hl[c]), val(s, e + 1, 2));
                }
            }
            if (end >= 0) { i = end; continue; }
        }
        put(d, s[i++]);
    }
}

/* TIME (?<![\d:.])([01]?\d|2[0-4]):([0-5]\d)(?::([0-5]\d))?(?![\d:]) */
static void p_time(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !DG(i - 1) && !AT(i - 1, ':') && !AT(i - 1, '.')) {
            int hl[3], nh = hours(s, n, i, '4', hl), end = -1, h = 0, mi = 0, sec = 0;
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
            if (end >= 0) {
                clock_out(d, h, mi);
                if (sec) { d->n--; puts8(d, " ja "); card_i(d, sec); puts8(d, " sekuntia "); }
                i = end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* PHONE (?<![\d])(?:\+\d{1,3}[\s-])?\d{2,4}(?:[\s-]\d{2,4}){2,4}(?![\d]) | (?<![\d.,])0\d{2,}(?![\d]|[.,]\d) */
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
                int r0 = drun(s, n, p);
                if (r0 >= 2 && r0 <= 4) e = phone_groups(s, n, p + r0, 2, 4, 2);
            }
        }
        if (e < 0 && AT(i, '0') && !DG(i - 1) && !AT(i - 1, '.') && !AT(i - 1, ',')) {
            int r = drun(s, n, i), q = i + r;
            if (r >= 3 && !((AT(q, '.') || AT(q, ',')) && DG(q + 1))) e = q;
        }
        if (e >= 0) { phone_out(s, i, e, d); i = e; continue; }
        put(d, s[i++]);
    }
}

/* _money(num, cur, sign) */
static void money_out(lb_t *d, const uint32_t *num, int nn, const vtts_fi_reading *cur, int neg) {
    int ie, f0;
    uint32_t mark;
    parse_number(num, nn, &ie, &f0, &mark);
    put(d, ' ');
    if (f0 >= 0 && nn - f0 == 2 && (strcmp(cur->key, "€") == 0 || strcmp(cur->key, "EUR") == 0)) {
        int st, nd = sig(num, ie, &st), cents = val(num, f0, 2);
        if (neg) puts8(d, "miinus ");
        card(d, num, ie, NOM);
        put(d, ' ');
        puts8(d, nd == 1 && vtts_u_digit(num[st]) == 1 ? cur->one : cur->many);
        if (cents) { put(d, ' '); card_i(d, cents); puts8(d, cents == 1 ? " sentti" : " senttiä"); }
        put(d, ' ');
        return;
    }
    number(d, num, nn, neg);
    put(d, ' ');
    puts8(d, is_one(num, nn) ? cur->one : cur->many);
    put(d, ' ');
}

/* MONEY_BEFORE (CUR)\s?(NUM) */
static void p_money_before(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        int e = -1, j = 0, k;
        for (k = 0; k < VTTS_FI_N_CURRENCY && e < 0; k++) {
            int l = key_at(s, n, i, VTTS_FI_CURRENCY[k].key);
            if (!l) continue;
            for (int sp = SP(i + l); sp >= 0 && e < 0; sp--) {
                j = i + l + sp;
                e = num_match(s, n, j, ok_always, NULL);
            }
        }
        if (e >= 0) { money_out(d, s + j, e - j, &VTTS_FI_CURRENCY[k - 1], 0); i = e; continue; }
        put(d, s[i++]);
    }
}

/* MONEY_AFTER (?<![\w.,])(-?)(NUM)\s?(CUR)(?![\w]) */
static void p_money_after(const uint32_t *s, int n, lb_t *d) {
    keys_m m = {VTTS_FI_CURRENCY, VTTS_FI_N_CURRENCY, 1, 0, 0};
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
                number(d, s + j, e - j, j > i);
                puts8(d, is_one(s + j, e - j) ? " prosentti " : " prosenttia ");
                i = end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* UNIT (?<![\w.,])(-?)(NUM)\s?(UNITS)(?![\w]) */
static void p_unit(const uint32_t *s, int n, lb_t *d) {
    keys_m m = {VTTS_FI_UNITS, VTTS_FI_N_UNITS, 1, 0, 0};
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int j = i + AT(i, '-'), e = num_match(s, n, j, ok_keys, &m);
            if (e >= 0) {
                put(d, ' ');
                number(d, s + j, e - j, j > i);
                put(d, ' ');
                puts8(d, is_one(s + j, e - j) ? m.keys[m.key].one : m.keys[m.key].many);
                put(d, ' ');
                i = m.end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* ORDINAL (?<![\w.,])(\d+)\.(?=\s+[a-zåäö]) */
static void p_ordinal(const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !WDC(i - 1)) {
            int r = drun(s, n, i), p = i + r + 1, q = p;
            while (SP(q)) q++;
            if (AT(i + r, '.') && q > p && IN(q) && ((s[q] >= 'a' && s[q] <= 'z') || s[q] == 0xE5 || s[q] == 0xE4 || s[q] == 0xF6)) {
                put(d, ' ');
                ordinal(d, s + i, r);
                put(d, ' ');
                i = p;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* RANGE (?<![\w.,])(\d+)\s?[-–]\s?(\d+)(?![\w]) -> " elative illative " */
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
                        card(d, s + i, r1, ELA);
                        put(d, ' ');
                        card(d, s + b0, r2, ILL);
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

static const char *letter_name(uint32_t c) {
    for (int k = 0; k < VTTS_FI_N_LETTERS; k++) if (VTTS_FI_LETTERS[k].cp == c) return VTTS_FI_LETTERS[k].name;
    return NULL;
}

static int upper_az(uint32_t c) { return c >= 'A' && c <= 'Z'; }

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
                    puts8(d, upper_az(s[k]) ? letter_name(s[k] + 32) : VTTS_FI_ONES[s[k] - '0']);
                }
                put(d, ' ');
                i = j;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* NUMBER (?<![\w.,])(-?)(NUM)(?![\d]) -> " number " */
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
        for (int k = 0; k < VTTS_FI_N_SYMBOLS && !r; k++) if (VTTS_FI_SYMBOLS[k].cp == s[i]) r = VTTS_FI_SYMBOLS[k].name;
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
                if (in_sorted(VTTS_FI_ACRONYM_WORDS, VTTS_FI_N_ACRONYM_WORDS, low)) {
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

int vtts_fi_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, const uint32_t **out) {
    lb_t p = {a, 0, cap, 0}, q = {b, 0, cap, 0};
    putn(&p, in, n);
    if (p.err) return -1;
#define SWAP() do { if (q.err) return -1; lb_t t_ = p; p = q; q = t_; } while (0)
#define PASS(fn) do { q.n = 0; fn(p.p, p.n, &q); SWAP(); } while (0)
    for (int k = 0; k < VTTS_FI_N_ABBREV; k++) { q.n = 0; p_abbrev(k, p.p, p.n, &q); SWAP(); }
    PASS(p_drop);
    PASS(p_phone_first);
    PASS(p_space_thousands);
    PASS(p_date_iso);
    PASS(p_date_slash);
    PASS(p_time_dot);
    PASS(p_date_dot);
    PASS(p_time_hm);
    PASS(p_time);
    PASS(p_phone);
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

/* ======================= tagging (latin.latin_word_lang, mode fi) ======================= */

static int camel(const uint32_t *w, int n) {
    for (int i = 0; i + 1 < n; i++)
        if (w[i] >= 'a' && w[i] <= 'z' && w[i + 1] >= 'A' && w[i + 1] <= 'Z') return 1;
    return 0;
}

static int has_sub(const char *w, int n, const char *f) {
    int m = (int)strlen(f);
    for (int i = 0; i + m <= n; i++) if (memcmp(w + i, f, (size_t)m) == 0) return 1;
    return 0;
}

static int fi_vowel(char c) { return c && strchr("aeiouy", c) != NULL; }

static int onset_ok(const char *r, int len) { return len == 1 || in_list(VTTS_FI_ONSETS, VTTS_FI_N_ONSETS, r, len); }
static int coda_ok(const char *r, int len) {
    return in_list(VTTS_FI_CODAS, VTTS_FI_N_CODAS, r, len) || (len == 1 && r[0] == 'N') ||
           (len == 2 && r[0] == 'n' && r[1] == 'N');
}

/* g2p_fi.valid_spelling of a lower-case ASCII word w[0..n) (n <= 64) */
static int valid_spelling(const char *w, int n) {
    char t[72];
    int m = 0;
    if (n <= 0 || n > 64) return 0;
    for (int i = 0; i < n; i++) if (w[i] < 'a' || w[i] > 'z') return 0;
    for (int k = 0; k < VTTS_FI_N_FOREIGN; k++) if (has_sub(w, n, VTTS_FI_FOREIGN[k])) return 0;
    if (n >= 2 && w[0] == 's' && w[1] == 'h') return 0;
    for (int k = 0; k < VTTS_FI_N_DISHARMONY; k++) if (has_sub(w, n, VTTS_FI_DISHARMONY[k])) return 0;
    for (int i = 0; i + 2 < n; i++) if (w[i] == w[i + 1] && w[i] == w[i + 2]) return 0;
    for (int i = 0; i < n; i++) { /* w.replace("ng", "N") */
        if (w[i] == 'n' && i + 1 < n && w[i + 1] == 'g') { t[m++] = 'N'; i++; }
        else t[m++] = w[i];
    }
    int any_v = 0;
    for (int i = 0; i < m; i++) any_v |= fi_vowel(t[i]);
    if (!any_v) return 0; /* consonant_runs: None */
    for (int k = 0; k < m;) { /* clusters_fit, runs of at most 3 */
        if (fi_vowel(t[k])) { k++; continue; }
        int j = k;
        while (j < m && !fi_vowel(t[j])) j++;
        const char *r = t + k;
        int len = j - k, start = k == 0, end = j == m;
        if (len > 3) return 0;
        if (start && !onset_ok(r, len)) return 0;
        if (end && !in_list(VTTS_FI_FINALS, VTTS_FI_N_FINALS, r, len)) return 0;
        if (!start && !end) {
            int ok = 0;
            for (int sp = 0; sp < len && !ok; sp++) ok = (sp == 0 || coda_ok(r, sp)) && onset_ok(r + sp, len - sp);
            if (!ok) return 0;
        }
        k = j;
    }
    return 1;
}

static int plain_latin(const uint32_t *w, int n) {
    int alpha = 0;
    for (int i = 0; i < n; i++) {
        int a = (w[i] | 32) >= 'a' && (w[i] | 32) <= 'z';
        if (w[i] >= 0x80 || !(a || w[i] == '-' || w[i] == '\'')) return 0;
        alpha |= a;
    }
    return n > 0 && alpha;
}

int vtts_fi_word_lang(const uint32_t *w, int n) {
    char low[72];
    if (n <= 0) return -1;
    for (int i = 0; i < n; i++) if (in_u8(w[i], VTTS_FI_OWN)) return 1;
    if (!plain_latin(w, n)) return -1;
    if (n > 64) return 0; /* longer than any table word; Finnish spelling is checked below for <= 64 */
    for (int i = 0; i < n; i++) low[i] = (char)((w[i] >= 'A' && w[i] <= 'Z') ? w[i] + 32 : w[i]);
    low[n] = 0;
    if (in_sorted(VTTS_FI_NATIVE, VTTS_FI_N_NATIVE, low) || in_sorted(VTTS_FI_TABLE_KEYS, VTTS_FI_N_TABLE_KEYS, low))
        return 1;
    if (in_sorted(VTTS_FI_ENGLISH, VTTS_FI_N_ENGLISH, low)) return 0;
    int all_caps = 1, all_valid = 1;
    for (int a = 0; a < n;) {
        int b = a;
        while (b < n && w[b] != '-' && w[b] != '\'') b++;
        if (b > a) {
            if (camel(w + a, b - a)) return 0;
            int up = b - a >= 2 && b - a <= 5;
            for (int k = a; k < b; k++) up &= w[k] >= 'A' && w[k] <= 'Z';
            all_caps &= up;
            all_valid &= valid_spelling(low + a, b - a);
        }
        a = b + 1;
    }
    if (n == 1 || all_caps) return 1;
    return all_valid ? 1 : 0;
}

int vtts_fi_ambiguous(const uint32_t *w, int n) {
    char low[72];
    if (n <= 0 || n > 64) return 0;
    for (int i = 0; i < n; i++) {
        if (w[i] >= 0x80) return 0;
        low[i] = (char)((w[i] >= 'A' && w[i] <= 'Z') ? w[i] + 32 : w[i]);
    }
    low[n] = 0;
    return in_sorted(VTTS_FI_BOTH, VTTS_FI_N_BOTH, low);
}

/* ======================= g2p ======================= */

/* fold() of one code point into o (0..2 letters) */
static int fold1(uint32_t c, uint32_t *o) {
    if (c < 0x80) {
        if (c >= 'A' && c <= 'Z') { o[0] = c + 32; return 1; }
        if (c >= 'a' && c <= 'z') { o[0] = c; return 1; }
        return 0;
    }
    for (int k = 0; k < VTTS_FI_N_FOLD2; k++)
        if (VTTS_FI_FOLD2[k][0] == c) { o[0] = VTTS_FI_FOLD2[k][1]; o[1] = VTTS_FI_FOLD2[k][2]; return 2; }
    int lo = 0, hi = VTTS_FI_N_FOLD - 1, k = -1;
    while (lo <= hi) {
        int m = (lo + hi) / 2;
        if (VTTS_FI_FOLD[m].start <= c) { k = m; lo = m + 1; } else hi = m - 1;
    }
    if (k < 0 || c - VTTS_FI_FOLD[k].start >= VTTS_FI_FOLD[k].count) return 0;
    o[0] = VTTS_FI_FOLD[k].first + (c - VTTS_FI_FOLD[k].start) * VTTS_FI_FOLD[k].step;
    return 1;
}

static int fold_word(const uint32_t *w, int n, uint32_t *o) {
    int m = 0;
    uint32_t f[2];
    for (int i = 0; i < n; i++) {
        int k = fold1(w[i], f);
        for (int j = 0; j < k && m < VTTS_FI_MAXW; j++) o[m++] = f[j];
    }
    return m;
}

static int is_vowel_letter(uint32_t c) {
    return c == 'a' || c == 'e' || c == 'i' || c == 'o' || c == 'u' || c == 'y' || c == 0xE4 || c == 0xF6 || c == 0xE5;
}

static const char *vowel_name(uint32_t c) {
    switch (c) {
    case 0xE4: return "ae";
    case 0xF6: return "oe";
    case 0xE5: return "o";
    default: return NULL;
    }
}

typedef struct { uint8_t *out; int n, cap; } emit_t;

static void emit(emit_t *e, const char *name, int stress) {
    char t[8];
    size_t l = strlen(name);
    memcpy(t, name, l);
    if (stress) t[l++] = '1';
    t[l] = 0;
    for (int k = 0; k < VTTS_FI_N_TOKENS; k++)
        if (strcmp(VTTS_FI_TOKENS[k], t) == 0) {
            if (e->n < e->cap) e->out[e->n++] = (uint8_t)(VTTS_FI_TOK0 + k);
            return;
        }
}

/* _segments of w[a..b) emitted with the stress on the first vowel when stressed */
static void segments(emit_t *e, const uint32_t *w, int a, int b, int stressed) {
    char v1[2] = {0, 0};
    for (int i = a; i < b;) {
        uint32_t c = w[i], nx = i + 1 < b ? w[i + 1] : 0, nx2 = i + 2 < b ? w[i + 2] : 0;
        if (is_vowel_letter(c)) {
            const char *nm = vowel_name(c);
            if (!nm) { v1[0] = (char)c; nm = v1; }
            emit(e, nm, stressed);
            stressed = 0;
            if (nx == c) { emit(e, ":", 0); i += 2; } else i++;
            continue;
        }
        if (c == 'n' && nx == 'g') {
            emit(e, "ng", 0);
            if (is_vowel_letter(nx2)) emit(e, ":", 0);
            i += 2;
            continue;
        }
        if (c == 'n' && nx == 'k') { emit(e, "ng", 0); i++; continue; }
        if (c == 'n' && (nx == 'p' || nx == 'b')) { emit(e, "m", 0); i++; continue; }
        if (c == 's' && nx == 'c' && nx2 == 'h') { emit(e, "sh", 0); i += 3; continue; }
        if (c == 'c' && nx == 'h') { emit(e, "sh", 0); i += 2; continue; }
        if (c == 'p' && nx == 'h') { emit(e, "f", 0); i += 2; continue; }
        if (c == 't' && nx == 'h') { emit(e, "t", 0); i += 2; continue; }
        if (c == 'c' && nx == 'k') { emit(e, "k", 0); emit(e, ":", 0); i += 2; continue; }
        if (c == 'q' && nx == 'u') { emit(e, "k", 0); emit(e, "v", 0); i += 2; continue; }
        if (c == 'x') { emit(e, "k", 0); emit(e, "s", 0); i++; continue; }
        if (c == 'z') {
            emit(e, "t", 0);
            if (nx == 'z') { emit(e, ":", 0); i++; }
            emit(e, "s", 0);
            i++;
            continue;
        }
        char one[2] = {(char)c, 0};
        const char *nm = one;
        if (c == 'c') nm = (!nx || nx == 'e' || nx == 'i' || nx == 'y' || nx == 0xE4 || nx == 0xF6) ? "s" : "k";
        else if (c == 'q') nm = "k";
        else if (c == 'w') nm = "v";
        else if (c == 0x161) nm = "sh";
        else if (c == 0x17E) nm = "zh";
        else if (c >= 0x80) { i++; continue; } /* not a letter of the g2p (never: fold keeps Finnish letters) */
        emit(e, nm, 0);
        if (nx == c) { emit(e, ":", 0); i += 2; } else i++;
    }
}

/* number_parts(w): choice[k] = the part at k of the split (first in NUMBER_PARTS order whose rest
 * splits), -1 none; returns the number of parts or 0 */
static int number_parts(const uint32_t *w, int n, uint32_t *choice) {
    choice[n] = 0xFFFFFFFEu; /* the empty rest splits */
    for (int k = n - 1; k >= 0; k--) {
        choice[k] = 0xFFFFFFFFu;
        for (int p = 0; p < VTTS_FI_N_NUMBER_PARTS; p++) {
            uint32_t b[24];
            int l = u8_decode(VTTS_FI_NUMBER_PARTS[p], b, 24);
            if (k + l > n || choice[k + l] == 0xFFFFFFFFu || memcmp(w + k, b, (size_t)l * sizeof(uint32_t)) != 0) continue;
            choice[k] = (uint32_t)p;
            break;
        }
    }
    if (choice[0] == 0xFFFFFFFFu) return 0;
    int cnt = 0;
    for (int k = 0; k < n; cnt++) {
        uint32_t b[24];
        k += u8_decode(VTTS_FI_NUMBER_PARTS[choice[k]], b, 24);
    }
    return cnt;
}

static int unstressed(const uint32_t *w, int n) {
    for (int k = 0; k < VTTS_FI_N_UNSTRESSED; k++) if (eq_u8(w, n, VTTS_FI_UNSTRESSED[k])) return 1;
    return 0;
}

/* phonemes(word) of the folded word f[0..m) */
static void phonemes(emit_t *e, const uint32_t *f, int m, uint32_t *f2, uint32_t *choice) {
    const uint32_t *w = f;
    int n = m;
    for (int k = 0; k < VTTS_FI_N_OVERRIDES; k++)
        if (eq_u8(f, m, VTTS_FI_OVERRIDES[k][0])) {
            uint32_t raw[64];
            int r = u8_decode(VTTS_FI_OVERRIDES[k][1], raw, 64);
            n = fold_word(raw, r, f2);
            w = f2;
            break;
        }
    if (!n) return;
    int stressed = !unstressed(w, n);
    if (number_parts(w, n, choice) >= 2) {
        uint32_t b[24];
        for (int k = 0; k < n;) {
            int l = u8_decode(VTTS_FI_NUMBER_PARTS[choice[k]], b, 24);
            segments(e, w, k, k + l, stressed);
            k += l;
        }
        return;
    }
    segments(e, w, 0, n, stressed);
}

int vtts_fi_word_ids(const uint32_t *w, int n, uint32_t *scratch, uint8_t *out, int cap) {
    emit_t e = {out, 0, cap};
    uint32_t *f = scratch, *f2 = scratch + VTTS_FI_MAXW, *choice = scratch + 2 * VTTS_FI_MAXW;
    int m = fold_word(w, n, f), vowel = 0;
    for (int i = 0; i < m; i++) vowel |= is_vowel_letter(f[i]);
    if (m && !vowel) { /* spelled letter by letter: LETTERS[ch] words, each read as a word */
        uint32_t c[2];
        for (int i = 0; i < n; i++) {
            int k = fold1(w[i], c);
            for (int j = 0; j < k; j++) {
                const char *name = letter_name(c[j]);
                if (!name) continue;
                uint32_t nb[32];
                int nn = u8_decode(name, nb, 32);
                for (int a = 0; a < nn;) {
                    int b = a;
                    while (b < nn && nb[b] != ' ') b++;
                    if (b > a) e.n += vtts_fi_word_ids(nb + a, b - a, scratch, out + e.n, cap - e.n);
                    a = b + 1;
                }
            }
        }
        return e.n;
    }
    phonemes(&e, f, m, f2, choice);
    return e.n;
}

#endif /* VTTS_ENABLE_FI */
