/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_ko.c -- Korean front-end of the device (token set ko-en): Hangul decomposition, the
 * exception table and the ordered pronunciation rules (mirrors src/vtts/frontend/ko/g2p_ko.py and
 * hangul.py), and normalization (mirrors src/vtts/frontend/ko/normalize_ko.py). All tables are in
 * the generated vtts_text_tables.h; no blob is needed. */
#include "vtts_langs.h"
#if VTTS_ENABLE_KO /* else an empty unit (vtts_langs.h) */

#include "vtts_text_ko.h"

#include <string.h>

#include "vtts_text_en.h"
#include "vtts_text_tables.h"

#define SYL0 0xAC00u
#define SYL1 0xD7A3u

int vtts_ko_is_syllable(uint32_t cp) { return cp >= SYL0 && cp <= SYL1; }

int vtts_ko_has_hangul(const uint32_t *w, int n) {
    for (int i = 0; i < n; i++)
        if (vtts_ko_is_syllable(w[i]) || (w[i] >= 0x3131 && w[i] <= 0x318E)) return 1;
    return 0;
}

/* ======================= pronunciation (g2p_ko.pronounce) ======================= */

/* consonant codes: compatibility jamo - 0x3130 */
enum {
    J_G = 1, J_GG, J_GS, J_N, J_NJ, J_NH, J_D, J_DD, J_L, J_LG, J_LM, J_LB, J_LS, J_LT, J_LP, J_LH,
    J_M, J_B, J_BB, J_BS, J_S, J_SS, J_NG, J_J, J_JJ, J_CH, J_K, J_T, J_P, J_H
};
enum { V_YEO = 6, V_UI = 19, V_I = 20 }; /* vowel indices (ㅏ 0 .. ㅣ 20) */

/* a, b: [onset, vowel, coda] of two adjacent syllables */

static void palatalize(uint8_t *a, uint8_t *b) { /* rule 17 */
    if (b[1] != V_I && b[1] != V_YEO) return;
    if (b[0] == J_NG && (a[2] == J_D || a[2] == J_T || a[2] == J_LT)) {
        uint8_t stay = a[2] == J_LT ? J_L : 0, on = a[2] == J_D ? J_J : J_CH;
        a[2] = stay;
        b[0] = on;
    } else if (b[0] == J_H && a[2] == J_D) {
        a[2] = 0;
        b[0] = J_CH;
    }
}

static void coda_h(uint8_t *a, uint8_t *b) { /* rule 12, coda ㅎ ㄶ ㅀ */
    if (!VTTS_KO_H_CODA[a[2]][0]) return;
    uint8_t rest = VTTS_KO_H_CODA[a[2]][1];
    if (VTTS_KO_ASPIRATED[b[0]]) { a[2] = rest; b[0] = VTTS_KO_ASPIRATED[b[0]]; }
    else if (b[0] == J_S) { a[2] = rest; b[0] = J_SS; }
    else if (b[0] == J_N) a[2] = rest ? rest : J_N;
    else if (b[0] == J_NG) a[2] = rest;
}

static void aspirate(uint8_t *a, uint8_t *b) { /* rule 12, onset ㅎ */
    if (b[0] == J_H && VTTS_KO_ASP_H[a[2]][0]) {
        b[0] = VTTS_KO_ASP_H[a[2]][2];
        a[2] = VTTS_KO_ASP_H[a[2]][1];
    }
}

static void liaison(uint8_t *a, uint8_t *b) { /* rules 13-14 */
    if (b[0] == J_NG && a[2] != 0 && a[2] != J_NG) {
        b[0] = VTTS_KO_LIAISON[a[2]][1];
        a[2] = VTTS_KO_LIAISON[a[2]][0];
    }
}

static void tensify(uint8_t *a, uint8_t *b) { /* rules 23-25 */
    if (!VTTS_KO_TENSE[b[0]]) return;
    if (VTTS_KO_OBSTRUENT[a[2]] ||
        (VTTS_KO_STEM[a[2]] && !((a[2] == J_NJ || a[2] == J_LM) && b[0] == J_G && b[1] == V_I)))
        b[0] = VTTS_KO_TENSE[b[0]];
}

static void neutralize(uint8_t *a, const uint8_t *b) { /* rules 9-11; b NULL for the last syllable */
    if (a[2] == J_LG && b && (b[0] == J_G || b[0] == J_GG)) a[2] = J_L;
    else if (VTTS_KO_NEUTRAL[a[2]] != 255) a[2] = VTTS_KO_NEUTRAL[a[2]];
}

static void l_to_n(uint8_t *a, uint8_t *b) { /* rule 19 */
    if (b[0] == J_L && (a[2] == J_M || a[2] == J_NG || a[2] == J_G || a[2] == J_D || a[2] == J_B)) b[0] = J_N;
}

static void nasalize(uint8_t *a, uint8_t *b) { /* rule 18 */
    if ((b[0] == J_N || b[0] == J_M) && (a[2] == J_G || a[2] == J_D || a[2] == J_B))
        a[2] = a[2] == J_G ? J_NG : a[2] == J_D ? J_N : J_M;
}

static void liquidize(uint8_t *a, uint8_t *b) { /* rule 20 */
    if ((a[2] == J_N && b[0] == J_L) || (a[2] == J_L && b[0] == J_N)) a[2] = b[0] = J_L;
}

static void vowels(uint8_t *s) { /* rule 5 */
    if (s[1] == V_UI && s[0] != J_NG) s[1] = V_I;
    else if ((s[0] == J_J || s[0] == J_JJ || s[0] == J_CH) && VTTS_KO_Y_PLAIN[s[1]] != 255) s[1] = VTTS_KO_Y_PLAIN[s[1]];
}

typedef void (*rule_fn)(uint8_t *a, uint8_t *b);

/* _apply_rules: each rule over every pair left to right, in the order of RULES */
static void apply_rules(uint8_t *s, int n) {
    static const rule_fn PAIR1[] = {palatalize, coda_h, aspirate, liaison, tensify};
    static const rule_fn PAIR2[] = {l_to_n, nasalize, liquidize};
    for (size_t r = 0; r < sizeof PAIR1 / sizeof *PAIR1; r++)
        for (int i = 0; i + 1 < n; i++) PAIR1[r](s + 3 * i, s + 3 * (i + 1));
    for (int i = 0; i < n; i++) neutralize(s + 3 * i, i + 1 < n ? s + 3 * (i + 1) : NULL);
    for (size_t r = 0; r < sizeof PAIR2 / sizeof *PAIR2; r++)
        for (int i = 0; i + 1 < n; i++) PAIR2[r](s + 3 * i, s + 3 * (i + 1));
    for (int i = 0; i < n; i++) vowels(s + 3 * i);
}

/* apply_overrides: forward longest match of the exception table; returns the new length or -1 */
static int overrides(const uint32_t *w, int n, uint32_t *o, int cap) {
    int m = 0;
    for (int i = 0; i < n;) {
        int hit = -1, len = n - i < VTTS_KO_OVR_MAX ? n - i : VTTS_KO_OVR_MAX;
        for (; len > 0 && hit < 0; len--)
            for (int k = 0; k < VTTS_KO_N_OVERRIDES && hit < 0; k++) {
                if (VTTS_KO_OVERRIDES[k].nk != len) continue;
                int t = 0;
                while (t < len && w[i + t] == SYL0 + VTTS_KO_OVERRIDES[k].k[t]) t++;
                if (t == len) hit = k;
            }
        if (hit >= 0) {
            len++; /* the loop decremented past the match */
            if (m + VTTS_KO_OVERRIDES[hit].nr > cap) return -1;
            for (int t = 0; t < VTTS_KO_OVERRIDES[hit].nr; t++) o[m++] = SYL0 + VTTS_KO_OVERRIDES[hit].r[t];
            i += len;
            continue;
        }
        if (m >= cap) return -1;
        o[m++] = w[i++];
    }
    return m;
}

int vtts_ko_pronounce(const uint32_t *w, int n, uint32_t *tmp, int tmp_cap, uint8_t *syl, int syl_cap) {
    int m = overrides(w, n, tmp, tmp_cap), cnt = 0, run = 0;
    if (m < 0) return -1;
    for (int i = 0; i <= m; i++) {
        if (i < m && vtts_ko_is_syllable(tmp[i])) {
            if (cnt >= syl_cap) return -1;
            uint32_t x = tmp[i] - SYL0;
            uint8_t *s = syl + 3 * cnt++;
            s[0] = VTTS_KO_ONSETS[x / 588];
            s[1] = (uint8_t)(x / 28 % 21);
            s[2] = VTTS_KO_CODAS[x % 28];
            continue;
        }
        if (cnt > run) apply_rules(syl + 3 * run, cnt - run);
        run = cnt;
    }
    return cnt;
}

int vtts_ko_syllable_ids(const uint8_t *s, uint8_t *out) {
    int n = 0;
    if (s[0] != J_NG && VTTS_KO_ONSET_ID[s[0]]) out[n++] = VTTS_KO_ONSET_ID[s[0]];
    out[n++] = VTTS_KO_VOWEL_ID[s[1]];
    if (s[2] && VTTS_KO_CODA_ID[s[2]]) out[n++] = VTTS_KO_CODA_ID[s[2]];
    return n;
}

/* ======================= normalization (normalize_ko) =======================
 * Each regex pass of the Python normalizer is one function from buffer s (n code points) to buffer
 * d; matches are found left to right without overlap, like re.sub, and lookarounds look at the
 * pass's input. Where backtracking can change a match, the candidate ends are tried in the order
 * the regex engine tries them. */

typedef struct { uint32_t *p; int n, cap, err; } kb_t;
typedef struct { uint32_t *a, *b; int cap; char *out; int out_cap; } scratch_t; /* a: digits of a number */

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

static void put(kb_t *d, uint32_t c) { if (d->n < d->cap) d->p[d->n++] = c; else d->err = 1; }
static void put_utf8(kb_t *d, const char *s) {
    uint32_t c;
    int l;
    while ((l = dec1(s, &c)) > 0) { put(d, c); s += l; }
}
static void put_cps(kb_t *d, const uint32_t *s, int n) { for (int i = 0; i < n; i++) put(d, s[i]); }

static int DG(const uint32_t *s, int n, int i) { return i >= 0 && i < n && s[i] >= '0' && s[i] <= '9'; }
static int AZ(const uint32_t *s, int n, int i) { return i >= 0 && i < n && (s[i] | 32) >= 'a' && (s[i] | 32) <= 'z'; }
static int AN(const uint32_t *s, int n, int i) { return DG(s, n, i) || AZ(s, n, i); } /* [A-Za-z0-9] */
static int SP(const uint32_t *s, int n, int i) { return i >= 0 && i < n && vtts_cp_is_space(s[i]); }
static int AT(const uint32_t *s, int n, int i, uint32_t c) { return i >= 0 && i < n && s[i] == c; }
static int HG(const uint32_t *s, int n, int i) { return i >= 0 && i < n && vtts_ko_is_syllable(s[i]); }
static int digit_run(const uint32_t *s, int n, int i) { int j = i; while (DG(s, n, j)) j++; return j - i; }
static int hangul_run(const uint32_t *s, int n, int i) { int j = i; while (HG(s, n, j)) j++; return j - i; }

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

static void digits(kb_t *d, const uint32_t *s, int n, const char *const *names) { /* digits(): non-digits skipped */
    for (int i = 0; i < n; i++) if (s[i] >= '0' && s[i] <= '9') put_utf8(d, names[s[i] - '0']);
}

static void section(kb_t *d, int v) { /* _section, v = 1..9999: 천 백 십 without a leading 일 */
    static const int DIV[4] = {1000, 100, 10, 1};
    for (int k = 0; k < 4; k++) {
        int dg = v / DIV[k] % 10;
        if (!dg) continue;
        if (!(dg == 1 && *VTTS_KO_SECTION_UNITS[k])) put_utf8(d, VTTS_KO_SINO_DIGITS[dg]);
        put_utf8(d, VTTS_KO_SECTION_UNITS[k]);
    }
}

/* sino(int(s)) for ASCII digits */
static void sino_u(kb_t *d, const uint32_t *s, int n) {
    while (n > 0 && *s == '0') { s++; n--; }
    if (!n) { put_utf8(d, VTTS_KO_SINO_DIGITS[0]); return; }
    int ng = (n + 3) / 4;
    if (ng > 5) { /* digits("".join(str(g) for g in groups)), least significant group first */
        for (int idx = 0; idx < ng; idx++) {
            int end = n - 4 * idx, start = end - 4 < 0 ? 0 : end - 4;
            while (start < end - 1 && s[start] == '0') start++;
            digits(d, s + start, end - start, VTTS_KO_SINO_DIGITS);
        }
        return;
    }
    for (int idx = ng - 1; idx >= 0; idx--) {
        int end = n - 4 * idx, start = end - 4 < 0 ? 0 : end - 4, g = 0;
        for (int i = start; i < end; i++) g = g * 10 + (int)(s[i] - '0');
        if (!g) continue;
        if (!(g == 1 && idx == 1)) section(d, g);
        put_utf8(d, VTTS_KO_GROUP_UNITS[idx]);
    }
}

static void sino_i(kb_t *d, int v) {
    uint32_t b[12];
    int n = 0;
    do { b[n++] = (uint32_t)('0' + v % 10); v /= 10; } while (v && n < 11);
    for (int i = 0; i < n / 2; i++) { uint32_t t = b[i]; b[i] = b[n - 1 - i]; b[n - 1 - i] = t; }
    sino_u(d, b, n);
}

static void native(kb_t *d, int v, int counter) { /* 1..99 */
    if (counter && v == 20) { put_utf8(d, "스무"); return; }
    put_utf8(d, VTTS_KO_NATIVE_TENS[v / 10]);
    put_utf8(d, (counter ? VTTS_KO_NATIVE_ONES_COUNTER : VTTS_KO_NATIVE_ONES)[v % 10]);
}

/* value of ASCII digits, capped at 1000 (enough for the 1..99 and month tests) */
static int small_value(const uint32_t *s, int n) {
    int v = 0;
    for (int i = 0; i < n; i++) { v = v * 10 + (int)(s[i] - '0'); if (v > 1000) v = 1000; }
    return v;
}

/* decimal(): commas dropped, leading '-' is 마이너스, "a.b" is sino(a) 점 digits(b) */
static void decimal_u(kb_t *d, const scratch_t *x, const uint32_t *s, int n) {
    int i = 0, neg = 0, first = 1;
    for (; i < n && (s[i] == ',' || s[i] == '-'); i++) {
        if (s[i] == '-') { neg |= first; }
        if (s[i] != ',') first = 0;
    }
    int na = 0;
    for (; i < n && s[i] != '.'; i++) {
        if (s[i] == ',') continue;
        if (na >= x->cap) { d->err = 1; return; }
        x->a[na++] = s[i];
    }
    if (neg) put_utf8(d, "마이너스 ");
    sino_u(d, x->a, na);
    if (i < n) { /* s[i] == '.' */
        put_utf8(d, " 점 ");
        digits(d, s + i + 1, n - i - 1, VTTS_KO_SINO_DIGITS);
    }
}

static int counter_kind(const uint32_t *w, int n) { /* 1 native, 2 sino, 3 joined, 0 none */
    for (int k = 0; k < VTTS_KO_N_COUNTERS; k++) if (key_at(w, n, 0, VTTS_KO_COUNTERS[k].word)) return VTTS_KO_COUNTERS[k].kind;
    return 0;
}

/* read_number(num, suffix, space) */
static void read_number(kb_t *d, const scratch_t *x, const uint32_t *num, int nn, const uint32_t *suf, int ns, int space) {
    int kind = ns ? counter_kind(suf, ns) : 0, plain_digits = 0, all = 1;
    for (int i = 0; i < nn; i++) {
        if (num[i] == ',') continue;
        if (num[i] >= '0' && num[i] <= '9') plain_digits++;
        else all = 0;
    }
    int isdigit = all && plain_digits > 0, v = 0;
    if (isdigit) {
        for (int i = 0; i < nn; i++) if (num[i] != ',') { v = v * 10 + (int)(num[i] - '0'); if (v > 1000) v = 1000; }
    }
    if (kind == 1 && isdigit && v >= 1 && v <= 99) {
        if (v == 1 && key_at(suf, ns, 0, "번째")) put_utf8(d, "첫 ");
        else { native(d, v, 1); put(d, ' '); }
        put_cps(d, suf, ns);
        return;
    }
    if (kind == 3 && key_at(suf, ns, 0, "월") && isdigit) {
        for (int k = 0; k < VTTS_KO_N_MONTHS; k++)
            if (VTTS_KO_MONTHS[k].month == v) {
                put_utf8(d, VTTS_KO_MONTHS[k].name);
                put_cps(d, suf + 1, ns - 1);
                return;
            }
    }
    decimal_u(d, x, num, nn);
    if (kind == 1 || kind == 2) put(d, ' ');
    else if (space) put(d, ' ');
    put_cps(d, suf, ns);
}

/* _NUM = (?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)? at i: the first end, in the regex's order, for which
 * ok() accepts the rest of the pattern; -1 if none */
typedef int (*end_ok)(const uint32_t *s, int n, int end, void *u);

static int try_frac(const uint32_t *s, int n, int b, end_ok ok, void *u) {
    if (AT(s, n, b, '.') && DG(s, n, b + 1))
        for (int k = digit_run(s, n, b + 1); k >= 1; k--) if (ok(s, n, b + 1 + k, u)) return b + 1 + k;
    return ok(s, n, b, u) ? b : -1;
}

static int num_match(const uint32_t *s, int n, int i, end_ok ok, void *u) {
    if (!DG(s, n, i)) return -1;
    int r = digit_run(s, n, i), e;
    if (r <= 3) { /* \d{1,3}(?:,\d{3})+ (a shorter first part would be followed by a digit) */
        int k = i + r, m = 0;
        while (AT(s, n, k, ',') && DG(s, n, k + 1) && DG(s, n, k + 2) && DG(s, n, k + 3)) { k += 4; m++; }
        for (int g = m; g >= 1; g--) if ((e = try_frac(s, n, i + r + 4 * g, ok, u)) >= 0) return e;
    }
    for (int k = r; k >= 1; k--) if ((e = try_frac(s, n, i + k, ok, u)) >= 0) return e;
    return -1;
}

/* ---- passes, in the order of normalize_ko ---- */

static void p_fullwidth(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n; i++) {
        uint32_t c = s[i];
        if (c >= 0xFF01 && c < 0xFF5F) c -= 0xFEE0;
        else for (int k = 0; k < VTTS_KO_N_FULLWIDTH; k++) if (VTTS_KO_FULLWIDTH[k][0] == c) { c = VTTS_KO_FULLWIDTH[k][1]; break; }
        put(d, c);
    }
}

static void p_pause(const uint32_t *s, int n, kb_t *d) { /* …+ | —+ | \.{3,} | · | ㆍ -> "," */
    for (int i = 0; i < n;) {
        uint32_t c = s[i];
        if (c == 0x00B7 || c == 0x318D) { put(d, ','); i++; continue; }
        if (c == 0x2026 || c == 0x2014 || c == '.') {
            int j = i;
            while (j < n && s[j] == c) j++;
            if (c != '.' || j - i >= 3) { put(d, ','); i = j; continue; }
        }
        put(d, c);
        i++;
    }
}

static void p_symbols(const uint32_t *s, int n, kb_t *d) {
    /* the str.replace calls in order; their outputs hold no key, so one pass is the same */
    for (int i = 0; i < n;) {
        int m = 0, k = 0;
        for (; k < VTTS_KO_N_SYMBOLS && !m; k++) m = key_at(s, n, i, VTTS_KO_SYMBOLS[k][0]);
        if (m) { put_utf8(d, VTTS_KO_SYMBOLS[k - 1][1]); i += m; continue; }
        put(d, s[i++]);
    }
}

static void p_drop(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n; i++) {
        uint32_t c = s[i];
        for (int k = 0; k < VTTS_KO_N_DROP; k++) if (VTTS_KO_DROP[k] == c) { c = ' '; break; }
        put(d, c);
    }
}

typedef struct { int unit, end; } unit_m;

static int unit_ok(const uint32_t *s, int n, int end, void *u) { /* \s?(units)(?![A-Za-z]) */
    unit_m *m = u;
    for (int sp = SP(s, n, end); sp >= 0; sp--) {
        int p = end + sp;
        for (int k = 0; k < VTTS_KO_N_UNITS; k++) {
            int l = key_at(s, n, p, VTTS_KO_UNITS[k][0]);
            if (l && !AZ(s, n, p + l)) { m->unit = k; m->end = p + l; return 1; }
        }
    }
    return 0;
}

/* (?<![A-Za-z0-9])(-?NUM)\s?(km|kg|...)(?![A-Za-z]) -> " decimal unit " */
static void p_unit(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        if (!AN(s, n, i - 1)) {
            int j = i + AT(s, n, i, '-');
            unit_m m;
            int e = num_match(s, n, j, unit_ok, &m);
            if (e >= 0) {
                put(d, ' ');
                decimal_u(d, x, s + i, e - i);
                put(d, ' ');
                put_utf8(d, VTTS_KO_UNITS[m.unit][1]);
                put(d, ' ');
                i = m.end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int upper(uint32_t c) { return c >= 'A' && c <= 'Z'; }

/* (?<![A-Za-z0-9])(?=[A-Z0-9]*[A-Z])(?=[A-Z0-9]*[0-9])[A-Z0-9]+(?![A-Za-z0-9]) -> letters and digits in English */
static void p_code(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (!AN(s, n, i - 1) && (upper(s[i]) || DG(s, n, i))) {
            int j = i, up = 0, dg = 0;
            while (j < n && (upper(s[j]) || DG(s, n, j))) { up |= upper(s[j]); dg |= DG(s, n, j); j++; }
            if (up && dg && !AN(s, n, j)) {
                put(d, ' ');
                for (int k = i; k < j; k++) {
                    put(d, ' ');
                    if (upper(s[k])) put(d, s[k] + 32);
                    else put_utf8(d, VTTS_EN_ONES[s[k] - '0']);
                    put(d, ' ');
                }
                put(d, ' ');
                i = j;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int value(const uint32_t *s, int n) { return small_value(s, n); }

/* (?<!\d)(\d{4})(?:-(\d{1,2})-(\d{1,2})|\.\s?(\d{1,2})\.\s?(\d{1,2})\.?)(?!\d) */
static void p_iso_date(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        if (!DG(s, n, i - 1) && digit_run(s, n, i) == 4) {
            int m0 = -1, ml = 0, d0 = -1, dl = 0, end = -1;
            if (AT(s, n, i + 4, '-')) {
                m0 = i + 5;
                ml = digit_run(s, n, m0);
                if (ml >= 1 && ml <= 2 && AT(s, n, m0 + ml, '-')) {
                    d0 = m0 + ml + 1;
                    dl = digit_run(s, n, d0);
                    if (dl >= 1 && dl <= 2) end = d0 + dl;
                }
            } else if (AT(s, n, i + 4, '.')) {
                m0 = i + 5;
                if (SP(s, n, m0)) m0++;
                ml = digit_run(s, n, m0);
                if (ml >= 1 && ml <= 2 && AT(s, n, m0 + ml, '.')) {
                    d0 = m0 + ml + 1;
                    if (SP(s, n, d0)) d0++;
                    dl = digit_run(s, n, d0);
                    if (dl >= 1 && dl <= 2) {
                        end = d0 + dl;
                        if (AT(s, n, end, '.') && !DG(s, n, end + 1)) end++;
                    }
                }
            }
            if (end >= 0) {
                int mo = value(s + m0, ml), dd = value(s + d0, dl);
                if (mo >= 1 && mo <= 12 && dd >= 1 && dd <= 31) {
                    uint32_t mcp[2], wol = 0xC6D4; /* 월 */
                    int mn = 0;
                    if (mo >= 10) mcp[mn++] = '1';
                    mcp[mn++] = (uint32_t)('0' + mo % 10);
                    put(d, ' ');
                    sino_u(d, s + i, 4);
                    put_utf8(d, "년 ");
                    read_number(d, x, mcp, mn, &wol, 1, 0);
                    put(d, ' ');
                    sino_i(d, dd);
                    put_utf8(d, "일 ");
                } else {
                    put_cps(d, s + i, end - i);
                }
                i = end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static void phone_digits(kb_t *d, const uint32_t *s, int n) { /* " ".join(digits(g) for g in split("-")) */
    for (int i = 0; i < n; i++) {
        if (s[i] == '-') put(d, ' ');
        else if (s[i] >= '0' && s[i] <= '9') put_utf8(d, VTTS_KO_PHONE_DIGITS[s[i] - '0']);
    }
}

/* (?<![\d-])0\d{1,2}-\d{3,4}-\d{4}(?![\d-]) | (?<![\d.,])0\d{2,}(?![\d.,]) -> digits, 0 = 공 */
static void p_phone(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (AT(s, n, i, '0')) {
            int end = -1;
            if (!DG(s, n, i - 1) && !AT(s, n, i - 1, '-')) {
                int r1 = digit_run(s, n, i + 1), p = i + 2 + r1;
                if (r1 >= 1 && r1 <= 2 && AT(s, n, i + 1 + r1, '-')) {
                    int r2 = digit_run(s, n, p), q = p + r2 + 1;
                    if (r2 >= 3 && r2 <= 4 && AT(s, n, p + r2, '-') && digit_run(s, n, q) == 4 && !AT(s, n, q + 4, '-'))
                        end = q + 4;
                }
            }
            if (end < 0 && !DG(s, n, i - 1) && !AT(s, n, i - 1, '.') && !AT(s, n, i - 1, ',')) {
                int r = digit_run(s, n, i);
                if (r >= 3 && !AT(s, n, i + r, '.') && !AT(s, n, i + r, ',')) end = i + r;
            }
            if (end >= 0) {
                put(d, ' ');
                phone_digits(d, s + i, end - i);
                put(d, ' ');
                i = end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int two(const uint32_t *s, int i) { return (int)(s[i] - '0') * 10 + (int)(s[i + 1] - '0'); }
static int not_dc(const uint32_t *s, int n, int i) { return !DG(s, n, i) && !AT(s, n, i, ':'); }

/* (?<![\d:])([01]?\d|2[0-4]):([0-5]\d)(?::([0-5]\d))?(?![\d:]) -> " H 시 [M 분] [S 초] " */
static void p_time(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i) && not_dc(s, n, i - 1)) {
            int hl[3], nh = 0;
            if ((s[i] == '0' || s[i] == '1') && DG(s, n, i + 1)) hl[nh++] = 2; /* [01]\d */
            hl[nh++] = 1;                                                    /* \d */
            if (s[i] == '2' && i + 1 < n && s[i + 1] >= '0' && s[i + 1] <= '4') hl[nh++] = 2; /* 2[0-4] */
            int done = 0;
            for (int c = 0; c < nh && !done; c++) {
                int j = i + hl[c];
                if (!(AT(s, n, j, ':') && j + 2 < n && s[j + 1] >= '0' && s[j + 1] <= '5' && DG(s, n, j + 2))) continue;
                int k = j + 3, sec = -1, end = -1;
                if (AT(s, n, k, ':') && k + 2 < n && s[k + 1] >= '0' && s[k + 1] <= '5' && DG(s, n, k + 2) && not_dc(s, n, k + 3)) {
                    sec = two(s, k + 1);
                    end = k + 3;
                } else if (not_dc(s, n, k)) {
                    end = k;
                }
                if (end < 0) continue;
                int h = hl[c] == 2 ? two(s, i) : (int)(s[i] - '0'), mi = two(s, j + 1);
                uint32_t hcp[2], si = 0xC2DC; /* 시 */
                int hn = 0;
                if (h >= 10) hcp[hn++] = (uint32_t)('0' + h / 10);
                hcp[hn++] = (uint32_t)('0' + h % 10);
                put(d, ' ');
                read_number(d, x, hcp, hn, &si, 1, 0);
                if (mi) { put(d, ' '); sino_i(d, mi); put_utf8(d, " 분"); }
                if (sec > 0) { put(d, ' '); sino_i(d, sec); put_utf8(d, " 초"); }
                put(d, ' ');
                i = end;
                done = 1;
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

static int always(const uint32_t *s, int n, int end, void *u) { (void)s; (void)n; (void)end; (void)u; return 1; }

/* ([₩$€¥£])\s?(NUM) -> " decimal currency " */
static void p_money(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        const char *name = NULL;
        for (int k = 0; k < VTTS_KO_N_CURRENCY; k++) if (VTTS_KO_CURRENCY[k].cp == s[i]) name = VTTS_KO_CURRENCY[k].name;
        if (name) {
            int j = i + 1;
            if (SP(s, n, j)) j++;
            int e = num_match(s, n, j, always, NULL);
            if (e >= 0) {
                put(d, ' ');
                decimal_u(d, x, s + j, e - j);
                put(d, ' ');
                put_utf8(d, name);
                put(d, ' ');
                i = e;
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

/* (-?NUM)\s?% -> " decimal 퍼센트 " */
static void p_percent(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        int j = i + AT(s, n, i, '-'), pe = 0;
        int e = num_match(s, n, j, pct_ok, &pe);
        if (e >= 0) {
            put(d, ' ');
            decimal_u(d, x, s + i, e - i);
            put_utf8(d, " 퍼센트 ");
            i = pe;
            continue;
        }
        put(d, s[i++]);
    }
}

static int is_dash(const uint32_t *s, int n, int i) { return AT(s, n, i, '~') || AT(s, n, i, '-'); }

/* (?<![\d.])(\d+)\s?[~-]\s?(\d+)(?![\d.])(\s?)([가-힣]*) -> "A에서 " + read_number(B, suffix) */
static void p_range(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i) && !DG(s, n, i - 1) && !AT(s, n, i - 1, '.')) {
            int ra = digit_run(s, n, i), j = i + ra, sep = -1;
            if (SP(s, n, j) && is_dash(s, n, j + 1)) sep = j + 1;
            else if (is_dash(s, n, j)) sep = j;
            if (sep >= 0) {
                int k = sep + 1;
                if (SP(s, n, k) && DG(s, n, k + 1)) k++;
                int rb = digit_run(s, n, k), e = k + rb;
                if (rb && !AT(s, n, e, '.')) {
                    int sp = SP(s, n, e), f = e + sp, ns = hangul_run(s, n, f);
                    int va = small_value(s + i, ra), vb = small_value(s + k, rb);
                    int native_ok = counter_kind(s + f, ns) == 1 && va >= 1 && va <= 99 && vb >= 1 && vb <= 99;
                    if (native_ok) native(d, va, 0);
                    else sino_u(d, s + i, ra);
                    put_utf8(d, "에서 ");
                    read_number(d, x, s + k, rb, s + f, ns, sp);
                    i = f + ns;
                    continue;
                }
            }
        }
        put(d, s[i++]);
    }
}

static int not_digit(const uint32_t *s, int n, int end, void *u) { (void)u; return !DG(s, n, end); }

/* (?<![A-Za-z0-9.])(-?)(NUM)(?![\d])(\s?)([가-힣]*) -> read_number */
static void p_number(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        if (!AN(s, n, i - 1) && !AT(s, n, i - 1, '.')) {
            int j = i + AT(s, n, i, '-');
            int e = num_match(s, n, j, not_digit, NULL);
            if (e >= 0) {
                int sp = SP(s, n, e), f = e + sp, ns = hangul_run(s, n, f);
                read_number(d, x, s + i, e - i, s + f, ns, sp);
                i = f + ns;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* [A-Za-z](?:[A-Za-z'-]*[A-Za-z])? -> " " + normalize_en(word) + " " */
static void p_latin(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        if (AZ(s, n, i)) {
            int j = i + 1, e = i + 1;
            while (j < n && (AZ(s, n, j) || s[j] == '\'' || s[j] == '-')) { j++; if (AZ(s, n, j - 1)) e = j; }
            int m = vtts_en_normalize(s + i, e - i, x->a, x->b, x->cap, x->out, x->out_cap);
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

static int is_mark(uint32_t c) { return c == ',' || c == '.' || c == '?' || c == '!' || c == ';' || c == ':'; }

/* findall([가-힣]+|[a-z][a-z']*|[,.?!;:]) joined by single spaces; a mark after a mark is dropped */
static void p_words(const uint32_t *s, int n, kb_t *d) {
    int any = 0, last_mark = 0;
    for (int i = 0; i < n;) {
        int j = i;
        if (HG(s, n, i)) {
            j = i + hangul_run(s, n, i);
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

int vtts_ko_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, uint32_t *ea,
                      uint32_t *eb, int ecap, char *eout, int eout_cap, const uint32_t **out) {
    kb_t x = {a, 0, cap, 0}, y = {b, 0, cap, 0};
    scratch_t e = {ea, eb, ecap, eout, eout_cap};
    p_fullwidth(in, n, &x);
    if (x.err) return -1;
#define PASS(call) do { y.n = 0; call; if (y.err) return -1; kb_t t_ = x; x = y; y = t_; } while (0)
    PASS(p_pause(x.p, x.n, &y));
    PASS(p_symbols(x.p, x.n, &y));
    PASS(p_drop(x.p, x.n, &y));
    PASS(p_unit(x.p, x.n, &y, &e));
    PASS(p_code(x.p, x.n, &y));
    PASS(p_iso_date(x.p, x.n, &y, &e));
    PASS(p_phone(x.p, x.n, &y));
    PASS(p_time(x.p, x.n, &y, &e));
    PASS(p_money(x.p, x.n, &y, &e));
    PASS(p_percent(x.p, x.n, &y, &e));
    PASS(p_range(x.p, x.n, &y, &e));
    PASS(p_number(x.p, x.n, &y, &e));
    PASS(p_latin(x.p, x.n, &y, &e));
    PASS(p_words(x.p, x.n, &y));
#undef PASS
    *out = x.p;
    return x.n;
}

#endif /* VTTS_ENABLE_KO */
