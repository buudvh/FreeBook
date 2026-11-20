/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_hi.c -- Hindi front-end of the device (token set hi-en): Devanagari letters to phonemes
 * with the nasal and schwa-deletion rules and the exception table (mirrors
 * src/vtts/frontend/hi/g2p_hi.py), and normalization (mirrors src/vtts/frontend/hi/normalize_hi.py).
 * All tables are in the generated vtts_text_tables.h; no blob is needed. */
#include "vtts_langs.h"
#if VTTS_ENABLE_HI /* else an empty unit (vtts_langs.h) */

#include "vtts_text_hi.h"

#include <string.h>

#include "vtts_text_en.h"
#include "vtts_text_tables.h"

enum { K_LETTER = 1, K_VOWEL, K_MATRA, K_ANUSVARA, K_CANDRA, K_VISARGA, K_VIRAMA, K_NUKTA, K_OM, K_PRECOMP };

#define VIRAMA 0x094Du
#define NUKTA 0x093Cu
#define NONE 255

static const uint8_t *char_info(uint32_t c) { return c >= 0x900 && c <= 0x97F ? VTTS_HI_CHARS[c - 0x900] : NULL; }
static int kind_of(uint32_t c) { const uint8_t *t = char_info(c); return t ? t[0] : 0; }

int vtts_hi_is_devanagari(uint32_t c) { return (c >= 0x900 && c <= 0x97F) || (c >= 0xA8E0 && c <= 0xA8FF); }

int vtts_hi_has_devanagari(const uint32_t *w, int n) {
    for (int i = 0; i < n; i++)
        if (vtts_hi_is_devanagari(w[i]) && w[i] != 0x964 && w[i] != 0x965 && !(w[i] >= 0x966 && w[i] <= 0x96F)) return 1;
    return 0;
}

static int dec1(const char *s, uint32_t *c) { /* one UTF-8 sequence (valid input: the tables) */
    const unsigned char *p = (const unsigned char *)s;
    if (!p[0]) return 0;
    if (p[0] < 0x80) { *c = p[0]; return 1; }
    int extra = (p[0] >> 5) == 6 ? 1 : (p[0] >> 4) == 14 ? 2 : 3;
    uint32_t v = p[0] & (0x3Fu >> extra);
    for (int k = 1; k <= extra; k++) v = (v << 6) | (p[k] & 0x3F);
    *c = v;
    return extra + 1;
}

/* the whole of w equals the UTF-8 string k */
static int equals(const uint32_t *w, int n, const char *k) {
    int m = 0, l;
    uint32_t c;
    while ((l = dec1(k, &c)) > 0) {
        if (m >= n || w[m] != c) return 0;
        m++;
        k += l;
    }
    return m == n;
}

int vtts_hi_latin_word(const uint32_t *w, int n) {
    for (int k = 0; k < VTTS_HI_N_LATIN_WORDS; k++) if (equals(w, n, VTTS_HI_LATIN_WORDS[k])) return 1;
    return 0;
}

/* ======================= NFC ======================= */

static int ccc(uint32_t c) { /* canonical combining class; 0 outside the generated ranges */
    if (!((c >= 0x300 && c <= 0x36F) || vtts_hi_is_devanagari(c))) return 0;
    for (int k = 0; k < VTTS_HI_N_CCC; k++) if (VTTS_HI_CCC[k].cp == c) return VTTS_HI_CCC[k].ccc;
    return 0;
}

static uint32_t singleton(uint32_t c) { /* NFC singleton decompositions that matter here */
    switch (c) {
    case 0x0340: return 0x0300;
    case 0x0341: return 0x0301;
    case 0x0343: return 0x0313;
    case 0x037E: return ';';
    case 0x0387: return 0x00B7;
    case 0x2000: return 0x2002;
    case 0x2001: return 0x2003;
    case 0x2126: return 0x03A9;
    case 0x212A: return 'K';
    case 0x212B: return 0x00C5;
    default: return c;
    }
}

/* unicodedata.normalize("NFC") for Devanagari (nukta letters, mark order) and a few singletons;
 * compose = 0 leaves the nukta letters decomposed (the form the g2p reads). Latin letters with
 * separate combining marks are not composed. Returns the length, or -1 when cap is too small. */
static int deva_nfc(const uint32_t *s, int n, uint32_t *o, int cap, int compose) {
    int m = 0;
    for (int i = 0; i < n; i++) {
        uint32_t c = singleton(s[i]);
        if (kind_of(c) == K_PRECOMP) {
            if (m + 2 > cap) return -1;
            o[m++] = 0x900 + char_info(c)[1];
            o[m++] = NUKTA;
            continue;
        }
        if (m >= cap) return -1;
        o[m++] = c;
    }
    for (int i = 1; i < m; i++) { /* canonical ordering: stable insertion sort of each run of marks */
        int cc = ccc(o[i]);
        if (!cc) continue;
        for (int j = i; j > 0 && ccc(o[j - 1]) > cc; j--) { uint32_t t = o[j]; o[j] = o[j - 1]; o[j - 1] = t; }
    }
    if (!compose) return m;
    for (int i = 0; i < m; i++) { /* न र ळ + nukta -> ऩ ऱ ऴ (the other nukta letters are excluded) */
        if (o[i] != 0x928 && o[i] != 0x930 && o[i] != 0x933) continue;
        int k = i + 1;
        while (k < m && o[k] != NUKTA && ccc(o[k]) > 0 && ccc(o[k]) < 7) k++;
        if (k < m && o[k] == NUKTA) {
            o[i] += 1;
            memmove(o + k, o + k + 1, sizeof *o * (size_t)(m - k - 1));
            m--;
        }
    }
    return m;
}

/* ======================= phonemes (g2p_hi.phonemes) ======================= */

/* a segment: phoneme index | V << 8 | inherent << 9 | sign << 10 */
#define S_V 0x100u
#define S_INH 0x200u
enum { SIGN_NONE = 0, SIGN_ANUSVARA, SIGN_CANDRA, SIGN_VISARGA, SIGN_KEPT };
#define PH(s) ((s) & 0xFFu)
#define SIGN(s) (((s) >> 10) & 7u)
#define WITH_SIGN(s, g) (((s) & ~(7u << 10)) | ((uint32_t)(g) << 10))

static int ph_index(const char *name) {
    for (int k = 0; k < VTTS_HI_N_PHONEMES; k++) if (strcmp(VTTS_HI_PHONEMES[k], name) == 0) return k;
    return 0;
}

typedef struct { uint32_t *p; int n, cap; } segs_t;

static void seg(segs_t *g, uint32_t s) { if (g->n < g->cap) g->p[g->n++] = s; }

static void vowel(segs_t *g, const uint8_t *t, int inherent) { /* t[1] consonant or NONE, t[2] vowel */
    if (t[1] != NONE) seg(g, t[1]);
    seg(g, t[2] | S_V | (inherent ? S_INH : 0));
}

static int is_v(uint32_t s) { return (s & S_V) != 0; }

static void parse(const uint32_t *ch, int n, segs_t *g) { /* _parse; ch: NFC, nukta letters decomposed */
    static const uint8_t SCHWA[3] = {0, NONE, 0};
    const int G = ph_index("g"), Y = ph_index("y"), H = ph_index("h"), O = ph_index("o"), M = ph_index("m");
    for (int i = 0; i < n;) {
        const uint8_t *t = char_info(ch[i]);
        int kind = t ? t[0] : 0;
        if (kind == K_LETTER) {
            uint32_t c = ch[i];
            int nk = i + 1 < n && ch[i + 1] == NUKTA;
            i += 1 + nk;
            if (c == 0x91C && !nk && i + 1 < n && ch[i] == VIRAMA && ch[i + 1] == 0x91E) { /* ज्ञ */
                seg(g, (uint32_t)G);
                seg(g, (uint32_t)Y);
                i += 2;
            } else {
                seg(g, nk ? t[3] : t[1]);
            }
            if (i < n && ch[i] == VIRAMA) {
                i++;
            } else if (i < n && kind_of(ch[i]) == K_MATRA) {
                vowel(g, char_info(ch[i]), 0);
                i++;
            } else {
                vowel(g, SCHWA, 1);
            }
            continue;
        }
        if (kind == K_VOWEL) {
            vowel(g, t, 0);
        } else if (kind == K_ANUSVARA || kind == K_CANDRA) {
            if (g->n && is_v(g->p[g->n - 1])) g->p[g->n - 1] = WITH_SIGN(g->p[g->n - 1], kind == K_ANUSVARA ? SIGN_ANUSVARA : SIGN_CANDRA);
        } else if (kind == K_VISARGA) {
            if (g->n && is_v(g->p[g->n - 1]) && !SIGN(g->p[g->n - 1])) g->p[g->n - 1] = WITH_SIGN(g->p[g->n - 1], SIGN_VISARGA);
            seg(g, (uint32_t)H);
        } else if (kind == K_OM) {
            seg(g, (uint32_t)O | S_V);
            seg(g, (uint32_t)M);
        }
        i++;
    }
}

/* _nasals: anusvara after a short vowel before a stop -> that stop's nasal (the vowel keeps a sign
 * that is not a nasalization); the decisions use the segments before any insertion */
static void nasals(segs_t *g) {
    int add = 0, n = g->n;
    for (int k = 0; k + 1 < n; k++) { /* mark: bit 13, the nasal in bits 16..23 */
        uint32_t s = g->p[k], nx = g->p[k + 1];
        if (is_v(s) && SIGN(s) == SIGN_ANUSVARA && VTTS_HI_SHORT[PH(s)] && !is_v(nx) && VTTS_HI_HOMORGANIC[PH(nx)] != NONE) {
            g->p[k] = WITH_SIGN(s, SIGN_KEPT) | (1u << 13) | ((uint32_t)VTTS_HI_HOMORGANIC[PH(nx)] << 16);
            add++;
        }
    }
    for (int k = n - 1, w = n + add; k >= 0; k--) { /* insert from the back (w >= k: nothing unread is overwritten) */
        uint32_t s = g->p[k];
        if (s & (1u << 13)) {
            if (--w < g->cap) g->p[w] = s >> 16;
            s &= 0x1FFFu;
        }
        if (--w < g->cap) g->p[w] = s;
    }
    g->n = n + add < g->cap ? n + add : g->cap; /* cut (words longer than the scratch) */
}

static int deletable(uint32_t s) { return is_v(s) && (s & S_INH) && !SIGN(s); }

static void delete_schwas(segs_t *g) {
    uint32_t *p = g->p;
    int n = g->n, vowels = 0;
    for (int k = 0; k < n; k++) vowels += is_v(p[k]);
    if (n >= 2 && deletable(p[n - 1]) && vowels > 1 && !(n >= 3 && !is_v(p[n - 3]) && VTTS_HI_FINAL_KEEP[PH(p[n - 2])]))
        n--;
    for (int k = n - 3; k > 1; k--) {
        if (deletable(p[k]) && !is_v(p[k - 1]) && is_v(p[k - 2]) && !is_v(p[k + 1]) && is_v(p[k + 2])) {
            memmove(p + k, p + k + 1, sizeof *p * (size_t)(n - k - 1));
            n--;
        }
    }
    g->n = n;
}

int vtts_hi_word_ids(const uint32_t *w, int n, uint32_t *chars, int chars_cap, uint32_t *segs, int segs_cap,
                     uint8_t *out, int cap) {
    int m = deva_nfc(w, n, chars, chars_cap, 0), k = 0;
    if (m < 0) { /* cut */
        int cut = n;
        while (cut > 0 && (m = deva_nfc(w, cut, chars, chars_cap, 0)) < 0) cut /= 2;
        if (m < 0) return 0;
    }
    for (int e = 0; e < VTTS_HI_N_OVERRIDES; e++) {
        if (!equals(chars, m, VTTS_HI_OVERRIDES[e].word)) continue;
        for (int i = 0; i < VTTS_HI_OVERRIDES[e].n && k < cap; i++) out[k++] = (uint8_t)(VTTS_HIEN_HI0 + VTTS_HI_OVERRIDES[e].ph[i]);
        return k;
    }
    segs_t g = {segs, 0, segs_cap / 2};
    parse(chars, m, &g);
    g.cap = segs_cap;
    nasals(&g);
    delete_schwas(&g);
    for (int i = 0; i < g.n && k < cap; i++) {
        uint32_t s = g.p[i];
        out[k++] = (uint8_t)(VTTS_HIEN_HI0 + PH(s));
        if (is_v(s) && (SIGN(s) == SIGN_ANUSVARA || SIGN(s) == SIGN_CANDRA) && k < cap)
            out[k++] = (uint8_t)(VTTS_HIEN_HI0 + VTTS_HI_PH_NASAL);
    }
    return k;
}

/* ======================= normalization (normalize_hi) =======================
 * Each regex pass of the Python normalizer is one function from buffer s (n code points) to buffer
 * d; matches are found left to right without overlap, like re.sub, and lookarounds look at the
 * pass's input. Where backtracking can change a match, the candidates are tried in the order the
 * regex engine tries them. */

typedef struct { uint32_t *p; int n, cap, err; } kb_t;
typedef struct { uint32_t *a, *b; int cap; char *out; int out_cap; } scratch_t;

static void put(kb_t *d, uint32_t c) { if (d->n < d->cap) d->p[d->n++] = c; else d->err = 1; }
static void put_utf8(kb_t *d, const char *s) {
    uint32_t c;
    int l;
    while ((l = dec1(s, &c)) > 0) { put(d, c); s += l; }
}
static void put_cps(kb_t *d, const uint32_t *s, int n) { for (int i = 0; i < n; i++) put(d, s[i]); }

static int hi_w(uint32_t c) { /* Python \w */
    if (c >= 0x900 && c <= 0x97F) return VTTS_HI_WORD_BITS[(c - 0x900) >> 3] >> ((c - 0x900) & 7) & 1;
    if (c >= 0xA8E0 && c <= 0xA8FF) return VTTS_HI_WORD_BITS[(128 + c - 0xA8E0) >> 3] >> ((128 + c - 0xA8E0) & 7) & 1;
    return vtts_cp_is_word(c);
}

static int DG(const uint32_t *s, int n, int i) { return i >= 0 && i < n && s[i] >= '0' && s[i] <= '9'; }
static int W(const uint32_t *s, int n, int i) { return i >= 0 && i < n && hi_w(s[i]); }
static int DV(const uint32_t *s, int n, int i) { return i >= 0 && i < n && s[i] >= 0x900 && s[i] <= 0x97F; } /* [ऀ-ॿ] */
static int SP(const uint32_t *s, int n, int i) { return i >= 0 && i < n && vtts_cp_is_space(s[i]); }
static int AT(const uint32_t *s, int n, int i, uint32_t c) { return i >= 0 && i < n && s[i] == c; }
static int UP(const uint32_t *s, int n, int i) { return i >= 0 && i < n && s[i] >= 'A' && s[i] <= 'Z'; }
static int digit_run(const uint32_t *s, int n, int i) { int j = i; while (DG(s, n, j)) j++; return j - i; }
static int no_wdc(const uint32_t *s, int n, int i) { return !W(s, n, i) && !AT(s, n, i, '.') && !AT(s, n, i, ','); } /* (?<![\w.,]) */

/* UTF-8 key at s[i]: its length in code points, or 0 */
static int key_at(const uint32_t *s, int n, int i, const char *k) {
    int m = 0, l;
    uint32_t c;
    while ((l = dec1(k, &c)) > 0) {
        if (i + m >= n || s[i + m] != c) return 0;
        m++;
        k += l;
    }
    return m;
}

/* ---- numbers ---- */

static void nw(kb_t *d, int v) { put_utf8(d, VTTS_HI_NUMBERS[v]); }

static void card_i(kb_t *d, long long v) { /* cardinal(), v < 10**15 */
    static const long long SC[4] = {10000000LL, 100000LL, 1000LL, 100LL};
    if (v < 100) { nw(d, (int)v); return; }
    int first = 1;
    for (int k = 0; k < 4; k++) {
        long long q = v / SC[k];
        v %= SC[k];
        if (!q) continue;
        if (!first) put(d, ' ');
        card_i(d, q);
        put(d, ' ');
        put_utf8(d, VTTS_HI_SCALES[k]);
        first = 0;
    }
    if (v) { put(d, ' '); nw(d, (int)v); }
}

static void digit_names(kb_t *d, const uint32_t *s, int n) { /* digits(): names joined by spaces */
    int first = 1;
    for (int i = 0; i < n; i++) {
        if (s[i] < '0' || s[i] > '9') continue;
        if (!first) put(d, ' ');
        nw(d, (int)(s[i] - '0'));
        first = 0;
    }
}

/* cardinal(int(s)) for ASCII digits (commas skipped); >= 10**15 digit by digit */
static void card_span(kb_t *d, const uint32_t *s, int n) {
    int i = 0, len = 0;
    while (i < n && (s[i] == '0' || s[i] == ',')) i++;
    for (int k = i; k < n; k++) len += s[k] != ',';
    if (len > 15) { digit_names(d, s + i, n - i); return; }
    long long v = 0;
    for (int k = i; k < n; k++) if (s[k] != ',') v = v * 10 + (s[k] - '0');
    card_i(d, v);
}

static long long small_value(const uint32_t *s, int n) { /* int(s), capped at 10**6 */
    long long v = 0;
    for (int i = 0; i < n; i++) if (s[i] >= '0' && s[i] <= '9') { v = v * 10 + (s[i] - '0'); if (v > 1000000) v = 1000000; }
    return v;
}

static void year(kb_t *d, int y) {
    if (y >= 1100 && y <= 1999) {
        card_i(d, y / 100);
        put(d, ' ');
        put_utf8(d, VTTS_HI_SAU);
        if (y % 100) { put(d, ' '); card_i(d, y % 100); }
        return;
    }
    card_i(d, y);
}

/* number(): '-' is माइनस, commas dropped, the decimals after दशमलव digit by digit */
static void number(kb_t *d, const uint32_t *s, int n) {
    int i = 0;
    if (n && s[0] == '-') { put_utf8(d, VTTS_HI_MINUS); i = 1; }
    int dot = i;
    while (dot < n && s[dot] != '.') dot++;
    card_span(d, s + i, dot - i);
    if (dot < n) {
        put_utf8(d, VTTS_HI_POINT);
        digit_names(d, s + dot + 1, n - dot - 1);
    }
}

/* NUM = \d{1,3}(?:,\d{2,3})+(?:\.\d+)?|\d+(?:\.\d+)? at i: the first end, in the regex's order,
 * for which ok() accepts the rest of the pattern; -1 if none. A group that leaves a digit behind
 * is never accepted by the callers (each rejects a digit right after the number, or takes the
 * first end), so the comma groups are greedy. */
typedef int (*end_ok)(const uint32_t *s, int n, int end, void *u);

static int try_frac(const uint32_t *s, int n, int b, end_ok ok, void *u) {
    if (AT(s, n, b, '.') && DG(s, n, b + 1))
        for (int k = digit_run(s, n, b + 1); k >= 1; k--) if (ok(s, n, b + 1 + k, u)) return b + 1 + k;
    return ok(s, n, b, u) ? b : -1;
}

static int num_match(const uint32_t *s, int n, int i, end_ok ok, void *u) {
    if (!DG(s, n, i)) return -1;
    int r = digit_run(s, n, i), e;
    if (r <= 3) {
        int k = i + r, g = 0;
        while (AT(s, n, k, ',') && digit_run(s, n, k + 1) >= 2) {
            int gl = digit_run(s, n, k + 1) >= 3 ? 3 : 2;
            k += 1 + gl;
            g++;
        }
        for (; g >= 1; g--) { /* end of group g, then back to the end of group g - 1 */
            if ((e = try_frac(s, n, k, ok, u)) >= 0) return e;
            k = AT(s, n, k - 3, ',') ? k - 3 : k - 4;
        }
    }
    for (int k = r; k >= 1; k--) if ((e = try_frac(s, n, i + k, ok, u)) >= 0) return e;
    return -1;
}

static int always(const uint32_t *s, int n, int end, void *u) { (void)s; (void)n; (void)end; (void)u; return 1; }
static int not_digit(const uint32_t *s, int n, int end, void *u) { (void)u; return !DG(s, n, end); }

/* ---- passes, in the order of normalize_hi ---- */

static void p_digits(const uint32_t *s, int n, kb_t *d) { /* ०-९ -> 0-9, ॰ -> . */
    for (int i = 0; i < n; i++) {
        uint32_t c = s[i];
        if (c >= 0x966 && c <= 0x96F) c = '0' + (c - 0x966);
        else if (c == 0x970) c = '.';
        put(d, c);
    }
}

/* (?<![ऀ-ॿ\w])key -> " reading " per key, longest first (the keys end with '.' and their readings
 * hold none, so one pass trying the longest key first is the same) */
static void p_abbrev(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (!DV(s, n, i - 1) && !W(s, n, i - 1)) {
            int l = 0, k = 0;
            for (; k < VTTS_HI_N_ABBREV && !l; k++) l = key_at(s, n, i, VTTS_HI_ABBREV[k][0]);
            if (l) {
                put(d, ' ');
                put_utf8(d, VTTS_HI_ABBREV[k - 1][1]);
                put(d, ' ');
                i += l;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static void p_danda_drop(const uint32_t *s, int n, kb_t *d) { /* ॥ । -> " . ", DROP -> space */
    for (int i = 0; i < n; i++) {
        uint32_t c = s[i];
        if (c == 0x964 || c == 0x965) { put(d, ' '); put(d, '.'); put(d, ' '); continue; }
        for (int k = 0; k < VTTS_HI_N_DROP; k++) if (VTTS_HI_DROP[k] == c) { c = ' '; break; }
        put(d, c);
    }
}

/* _date: " d month [year] ", or 0 for an invalid day or month */
static int date_out(kb_t *d, int dd, int mm, const uint32_t *y, int yl) {
    if (!(dd >= 1 && dd <= 31 && mm >= 1 && mm <= 12)) return 0;
    put(d, ' ');
    card_i(d, dd);
    put(d, ' ');
    put_utf8(d, VTTS_HI_MONTHS[mm]);
    if (y) {
        put(d, ' ');
        year(d, (int)small_value(y, yl) + (yl == 2 ? 2000 : 0));
    }
    put(d, ' ');
    return 1;
}

/* (?<![\d-])(\d{4})-(\d{1,2})-(\d{1,2})(?![\d-]) */
static void p_date_iso(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (!DG(s, n, i - 1) && !AT(s, n, i - 1, '-') && digit_run(s, n, i) == 4 && AT(s, n, i + 4, '-')) {
            int m0 = i + 5, ml = digit_run(s, n, m0), d0 = m0 + ml + 1, dl = digit_run(s, n, d0);
            if (ml >= 1 && ml <= 2 && AT(s, n, m0 + ml, '-') && dl >= 1 && dl <= 2 && !AT(s, n, d0 + dl, '-')) {
                int end = d0 + dl;
                if (!date_out(d, (int)small_value(s + d0, dl), (int)small_value(s + m0, ml), s + i, 4)) put_cps(d, s + i, end - i);
                i = end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int dmy_sep(uint32_t c) { return c == '/' || c == '.' || c == '-'; }

/* (?<![\d/.-])(\d{1,2})([/.-])(\d{1,2})\2(\d{4}|\d{2})(?![\d/.-]) */
static void p_date_dmy(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i) && !DG(s, n, i - 1) && !(i > 0 && dmy_sep(s[i - 1]))) {
            int r1 = digit_run(s, n, i), p = i + r1;
            if (r1 <= 2 && p < n && dmy_sep(s[p])) {
                uint32_t sep = s[p];
                int r2 = digit_run(s, n, p + 1), q = p + 1 + r2;
                if (r2 >= 1 && r2 <= 2 && AT(s, n, q, sep)) {
                    int r3 = digit_run(s, n, q + 1), end = q + 1 + r3;
                    if ((r3 == 4 || r3 == 2) && !(end < n && dmy_sep(s[end]))) {
                        if (!date_out(d, (int)small_value(s + i, r1), (int)small_value(s + p + 1, r2), s + q + 1, r3))
                            put_cps(d, s + i, end - i);
                        i = end;
                        continue;
                    }
                }
            }
        }
        put(d, s[i++]);
    }
}

static int two(const uint32_t *s, int i) { return (int)(s[i] - '0') * 10 + (int)(s[i + 1] - '0'); }
static int not_dc(const uint32_t *s, int n, int i) { return !DG(s, n, i) && !AT(s, n, i, ':'); }
static int d05(const uint32_t *s, int n, int i) { return i >= 0 && i < n && s[i] >= '0' && s[i] <= '5'; }

/* (?<![\d:.])([01]?\d|2[0-4]):([0-5]\d)(?::([0-5]\d))?(?![\d:])(\s*बजे)? -> _time */
static void p_time(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i) && !DG(s, n, i - 1) && !AT(s, n, i - 1, ':') && !AT(s, n, i - 1, '.')) {
            int hl[3], nh = 0, done = 0;
            if ((s[i] == '0' || s[i] == '1') && DG(s, n, i + 1)) hl[nh++] = 2; /* [01]\d */
            hl[nh++] = 1;                                                    /* \d */
            if (s[i] == '2' && i + 1 < n && s[i + 1] >= '0' && s[i + 1] <= '4') hl[nh++] = 2; /* 2[0-4] */
            for (int c = 0; c < nh && !done; c++) {
                int j = i + hl[c];
                if (!(AT(s, n, j, ':') && d05(s, n, j + 1) && DG(s, n, j + 2))) continue;
                int k = j + 3, sec = -1, end = -1;
                if (AT(s, n, k, ':') && d05(s, n, k + 1) && DG(s, n, k + 2) && not_dc(s, n, k + 3)) {
                    sec = two(s, k + 1);
                    end = k + 3;
                } else if (not_dc(s, n, k)) {
                    end = k;
                }
                if (end < 0) continue;
                int e2 = end;
                while (SP(s, n, e2)) e2++;
                int bl = key_at(s, n, e2, VTTS_HI_BAJE);
                if (bl) end = e2 + bl;
                int h = hl[c] == 2 ? two(s, i) : (int)(s[i] - '0'), mi = two(s, j + 1);
                put(d, ' ');
                card_i(d, h);
                put(d, ' ');
                if (!mi) {
                    put_utf8(d, VTTS_HI_BAJE);
                } else {
                    put_utf8(d, VTTS_HI_BAJKAR);
                    put(d, ' ');
                    card_i(d, mi);
                    put(d, ' ');
                    put_utf8(d, VTTS_HI_MINUTE);
                }
                if (sec > 0) {
                    put(d, ' ');
                    card_i(d, sec);
                    put(d, ' ');
                    put_utf8(d, VTTS_HI_SECOND);
                }
                put(d, ' ');
                i = end;
                done = 1;
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

/* (सन्?|ईस्वी)\s+(\d{4})(?!\d) -> " prefix year " */
static void p_year(const uint32_t *s, int n, kb_t *d) {
    static const char *const PRE[3] = {VTTS_HI_SAN_H, VTTS_HI_SAN, VTTS_HI_ISVI};
    for (int i = 0; i < n;) {
        int done = 0;
        for (int k = 0; k < 3 && !done; k++) {
            int l = key_at(s, n, i, PRE[k]), j = i + l;
            if (!l || !SP(s, n, j)) continue;
            while (SP(s, n, j)) j++;
            if (digit_run(s, n, j) != 4) continue;
            put(d, ' ');
            put_utf8(d, PRE[k]);
            put(d, ' ');
            year(d, (int)small_value(s + j, 4));
            put(d, ' ');
            i = j + 4;
            done = 1;
        }
        if (done) continue;
        put(d, s[i++]);
    }
}

/* (?<![\wऀ-ॿ])(currency)\s?(NUM)(\s?(?:हज़ार|लाख|करोड़))? -> _money */
static void p_money(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        int done = 0;
        if (!W(s, n, i - 1) && !DV(s, n, i - 1)) {
            for (int k = 0; k < VTTS_HI_N_CURRENCY && !done; k++) {
                int l = key_at(s, n, i, VTTS_HI_CURRENCY[k][0]);
                if (!l) continue;
                int j = i + l, ns = j, e = -1;
                if (SP(s, n, j)) { ns = j + 1; e = num_match(s, n, ns, always, NULL); }
                if (e < 0) { ns = j; e = num_match(s, n, ns, always, NULL); }
                if (e < 0) continue;
                int sc = -1, se = e;
                for (int sp = SP(s, n, e); sp >= 0 && sc < 0; sp--)
                    for (int q = 0; q < VTTS_HI_N_MONEY_SCALES && sc < 0; q++) {
                        int ql = key_at(s, n, e + sp, VTTS_HI_MONEY_SCALES[q]);
                        if (ql) { sc = q; se = e + sp + ql; }
                    }
                const char *name = VTTS_HI_CURRENCY[k][1];
                const uint32_t *num = s + ns;
                int nn = e - ns, dot = 0;
                while (dot < nn && num[dot] != '.') dot++;
                int fl = dot < nn ? nn - dot - 1 : 0;
                if (strcmp(name, VTTS_HI_RUPAYE) == 0 && sc < 0 && (fl == 2 || dot == nn)) {
                    int one = small_value(num, dot) == 1;
                    put(d, ' ');
                    card_span(d, num, dot);
                    put(d, ' ');
                    put_utf8(d, one ? VTTS_HI_RUPAYA : VTTS_HI_RUPAYE);
                    if (fl == 2 && small_value(num + dot + 1, 2)) {
                        put(d, ' ');
                        card_span(d, num + dot + 1, 2);
                        put(d, ' ');
                        put_utf8(d, VTTS_HI_PAISE);
                    }
                    put(d, ' ');
                } else {
                    put(d, ' ');
                    number(d, num, nn);
                    if (sc >= 0) { put(d, ' '); put_utf8(d, VTTS_HI_MONEY_SCALES[sc]); }
                    put(d, ' ');
                    put_utf8(d, name);
                    put(d, ' ');
                }
                i = se;
                done = 1;
            }
        }
        if (done) continue;
        put(d, s[i++]);
    }
}

static int phone_sep(const uint32_t *s, int n, int i) { return SP(s, n, i) || AT(s, n, i, '-'); }

/* (?:[\s-]\d{2,5}){0,3}(?![\d.,]) after the main digits ending at e: the end, or -1 */
static int phone_tail(const uint32_t *s, int n, int e) {
    int ends[4], m = 0;
    ends[0] = e;
    while (m < 3 && phone_sep(s, n, ends[m])) {
        int r = digit_run(s, n, ends[m] + 1);
        if (r < 2 || r > 5) break;
        ends[m + 1] = ends[m] + 1 + r;
        m++;
    }
    int end = ends[m];
    if (!DG(s, n, end) && !AT(s, n, end, '.') && !AT(s, n, end, ',')) return end;
    return m > 0 ? ends[m - 1] : -1;
}

/* (?<![\d.,])(?:\+\d{1,3}[\s-]?)?\d{2,12}(?:[\s-]\d{2,5}){0,3}(?![\d.,]) -> _phone */
static void p_phone(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        int end = -1;
        if (!DG(s, n, i - 1) && !AT(s, n, i - 1, '.') && !AT(s, n, i - 1, ',')) {
            if (AT(s, n, i, '+')) {
                int r0 = digit_run(s, n, i + 1);
                for (int c = r0 < 3 ? r0 : 3; c >= 1 && end < 0; c--) {
                    int p = i + 1 + c;
                    if (c == r0 && phone_sep(s, n, p)) {
                        int l = digit_run(s, n, p + 1);
                        if (l >= 2 && l <= 12) end = phone_tail(s, n, p + 1 + l);
                        if (end >= 0) break;
                    }
                    int l = c < r0 ? r0 - c : 0;
                    if (l >= 2 && l <= 12) end = phone_tail(s, n, p + l);
                }
            } else if (DG(s, n, i)) {
                int l = digit_run(s, n, i);
                if (l >= 2 && l <= 12) end = phone_tail(s, n, i + l);
            }
        }
        if (end >= 0) {
            int nd = 0;
            for (int k = i; k < end; k++) nd += DG(s, n, k);
            if (nd < 10 && s[i] != '+') {
                put_cps(d, s + i, end - i);
            } else {
                put(d, ' ');
                if (s[i] == '+') put_utf8(d, VTTS_HI_PLUS);
                digit_names(d, s + i, end - i);
                put(d, ' ');
            }
            i = end;
            continue;
        }
        put(d, s[i++]);
    }
}

static int pct_ok(const uint32_t *s, int n, int end, void *u) { /* \s?% */
    int *pe = u;
    if (SP(s, n, end) && AT(s, n, end + 1, '%')) { *pe = end + 2; return 1; }
    if (AT(s, n, end, '%')) { *pe = end + 1; return 1; }
    return 0;
}

/* (?<![\w.,])(-?)(NUM)\s?% -> " number प्रतिशत " */
static void p_percent(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (no_wdc(s, n, i - 1)) {
            int j = i + AT(s, n, i, '-'), pe = 0;
            int e = num_match(s, n, j, pct_ok, &pe);
            if (e >= 0) {
                put(d, ' ');
                number(d, s + i, e - i);
                put(d, ' ');
                put_utf8(d, VTTS_HI_PERCENT);
                put(d, ' ');
                i = pe;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

typedef struct { int unit, end; } unit_m;

static int unit_ok(const uint32_t *s, int n, int end, void *u) { /* \s?(units)(?![\w]) */
    unit_m *m = u;
    for (int sp = SP(s, n, end); sp >= 0; sp--) {
        int p = end + sp;
        for (int k = 0; k < VTTS_HI_N_UNITS; k++) {
            int l = key_at(s, n, p, VTTS_HI_UNITS[k][0]);
            if (l && !W(s, n, p + l)) { m->unit = k; m->end = p + l; return 1; }
        }
    }
    return 0;
}

/* (?<![\w.,])(-?)(NUM)\s?(units)(?![\w]) -> " number unit " */
static void p_unit(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (no_wdc(s, n, i - 1)) {
            int j = i + AT(s, n, i, '-');
            unit_m m;
            int e = num_match(s, n, j, unit_ok, &m);
            if (e >= 0) {
                put(d, ' ');
                number(d, s + i, e - i);
                put(d, ' ');
                put_utf8(d, VTTS_HI_UNITS[m.unit][1]);
                put(d, ' ');
                i = m.end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![\w])(\d+)\s?(वाँ|वां|वीं|वी|वें|वे)(?![ऀ-ॿ]) -> _ordinal */
static void p_ordinal(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i) && !W(s, n, i - 1)) {
            int r = digit_run(s, n, i), j = i + r, hit = -1, end = 0;
            for (int sp = SP(s, n, j); sp >= 0 && hit < 0; sp--)
                for (int k = 0; k < VTTS_HI_N_ORD_ENDINGS && hit < 0; k++) {
                    int l = key_at(s, n, j + sp, VTTS_HI_ORD_ENDINGS[k][0]);
                    if (l && !DV(s, n, j + sp + l)) { hit = k; end = j + sp + l; }
                }
            if (hit >= 0) {
                long long v = small_value(s + i, r);
                const char *stem = NULL;
                for (int k = 0; k < VTTS_HI_N_ORD_STEMS; k++) if (VTTS_HI_ORD_STEMS[k].n == v) stem = VTTS_HI_ORD_STEMS[k].stem;
                put(d, ' ');
                if (stem) {
                    put_utf8(d, stem);
                    put_utf8(d, VTTS_HI_ORD_ENDINGS[hit][1]);
                } else {
                    card_span(d, s + i, r);
                    put_utf8(d, VTTS_HI_ORD_ENDINGS[hit][0]);
                }
                put(d, ' ');
                i = end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int dash(const uint32_t *s, int n, int i) { return AT(s, n, i, '-') || AT(s, n, i, 0x2013); }

/* (?<![\w.,])(\d+)\s?[-–]\s?(\d+)(?![\w]) -> " a से b " */
static void p_range(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i) && no_wdc(s, n, i - 1)) {
            int ra = digit_run(s, n, i), j = i + ra, k = -1, b0 = -1, rb = 0;
            if (SP(s, n, j) && dash(s, n, j + 1)) k = j + 2;
            else if (dash(s, n, j)) k = j + 1;
            if (k >= 0) {
                if (SP(s, n, k) && DG(s, n, k + 1)) {
                    rb = digit_run(s, n, k + 1);
                    if (!W(s, n, k + 1 + rb)) b0 = k + 1;
                } else if (DG(s, n, k)) {
                    rb = digit_run(s, n, k);
                    if (!W(s, n, k + rb)) b0 = k;
                }
            }
            if (b0 >= 0) {
                put(d, ' ');
                card_span(d, s + i, ra);
                put(d, ' ');
                put_utf8(d, VTTS_HI_SE);
                put(d, ' ');
                card_span(d, s + b0, rb);
                put(d, ' ');
                i = b0 + rb;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int pause_dash(const uint32_t *s, int n, int i) { return dash(s, n, i) || AT(s, n, i, 0x2014); }

/* …+ | \.{3,} | \s[—–-]+\s | —+ | –+ -> " , " */
static void p_pause(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        uint32_t c = s[i];
        int end = -1;
        if (c == 0x2026 || c == 0x2014 || c == 0x2013 || c == '.') {
            int j = i;
            while (j < n && s[j] == c) j++;
            if (c != '.' || j - i >= 3) end = j;
        } else if (SP(s, n, i)) {
            int j = i + 1;
            while (pause_dash(s, n, j)) j++;
            if (j > i + 1 && SP(s, n, j)) end = j + 1;
        }
        if (end >= 0) {
            put_utf8(d, " , ");
            i = end;
            continue;
        }
        put(d, s[i++]);
    }
}

/* (?<![\w])(?=[A-Z0-9]*[A-Z])(?=[A-Z0-9]*[0-9])[A-Z0-9]+(?![\w]) -> letters by their Hindi names,
 * digits one by one */
static void p_code(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (!W(s, n, i - 1) && (UP(s, n, i) || DG(s, n, i))) {
            int j = i, up = 0, dg = 0;
            while (UP(s, n, j) || DG(s, n, j)) { up |= UP(s, n, j); dg |= DG(s, n, j); j++; }
            if (up && dg && !W(s, n, j)) {
                put(d, ' ');
                for (int k = i; k < j; k++) {
                    if (k > i) put(d, ' ');
                    if (UP(s, n, k)) put_utf8(d, VTTS_HI_LETTERS[s[k] - 'A']);
                    else nw(d, (int)(s[k] - '0'));
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
static void p_number(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (no_wdc(s, n, i - 1)) {
            int j = i + AT(s, n, i, '-');
            int e = num_match(s, n, j, not_digit, NULL);
            if (e >= 0) {
                put(d, ' ');
                number(d, s + i, e - i);
                put(d, ' ');
                i = e;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int lat(const uint32_t *s, int n, int i) { /* [A-Za-zÀ-ɏ] */
    if (i < 0 || i >= n) return 0;
    uint32_t c = s[i];
    return ((c | 32) >= 'a' && (c | 32) <= 'z') || (c >= 0xC0 && c <= 0x24F);
}

/* [A-Za-zÀ-ɏ](?:[A-Za-zÀ-ɏ'-]*[A-Za-zÀ-ɏ])? -> " " + normalize_en(ASCII of its NFKD form) + " " */
static void p_latin(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    const int half = x->cap / 2;
    for (int i = 0; i < n;) {
        if (lat(s, n, i)) {
            int j = i + 1, e = i + 1, f = 0;
            while (j < n && (lat(s, n, j) || s[j] == '\'' || s[j] == '-')) { j++; if (lat(s, n, j - 1)) e = j; }
            for (int k = i; k < e; k++) {
                uint32_t c = s[k];
                if (c < 0x80) {
                    if (f < x->cap) x->b[f++] = c;
                    continue;
                }
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

static void p_symbols(const uint32_t *s, int n, kb_t *d) { /* SYMBOLS in order, then - and – -> space */
    for (int i = 0; i < n; i++) {
        uint32_t c = s[i], k0;
        int k = 0;
        for (; k < VTTS_HI_N_SYMBOLS; k++) if (dec1(VTTS_HI_SYMBOLS[k][0], &k0) && k0 == c) break;
        if (k < VTTS_HI_N_SYMBOLS) put_utf8(d, VTTS_HI_SYMBOLS[k][1]);
        else put(d, c == '-' || c == 0x2013 ? ' ' : c);
    }
}

static int is_mark(uint32_t c) { return c == ',' || c == '.' || c == '?' || c == '!' || c == ';' || c == ':'; }
static int deva_word(uint32_t c) { return (c >= 0x900 && c <= 0x963) || (c >= 0x971 && c <= 0x97F) || (c >= 0xA8E0 && c <= 0xA8FF); }
static int alpha(uint32_t c) { return hi_w(c) && !(c >= '0' && c <= '9') && !(c >= 0x966 && c <= 0x96F) && c != '_'; } /* [^\W\d_] */

/* findall([ऀ-ॣॱ-ॿ꣠-ꣿ]+|[^\W\d_]+(?:'[^\W\d_]+)*|[,.?!;:]) joined by single spaces; a mark after a
 * mark is dropped. The text has no upper-case ASCII letters left (lower() is a no-op for the ids). */
static void p_words(const uint32_t *s, int n, kb_t *d) {
    int any = 0, last_mark = 0;
    for (int i = 0; i < n;) {
        int j = i;
        if (deva_word(s[i])) {
            while (j < n && deva_word(s[j])) j++;
        } else if (alpha(s[i])) {
            while (j < n && alpha(s[j])) j++;
            while (j + 1 < n && s[j] == '\'' && alpha(s[j + 1])) {
                j++;
                while (j < n && alpha(s[j])) j++;
            }
        } else if (is_mark(s[i])) {
            if (!any || !last_mark) {
                if (any) put(d, ' ');
                put(d, s[i]);
                any = last_mark = 1;
            }
            i++;
            continue;
        } else {
            i++;
            continue;
        }
        if (any) put(d, ' ');
        put_cps(d, s + i, j - i);
        any = 1;
        last_mark = 0;
        i = j;
    }
}

int vtts_hi_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, uint32_t *ea, uint32_t *eb,
                      int ecap, char *eout, int eout_cap, const uint32_t **out) {
    kb_t x = {a, 0, cap, 0}, y = {b, 0, cap, 0};
    scratch_t e = {ea, eb, ecap, eout, eout_cap};
    int m = deva_nfc(in, n, ea, ecap, 1); /* in may share memory with a and b */
    if (m < 0) return -1;
    p_digits(ea, m, &x);
    if (x.err) return -1;
#define PASS(call) do { y.n = 0; call; if (y.err) return -1; kb_t t_ = x; x = y; y = t_; } while (0)
    PASS(p_abbrev(x.p, x.n, &y));
    PASS(p_danda_drop(x.p, x.n, &y));
    PASS(p_date_iso(x.p, x.n, &y));
    PASS(p_date_dmy(x.p, x.n, &y));
    PASS(p_time(x.p, x.n, &y));
    PASS(p_year(x.p, x.n, &y));
    PASS(p_money(x.p, x.n, &y));
    PASS(p_phone(x.p, x.n, &y));
    PASS(p_percent(x.p, x.n, &y));
    PASS(p_unit(x.p, x.n, &y));
    PASS(p_ordinal(x.p, x.n, &y));
    PASS(p_range(x.p, x.n, &y));
    PASS(p_pause(x.p, x.n, &y));
    PASS(p_code(x.p, x.n, &y));
    PASS(p_number(x.p, x.n, &y));
    PASS(p_latin(x.p, x.n, &y, &e));
    PASS(p_symbols(x.p, x.n, &y));
    PASS(p_words(x.p, x.n, &y));
#undef PASS
    *out = x.p;
    return x.n;
}

#endif /* VTTS_ENABLE_HI */
