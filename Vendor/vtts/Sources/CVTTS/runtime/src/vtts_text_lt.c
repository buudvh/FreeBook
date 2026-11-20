/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_lt.c -- Latin-script pair languages of the device front-end: Spanish (es-en),
 * Indonesian (id-en) and Brazilian Portuguese (pt-en). Mirrors src/vtts/frontend/latin.py
 * (tagging of plain Latin words), latin_norm.py and es|id|pt/normalize_*.py (normalization, pass by
 * pass) and es|id|pt/g2p_*.py (spelling rules, stress). All tables are in the generated
 * vtts_text_tables.h; no blob is needed. The Unicode classes and the shared English word list are
 * always built (other Latin-script modules use them); the rest only with VTTS_ENABLE_ES, _ID or _PT. */
#include "vtts_text_lt.h"
#include "vtts_langs.h"

#include <string.h>

#include "vtts_text_tables.h"
#if VTTS_ENABLE_MS
#include "vtts_text_ms_tables.h"
#endif

/* Malay runs the Indonesian code paths (IDL: Indonesian or Malay) with its own tables and the
 * differences of ms/normalize_ms.py and ms/g2p_ms.py under MS(k) */
#if VTTS_ENABLE_MS
#define MS(k) ((k) == VTTS_LT_MS)
#define LT_LAST VTTS_LT_MS
#else
#define MS(k) 0
#define LT_LAST VTTS_LT_PT
#endif
#define IDL(k) ((k) == VTTS_LT_ID || MS(k))

#if VTTS_ENABLE_LT
static const vtts_lt_lang *lt_lang(int k) {
#if VTTS_ENABLE_MS
    if (k == VTTS_LT_MS) return &VTTS_MS_LANG;
#endif
    return &VTTS_LT_LANGS[k];
}
#endif

/* ======================= Unicode classes of Python's re ======================= */

static int in_ranges(const uint32_t (*r)[2], int n, uint32_t c) {
    int lo = 0, hi = n - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2;
        if (c < r[m][0]) hi = m - 1;
        else if (c > r[m][1]) lo = m + 1;
        else return m;
    }
    return -1;
}

int vtts_u_word(uint32_t c) {
    if (c < 0x80) return (c >= '0' && c <= '9') || ((c | 32) >= 'a' && (c | 32) <= 'z') || c == '_';
    return in_ranges(VTTS_U_WORD, VTTS_U_N_WORD, c) >= 0;
}

int vtts_u_digit(uint32_t c) {
    if (c >= '0' && c <= '9') return (int)(c - '0');
    if (c < 0x80) return -1;
    int k = in_ranges(VTTS_U_DECIMAL, VTTS_U_N_DECIMAL, c);
    return k < 0 ? -1 : (int)((c - VTTS_U_DECIMAL[k][0]) % 10);
}

int vtts_u_space(uint32_t c) {
    if (c > 0x20 && c < 0x85) return 0;
    for (int k = 0; k < VTTS_U_N_SPACE; k++) if (VTTS_U_SPACE[k] == c) return 1;
    return 0;
}

uint32_t vtts_u_lower(uint32_t c) {
    if (c < 0x80) return c >= 'A' && c <= 'Z' ? c + 32 : c;
    int lo = 0, hi = VTTS_U_N_LOWER - 1, k = -1;
    while (lo <= hi) {
        int m = (lo + hi) / 2;
        if ((uint32_t)VTTS_U_LOWER[m][0] <= c) { k = m; lo = m + 1; } else hi = m - 1;
    }
    if (k < 0) return c;
    const int32_t *r = VTTS_U_LOWER[k];
    uint32_t off = c - (uint32_t)r[0];
    if (off % (uint32_t)r[3] || off / (uint32_t)r[3] >= (uint32_t)r[1]) return c;
    return (uint32_t)((int32_t)c + r[2]);
}

/* sorted list of ASCII strings */
static int in_sorted(const char *const *list, int n, const char *w) {
    int lo = 0, hi = n - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2, c = strcmp(list[m], w);
        if (!c) return 1;
        if (c < 0) lo = m + 1; else hi = m - 1;
    }
    return 0;
}

/* lexicons/latin/english.txt is shared by every Latin-script pair (fr, de, it, tr, pl, fi ...) */
int vtts_lt_english_word(const char *low) { return in_sorted(VTTS_LT_ENGLISH, VTTS_LT_N_ENGLISH, low); }

/* everything below is the es, id and pt module (VTTS_ENABLE_ES|ID|PT, vtts_langs.h) */
#if VTTS_ENABLE_LT

static int is_letter(uint32_t c) { return c != '_' && vtts_u_word(c) && vtts_u_digit(c) < 0; } /* [^\W\d_] */

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

/* c is one of the code points of the UTF-8 string set (0 never is) */
static int in_u8(uint32_t c, const char *set) {
    uint32_t x;
    int l;
    if (!c) return 0;
    while ((l = dec1(set, &x)) > 0) { if (x == c) return 1; set += l; }
    return 0;
}

/* the n code points w equal the UTF-8 string k */
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

/* list of strings holds the len chars s */
static int in_list(const char *const *list, int n, const char *s, int len) {
    for (int k = 0; k < n; k++) if ((int)strlen(list[k]) == len && memcmp(list[k], s, (size_t)len) == 0) return 1;
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
    uint32_t b[16];
    int m = u8_decode(k, b, 16);
    if (d->n - start < m) return 0;
    for (int i = 0; i < m; i++) if (d->p[d->n - m + i] != b[i]) return 0;
    return 1;
}

/* re.sub(pat + r"\b", rep) over the text written since start (pat and rep of the same length,
 * words of letters and spaces, so \b after a letter is "a space or the end follows") */
static void sub_word_end(lb_t *d, int start, const char *pat, const char *rep) {
    uint32_t p[16], r[16];
    int m = u8_decode(pat, p, 16);
    u8_decode(rep, r, 16);
    for (int i = start; i + m <= d->n; i++) {
        if (memcmp(d->p + i, p, (size_t)m * sizeof(uint32_t)) != 0) continue;
        if (i + m < d->n && vtts_u_word(d->p[i + m])) continue;
        memcpy(d->p + i, r, (size_t)m * sizeof(uint32_t));
        i += m - 1;
    }
}

/* ======================= language context and numbers ======================= */

typedef struct {
    const vtts_lt_lang *L;
    int k;                       /* VTTS_LT_* */
    const char *const *digits;   /* digit names 0..9 */
} lt_t;

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

/* significant digits of s[0..n) (decimal digits; other code points are separators): count, *st the first */
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

/* digits(): the name of every digit of s[from..n), joined by spaces */
static void digit_words(lb_t *d, const char *const *names, const uint32_t *s, int n, int from) {
    int first = 1;
    for (int i = from; i < n; i++) {
        int v = vtts_u_digit(s[i]);
        if (v < 0) continue;
        if (!first) put(d, ' ');
        puts8(d, names[v]);
        first = 0;
    }
}

static uint64_t value(const uint32_t *s, int n, int st) {
    uint64_t v = 0;
    for (int i = st; i < n; i++) { int x = vtts_u_digit(s[i]); if (x >= 0) v = v * 10 + (uint64_t)x; }
    return v;
}

/* ---- Spanish ---- */

static void es_apocope(lb_t *d, int start) { /* uno -> un at the end, veintiuno -> veintiún */
    if (tail_is(d, start, "veintiuno")) { d->n -= 9; puts8(d, "veintiún"); }
    else if (tail_is(d, start, "uno")) d->n -= 1;
}

static void es_below_100(lb_t *d, int v) {
    if (v < 30) { puts8(d, VTTS_ES_ONES[v]); return; }
    puts8(d, VTTS_ES_TENS[v / 10]);
    if (v % 10) { puts8(d, " y "); puts8(d, VTTS_ES_ONES[v % 10]); }
}

static void es_below_1000(lb_t *d, int v) {
    if (v == 100) { puts8(d, "cien"); return; }
    int h = v / 100, r = v % 100;
    if (h) puts8(d, VTTS_ES_HUNDREDS[h]);
    if (r) { if (h) put(d, ' '); es_below_100(d, r); }
}

static void es_below_million(lb_t *d, int v) {
    int th = v / 1000, r = v % 1000;
    if (th == 1) puts8(d, "mil");
    else if (th) { int st = d->n; es_below_1000(d, th); es_apocope(d, st); puts8(d, " mil"); }
    if (r) { if (th) put(d, ' '); es_below_1000(d, r); }
}

static void es_card(lb_t *d, const uint32_t *s, int n) {
    int st, nd = sig(s, n, &st);
    if (!nd) { puts8(d, VTTS_ES_ONES[0]); return; }
    if (nd > 24) { digit_words(d, VTTS_ES_ONES, s, n, st); return; }
    uint8_t dg[24] = {0};
    int k = 24 - nd, g[4], any = 0;
    for (int i = st; i < n; i++) { int x = vtts_u_digit(s[i]); if (x >= 0) dg[k++] = (uint8_t)x; }
    for (int q = 0; q < 4; q++) { g[q] = 0; for (int i = 0; i < 6; i++) g[q] = g[q] * 10 + dg[6 * q + i]; }
    for (int q = 0; q < 3; q++) {
        if (!g[q]) continue;
        if (any) put(d, ' ');
        if (g[q] == 1) { puts8(d, "un "); puts8(d, VTTS_ES_SCALES[q][0]); }
        else { int s0 = d->n; es_below_million(d, g[q]); es_apocope(d, s0); put(d, ' '); puts8(d, VTTS_ES_SCALES[q][1]); }
        any = 1;
    }
    if (g[3]) { if (any) put(d, ' '); es_below_million(d, g[3]); }
}

/* ---- Indonesian ---- */

static void below_1000_ones(lb_t *d, int v, const char *const *ones) { /* _below_1000(n, ones) */
    int h = v / 100, r = v % 100;
    if (h) { if (h == 1) puts8(d, "seratus"); else { puts8(d, ones[h]); puts8(d, " ratus"); } }
    if (!r) return;
    if (h) put(d, ' ');
    if (r >= 20) {
        puts8(d, ones[r / 10]);
        puts8(d, " puluh");
        if (r % 10) { put(d, ' '); puts8(d, ones[r % 10]); }
    } else if (r >= 12) { puts8(d, ones[r - 10]); puts8(d, " belas"); }
    else if (r == 11) puts8(d, "sebelas");
    else if (r == 10) puts8(d, "sepuluh");
    else puts8(d, ones[r]);
}

static void id_below_1000(lb_t *d, int v) { below_1000_ones(d, v, VTTS_ID_ONES); }

static void id_card_v(lb_t *d, uint64_t v) {
    static const uint64_t SC[3] = {1000000000000ull, 1000000000ull, 1000000ull};
    int any = 0;
    if (!v) { puts8(d, VTTS_ID_ONES[0]); return; }
    for (int k = 0; k < 3; k++) {
        uint64_t q = v / SC[k];
        v %= SC[k];
        if (!q) continue;
        if (any) put(d, ' ');
        id_card_v(d, q);
        put(d, ' ');
        puts8(d, VTTS_ID_SCALES[k]);
        any = 1;
    }
    int th = (int)(v / 1000), r = (int)(v % 1000);
    if (th) { if (any) put(d, ' '); if (th == 1) puts8(d, "seribu"); else { id_below_1000(d, th); puts8(d, " ribu"); } any = 1; }
    if (r) { if (any) put(d, ' '); id_below_1000(d, r); }
}

/* ---- Malay (normalize_ms.cardinal: lapan, sejuta, bilion, sifar) ---- */

#if VTTS_ENABLE_MS
static void ms_card_v(lb_t *d, uint64_t v) {
    static const uint64_t SC[3] = {1000000000000ull, 1000000000ull, 1000000ull};
    int any = 0;
    if (!v) { puts8(d, VTTS_MS_ZERO); return; }
    for (int k = 0; k < 3; k++) {
        uint64_t q = v / SC[k];
        v %= SC[k];
        if (!q) continue;
        if (any) put(d, ' ');
        if (q == 1 && k == 2) puts8(d, "se");
        else { ms_card_v(d, q); put(d, ' '); }
        puts8(d, VTTS_MS_SCALES[k]);
        any = 1;
    }
    int th = (int)(v / 1000), r = (int)(v % 1000);
    if (th) {
        if (any) put(d, ' ');
        if (th == 1) puts8(d, "seribu"); else { below_1000_ones(d, th, VTTS_MS_ONES); puts8(d, " ribu"); }
        any = 1;
    }
    if (r) { if (any) put(d, ' '); below_1000_ones(d, r, VTTS_MS_ONES); }
}
#endif

/* ---- Portuguese ---- */

static void pt_below_1000(lb_t *d, int v) {
    if (v == 100) { puts8(d, "cem"); return; }
    int h = v / 100, r = v % 100;
    if (h) puts8(d, VTTS_PT_HUNDREDS[h]);
    if (!r) return;
    if (h) puts8(d, " e ");
    if (r < 20) puts8(d, VTTS_PT_ONES[r]);
    else { puts8(d, VTTS_PT_TENS[r / 10]); if (r % 10) { puts8(d, " e "); puts8(d, VTTS_PT_ONES[r % 10]); } }
}

static void pt_card_v(lb_t *d, uint64_t v) {
    static const uint64_t SC[4] = {1000000000000ull, 1000000000ull, 1000000ull, 1000ull};
    int q[5], sc[5], ng = 0;
    if (!v) { puts8(d, VTTS_PT_ONES[0]); return; }
    for (int k = 0; k < 4; k++) {
        uint64_t x = v / SC[k];
        v %= SC[k];
        if (x) { q[ng] = (int)x; sc[ng++] = k; }
    }
    if (v) { q[ng] = (int)v; sc[ng++] = -1; }
    for (int i = 0; i < ng; i++) {
        if (i) put(d, ' ');
        if (i == ng - 1 && ng > 1 && (q[i] < 100 || q[i] % 100 == 0)) puts8(d, "e ");
        if (sc[i] < 0) pt_below_1000(d, q[i]);
        else if (q[i] == 1) { if (sc[i] == 3) puts8(d, "mil"); else { puts8(d, "um "); puts8(d, VTTS_PT_SCALES[sc[i]][0]); } }
        else { pt_below_1000(d, q[i]); put(d, ' '); puts8(d, VTTS_PT_SCALES[sc[i]][1]); }
    }
}

/* cardinal(int(s)) of the digits of s[0..n) */
static void card(const lt_t *x, lb_t *d, const uint32_t *s, int n) {
    if (x->k == VTTS_LT_ES) { es_card(d, s, n); return; }
    int st, nd = sig(s, n, &st);
    if (nd > 15) { digit_words(d, x->digits, s, n, st); return; }
#if VTTS_ENABLE_MS
    if (x->k == VTTS_LT_MS) { ms_card_v(d, value(s, n, st)); return; }
#endif
    if (x->k == VTTS_LT_ID) id_card_v(d, value(s, n, st)); else pt_card_v(d, value(s, n, st));
}

static void card_i(const lt_t *x, lb_t *d, int v) {
    uint32_t b[12];
    int k = 0;
    char t[12];
    int m = 0;
    do { t[m++] = (char)('0' + v % 10); v /= 10; } while (v && m < 11);
    while (m) b[k++] = (uint32_t)t[--m];
    card(x, d, b, k);
}

/* latin_norm.parse_number of a written number s[0..n): integer part [0, *ie) (separators skipped),
 * decimal part [*f0, n) or *f0 = -1, decimal mark *mark */
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

/* read_number of a number without sign; *one: the integer part is 1 and there is no decimal part.
 * Returns 1 when there is a decimal part. */
static int read_number(const lt_t *x, lb_t *d, const uint32_t *s, int n, int *one) {
    int ie, f0, st;
    uint32_t mark;
    parse_number(s, n, &ie, &f0, &mark);
    card(x, d, s, ie);
    int nd = sig(s, ie, &st);
    if (one) *one = f0 < 0 && nd == 1 && vtts_u_digit(s[st]) == 1;
    if (f0 < 0) return 0;
    put(d, ' ');
    puts8(d, mark == ',' ? x->L->comma : x->L->period);
    put(d, ' ');
    if (f0 < n && n - f0 <= 2 && s[f0] != '0') card(x, d, s + f0, n - f0);
    else digit_words(d, x->digits, s, n, f0);
    return 1;
}

#if VTTS_ENABLE_MS
/* normalize_ms.parse_number: 1,250.50 (comma groups, point decimals); 1.000.000 (two or more dot
 * groups, comma decimals); else the first point, else the first comma is the decimal mark (the
 * integer part [0, *ie) may hold commas: they are skipped like every separator) */
static void ms_parse_number(const uint32_t *s, int n, int *ie, int *f0) {
    if (groups_full(s, n, ',', '.', ie, f0)) return;
    if (groups_full(s, n, '.', ',', ie, f0) && (*ie - drun(s, n, 0)) / 4 >= 2) return;
    for (int m = 0; m < 2; m++) {
        uint32_t c = m ? ',' : '.';
        for (int i = 0; i < n; i++)
            if (s[i] == c) { *ie = i; *f0 = i + 1; return; }
    }
    *ie = n;
    *f0 = -1;
}

/* normalize_ms.number: negatif, the cardinal, perpuluhan and the decimals digit by digit */
static void ms_number(const lt_t *x, lb_t *d, const uint32_t *s, int n, int neg) {
    int ie, f0;
    if (neg) puts8(d, "negatif ");
    ms_parse_number(s, n, &ie, &f0);
    card(x, d, s, ie);
    if (f0 >= 0 && f0 < n) {
        put(d, ' ');
        puts8(d, VTTS_MS_POINT);
        put(d, ' ');
        digit_words(d, x->digits, s, n, f0);
    }
}
#endif

/* number(sign + s): es with before_word (un, veintiún before a word); *one as read_number */
static void number(const lt_t *x, lb_t *d, const uint32_t *s, int n, int neg, int before_word, int *one) {
#if VTTS_ENABLE_MS
    if (x->k == VTTS_LT_MS) { ms_number(x, d, s, n, neg); if (one) *one = 0; return; }
#endif
    if (neg) puts8(d, x->k == VTTS_LT_ID ? "minus " : "menos ");
    int st = d->n, frac = read_number(x, d, s, n, one);
    if (x->k == VTTS_LT_ES && before_word && !frac) es_apocope(d, st);
}

static void es_feminine(lb_t *d, int start) {
    if (tail_is(d, start, "uno")) d->p[d->n - 1] = 'a';
    sub_word_end(d, start, "ientos", "ientas");
}

static void pt_feminine(lb_t *d, int start) {
    if (tail_is(d, start, "um") && (d->n - start == 2 || !vtts_u_word(d->p[d->n - 3]))) put(d, 'a');
    else if (tail_is(d, start, "dois") && (d->n - start == 4 || !vtts_u_word(d->p[d->n - 5]))) {
        d->n -= 4;
        puts8(d, "duas");
    }
    sub_word_end(d, start, "entos", "entas");
}

/* ordinal(n, fem) of es and pt (1..999 by parts, else the cardinal); er: 1.er, 3.er */
static void ordinal(const lt_t *x, lb_t *d, const uint32_t *s, int n, int fem, int er) {
    int st, nd = sig(s, n, &st), s0 = d->n;
    if (nd < 1 || nd > 3) { card(x, d, s, n); }
    else {
        int v = (int)value(s, n, st), h = v / 100, r = v % 100, t = r / 10, u = r % 10, any = 0;
        const char *const *OH = x->k == VTTS_LT_ES ? VTTS_ES_ORD_HUNDREDS : VTTS_PT_ORD_HUNDREDS;
        const char *const *OT = x->k == VTTS_LT_ES ? VTTS_ES_ORD_TENS : VTTS_PT_ORD_TENS;
        const char *const *OO = x->k == VTTS_LT_ES ? VTTS_ES_ORD_ONES : VTTS_PT_ORD_ONES;
        const char *parts[3] = {OH[h], OT[t], OO[u]};
        if (x->k == VTTS_LT_ES && (r == 11 || r == 12)) { parts[1] = r == 11 ? "undécimo" : "duodécimo"; parts[2] = ""; }
        for (int k = 0; k < 3; k++) {
            if (!*parts[k]) continue;
            if (any) put(d, ' ');
            puts8(d, parts[k]);
            any = 1;
        }
        if (fem) sub_word_end(d, s0, "o", "a");
    }
    if (er && (tail_is(d, s0, "primero") || tail_is(d, s0, "tercero"))) d->n -= 1;
}

/* ======================= normalization passes =======================
 * Each regex pass of the Python normalizer is one function from s (n code points) to d; matches
 * are found left to right without overlap, like re.sub, and lookarounds look at the pass's input.
 * Where backtracking can change a match, the candidate ends are tried in the regex's order. */

typedef int (*end_ok)(const uint32_t *s, int n, int end, void *u);

/* (?:[.,]\d+)? at b, then ok() */
static int try_dec(const uint32_t *s, int n, int b, end_ok ok, void *u) {
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

typedef struct { const vtts_lt_reading *keys; int nk, word_end, key, end; } keys_m;

static int ok_keys(const uint32_t *s, int n, int e, void *u) { /* \s?(k1|k2|...)[(?![\w])] */
    keys_m *m = u;
    for (int sp = SP(e); sp >= 0; sp--)
        for (int k = 0; k < m->nk; k++) {
            int l = key_at(s, n, e + sp, m->keys[k].key);
            if (l && !(m->word_end && W(e + sp + l))) { m->key = k; m->end = e + sp + l; return 1; }
        }
    return 0;
}

/* the reading of currency key k */
static const vtts_lt_reading *currency(const lt_t *x, const char *key) {
    for (int k = 0; k < x->L->n_currency; k++) if (strcmp(x->L->currency[k].key, key) == 0) return &x->L->currency[k];
    return &x->L->currency[0];
}

/* apply_abbreviations, one key: (?<![\w])KEY[(?![\w])] -> " reading " (+ "." at the end of the text) */
static void p_abbrev(const lt_t *x, int k, const uint32_t *s, int n, lb_t *d) {
    const char *key = x->L->abbrev[k][0];
    int dot = key[strlen(key) - 1] == '.';
    for (int i = 0; i < n;) {
        int m;
        if (!W(i - 1) && (m = key_at(s, n, i, key)) && (dot || !W(i + m))) {
            int end = dot;
            for (int q = i + m; q < n && end; q++) end = vtts_u_space(s[q]);
            put(d, ' ');
            puts8(d, x->L->abbrev[k][1]);
            put(d, ' ');
            if (end) put(d, '.');
            i += m;
            continue;
        }
        put(d, s[i++]);
    }
}

static void p_drop(const lt_t *x, const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n; i++) put(d, in_u8(s[i], x->L->drop) ? ' ' : s[i]);
}

/* _date(d, m, y): " out " or the original text when the day or month is out of range */
static void date_out(const lt_t *x, lb_t *d, int dd, int mm, const uint32_t *y, int yl, const uint32_t *orig, int on) {
    if (!(dd >= 1 && dd <= 31 && mm >= 1 && mm <= 12)) { putn(d, orig, on); return; }
    put(d, ' ');
    if (x->k == VTTS_LT_PT && dd == 1) puts8(d, "primeiro"); else card_i(x, d, dd);
    puts8(d, IDL(x->k) ? " " : " de ");
    puts8(d, x->L->months[mm]);
    if (y) {
        puts8(d, IDL(x->k) ? " " : " de ");
        card_i(x, d, val(y, 0, yl) + (yl == 2 ? 2000 : 0));
    }
    put(d, ' ');
}

/* (?<![\d-])(\d{4})-(\d{1,2})-(\d{1,2})(?![\d-]) */
static void p_date_iso(const lt_t *x, const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !DG(i - 1) && !AT(i - 1, '-') && DG(i + 1) && DG(i + 2) && DG(i + 3) && AT(i + 4, '-')) {
            int m0 = i + 5, ml = drun(s, n, m0);
            if (ml >= 1 && ml <= 2 && AT(m0 + ml, '-')) {
                int d0 = m0 + ml + 1, dl = drun(s, n, d0);
                if (dl >= 1 && dl <= 2 && !AT(d0 + dl, '-')) {
                    date_out(x, d, val(s, d0, dl), val(s, m0, ml), s + i, 4, s + i, d0 + dl - i);
                    i = d0 + dl;
                    continue;
                }
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![\d/])(\d{1,2})/(\d{1,2})/(\d{4}|\d{2})(?![\d/]) */
static void p_date_dmy(const lt_t *x, const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !DG(i - 1) && !AT(i - 1, '/')) {
            int r1 = drun(s, n, i);
            if (r1 <= 2 && AT(i + r1, '/')) {
                int m0 = i + r1 + 1, r2 = drun(s, n, m0);
                if (r2 >= 1 && r2 <= 2 && AT(m0 + r2, '/')) {
                    int y0 = m0 + r2 + 1, ry = drun(s, n, y0);
                    if ((ry == 4 || ry == 2) && !AT(y0 + ry, '/')) {
                        date_out(x, d, val(s, i, r1), val(s, m0, r2), s + y0, ry, s + i, y0 + ry - i);
                        i = y0 + ry;
                        continue;
                    }
                }
            }
        }
        put(d, s[i++]);
    }
}

#if VTTS_ENABLE_MS
/* the ASCII letter a (lower case) under re.IGNORECASE: c is a, A or one of VTTS_MS_ICASE */
static int icase_eq(uint32_t c, char a) {
    if (c == (uint32_t)a || c == (uint32_t)a - 32) return 1;
    if (c < 0x80) return 0;
    for (size_t k = 0; k < sizeof VTTS_MS_ICASE / sizeof *VTTS_MS_ICASE; k++)
        if (VTTS_MS_ICASE[k][0] == c && VTTS_MS_ICASE[k][1] == (uint32_t)a) return 1;
    return 0;
}

/* re.IGNORECASE match of the ASCII text k (lower case; a space matches itself) at s[i] */
static int icase_at(const uint32_t *s, int n, int i, const char *k) {
    int m = 0;
    for (; k[m]; m++)
        if (!IN(i + m) || (k[m] == ' ' ? s[i + m] != ' ' : !icase_eq(s[i + m], k[m]))) return 0;
    return m;
}

/* ms DATE_ABBR: (?<![\d])(\d{1,2})\s+(ABBR...|MONTH...)\.?(?:\s+(\d{4}))?(?![\w]) (re.IGNORECASE) ->
 * _date(d, month, y); the month is that of the alternative when the matched letters lower() to it,
 * else (ſ, İ, ı) the text is kept */
static void p_date_abbr(const lt_t *x, const uint32_t *s, int n, lb_t *d) {
    const int na = (int)(sizeof VTTS_MS_MONTH_ALTS / sizeof *VTTS_MS_MONTH_ALTS);
    for (int i = 0; i < n;) {
        int r = DG(i) && !DG(i - 1) ? drun(s, n, i) : 0, end = -1, mm = 0, y0 = -1, a0 = 0, al = 0;
        if (r >= 1 && r <= 2 && SP(i + r)) {
            int p = i + r;
            while (SP(p)) p++;
            for (int k = 0; k < na && end < 0; k++) {
                int l = icase_at(s, n, p, VTTS_MS_MONTH_ALTS[k].key);
                if (!l) continue;
                for (int dot = AT(p + l, '.'); dot >= 0 && end < 0; dot--) {
                    int q = p + l + dot, t = q;
                    while (SP(t)) t++;
                    if (t > q && drun(s, n, t) >= 4 && !W(t + 4)) { end = t + 4; y0 = t; }
                    else if (!W(q)) end = q;
                    if (end >= 0) { mm = VTTS_MS_MONTH_ALTS[k].month; a0 = p; al = l; }
                }
            }
        }
        if (end < 0) { put(d, s[i++]); continue; }
        for (int k = a0; k < a0 + al; k++)
            if (s[k] == 0x130 || vtts_u_lower(s[k]) >= 0x80) mm = 0; /* key not in the tables: no date */
        date_out(x, d, val(s, i, r), mm, y0 >= 0 ? s + y0 : NULL, 4, s + i, end - i);
        i = end;
    }
}
#endif

/* ([01]?\d|2[0-4]) at i: the hour lengths in the order the regex tries them */
static int hours(const uint32_t *s, int n, int i, int hl[3]) {
    int k = 0;
    if ((AT(i, '0') || AT(i, '1')) && DG(i + 1)) hl[k++] = 2;
    if (DG(i)) hl[k++] = 1;
    if (AT(i, '2') && IN(i + 1) && s[i + 1] >= '0' && s[i + 1] <= '4') hl[k++] = 2;
    return k;
}

static int m05(const uint32_t *s, int n, int j) { return IN(j) && s[j] >= '0' && s[j] <= '5' && DG(j + 1); } /* [0-5]\d */
static int no_dc(const uint32_t *s, int n, int e) { return !DG(e) && !AT(e, ':'); }

static void time_out(const lt_t *x, lb_t *d, int h, int mi, int sec) {
    put(d, ' ');
    int st = d->n;
    card_i(x, d, h);
    if (x->k == VTTS_LT_ES) {
        es_feminine(d, st);
        if (mi) { puts8(d, " y "); card_i(x, d, mi); } else puts8(d, " en punto");
        if (sec > 0) { puts8(d, " y "); card_i(x, d, sec); puts8(d, " segundos"); }
    } else if (MS(x->k)) {
        if (mi) { put(d, ' '); card_i(x, d, mi); puts8(d, " minit"); }
        if (sec > 0) { put(d, ' '); card_i(x, d, sec); puts8(d, " saat"); }
    } else if (x->k == VTTS_LT_ID) {
        if (mi) { puts8(d, " lewat "); card_i(x, d, mi); puts8(d, " menit"); }
        if (sec > 0) { put(d, ' '); card_i(x, d, sec); puts8(d, " detik"); }
    } else {
        pt_feminine(d, st);
        if (!mi) puts8(d, h == 1 ? " hora" : " horas");
        else { puts8(d, " e "); card_i(x, d, mi); }
        if (sec > 0) { puts8(d, " e "); card_i(x, d, sec); puts8(d, " segundos"); }
    }
    put(d, ' ');
}

/* re.IGNORECASE lookbehind for the ASCII text k (letters and a final space) ending at i */
static int behind_icase(const uint32_t *s, int n, int i, const char *k) {
    int m = (int)strlen(k);
    (void)n;
    if (i < m) return 0;
    for (int q = 0; q < m; q++) {
        uint32_t c = s[i - m + q];
        if (k[q] == ' ') { if (c != ' ') return 0; continue; }
        int ok = 0;
        for (int r = 0; r < VTTS_U_N_ICASE && !ok; r++) {
            if (VTTS_U_ICASE[r][1] != (uint32_t)k[q]) continue;
            for (int v = 0; VTTS_U_ICASE[r][v]; v++) ok |= VTTS_U_ICASE[r][v] == c;
        }
        if (!ok) return 0;
    }
    return 1;
}

static void p_time(const lt_t *x, const uint32_t *s, int n, lb_t *d) {
    static const char *const SUF[3] = {"h", "hs", "hrs"};
    for (int i = 0; i < n;) {
        int hl[3], nh = DG(i) ? hours(s, n, i, hl) : 0, end = -1, h = 0, mi = 0, sec = -1;
        /* es (?<![\d:])H:M(?::S)?(?:\s?(?:h|hs|hrs)(?![\w]))?(?![\d:]); id: (?<![\d:.])H:M(?::S)?(?![\d:]);
         * pt (?<![\d:])H(?::|h)M(?::S)?(?:\s?h(?![\w]))?(?![\d:]) */
        if (nh && !DG(i - 1) && !AT(i - 1, ':') && !(IDL(x->k) && AT(i - 1, '.'))) {
            for (int c = 0; c < nh && end < 0; c++) {
                int j = i + hl[c];
                if (!((AT(j, ':') || (x->k == VTTS_LT_PT && AT(j, 'h'))) && m05(s, n, j + 1))) continue;
                int k = j + 3, has = AT(k, ':') && m05(s, n, k + 1);
                for (int sv = has; sv >= 0 && end < 0; sv--) {
                    int k2 = sv ? k + 3 : k;
                    if (!IDL(x->k))
                        for (int sp = SP(k2); sp >= 0 && end < 0; sp--)
                            for (int a = 0; a < (x->k == VTTS_LT_ES ? 3 : 1) && end < 0; a++) {
                                int p = k2 + sp, l = key_at(s, n, p, SUF[a]);
                                if (l && !W(p + l) && no_dc(s, n, p + l)) end = p + l;
                            }
                    if (end < 0 && no_dc(s, n, k2)) end = k2;
                    if (end >= 0) { h = val(s, i, hl[c]); mi = val(s, j + 1, 2); sec = sv ? val(s, k + 1, 2) : -1; }
                }
            }
        }
        /* id: (?<=pukul |jam )H\.M(?![\d.]) (re.IGNORECASE) */
        if (end < 0 && nh && IDL(x->k) && (behind_icase(s, n, i, "pukul ") || behind_icase(s, n, i, "jam ")))
            for (int c = 0; c < nh && end < 0; c++) {
                int j = i + hl[c];
                if (AT(j, '.') && m05(s, n, j + 1) && !DG(j + 3) && !AT(j + 3, '.')) {
                    end = j + 3;
                    h = val(s, i, hl[c]);
                    mi = val(s, j + 1, 2);
                }
            }
#if VTTS_ENABLE_MS
        /* ms: (?<![\d.,])H\.M(?![\d.])(?=\s+(?:pagi|tengah hari|...)) (re.IGNORECASE) */
        if (end < 0 && nh && MS(x->k) && !DG(i - 1) && !AT(i - 1, '.') && !AT(i - 1, ','))
            for (int c = 0; c < nh && end < 0; c++) {
                int j = i + hl[c], q = j + 3;
                if (!(AT(j, '.') && m05(s, n, j + 1) && !DG(q) && !AT(q, '.') && SP(q))) continue;
                while (SP(q)) q++;
                for (size_t k = 0; k < sizeof VTTS_MS_DAY_PARTS / sizeof *VTTS_MS_DAY_PARTS && end < 0; k++)
                    if (icase_at(s, n, q, VTTS_MS_DAY_PARTS[k])) { end = j + 3; h = val(s, i, hl[c]); mi = val(s, j + 1, 2); sec = -1; }
            }
#endif
        /* pt: (?<![\w:.,])Hh(?![\w]) */
        if (end < 0 && nh && x->k == VTTS_LT_PT && !WDC(i - 1) && !AT(i - 1, ':'))
            for (int c = 0; c < nh && end < 0; c++) {
                int j = i + hl[c];
                if (AT(j, 'h') && !W(j + 1)) { end = j + 1; h = val(s, i, hl[c]); mi = 0; sec = -1; }
            }
        if (end >= 0) {
            time_out(x, d, h, mi, sec);
            i = end;
            continue;
        }
        put(d, s[i++]);
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

/* PHONE: es/id (?<![\d])(?:\+\d{1,3}[\s-])?\d{2,4}(?:[\s-]\d{2,4}){2,4}(?![\d]); pt adds an
 * optional (\d{2})\s? and has groups of 2-5 digits, 1-4 times; both | (?<![\d.,])0\d{2,}(?![\d]|[.,]\d) */
static void p_phone(const lt_t *x, const uint32_t *s, int n, lb_t *d) {
    const int pt = x->k == VTTS_LT_PT, hi = pt ? 5 : 4, gmin = pt ? 1 : 2;
    const char *plus = x->k == VTTS_LT_ES ? "más" : x->k == VTTS_LT_ID ? "plus" : MS(x->k) ? "tambah" : "mais";
    for (int i = 0; i < n;) {
        int e = -1;
        if (!DG(i - 1) && (AT(i, '+') || DG(i) || (pt && AT(i, '(')))) {
            for (int pre = AT(i, '+'); pre >= 0 && e < 0; pre--) {
                int p = i;
                if (pre) {
                    int r = drun(s, n, i + 1);
                    if (!(r >= 1 && r <= 3 && SPD(i + 1 + r))) continue;
                    p = i + 2 + r;
                }
                if (pt && AT(p, '(') && DG(p + 1) && DG(p + 2) && AT(p + 3, ')'))
                    for (int sp = SP(p + 4); sp >= 0 && e < 0; sp--) e = phone_core(s, n, p + 4 + sp, 2, hi, gmin, 4);
                if (e < 0) e = phone_core(s, n, p, 2, hi, gmin, 4);
            }
        }
        if (e < 0 && AT(i, '0') && !DG(i - 1) && !AT(i - 1, '.') && !AT(i - 1, ',')) {
            int r = drun(s, n, i), q = i + r;
            if (r >= 3 && !((AT(q, '.') || AT(q, ',')) && DG(q + 1))) e = q;
        }
        if (e >= 0) { /* phone_digits */
            int cnt = 0;
            for (int q = i; q < e; q++) cnt += vtts_u_digit(s[q]) >= 0;
            if (cnt < 7 && s[i] != '0') putn(d, s + i, e - i);
            else {
                put(d, ' ');
                if (s[i] == '+') { puts8(d, plus); put(d, ' '); }
                digit_words(d, x->digits, s, e, i);
                put(d, ' ');
            }
            i = e;
            continue;
        }
        put(d, s[i++]);
    }
}

static void p_parens(const lt_t *x, const uint32_t *s, int n, lb_t *d) {
    (void)x;
    for (int i = 0; i < n; i++) put(d, s[i] == '(' || s[i] == ')' ? ' ' : s[i]);
}

/* es/pt _money(num, cur, scale) and id " number(num) [scale] CURRENCY " */
static void money_out(const lt_t *x, lb_t *d, const uint32_t *num, int nn, const vtts_lt_reading *cur,
                      const uint32_t *scale, int sn) {
    int one;
    put(d, ' ');
#if VTTS_ENABLE_MS
    if (MS(x->k)) { /* _ringgit: RM12.50 -> dua belas ringgit lima puluh sen */
        int ie, f0;
        ms_parse_number(num, nn, &ie, &f0);
        if (!scale && f0 >= 0 && nn - f0 == 2 && strcmp(cur->one, "ringgit") == 0) {
            int st, cents = val(num, f0, 2);
            if (sig(num, ie, &st)) { card(x, d, num, ie); puts8(d, " ringgit "); }
            if (cents) { card_i(x, d, cents); puts8(d, " sen"); }
            put(d, ' ');
            return;
        }
        ms_number(x, d, num, nn, 0);
        if (scale) { put(d, ' '); putn(d, scale, sn); }
        put(d, ' ');
        puts8(d, cur->one);
        put(d, ' ');
        return;
    }
#endif
    if (x->k == VTTS_LT_ID) {
        number(x, d, num, nn, 0, 0, NULL);
        if (scale) { put(d, ' '); putn(d, scale, sn); }
        put(d, ' ');
        puts8(d, cur->one);
        put(d, ' ');
        return;
    }
    if (x->k == VTTS_LT_PT) {
        int ie, f0;
        uint32_t mark;
        parse_number(num, nn, &ie, &f0, &mark);
        if (scale) {
            number(x, d, num, nn, 0, 1, NULL);
            put(d, ' ');
            putn(d, scale, sn);
            puts8(d, " de ");
            puts8(d, cur->many);
            put(d, ' ');
            return;
        }
        if (f0 >= 0 && nn - f0 == 2) {
            int st, nd = sig(num, ie, &st), cents = val(num, f0, 2);
            card(x, d, num, ie);
            put(d, ' ');
            puts8(d, nd == 1 && vtts_u_digit(num[st]) == 1 ? cur->one : cur->many);
            if (cents) { puts8(d, " e "); card_i(x, d, cents); puts8(d, cents == 1 ? " centavo" : " centavos"); }
            put(d, ' ');
            return;
        }
    }
    number(x, d, num, nn, 0, 1, &one);
    put(d, ' ');
    puts8(d, one ? cur->one : cur->many);
    put(d, ' ');
}

/* (CUR)\s?(NUM) [id: (\s?(?:ribu|juta|miliar|triliun))?; pt: (\s?(?:milhões|milhão|bilhões|bilhão|mil)(?![\w]))?] */
static void p_money_before(const lt_t *x, const uint32_t *s, int n, lb_t *d) {
    static const char *const ID_SCALES[] = {"ribu", "juta", "miliar", "triliun"};
    static const char *const MS_SCALES[] = {"ribu", "juta", "bilion", "trilion"};
    static const char *const PT_SCALES[] = {"milhões", "milhão", "bilhões", "bilhão", "mil"};
    for (int i = 0; i < n;) {
        int e = -1, j = 0, k;
        for (k = 0; k < x->L->n_currency && e < 0; k++) {
            int l = key_at(s, n, i, x->L->currency[k].key);
            if (!l) continue;
            for (int sp = SP(i + l); sp >= 0 && e < 0; sp--) {
                j = i + l + sp;
                e = num_match(s, n, j, ok_always, NULL);
            }
        }
        if (e >= 0) {
            const vtts_lt_reading *cur = &x->L->currency[k - 1];
            int sc0 = -1, sl = 0, end = e;
            if (x->k != VTTS_LT_ES) {
                const char *const *SC = x->k == VTTS_LT_ID ? ID_SCALES : MS(x->k) ? MS_SCALES : PT_SCALES;
                int nsc = IDL(x->k) ? 4 : 5;
                for (int sp = SP(e); sp >= 0 && sc0 < 0; sp--)
                    for (int a = 0; a < nsc && sc0 < 0; a++) {
                        int l = key_at(s, n, e + sp, SC[a]);
                        if (l && !(x->k == VTTS_LT_PT && W(e + sp + l))) { sc0 = e + sp; sl = l; end = sc0 + l; }
                    }
            }
            money_out(x, d, s + j, e - j, cur, sc0 >= 0 ? s + sc0 : NULL, sl);
            i = end;
            continue;
        }
        put(d, s[i++]);
    }
}

/* (?<![\w.,])(NUM)\s?(CUR): es all currencies; id (€|£|¥|\$); pt (€|£|¥) */
static void p_money_after(const lt_t *x, const uint32_t *s, int n, lb_t *d) {
    static const vtts_lt_reading ID_AFTER[] = {{"€", 0, 0}, {"£", 0, 0}, {"¥", 0, 0}, {"$", 0, 0}};
    keys_m m = {x->L->currency, x->L->n_currency, 0, 0, 0};
    if (x->k != VTTS_LT_ES) { m.keys = ID_AFTER; m.nk = x->k == VTTS_LT_ID ? 4 : 3; }
#if VTTS_ENABLE_MS
    if (MS(x->k)) { m.keys = VTTS_MS_CURRENCY_AFTER; m.nk = 4; }
#endif
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int e = num_match(s, n, i, ok_keys, &m);
            if (e >= 0) {
                money_out(x, d, s + i, e - i, MS(x->k) ? &m.keys[m.key] : currency(x, m.keys[m.key].key), NULL, 0);
                i = m.end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

#if VTTS_ENABLE_MS
static int ok_sen(const uint32_t *s, int n, int e, void *u) { /* \s?sen(?![\w]) */
    int *end = u;
    for (int sp = SP(e); sp >= 0; sp--)
        if (key_at(s, n, e + sp, "sen") && !W(e + sp + 3)) { *end = e + sp + 3; return 1; }
    return 0;
}

/* ms SEN: (?<![\w.,])(NUM)\s?sen(?![\w]) -> " number sen " */
static void p_sen(const lt_t *x, const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int end = 0, e = num_match(s, n, i, ok_sen, &end);
            if (e >= 0) {
                put(d, ' ');
                ms_number(x, d, s + i, e - i, 0);
                puts8(d, " sen ");
                i = end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}
#endif

/* (?<![\w.,])(-?)(NUM)\s?% -> " number por ciento | persen | por cento " */
static void p_percent(const lt_t *x, const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int j = i + AT(i, '-'), end = 0, e = num_match(s, n, j, ok_pct, &end);
            if (e >= 0) {
                put(d, ' ');
                number(x, d, s + j, e - j, j > i, 0, NULL);
                puts8(d, x->k == VTTS_LT_ES ? " por ciento " : x->k == VTTS_LT_ID ? " persen " : MS(x->k) ? " peratus " : " por cento ");
                i = end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![\w.,])(-?)(NUM)\s?(UNITS)(?![\w]) */
static void p_unit(const lt_t *x, const uint32_t *s, int n, lb_t *d) {
    keys_m m = {x->L->units, x->L->n_units, 1, 0, 0};
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int j = i + AT(i, '-'), e = num_match(s, n, j, ok_keys, &m);
            if (e >= 0) {
                int one;
                put(d, ' ');
                if (IDL(x->k)) number(x, d, s + j, e - j, j > i, 0, &one);
                else { if (j > i) puts8(d, "menos "); number(x, d, s + j, e - j, 0, 1, &one); }
                put(d, ' ');
                puts8(d, one || IDL(x->k) ? m.keys[m.key].one : m.keys[m.key].many);
                put(d, ' ');
                i = m.end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* es (?<![\w.,])(\d+)\.?(º|ª|er)(?![\w]); pt (?<![\w.,])(\d+)\.?(º|ª)(?![\w]); id (?<![\w])[Kk]e-?(\d+)(?![\d]) */
static void p_ordinal(const lt_t *x, const uint32_t *s, int n, lb_t *d) {
    static const char *const SUF[3] = {"º", "ª", "er"};
    for (int i = 0; i < n;) {
        if (IDL(x->k)) {
            if (!W(i - 1) && (AT(i, 'K') || AT(i, 'k')) && AT(i + 1, 'e')) {
                int q = AT(i + 2, '-') && DG(i + 3) ? i + 3 : i + 2;
                if (DG(q)) {
                    int r = drun(s, n, q), st, nd = sig(s + q, r, &st);
                    put(d, ' ');
                    if (nd == 1 && vtts_u_digit(s[q + st]) == 1) puts8(d, "pertama");
                    else { puts8(d, "ke"); card(x, d, s + q, r); }
                    put(d, ' ');
                    i = q + r;
                    continue;
                }
            }
        } else if (DG(i) && !WDC(i - 1)) {
            int r = drun(s, n, i), p = i + r, done = 0;
            for (int dot = AT(p, '.'); dot >= 0 && !done; dot--)
                for (int a = 0; a < (x->k == VTTS_LT_ES ? 3 : 2) && !done; a++) {
                    int l = key_at(s, n, p + dot, SUF[a]);
                    if (!l || W(p + dot + l)) continue;
                    put(d, ' ');
                    ordinal(x, d, s + i, r, a == 1, a == 2);
                    put(d, ' ');
                    i = p + dot + l;
                    done = 1;
                }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

/* (?<![\w.,])(\d+)\s?[-–]\s?(\d+)(?![\w]) -> " a a|sampai b " */
static void p_range(const lt_t *x, const uint32_t *s, int n, lb_t *d) {
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
                        card(x, d, s + i, r1);
                        puts8(d, x->k == VTTS_LT_ID ? " sampai " : MS(x->k) ? " hingga " : " a ");
                        card(x, d, s + b0, r2);
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
static void p_pause(const lt_t *x, const uint32_t *s, int n, lb_t *d) {
    (void)x;
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

static const char *letter_name(const vtts_lt_lang *L, uint32_t c) {
    for (int k = 0; k < L->n_letters; k++) if (L->letters[k].cp == c) return L->letters[k].name;
    return NULL;
}

static int upper_az(uint32_t c) { return c >= 'A' && c <= 'Z'; }

/* PRODUCT_CODE: (?<![\w])(?=..[A-Z])(?=..[0-9])[A-Z0-9]+(?![\w]) -> letters by name, digits one by one */
static void p_code(const lt_t *x, const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if ((upper_az(s[i]) || (s[i] >= '0' && s[i] <= '9')) && !W(i - 1)) {
            int j = i, up = 0, dg = 0;
            while (IN(j) && (upper_az(s[j]) || (s[j] >= '0' && s[j] <= '9'))) { up |= upper_az(s[j]); dg |= !upper_az(s[j]); j++; }
            if (up && dg && !W(j)) {
                put(d, ' ');
                for (int k = i; k < j; k++) {
                    if (k > i) put(d, ' ');
                    if (upper_az(s[k])) puts8(d, letter_name(x->L, s[k] + 32));
                    else puts8(d, x->digits[s[k] - '0']);
                }
                put(d, ' ');
                i = j;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* es (?<![\w.,])(-?)(NUM)(?![\d])(\s*)(?=([^\W\d_])?) -> " number(before_word=letter)" + spaces or " ";
 * id, pt (?<![\w.,])(-?)(NUM)(?![\d]) -> " number " */
static void p_number(const lt_t *x, const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int j = i + AT(i, '-'), e = num_match(s, n, j, ok_nodigit, NULL);
            if (e >= 0) {
                put(d, ' ');
                if (x->k == VTTS_LT_ES) {
                    int f = e;
                    while (SP(f)) f++;
                    number(x, d, s + j, e - j, j > i, IN(f) && is_letter(s[f]), NULL);
                    if (f > e) putn(d, s + e, f - e); else put(d, ' ');
                    i = f;
                } else {
                    number(x, d, s + j, e - j, j > i, 0, NULL);
                    put(d, ' ');
                    i = e;
                }
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* id REDUP: \b([^\W\d_]{2,})2\b -> \1 \1 */
static void p_redup(const lt_t *x, const uint32_t *s, int n, lb_t *d) {
    (void)x;
    for (int i = 0; i < n;) {
        if (is_letter(s[i]) && !W(i - 1)) {
            int j = i;
            while (IN(j) && is_letter(s[j])) j++;
            if (j - i >= 2 && AT(j, '2') && !W(j + 1)) {
                putn(d, s + i, j - i);
                put(d, ' ');
                putn(d, s + i, j - i);
                i = j + 1;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* SYMBOLS (in order; no reading holds a key), then "-" -> " " */
static void p_symbols(const lt_t *x, const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n; i++) {
        const char *r = NULL;
        for (int k = 0; k < x->L->n_symbols && !r; k++) if (x->L->symbols[k].cp == s[i]) r = x->L->symbols[k].name;
        if (r) puts8(d, r);
        else put(d, s[i] == '-' ? ' ' : s[i]);
    }
}

/* ACRONYM (?<![\w])[A-Z]{2,5}(?![\w]): spelled, or the lower-case word when it is read as a word */
static void p_acronym(const lt_t *x, const uint32_t *s, int n, lb_t *d) {
    for (int i = 0; i < n;) {
        if (upper_az(s[i]) && !W(i - 1)) {
            int j = i;
            while (IN(j) && upper_az(s[j])) j++;
            if (j - i >= 2 && j - i <= 5 && !W(j)) {
                char low[8];
                for (int k = i; k < j; k++) low[k - i] = (char)(s[k] + 32);
                low[j - i] = 0;
                if (in_sorted(x->L->acronym_words, x->L->n_acronym_words, low)) {
                    for (int k = i; k < j; k++) put(d, s[k] + 32);
                } else {
                    for (int k = i; k < j; k++) {
                        if (k > i) put(d, ' ');
                        puts8(d, letter_name(x->L, s[k] + 32));
                    }
                }
                i = j;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static void p_lower(const lt_t *x, const uint32_t *s, int n, lb_t *d) {
    (void)x;
    for (int i = 0; i < n; i++) {
        if (s[i] == 0x130) { put(d, 'i'); put(d, 0x307); }
        else put(d, vtts_u_lower(s[i]));
    }
}

static int is_mark(uint32_t c) { return c == ',' || c == '.' || c == '?' || c == '!' || c == ';' || c == ':'; }

/* finish(): findall([^\W\d_]+(?:'[^\W\d_]+)*|[,.?!;:]) joined by spaces, a mark after a mark dropped */
static void p_words(const lt_t *x, const uint32_t *s, int n, lb_t *d) {
    int any = 0, last_mark = 0;
    (void)x;
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

int vtts_lt_normalize(int lang, const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, const uint32_t **out) {
    static const char *const *const DIGITS[3] = {VTTS_ES_ONES, VTTS_ID_ONES, VTTS_PT_ONES};
    if (lang < 0 || lang > LT_LAST) return -1;
#if VTTS_ENABLE_MS
    lt_t x = {lt_lang(lang), lang, lang == VTTS_LT_MS ? VTTS_MS_ONES : DIGITS[lang]};
#else
    lt_t x = {lt_lang(lang), lang, DIGITS[lang]};
#endif
    lb_t p = {a, 0, cap, 0}, q = {b, 0, cap, 0};
    putn(&p, in, n);
    if (p.err) return -1;
#define PASS(fn) do { q.n = 0; fn(&x, p.p, p.n, &q); if (q.err) return -1; lb_t t_ = p; p = q; q = t_; } while (0)
    for (int k = 0; k < x.L->n_abbrev; k++) {
        q.n = 0;
        p_abbrev(&x, k, p.p, p.n, &q);
        if (q.err) return -1;
        lb_t t = p;
        p = q;
        q = t;
    }
    PASS(p_drop);
    PASS(p_date_iso);
    PASS(p_date_dmy);
#if VTTS_ENABLE_MS
    if (lang == VTTS_LT_MS) PASS(p_date_abbr);
#endif
    PASS(p_time);
    PASS(p_phone);
    if (lang == VTTS_LT_PT) PASS(p_parens);
    PASS(p_money_before);
    PASS(p_money_after);
#if VTTS_ENABLE_MS
    if (lang == VTTS_LT_MS) PASS(p_sen);
#endif
    PASS(p_percent);
    PASS(p_unit);
    PASS(p_ordinal);
    PASS(p_range);
    PASS(p_pause);
    PASS(p_code);
    PASS(p_number);
    if (IDL(lang)) PASS(p_redup);
    PASS(p_symbols);
    PASS(p_acronym);
    PASS(p_lower);
    PASS(p_words);
#undef PASS
    *out = p.p;
    return p.n;
}

/* ======================= tagging (latin.latin_word_lang) ======================= */

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

static int has_sub(const char *w, int n, const char *f) {
    int fl = (int)strlen(f);
    for (int i = 0; i + fl <= n; i++) if (memcmp(w + i, f, (size_t)fl) == 0) return 1;
    return 0;
}

static int lt_vowel(char c) { return c && strchr("aeiou", c) != NULL; }

static int onset_ok(const vtts_lt_lang *L, const char *r, int len) { return len == 1 || in_list(L->onsets, L->n_onsets, r, len); }

/* consonant_runs + clusters_fit */
static int clusters(const vtts_lt_lang *L, const char *w, int n, int yv) {
#define ISV(k) (lt_vowel(w[k]) || (yv && w[k] == 'y' && !((k) + 1 < n && lt_vowel(w[(k) + 1]))))
    int any = 0;
    for (int k = 0; k < n; k++) any |= ISV(k);
    if (!any) return 0;
    for (int k = 0; k < n;) {
        if (ISV(k)) { k++; continue; }
        int j = k;
        while (j < n && !ISV(j)) j++;
        const char *r = w + k;
        int len = j - k, start = k == 0, end = j == n;
        if (start && !onset_ok(L, r, len)) return 0;
        if (end && !in_list(L->finals, L->n_finals, r, len)) return 0;
        if (!start && !end) {
            int ok = 0;
            for (int sp = 0; sp < len && !ok; sp++)
                ok = (sp == 0 || in_list(L->codas, L->n_codas, r, sp)) && onset_ok(L, r + sp, len - sp);
            if (!ok) return 0;
        }
        k = j;
    }
    return 1;
#undef ISV
}

static int doubles_ok(const vtts_lt_lang *L, const char *w, int n, int ee_ok) {
    for (int i = 0; i + 1 < n; i++)
        if (w[i] == w[i + 1] && !in_list(L->doubles, L->n_doubles, w + i, 2) && !(ee_ok && w[i] == 'e')) return 0;
    return 1;
}

static int digraphs(const vtts_lt_lang *L, char *w, int n) {
    for (int k = 0; k < L->n_digraphs; k++) n = replace_all(w, n, L->digraphs[k][0], L->digraphs[k][1]);
    return n;
}

static int foreign(const vtts_lt_lang *L, const char *w, int n) {
    for (int k = 0; k < L->n_foreign; k++) if (has_sub(w, n, L->foreign[k])) return 1;
    return 0;
}

/* valid_spelling of a lower-case ASCII word (w is modified; t is scratch of n + 1 chars) */
static int valid_spelling(int lang, char *w, int n, char *t) {
    const vtts_lt_lang *L = lt_lang(lang);
    if (lang == VTTS_LT_ES) {
        memcpy(t, w, (size_t)n);
        int tn = replace_all(t, n, "desh", "dez");
        if (foreign(L, t, tn)) return 0;
        for (int i = 0; i < n;) {
            if (w[i] == 'q' && i + 1 < n && w[i + 1] == 'u') { i += 2; continue; }
            if (w[i] == 'q') return 0;
            i++;
        }
        if (!doubles_ok(L, w, n, 0)) return 0;
        n = digraphs(L, w, n);
        return clusters(L, w, n, 1);
    }
    if (IDL(lang)) { /* ms: the same check with gh and dh as one letter (L->digraphs) */
        for (int k = 0; k < n; k++)
            if (w[k] == 'c' && (k + 1 == n || !lt_vowel(w[k + 1]))) return 0;
        int ee = n >= 3 && (memcmp(w, "kee", 3) == 0 || memcmp(w, "see", 3) == 0);
        memcpy(t, w, (size_t)n);
        int tn = replace_all(t, n, "ngg", "ng");
        if (!doubles_ok(L, t, tn, ee)) return 0;
        n = digraphs(L, w, n);
        if (foreign(L, w, n)) return 0;
        return clusters(L, w, n, 0);
    }
    if (foreign(L, w, n)) return 0;
    if (!doubles_ok(L, w, n, 0)) return 0;
    n = digraphs(L, w, n);
    return clusters(L, w, n, 0);
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

int vtts_lt_word_lang(int lang, const uint32_t *w, int n) {
    if (lang < 0 || lang > LT_LAST) return -1;
    const vtts_lt_lang *L = lt_lang(lang);
    char low[128], part[128], t[128];
    if (n <= 0) return -1;
    for (int i = 0; i < n; i++) if (in_u8(w[i], L->own)) return 1;
    if (!plain_latin(w, n)) return -1;
    if (n < (int)sizeof low) {
        for (int i = 0; i < n; i++) low[i] = (char)(w[i] >= 'A' && w[i] <= 'Z' ? w[i] + 32 : w[i]);
        low[n] = 0;
        if (in_sorted(L->native, L->n_native, low) || in_sorted(L->table_keys, L->n_table_keys, low)) return 1;
        if (in_sorted(VTTS_LT_ENGLISH, VTTS_LT_N_ENGLISH, low)) return 0;
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
                if (len >= (int)sizeof part) all_valid = 0; /* longer than any word the rules accept is not checked */
                else {
                    for (int k = 0; k < len; k++) part[k] = (char)(w[a + k] | 32);
                    part[len] = 0;
                    all_valid = valid_spelling(lang, part, len, t);
                }
            }
        }
        a = b + 1;
    }
    if (n == 1 || all_caps) return 1;
    return all_valid ? 1 : 0;
}

/* ======================= g2p ======================= */

typedef struct { char kind; uint8_t acc, dia, nas; char ph[4]; } seg_t; /* kind 'C', 'V' or 'G' */

static uint32_t fold1(const vtts_lt_lang *L, int lang, uint32_t c) {
    if (c < 0x80) {
        if (c >= 'A' && c <= 'Z') return c + 32;
        if (c >= 'a' && c <= 'z') return c;
        return IDL(lang) && c == '\'' ? c : 0;
    }
    int lo = 0, hi = L->n_fold - 1, k = -1;
    while (lo <= hi) {
        int m = (lo + hi) / 2;
        if (L->fold[m].start <= c) { k = m; lo = m + 1; } else hi = m - 1;
    }
    if (k < 0 || c - L->fold[k].start >= L->fold[k].count) return 0;
    return L->fold[k].first + (c - L->fold[k].start) * L->fold[k].step;
}

static int fold_word(const vtts_lt_lang *L, int lang, const uint32_t *w, int n, uint32_t *o) {
    int m = 0;
    for (int i = 0; i < n && m < VTTS_LT_MAXW; i++) {
        uint32_t f = fold1(L, lang, w[i]);
        if (f) o[m++] = f;
    }
    return m;
}

static int fold_u8(const vtts_lt_lang *L, int lang, const char *s, uint32_t *o) {
    uint32_t c;
    int l, m = 0;
    while ((l = dec1(s, &c)) > 0 && m < VTTS_LT_MAXW) {
        uint32_t f = fold1(L, lang, c);
        if (f) o[m++] = f;
        s += l;
    }
    return m;
}

static const char *override(const vtts_lt_lang *L, const uint32_t *w, int n) {
    for (int k = 0; k < L->n_overrides; k++) if (eq_u8(w, n, L->overrides[k][0])) return L->overrides[k][1];
    return NULL;
}

static int unstressed(const vtts_lt_lang *L, const uint32_t *w, int n) {
    for (int k = 0; k < L->n_unstressed; k++) if (eq_u8(w, n, L->unstressed[k])) return 1;
    return 0;
}

typedef struct { const vtts_lt_lang *L; uint8_t *out; int n, cap; } emit_t;

static void emit(emit_t *e, const char *name) {
    for (int k = 0; k < e->L->n_tokens; k++)
        if (strcmp(e->L->tokens[k], name) == 0) {
            if (e->n < e->cap) e->out[e->n++] = (uint8_t)(e->L->tok0 + k);
            return;
        }
}

static void emit_ph(emit_t *e, const char *ph, int nasal, int stress) {
    char b[8];
    size_t l = strlen(ph);
    memcpy(b, ph, l);
    if (nasal) b[l++] = 'n';
    if (stress) b[l++] = '1';
    b[l] = 0;
    emit(e, b);
}

static void seg(seg_t *S, int *ns, char kind, const char *ph) {
    seg_t *s = &S[(*ns)++];
    memset(s, 0, sizeof *s);
    s->kind = kind;
    for (int k = 0; k < 3 && ph[k]; k++) s->ph[k] = ph[k]; /* names have at most 2 letters */
}

static int ends_with(const uint32_t *w, int n, const char *k) {
    int m = (int)strlen(k);
    if (n < m) return 0;
    for (int i = 0; i < m; i++) if (w[n - m + i] != (uint32_t)(unsigned char)k[i]) return 0;
    return 1;
}

#define AT_(k) ((k) >= 0 && (k) < n ? w[k] : 0)

/* ---- Spanish (g2p_es.phonemes) ---- */

static int es_front(uint32_t c) { return !c || in_u8(c, VTTS_ES_FRONT); } /* Python: "" in FRONT */

static void es_phonemes(emit_t *e, const uint32_t *word, int wn, uint32_t *w, seg_t *S) {
    const vtts_lt_lang *L = e->L;
    int n = fold_word(L, VTTS_LT_ES, word, wn, w), ns = 0;
    const char *r = override(L, w, n);
    if (r) n = fold_u8(L, VTTS_LT_ES, r, w);
    if (!n) return;
    for (int i = 0; i < n;) {
        uint32_t c = w[i], nx = AT_(i + 1), nx2 = AT_(i + 2), pv = AT_(i - 1);
        int step = 1;
        char one[4] = {0};
        if (in_u8(c, VTTS_ES_VOWELS)) {
            uint32_t a[8], b[8];
            int na = u8_decode(VTTS_ES_ACCENTED, a, 8), acc = 0;
            u8_decode(VTTS_ES_ACCENTED_BASE, b, 8);
            uint32_t base = c == 0xFC ? 'u' : c;
            for (int k = 0; k < na; k++) if (a[k] == c) { base = b[k]; acc = 1; }
            one[0] = (char)base;
            seg(S, &ns, 'V', one);
            S[ns - 1].acc = (uint8_t)acc;
        } else if (c == 'c') {
            if (nx == 'h') { seg(S, &ns, 'C', "ch"); step = 2; }
            else seg(S, &ns, 'C', es_front(nx) ? "th" : "k");
        } else if (c == 'q') {
            seg(S, &ns, 'C', "k");
            if (nx == 'u' && es_front(nx2)) step = 2;
        } else if (c == 'g') {
            if (es_front(nx)) seg(S, &ns, 'C', "x");
            else { seg(S, &ns, 'C', "g"); if (nx == 'u' && es_front(nx2)) step = 2; }
        } else if (c == 'l' && nx == 'l') { seg(S, &ns, 'C', "ll"); step = 2; }
        else if (c == 'r') {
            if (nx == 'r') { seg(S, &ns, 'C', "rr"); step = 2; }
            else seg(S, &ns, 'C', i == 0 || pv == 'n' || pv == 'l' || pv == 's' ? "rr" : "r");
        } else if (c == 'y') {
            if (nx && in_u8(nx, VTTS_ES_VOWELS)) seg(S, &ns, 'C', "y");
            else seg(S, &ns, 'V', "i");
        } else if (c == 'x') {
            if (i == 0) seg(S, &ns, 'C', "s");
            else { seg(S, &ns, 'C', "k"); seg(S, &ns, 'C', "s"); }
        } else if (c == 'h') {
        } else if (c == 'j') seg(S, &ns, 'C', "x");
        else if (c == 'z') seg(S, &ns, 'C', "th");
        else if (c == 0xF1) seg(S, &ns, 'C', "ny");
        else if (c == 'v') seg(S, &ns, 'C', "b");
        else { one[0] = (char)c; seg(S, &ns, 'C', one); }
        i += step;
    }
    /* _nuclei: in a run of vowels the strong ones (a e o, accented) are nuclei, the others glides */
    for (int i = 0; i < ns;) {
        if (S[i].kind != 'V') { i++; continue; }
        int j = i, strong = 0;
        while (j < ns && S[j].kind == 'V') { strong |= S[j].acc || strchr("aeo", S[j].ph[0]); j++; }
        for (int k = i; k < j; k++) {
            int st = S[k].acc || strchr("aeo", S[k].ph[0]);
            if (strong ? !st : k != j - 1) { S[k].kind = 'G'; strcpy(S[k].ph, S[k].ph[0] == 'i' ? "j" : "w"); }
        }
        i = j;
    }
    int stress = -1, last = -1, prev = -1, cnt = 0, marked = -1;
    for (int k = 0; k < ns; k++)
        if (S[k].kind == 'V') { prev = last; last = k; cnt++; if (S[k].acc) marked = k; }
    if (cnt && !unstressed(L, w, n)) {
        if (marked >= 0) stress = marked;
        else if (cnt == 1) stress = last;
        else stress = strchr("aeiouns", (int)(w[n - 1] < 0x80 ? w[n - 1] : 1)) ? prev : last;
    }
    for (int k = 0; k < ns; k++) emit_ph(e, S[k].ph, 0, k == stress);
}

/* ---- Indonesian (g2p_id.phonemes) ---- */

static void id_phonemes(emit_t *e, const uint32_t *word, int wn, uint32_t *w, uint32_t *t, seg_t *S) {
    const vtts_lt_lang *L = e->L;
    const int malay = MS(VTTS_LT_MS) && L->code[0] == 'm'; /* g2p_ms: rule_phonemes(..., malay=True) */
    int n = fold_word(L, VTTS_LT_ID, word, wn, w), ns = 0, explicit_ = 0, tn = -1;
    const char *r = override(L, w, n);
    if (r) { tn = u8_decode(r, t, VTTS_LT_MAXW); explicit_ = 1; }
    for (int p = -1; p < (int)(sizeof VTTS_ID_PREFIXES / sizeof *VTTS_ID_PREFIXES) && tn < 0; p++) { /* respell: a stem with its affixes */
        const char *pre = p < 0 ? "" : VTTS_ID_PREFIXES[p];
        int lp = (int)strlen(pre);
        if (n < lp || !ends_with(w, lp, pre)) continue; /* startswith */
        const uint32_t *rest = w + lp;
        int rn = n - lp;
        for (int q = -1; q < (int)(sizeof VTTS_ID_SUFFIXES / sizeof *VTTS_ID_SUFFIXES) && tn < 0; q++) {
            const char *suf = q < 0 ? "" : VTTS_ID_SUFFIXES[q];
            int ls = (int)strlen(suf);
            if ((!lp && !ls) || !ends_with(rest, rn, suf) || rn - ls < 3) continue;
            const char *rd = override(L, rest, rn - ls);
            if (!rd) continue;
            tn = 0;
            for (int k = 0; k < lp; k++) t[tn++] = (uint32_t)pre[k];
            tn += u8_decode(rd, t + tn, VTTS_LT_MAXW - tn - 8);
            for (int k = 0; k < ls; k++) t[tn++] = (uint32_t)suf[k];
            explicit_ = 1;
        }
    }
    if (tn < 0) { memcpy(t, w, (size_t)n * sizeof *w); tn = n; }
    n = fold_word(L, VTTS_LT_ID, t, tn, w);
    int letters = 0;
    for (int i = 0; i < n; i++) letters |= w[i] != '\'';
    if (!letters) return;
    for (int i = 0; i < n;) {
        uint32_t c = w[i], nx = AT_(i + 1);
        char one[4] = {0};
#if VTTS_ENABLE_MS
        if (malay) { /* Malay digraphs (gh dh th sh ch too) and letter sounds (q k, sh sy, ch c) */
            const char *snd = NULL;
            int two = 0;
            one[0] = (char)c;
            one[1] = (char)nx;
            for (size_t k = 0; c < 0x80 && nx && nx < 0x80 && k < sizeof VTTS_MS_DIGRAPH_SOUNDS / sizeof *VTTS_MS_DIGRAPH_SOUNDS; k++)
                if (!strcmp(one, VTTS_MS_DIGRAPH_SOUNDS[k])) two = 1;
            if (!two) one[1] = 0;
            for (size_t k = 0; c < 0x80 && k < sizeof VTTS_MS_LETTER_SOUNDS / sizeof *VTTS_MS_LETTER_SOUNDS; k++)
                if (!strcmp(one, VTTS_MS_LETTER_SOUNDS[k][0])) { snd = VTTS_MS_LETTER_SOUNDS[k][1]; break; }
            if (two) { seg(S, &ns, 'C', snd ? snd : one); i += 2; continue; }
            if (c == 'a' || c == 'i' || c == 'u' || c == 'o') seg(S, &ns, 'V', one);
            else if (c == 0xE9) seg(S, &ns, 'V', "e");
            else if (c == 'e') seg(S, &ns, 'V', "E");
            else if (c == '\'') seg(S, &ns, 'C', "?");
            else if (c == 'x') { if (i) seg(S, &ns, 'C', "k"); seg(S, &ns, 'C', "s"); }
            else if (i && c == w[i - 1] && !in_u8(c, VTTS_ID_VOWELS) && !(i >= 2 && w[i - 2] == 'n' && w[i - 1] == 'g')) { }
            else seg(S, &ns, 'C', snd ? snd : one);
            i++;
            continue;
        }
#endif
        if ((c == 'n' && (nx == 'g' || nx == 'y')) || (c == 's' && nx == 'y') || (c == 'k' && nx == 'h')) {
            one[0] = (char)c;
            one[1] = (char)nx;
            seg(S, &ns, 'C', one);
            i += 2;
            continue;
        }
        if (c == 'a' || c == 'i' || c == 'u' || c == 'o') { one[0] = (char)c; seg(S, &ns, 'V', one); }
        else if (c == 0xE9) seg(S, &ns, 'V', "e");
        else if (c == 'e') seg(S, &ns, 'V', "E");
        else if (c == '\'') seg(S, &ns, 'C', "?");
        else if (c == 'x') { if (i) seg(S, &ns, 'C', "k"); seg(S, &ns, 'C', "s"); }
        else if (i && c == w[i - 1] && !in_u8(c, VTTS_ID_VOWELS)) { }
        else { one[0] = (char)(c == 'v' ? 'f' : c == 'q' ? 'k' : c); seg(S, &ns, 'C', one); }
        i++;
    }
    if (ns && S[ns - 1].kind == 'C' && strcmp(S[ns - 1].ph, "k") == 0) strcpy(S[ns - 1].ph, "?");
    /* _resolve_e */
    int lastv = -1;
    for (int k = 0; k < ns; k++) if (S[k].kind == 'V') lastv = k;
    int kese = eq_u8(w, n, "ke") || eq_u8(w, n, "se");
    for (int k = 0; k < ns; k++) {
        if (S[k].kind != 'V' || strcmp(S[k].ph, "E") != 0) continue;
        int prefix = malay && k == 1 && n >= 3 && (w[0] == 'k' || w[0] == 's') && w[1] == 'e' &&
                     (w[2] == 'a' || w[2] == 'i' || w[2] == 'o' || w[2] == 'u'); /* seorang, keadaan */
        if (explicit_ || kese || prefix) { strcpy(S[k].ph, "@"); continue; }
        int next_v = (k > 0 && S[k - 1].kind == 'V') || (k + 1 < ns && S[k + 1].kind == 'V');
        int last = k == lastv, open_end = last && k + 1 == ns, closed_end = last && k + 1 < ns && strcmp(S[ns - 1].ph, "r") != 0;
        strcpy(S[k].ph, next_v || open_end || closed_end ? "e" : "@");
    }
    if (ns >= 2 && S[ns - 1].kind == 'V' && S[ns - 2].kind == 'V') {
        char two[8];
        strcpy(two, S[ns - 2].ph);
        strcat(two, S[ns - 1].ph);
        if (!strcmp(two, "ai") || !strcmp(two, "au") || !strcmp(two, "oi") || !strcmp(two, "ei")) {
            S[ns - 1].kind = 'C';
            strcpy(S[ns - 1].ph, S[ns - 1].ph[0] == 'i' ? "y" : "w");
        }
    }
    int stress = -1, last = -1, prev = -1, cnt = 0;
    for (int k = 0; k < ns; k++) if (S[k].kind == 'V') { prev = last; last = k; cnt++; }
    if (cnt && !unstressed(L, w, n)) {
        stress = cnt == 1 ? last : prev;
        if (!strcmp(S[stress].ph, "@")) stress = last;
        if (!strcmp(S[stress].ph, "@")) stress = -1;
    }
    for (int k = 0; k < ns; k++) emit_ph(e, S[k].ph, 0, k == stress);
}

/* ---- Portuguese (g2p_pt.phonemes) ---- */

static int pt_vl(uint32_t c) { return c && in_u8(c, VTTS_PT_VOWEL_LETTERS); }
static int pt_front(uint32_t c) { return !c || in_u8(c, VTTS_PT_FRONT); } /* Python: "" in FRONT */

static void pt_vowel(seg_t *S, int *ns, uint32_t c) {
    char one[4] = {(char)c, 0, 0, 0};
    uint8_t acc = 0;
    for (int k = 0; k < VTTS_PT_N_BASE; k++)
        if (VTTS_PT_BASE[k].cp == c) { one[0] = VTTS_PT_BASE[k].base; acc = VTTS_PT_BASE[k].accent; }
    seg(S, ns, 'V', one);
    S[*ns - 1].acc = acc;
    S[*ns - 1].dia = c == 0xFC;
}

static void pt_phonemes(emit_t *e, const uint32_t *word, int wn, uint32_t *w, seg_t *S, seg_t *O) {
    const vtts_lt_lang *L = e->L;
    int n = fold_word(L, VTTS_LT_PT, word, wn, w), ns = 0, m = 0;
    const char *r = override(L, w, n);
    if (r) n = fold_u8(L, VTTS_LT_PT, r, w);
    if (!n) return;
    for (int i = 0; i < n;) {
        uint32_t c = w[i], nx = AT_(i + 1), nx2 = AT_(i + 2);
        int step = 1;
        char one[4] = {0};
        if (pt_vl(c) || c == 'y') pt_vowel(S, &ns, c == 'y' ? 'i' : c);
        else if (c == 'c') {
            if (nx == 'h') { seg(S, &ns, 'C', "sh"); step = 2; }
            else seg(S, &ns, 'C', pt_front(nx) ? "s" : "k");
        } else if (c == 0xE7) seg(S, &ns, 'C', "s");
        else if (c == 'g' || c == 'q') {
            if (c == 'g' && pt_front(nx)) seg(S, &ns, 'C', "zh");
            else {
                seg(S, &ns, 'C', c == 'g' ? "g" : "k");
                if (nx == 'u' && pt_front(nx2)) step = 2;
                else if (nx == 0xFC || (nx == 'u' && pt_vl(nx2))) { seg(S, &ns, 'G', "w"); step = 2; }
            }
        } else if (c == 'h') {
        } else if (c == 'j') seg(S, &ns, 'C', "zh");
        else if (c == 'l' && nx == 'h') { seg(S, &ns, 'C', "lh"); step = 2; }
        else if (c == 'n' && nx == 'h') { seg(S, &ns, 'C', "nh"); step = 2; }
        else if (c == 'r') {
            if (nx == 'r') { seg(S, &ns, 'C', "rr"); step = 2; }
            else {
                uint32_t pv = AT_(i - 1);
                int strong = i == 0 || pv == 'n' || pv == 'l' || pv == 's' || !pt_vl(nx);
                seg(S, &ns, 'C', strong ? "rr" : "r");
            }
        } else if (c == 's') {
            if (nx == 's' || (nx == 'c' && pt_front(nx2)) || nx == 0xE7) { seg(S, &ns, 'C', "s"); step = 2; }
            else if (pt_vl(AT_(i - 1)) && pt_vl(nx)) seg(S, &ns, 'C', "z");
            else seg(S, &ns, 'C', "s");
        } else if (c == 'x') {
            if (i == 0) seg(S, &ns, 'C', "sh");
            else if (nx == 'c' && pt_front(nx2)) { seg(S, &ns, 'C', "s"); step = 2; }
            else if (i == 1 && (w[0] == 'e' || w[0] == 0xE9 || w[0] == 0xEA)) seg(S, &ns, 'C', pt_vl(nx) ? "z" : "s");
            else if (!nx) { seg(S, &ns, 'C', "k"); seg(S, &ns, 'C', "s"); }
            else if (!pt_vl(nx)) seg(S, &ns, 'C', "s");
            else seg(S, &ns, 'C', "sh");
        } else if (c == 'z') seg(S, &ns, 'C', pt_vl(nx) ? "z" : "s");
        else if (c == 'w') seg(S, &ns, 'G', "w");
        else { one[0] = (char)c; seg(S, &ns, 'C', one); }
        i += step;
    }
    /* _nasalize */
    for (int k = 0; k < ns;) {
        seg_t s = S[k];
        const seg_t *nx = k + 1 < ns ? &S[k + 1] : NULL, *af = k + 2 < ns ? &S[k + 2] : NULL;
        if (s.kind == 'V' && s.acc == 3) {
            s.dia = 0;
            s.nas = 1;
            O[m++] = s;
            if (nx && nx->kind == 'V' && nx->acc == 0 && (nx->ph[0] == 'o' || nx->ph[0] == 'e')) {
                seg(O, &m, 'G', nx->ph[0] == 'o' ? "w" : "j");
                k++;
            }
            k++;
            continue;
        }
        if (s.kind == 'V' && nx && nx->kind == 'C' && (!strcmp(nx->ph, "m") || !strcmp(nx->ph, "n")) && (!af || af->kind == 'C')) {
            s.nas = 1;
            O[m++] = s;
            int rest_ok = k + 2 == ns || (k + 3 == ns && S[k + 2].kind == 'C' && !strcmp(S[k + 2].ph, "s"));
            if (rest_ok && (s.ph[0] == 'a' || s.ph[0] == 'e') && (s.ph[0] == 'e' || !strcmp(nx->ph, "m")))
                seg(O, &m, 'G', s.ph[0] == 'a' ? "w" : "j");
            k += 2;
            continue;
        }
        O[m++] = s;
        k++;
    }
    /* _glides */
    for (int k = 1; k < m; k++) {
        seg_t *s = &O[k];
        if (!(s->kind == 'V' && (s->ph[0] == 'i' || s->ph[0] == 'u') && s->acc == 0 && !s->dia && !s->nas && O[k - 1].kind == 'V')) continue;
        const seg_t *nx = k + 1 < m ? &O[k + 1] : NULL, *nx2 = k + 2 < m ? &O[k + 2] : NULL;
        if (nx && nx->kind == 'C' && (!strcmp(nx->ph, "nh") || ((!strcmp(nx->ph, "rr") || !strcmp(nx->ph, "r") || !strcmp(nx->ph, "l")) && (!nx2 || nx2->kind == 'C'))))
            continue;
        s->kind = 'G';
        strcpy(s->ph, s->ph[0] == 'i' ? "j" : "w");
    }
    /* _stress */
    int stress = -1, last = -1, prev = -1, cnt = 0, marked = -1, tilde = -1;
    for (int k = 0; k < m; k++)
        if (O[k].kind == 'V') {
            prev = last;
            last = k;
            cnt++;
            if (O[k].acc == 1 || O[k].acc == 2) marked = k;
            if (O[k].acc == 3) tilde = k;
        }
    if (cnt && !unstressed(L, w, n)) {
        static const char *const PEN[] = {"a", "e", "o", "as", "es", "os", "am", "em", "ens"};
        int pen = 0;
        for (int k = 0; k < 9; k++) pen |= ends_with(w, n, PEN[k]);
        stress = marked >= 0 ? marked : tilde >= 0 ? tilde : cnt == 1 ? last : pen ? prev : last;
    }
    for (int k = 0; k < m; k++) {
        seg_t *s = &O[k];
        if (s->kind != 'V') { emit_ph(e, s->ph, 0, 0); continue; }
        char v[4] = {s->ph[0], 0, 0, 0};
        if (k == stress) {
            if (!s->nas) { /* _quality */
                if (s->acc == 1) { if (v[0] == 'e' || v[0] == 'o') v[0] = (char)(v[0] - 32); }
                else if (s->acc != 2 && v[0] == 'e' && (ends_with(w, n, "el") || ends_with(w, n, "els") || ends_with(w, n, "ela") || ends_with(w, n, "elas"))) v[0] = 'E';
                else if (s->acc != 2 && v[0] == 'o' && (ends_with(w, n, "ol") || ends_with(w, n, "ols") || ends_with(w, n, "osa") || ends_with(w, n, "osas") || ends_with(w, n, "osos"))) v[0] = 'O';
            }
            emit_ph(e, v, s->nas, 1);
            continue;
        }
        if (!s->nas && (v[0] == 'e' || v[0] == 'o') && k == last) {
            int all_s = 1;
            for (int q = k + 1; q < m; q++) all_s &= O[q].kind == 'C' && !strcmp(O[q].ph, "s");
            if (all_s) v[0] = v[0] == 'e' ? 'i' : 'u';
        }
        emit_ph(e, v, s->nas, 0);
    }
}

#undef AT_

/* word_tokens_es / _id / _pt */
int vtts_lt_word_ids(int lang, const uint32_t *w, int n, uint32_t *scratch, uint8_t *out, int cap) {
    if (lang < 0 || lang > LT_LAST) return 0;
    const vtts_lt_lang *L = lt_lang(lang);
    uint32_t *f1 = scratch, *f2 = scratch + VTTS_LT_MAXW, *f3 = scratch + 2 * VTTS_LT_MAXW;
    seg_t *S = (seg_t *)(void *)(scratch + 3 * VTTS_LT_MAXW), *O = S + VTTS_LT_MAXW;
    emit_t e = {L, out, 0, cap};
    if (n > VTTS_LT_MAXW / 2) n = VTTS_LT_MAXW / 2; /* x reads as two sounds: segments <= 2 letters */
    int n1 = fold_word(L, lang, w, n, f1), vowel = 0;
    for (int i = 0; i < n1; i++) {
        uint32_t c = f1[i];
        vowel |= lang == VTTS_LT_ES ? in_u8(c, VTTS_ES_VOWELS) || c == 'y'
               : IDL(lang) ? in_u8(c, VTTS_ID_VOWELS)
                                    : pt_vl(c) || c == 'y';
    }
    if (n1 && !vowel) { /* spelled letter by letter */
        for (int i = 0; i < n1; i++) {
            const char *name = letter_name(L, f1[i]);
            while (name && *name) {
                uint32_t pc[32];
                int pn = 0;
                while (*name == ' ') name++;
                const char *sp = strchr(name, ' ');
                char piece[64];
                size_t l = sp ? (size_t)(sp - name) : strlen(name);
                if (!l || l >= sizeof piece) break;
                memcpy(piece, name, l);
                piece[l] = 0;
                pn = u8_decode(piece, pc, 32);
                if (lang == VTTS_LT_ES) es_phonemes(&e, pc, pn, f2, S);
                else if (IDL(lang)) id_phonemes(&e, pc, pn, f2, f3, S);
                else pt_phonemes(&e, pc, pn, f2, S, O);
                name += l;
            }
        }
        return e.n;
    }
    if (lang == VTTS_LT_ES) es_phonemes(&e, w, n, f2, S);
    else if (IDL(lang)) id_phonemes(&e, w, n, f2, f3, S);
    else pt_phonemes(&e, w, n, f2, S, O);
    return e.n;
}

#endif /* VTTS_ENABLE_LT */
