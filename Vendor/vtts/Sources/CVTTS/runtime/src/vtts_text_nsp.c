/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_nsp.c -- normalization engine shared by the Khmer and Burmese front-ends, pass by pass
 * like src/vtts/frontend/nospace_norm.py (the passes follow the Thai normalizer, vtts_text_th.c).
 * Each regex pass is one function from buffer s (n code points) to buffer d; matches are found
 * left to right without overlap, like re.sub, and lookarounds look at the pass's input. Where
 * backtracking can change a match, the candidate ends are tried in the order the regex engine
 * tries them. Compiled only when a language that uses it is enabled. */
#include "vtts_text_nsp.h"

#include "vtts_langs.h"

#if VTTS_ENABLE_NSP

#include <string.h>

#include "vtts_text_en.h"

#define GLUE VTTS_NSP_GLUE

typedef vtts_nsp_buf kb_t;
typedef struct { uint32_t *a, *b; int cap; char *out; int out_cap; } scratch_t;

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

void vtts_nsp_put(kb_t *d, uint32_t c) { if (d->n < d->cap) d->p[d->n++] = c; else d->err = 1; }
#define put vtts_nsp_put
void vtts_nsp_put_utf8(kb_t *d, const char *s) {
    uint32_t c;
    int l;
    while ((l = dec1(s, &c)) > 0) { put(d, c); s += l; }
}
#define put_utf8 vtts_nsp_put_utf8
static void put_cps(kb_t *d, const uint32_t *s, int n) { for (int i = 0; i < n; i++) put(d, s[i]); }

static const vtts_nsp_spec *SPEC; /* the spec of the current call (not re-entrant, like the workspace) */

static int DG(const uint32_t *s, int n, int i) { return i >= 0 && i < n && s[i] >= '0' && s[i] <= '9'; }
static int AZ(const uint32_t *s, int n, int i) { return i >= 0 && i < n && (s[i] | 32) >= 'a' && (s[i] | 32) <= 'z'; }
static int UP(const uint32_t *s, int n, int i) { return i >= 0 && i < n && s[i] >= 'A' && s[i] <= 'Z'; }
static int AN(const uint32_t *s, int n, int i) { return DG(s, n, i) || AZ(s, n, i); }
static int SP(const uint32_t *s, int n, int i) { return i >= 0 && i < n && vtts_cp_is_space(s[i]); }
static int AT(const uint32_t *s, int n, int i, uint32_t c) { return i >= 0 && i < n && s[i] == c; }
static int RG(const uint32_t *s, int n, int i, uint32_t lo, uint32_t hi) { return i >= 0 && i < n && s[i] >= lo && s[i] <= hi; }
static int LT(const uint32_t *s, int n, int i) { return i >= 0 && i < n && SPEC->is_letter(s[i]); }
static int W(const uint32_t *s, int n, int i) { /* Python \w */
    if (i < 0 || i >= n) return 0;
    int w = SPEC->is_word(s[i]);
    return w >= 0 ? w : vtts_cp_is_word(s[i]);
}
static int digit_run(const uint32_t *s, int n, int i) { int j = i; while (DG(s, n, j)) j++; return j - i; }
static int digits_at(const uint32_t *s, int n, int i, int k) {
    for (int q = 0; q < k; q++) if (!DG(s, n, i + q)) return 0;
    return 1;
}

static int key_at(const uint32_t *s, int n, int i, const char *k) { /* UTF-8 key at s[i]: its length */
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

void vtts_nsp_digits(const vtts_nsp_spec *sp, kb_t *d, const uint32_t *s, int n) {
    for (int i = 0; i < n; i++) if (s[i] >= '0' && s[i] <= '9') put_utf8(d, sp->digits[s[i] - '0']);
}

static int group_value(const uint32_t *s, int a, int b) {
    int v = 0;
    for (int i = a; i < b; i++) v = v * 10 + (int)(s[i] - '0');
    return v;
}

void vtts_nsp_cardinal_u(const vtts_nsp_spec *sp, kb_t *d, const uint32_t *s, int n) {
    while (n > 0 && *s == '0') { s++; n--; }
    if (!n) { put_utf8(d, sp->digits[0]); return; }
    int first = (n - 1) % 6 + 1;
    sp->below_million(d, group_value(s, 0, first));
    for (int a = first; a < n; a += 6) {
        int v = group_value(s, a, a + 6);
        put_utf8(d, sp->million);
        if (v) sp->below_million(d, v);
    }
}

void vtts_nsp_cardinal_i(const vtts_nsp_spec *sp, kb_t *d, int v) {
    uint32_t b[12];
    int n = 0;
    do { b[n++] = (uint32_t)('0' + v % 10); v /= 10; } while (v && n < 11);
    for (int i = 0; i < n / 2; i++) { uint32_t t = b[i]; b[i] = b[n - 1 - i]; b[n - 1 - i] = t; }
    vtts_nsp_cardinal_u(sp, d, b, n);
}

/* number(): commas dropped, a leading '-' is the minus word, "a.b" is cardinal(a) point digits(b) */
static void number(kb_t *d, const scratch_t *x, const uint32_t *s, int n) {
    int k = 0, i = 0, na = 0;
    while (k < n && s[k] == ',') k++;
    int neg = k < n && s[k] == '-';
    while (i < n && (s[i] == ',' || s[i] == '-')) i++;
    for (; i < n && s[i] != '.'; i++) {
        if (s[i] == ',') continue;
        if (na >= x->cap) { d->err = 1; return; }
        x->a[na++] = s[i];
    }
    if (neg) put_utf8(d, SPEC->minus);
    vtts_nsp_cardinal_u(SPEC, d, x->a, na);
    if (i < n) {
        put_utf8(d, SPEC->point);
        vtts_nsp_digits(SPEC, d, s + i + 1, n - i - 1);
    }
}

/* NUM = \d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)? at i: the first end, in the regex's order, for
 * which ok() accepts the rest of the pattern; -1 if none */
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
        int k = i + r, m = 0;
        while (AT(s, n, k, ',') && DG(s, n, k + 1) && DG(s, n, k + 2) && DG(s, n, k + 3)) { k += 4; m++; }
        for (int g = m; g >= 1; g--) if ((e = try_frac(s, n, i + r + 4 * g, ok, u)) >= 0) return e;
    }
    for (int k = r; k >= 1; k--) if ((e = try_frac(s, n, i + k, ok, u)) >= 0) return e;
    return -1;
}

static int always(const uint32_t *s, int n, int end, void *u) { (void)s; (void)n; (void)end; (void)u; return 1; }
static int not_digit(const uint32_t *s, int n, int end, void *u) { (void)u; return !DG(s, n, end); }

/* ---- passes, in the order of Normalizer.__call__ ---- */

static void p_translate(const uint32_t *s, int n, kb_t *d) { /* native digits, full-width forms */
    for (int i = 0; i < n; i++) {
        uint32_t c = s[i];
        if (c >= SPEC->digit0 && c <= SPEC->digit0 + 9) c = '0' + (c - SPEC->digit0);
        else if (c >= 0xFF01 && c < 0xFF5F) c -= 0xFEE0;
        put(d, c);
    }
}

static void p_replace(const uint32_t *s, int n, kb_t *d, const char *key, const char *val) { /* str.replace */
    for (int i = 0; i < n;) {
        int l = key_at(s, n, i, key);
        if (l) { put_utf8(d, val); i += l; continue; }
        put(d, s[i++]);
    }
}

static void p_pause(const uint32_t *s, int n, kb_t *d) { /* …+ | —+ | –(?!\d) | \.{3,} -> " , " */
    for (int i = 0; i < n;) {
        int j = i;
        if (s[i] == 0x2026 || s[i] == 0x2014) {
            while (j < n && s[j] == s[i]) j++;
        } else if (s[i] == 0x2013 && !DG(s, n, i + 1)) {
            j = i + 1;
        } else if (s[i] == '.') {
            while (j < n && s[j] == '.') j++;
            if (j - i < 3) j = i;
        }
        if (j > i) { put_utf8(d, " , "); i = j; continue; }
        put(d, s[i++]);
    }
}

static const uint32_t DROP[] = {0x201C, 0x201D, 0x2018, 0x2019, '"', 0xAB, 0xBB, 0x300C, 0x300D, 0x300E,
                                0x300F, '(', ')', '[', ']', '{', '}', '<', '>', 0xB7, 0x2022};

static void p_drop(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n; i++) {
        uint32_t c = s[i];
        for (unsigned k = 0; k < sizeof DROP / sizeof DROP[0]; k++) if (DROP[k] == c) { c = ' '; break; }
        put(d, c);
    }
}

static void p_abbrev(const uint32_t *s, int n, kb_t *d) { /* (?<![L.])(abbreviations) -> glued */
    for (int i = 0; i < n;) {
        if (!LT(s, n, i - 1) && !AT(s, n, i - 1, '.')) {
            int l = 0, k = 0;
            for (; k < SPEC->n_abbrev && !l; k++) l = key_at(s, n, i, SPEC->abbrev[k][0]);
            if (l) {
                put(d, GLUE);
                put_utf8(d, SPEC->abbrev[k - 1][1]);
                put(d, GLUE);
                i += l;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static void p_repeat(const uint32_t *s, int n, kb_t *d) { /* \s*R\s* -> R */
    const uint32_t r = SPEC->repeat;
    for (int i = 0; i < n;) {
        int j = i;
        while (SP(s, n, j)) j++;
        if (AT(s, n, j, r)) {
            put(d, r);
            j++;
            while (SP(s, n, j)) j++;
            i = j;
            continue;
        }
        if (j > i) { put_cps(d, s + i, j - i); i = j; continue; }
        put(d, s[i++]);
    }
}

/* PRODUCT_CODE -> letters in English, digit runs one by one in the language */
static void p_code(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (!AN(s, n, i - 1) && (UP(s, n, i) || DG(s, n, i))) {
            int j = i, up = 0, dg = 0;
            while (UP(s, n, j) || DG(s, n, j)) { up |= UP(s, n, j); dg |= DG(s, n, j); j++; }
            if (up && dg && !AN(s, n, j)) {
                put(d, ' ');
                for (int k = i; k < j;) {
                    if (UP(s, n, k)) { put(d, ' '); put(d, s[k] | 32); put(d, ' '); k++; continue; }
                    int r = digit_run(s, n, k);
                    put(d, GLUE);
                    vtts_nsp_digits(SPEC, d, s + k, r);
                    put(d, GLUE);
                    k += r;
                }
                put(d, ' ');
                i = j;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static void date_words(kb_t *d, int day, int month, const uint32_t *y, int ny) {
    put(d, GLUE);
    SPEC->date(SPEC, d, day, month, y, ny);
    put(d, GLUE);
}

/* (?<![\d/])(\d{1,2})/(\d{1,2})/(\d{4}|\d{2})(?![\d/]) */
static void p_date_dmy(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i) && !DG(s, n, i - 1) && !AT(s, n, i - 1, '/')) {
            int r1 = digit_run(s, n, i), p = i + r1 + 1;
            int r2 = digit_run(s, n, p), q = p + r2 + 1;
            int r3 = digit_run(s, n, q);
            if (r1 <= 2 && AT(s, n, i + r1, '/') && r2 >= 1 && r2 <= 2 && AT(s, n, p + r2, '/') && (r3 == 2 || r3 == 4) &&
                !AT(s, n, q + r3, '/')) {
                int day = group_value(s, i, i + r1), month = group_value(s, p, p + r2);
                if (month >= 1 && month <= 12 && day >= 1 && day <= 31) date_words(d, day, month, s + q, r3);
                else put_cps(d, s + i, q + r3 - i);
                i = q + r3;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![\d-])(\d{4})-(\d{1,2})-(\d{1,2})(?![\d-]) */
static void p_date_iso(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i) && !DG(s, n, i - 1) && !AT(s, n, i - 1, '-')) {
            int r1 = digit_run(s, n, i), p = i + r1 + 1;
            int r2 = digit_run(s, n, p), q = p + r2 + 1;
            int r3 = digit_run(s, n, q);
            if (r1 == 4 && AT(s, n, i + 4, '-') && r2 >= 1 && r2 <= 2 && AT(s, n, p + r2, '-') && r3 >= 1 && r3 <= 2 &&
                !AT(s, n, q + r3, '-')) {
                int day = group_value(s, q, q + r3), month = group_value(s, p, p + r2);
                if (month >= 1 && month <= 12 && day >= 1 && day <= 31) date_words(d, day, month, s + i, 4);
                else put_cps(d, s + i, q + r3 - i);
                i = q + r3;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int two(const uint32_t *s, int i) { return (int)(s[i] - '0') * 10 + (int)(s[i + 1] - '0'); }

/* (?<![\d:.])([01]?\d|2[0-4]):([0-5]\d)(?::([0-5]\d))?(?![\d:]) */
static void p_time(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i) && !DG(s, n, i - 1) && !AT(s, n, i - 1, ':') && !AT(s, n, i - 1, '.')) {
            int hl[3], nh = 0, done = 0;
            if ((s[i] == '0' || s[i] == '1') && DG(s, n, i + 1)) hl[nh++] = 2; /* [01]\d */
            hl[nh++] = 1;                                                    /* \d */
            if (s[i] == '2' && RG(s, n, i + 1, '0', '4')) hl[nh++] = 2;       /* 2[0-4] */
            for (int c = 0; c < nh && !done; c++) {
                int j = i + hl[c], end = -1, sec = 0;
                if (AT(s, n, j, ':') && RG(s, n, j + 1, '0', '5') && DG(s, n, j + 2)) {
                    int k = j + 3;
                    if (AT(s, n, k, ':') && RG(s, n, k + 1, '0', '5') && DG(s, n, k + 2) && !DG(s, n, k + 3) &&
                        !AT(s, n, k + 3, ':')) {
                        sec = two(s, k + 1);
                        end = k + 3;
                    } else if (!DG(s, n, k) && !AT(s, n, k, ':')) {
                        end = k;
                    }
                }
                if (end < 0) continue;
                int h = hl[c] == 2 ? two(s, i) : (int)(s[i] - '0'), mi = two(s, j + 1);
                put(d, GLUE);
                SPEC->time(SPEC, d, h, mi, sec);
                put(d, GLUE);
                i = end;
                done = 1;
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

static const char *currency_of(uint32_t c) {
    uint32_t k;
    for (int q = 0; q < SPEC->n_currency; q++)
        if (dec1(SPEC->currency[q][0], &k) && k == c) return SPEC->currency[q][1];
    return NULL;
}

/* ([symbols])\s?(NUM) -> glued number currency */
static void p_money_before(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        const char *name = currency_of(s[i]);
        if (name) {
            int j = i + 1;
            if (SP(s, n, j)) j++;
            int e = num_match(s, n, j, always, NULL);
            if (e >= 0) {
                put(d, GLUE);
                number(d, x, s + j, e - j);
                put_utf8(d, name);
                put(d, GLUE);
                i = e;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

typedef struct { int end; const char *name; } cur_m;

static int cur_ok(const uint32_t *s, int n, int end, void *u) { /* \s?([symbols]) */
    cur_m *m = u;
    const char *name;
    if (SP(s, n, end) && end + 1 < n && (name = currency_of(s[end + 1]))) { m->end = end + 2; m->name = name; return 1; }
    if (end < n && (name = currency_of(s[end]))) { m->end = end + 1; m->name = name; return 1; }
    return 0;
}

/* (?<![\d.,])(NUM)\s?([symbols]) -> glued number currency */
static void p_money_after(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        if (!DG(s, n, i - 1) && !AT(s, n, i - 1, '.') && !AT(s, n, i - 1, ',')) {
            cur_m m = {0, NULL};
            int e = num_match(s, n, i, cur_ok, &m);
            if (e >= 0) {
                put(d, GLUE);
                number(d, x, s + i, e - i);
                put_utf8(d, m.name);
                put(d, GLUE);
                i = m.end;
                continue;
            }
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

/* (-?)(NUM)\s?% -> glued [minus] number percent */
static void p_percent(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        int j = i + AT(s, n, i, '-'), pe = 0;
        int e = num_match(s, n, j, pct_ok, &pe);
        if (e >= 0) {
            put(d, GLUE);
            if (j > i) put_utf8(d, SPEC->minus);
            number(d, x, s + j, e - j);
            put_utf8(d, SPEC->percent);
            put(d, GLUE);
            i = pe;
            continue;
        }
        put(d, s[i++]);
    }
}

typedef struct { int end, unit; } unit_m;

static int unit_ok(const uint32_t *s, int n, int end, void *u) { /* \s?(units)(?![A-Za-z]) */
    unit_m *m = u;
    int p = end + SP(s, n, end);
    for (int k = 0; k < SPEC->n_units; k++) {
        int l = key_at(s, n, p, SPEC->units[k][0]);
        if (l && !AZ(s, n, p + l)) { m->end = p + l; m->unit = k; return 1; }
    }
    if (p > end) { /* \s? matched nothing */
        for (int k = 0; k < SPEC->n_units; k++) {
            int l = key_at(s, n, end, SPEC->units[k][0]);
            if (l && !AZ(s, n, end + l)) { m->end = end + l; m->unit = k; return 1; }
        }
    }
    return 0;
}

/* (?<![\w.,])(-?)(NUM)\s?(units)(?![A-Za-z]) -> glued [minus] number unit */
static void p_unit(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        if (!W(s, n, i - 1) && !AT(s, n, i - 1, '.') && !AT(s, n, i - 1, ',')) {
            int j = i + AT(s, n, i, '-');
            unit_m m = {0, 0};
            int e = num_match(s, n, j, unit_ok, &m);
            if (e >= 0) {
                put(d, GLUE);
                if (j > i) put_utf8(d, SPEC->minus);
                number(d, x, s + j, e - j);
                put_utf8(d, SPEC->units[m.unit][1]);
                put(d, GLUE);
                i = m.end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int sep_at(const uint32_t *s, int n, int i) { return SP(s, n, i) || AT(s, n, i, '-'); }

static int phone_rest(const uint32_t *s, int n, int p) { /* (?:[\s-]\d{3,4}){2}(?![\d-]) */
    for (int a = 4; a >= 3; a--) {
        if (!sep_at(s, n, p) || !digits_at(s, n, p + 1, a)) continue;
        int q = p + 1 + a;
        for (int b = 4; b >= 3; b--) {
            if (!sep_at(s, n, q) || !digits_at(s, n, q + 1, b)) continue;
            int e = q + 1 + b;
            if (!DG(s, n, e) && !AT(s, n, e, '-')) return e;
        }
    }
    return -1;
}

static int phone_core(const uint32_t *s, int n, int p) { /* 0?\d{1,2} + rest */
    for (int z = AT(s, n, p, '0'); z >= 0; z--)
        for (int k = 2; k >= 1; k--) {
            if (!digits_at(s, n, p + z, k)) continue;
            int e = phone_rest(s, n, p + z + k);
            if (e >= 0) return e;
        }
    return -1;
}

static int phone_match(const uint32_t *s, int n, int i) {
    if (AT(s, n, i, '+'))
        for (int c = 3; c >= 1; c--) {
            if (!digits_at(s, n, i + 1, c)) continue;
            int q = i + 1 + c;
            for (int sp = sep_at(s, n, q); sp >= 0; sp--) {
                int e = phone_core(s, n, q + sp);
                if (e >= 0) return e;
            }
        }
    int e = phone_core(s, n, i);
    if (e >= 0) return e;
    if (!AT(s, n, i, '0')) return -1;
    for (int a = 2; a >= 1; a--) {
        if (!digits_at(s, n, i + 1, a) || !AT(s, n, i + 1 + a, '-')) continue;
        int p = i + 2 + a;
        for (int b = 4; b >= 3; b--) {
            if (!digits_at(s, n, p, b)) continue;
            int q = p + b;
            for (int h = AT(s, n, q, '-'); h >= 0; h--)
                for (int c = 4; c >= 0; c--) {
                    int r = q + h;
                    if (!digits_at(s, n, r, c)) continue;
                    if (!DG(s, n, r + c) && !AT(s, n, r + c, '-')) return r + c;
                }
        }
    }
    return -1;
}

static void p_phone(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if ((AT(s, n, i, '+') || DG(s, n, i)) && !DG(s, n, i - 1) && !AT(s, n, i - 1, '.') && !AT(s, n, i - 1, ',') &&
            !AT(s, n, i - 1, '-')) {
            int e = phone_match(s, n, i);
            if (e >= 0) {
                put(d, GLUE);
                vtts_nsp_digits(SPEC, d, s + i, e - i);
                put(d, GLUE);
                i = e;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int range_ok(const uint32_t *s, int n, int end, void *u) { /* \s?[-–]\s?(?=\d) */
    int *pe = u, k;
    if (SP(s, n, end) && (AT(s, n, end + 1, '-') || AT(s, n, end + 1, 0x2013))) k = end + 2;
    else if (AT(s, n, end, '-') || AT(s, n, end, 0x2013)) k = end + 1;
    else return 0;
    if (SP(s, n, k) && DG(s, n, k + 1)) { *pe = k + 1; return 1; }
    if (DG(s, n, k)) { *pe = k; return 1; }
    return 0;
}

static void p_range(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        if (!DG(s, n, i - 1) && !AT(s, n, i - 1, '.') && !AT(s, n, i - 1, ',')) {
            int pe = 0, e = num_match(s, n, i, range_ok, &pe);
            if (e >= 0) {
                put(d, GLUE);
                number(d, x, s + i, e - i);
                put_utf8(d, SPEC->to);
                put(d, GLUE);
                i = pe;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static void p_negative(const uint32_t *s, int n, kb_t *d) { /* (?<![\w\d])-(?=\d) -> glued minus */
    for (int i = 0; i < n; i++) {
        if (s[i] == '-' && !W(s, n, i - 1) && !DG(s, n, i - 1) && DG(s, n, i + 1)) {
            put(d, GLUE);
            put_utf8(d, SPEC->minus);
            put(d, GLUE);
            continue;
        }
        put(d, s[i]);
    }
}

static int long_ok(const uint32_t *s, int n, int e) { /* (?![\d.,]\d) */
    return !((DG(s, n, e) || AT(s, n, e, '.') || AT(s, n, e, ',')) && DG(s, n, e + 1));
}

static void p_long_digits(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i) && !DG(s, n, i - 1) && !AT(s, n, i - 1, '.') && !AT(s, n, i - 1, ',')) {
            int r = digit_run(s, n, i), e = -1;
            if (s[i] == '0') for (int k = r; k >= 3 && e < 0; k--) if (long_ok(s, n, i + k)) e = i + k;
            if (e < 0) for (int k = r; k >= 8 && e < 0; k--) if (long_ok(s, n, i + k)) e = i + k;
            if (e >= 0) {
                put(d, GLUE);
                vtts_nsp_digits(SPEC, d, s + i, e - i);
                put(d, GLUE);
                i = e;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static void p_number(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        if (!DG(s, n, i - 1) && !AT(s, n, i - 1, '.') && !AT(s, n, i - 1, ',')) {
            int e = num_match(s, n, i, not_digit, NULL);
            if (e >= 0) {
                put(d, GLUE);
                number(d, x, s + i, e - i);
                put(d, GLUE);
                i = e;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static void p_symbol(const uint32_t *s, int n, kb_t *d, uint32_t c, const char *text) {
    int glue = text[0] != ' ' && text[strlen(text) - 1] != ' ';
    for (int i = 0; i < n; i++) {
        if (s[i] != c) { put(d, s[i]); continue; }
        if (glue) put(d, GLUE);
        put_utf8(d, text);
        if (glue) put(d, GLUE);
    }
}

static void p_latin(const uint32_t *s, int n, kb_t *d, const scratch_t *x) { /* [A-Za-z][A-Za-z']* */
    for (int i = 0; i < n;) {
        if (AZ(s, n, i)) {
            int j = i + 1;
            while (AZ(s, n, j) || AT(s, n, j, '\'')) j++;
            int m = vtts_en_normalize(s + i, j - i, x->a, x->b, x->cap, x->out, x->out_cap);
            if (m < 0) { d->err = 1; return; }
            put(d, ' ');
            for (int k = 0; k < m; k++) put(d, (uint8_t)x->out[k]);
            put(d, ' ');
            i = j;
            continue;
        }
        put(d, s[i++]);
    }
}

static void p_glue_space(const uint32_t *s, int n, kb_t *d) { /* \s*\x01\s* -> \x01 */
    for (int i = 0; i < n;) {
        int j = i;
        while (SP(s, n, j)) j++;
        if (AT(s, n, j, GLUE)) {
            put(d, GLUE);
            j++;
            while (SP(s, n, j)) j++;
            i = j;
            continue;
        }
        if (j > i) { put_cps(d, s + i, j - i); i = j; continue; }
        put(d, s[i++]);
    }
}

static void p_dedupe(const uint32_t *s, int n, kb_t *d, const char *w) { /* w GLUE w -> GLUE w */
    for (int i = 0; i < n;) {
        int l = key_at(s, n, i, w);
        if (l && AT(s, n, i + l, GLUE)) {
            int l2 = key_at(s, n, i + l + 1, w);
            if (l2) {
                put(d, GLUE);
                put_cps(d, s + i + l + 1, l2);
                i += l + 1 + l2;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static void p_script_space(const uint32_t *s, int n, kb_t *d) { /* (?<=[L])\s+(?=[L]) -> " , " */
    for (int i = 0; i < n;) {
        if (SP(s, n, i) && LT(s, n, i - 1)) {
            int j = i;
            while (SP(s, n, j)) j++;
            if (LT(s, n, j)) { put_utf8(d, " , "); i = j; continue; }
        }
        put(d, s[i++]);
    }
}

static void p_drop_glue(const uint32_t *s, int n, kb_t *d) { for (int i = 0; i < n; i++) if (s[i] != GLUE) put(d, s[i]); }

static int is_mark(uint32_t c) { return c == ',' || c == '.' || c == '?' || c == '!' || c == ';' || c == ':'; }

/* findall([L]+|[a-z][a-z']*|[,.?!;:]) joined by single spaces; a mark after a mark is dropped */
static void p_words(const uint32_t *s, int n, kb_t *d) {
    int any = 0, last_mark = 0;
    for (int i = 0; i < n;) {
        int j = i;
        if (LT(s, n, i)) {
            while (LT(s, n, j)) j++;
        } else if (s[i] >= 'a' && s[i] <= 'z') {
            j = i + 1;
            while (j < n && ((s[j] >= 'a' && s[j] <= 'z') || s[j] == '\'')) j++;
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

static const uint32_t SYMBOL_CPS[5] = {'+', '=', '&', '@', 0xD7};

int vtts_nsp_normalize(const vtts_nsp_spec *sp, const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap,
                       uint32_t *ea, uint32_t *eb, int ecap, char *eout, int eout_cap, const uint32_t **out) {
    kb_t x = {a, 0, cap, 0}, y = {b, 0, cap, 0};
    scratch_t e = {ea, eb, ecap, eout, eout_cap};
    SPEC = sp;
    if (sp->pre) {
        if (sp->pre(in, n, &y, &x) < 0 || y.err) return -1;
        x.n = 0;
        x.err = 0;
        p_translate(y.p, y.n, &x);
    } else {
        p_translate(in, n, &x);
    }
    if (x.err) return -1;
#define PASS(call) do { y.n = 0; call; if (y.err) return -1; kb_t t_ = x; x = y; y = t_; } while (0)
    for (int k = 0; k < sp->n_punct; k++) PASS(p_replace(x.p, x.n, &y, sp->punct[k][0], sp->punct[k][1]));
    PASS(p_pause(x.p, x.n, &y));
    PASS(p_drop(x.p, x.n, &y));
    if (sp->n_abbrev) PASS(p_abbrev(x.p, x.n, &y));
    if (sp->repeat) PASS(p_repeat(x.p, x.n, &y));
    PASS(p_code(x.p, x.n, &y));
    PASS(p_date_dmy(x.p, x.n, &y));
    PASS(p_date_iso(x.p, x.n, &y));
    PASS(p_time(x.p, x.n, &y));
    PASS(p_money_before(x.p, x.n, &y, &e));
    PASS(p_money_after(x.p, x.n, &y, &e));
    PASS(p_percent(x.p, x.n, &y, &e));
    PASS(p_unit(x.p, x.n, &y, &e));
    PASS(p_phone(x.p, x.n, &y));
    PASS(p_range(x.p, x.n, &y, &e));
    PASS(p_negative(x.p, x.n, &y));
    PASS(p_long_digits(x.p, x.n, &y));
    PASS(p_number(x.p, x.n, &y, &e));
    for (int k = 0; k < 5; k++) PASS(p_symbol(x.p, x.n, &y, SYMBOL_CPS[k], sp->symbols[k]));
    PASS(p_latin(x.p, x.n, &y, &e));
    PASS(p_glue_space(x.p, x.n, &y));
    for (int k = 0; k < sp->n_dedupe; k++) PASS(p_dedupe(x.p, x.n, &y, sp->dedupe[k]));
    if (sp->space_pause) PASS(p_script_space(x.p, x.n, &y));
    PASS(p_drop_glue(x.p, x.n, &y));
    PASS(p_words(x.p, x.n, &y));
#undef PASS
    *out = x.p;
    return x.n;
}

#else
typedef int vtts_text_nsp_unused; /* ISO C: a translation unit is not empty */
#endif
