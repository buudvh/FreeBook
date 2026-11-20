/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_ltx.h -- helpers shared by the Latin-script front-ends that are compiled one by one
 * (vtts_text_it.c, vtts_text_tr.c): UTF-8 table strings, an output buffer of code points, the
 * number pattern of latin_norm.NUM and the steps of latin_norm (pauses, finish) and of latin.py
 * (spelling clusters). Everything is static inline, so a translation unit pays only for what it
 * uses. Same behaviour as the helpers of vtts_text_lt.c (which keeps its own copies). */
#ifndef VTTS_TEXT_LTX_H
#define VTTS_TEXT_LTX_H

#include <stdint.h>
#include <string.h>

#include "vtts_text_lt.h"

/* ---- UTF-8 table strings ---- */

static inline int x_dec1(const char *s, uint32_t *c) { /* one UTF-8 sequence of a (valid) table string */
    const unsigned char *p = (const unsigned char *)s;
    if (!p[0]) return 0;
    if (p[0] < 0x80) { *c = p[0]; return 1; }
    int extra = (p[0] >> 5) == 6 ? 1 : (p[0] >> 4) == 14 ? 2 : 3;
    uint32_t v = p[0] & (0x3Fu >> extra);
    for (int k = 1; k <= extra; k++) v = (v << 6) | (p[k] & 0x3F);
    *c = v;
    return extra + 1;
}

static inline int x_in_u8(uint32_t c, const char *set) { /* c is a code point of set (0 never is) */
    uint32_t x;
    int l;
    if (!c) return 0;
    while ((l = x_dec1(set, &x)) > 0) { if (x == c) return 1; set += l; }
    return 0;
}

static inline int x_eq_u8(const uint32_t *w, int n, const char *k) { /* the n code points w equal k */
    uint32_t x;
    int l, i = 0;
    while ((l = x_dec1(k, &x)) > 0) { if (i >= n || w[i] != x) return 0; i++; k += l; }
    return i == n;
}

static inline int x_u8_decode(const char *k, uint32_t *o, int cap) {
    uint32_t x;
    int l, n = 0;
    while ((l = x_dec1(k, &x)) > 0 && n < cap) { o[n++] = x; k += l; }
    return n;
}

static inline int x_in_sorted(const char *const *list, int n, const char *w) { /* sorted ASCII/UTF-8 list */
    int lo = 0, hi = n - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2, c = strcmp(list[m], w);
        if (!c) return 1;
        if (c < 0) lo = m + 1; else hi = m - 1;
    }
    return 0;
}

static inline int x_in_list(const char *const *list, int n, const char *s, int len) {
    for (int k = 0; k < n; k++) if ((int)strlen(list[k]) == len && memcmp(list[k], s, (size_t)len) == 0) return 1;
    return 0;
}

/* UTF-8 of n code points into a NUL-terminated buffer of cap bytes; 0 when it does not fit */
static inline int x_to_u8(const uint32_t *w, int n, char *o, int cap) {
    int m = 0;
    for (int i = 0; i < n; i++) {
        uint32_t c = w[i];
        int l = c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4;
        if (m + l >= cap) return 0;
        if (l == 1) o[m++] = (char)c;
        else if (l == 2) { o[m++] = (char)(0xC0 | (c >> 6)); o[m++] = (char)(0x80 | (c & 0x3F)); }
        else if (l == 3) {
            o[m++] = (char)(0xE0 | (c >> 12)); o[m++] = (char)(0x80 | ((c >> 6) & 0x3F)); o[m++] = (char)(0x80 | (c & 0x3F));
        } else {
            o[m++] = (char)(0xF0 | (c >> 18)); o[m++] = (char)(0x80 | ((c >> 12) & 0x3F));
            o[m++] = (char)(0x80 | ((c >> 6) & 0x3F)); o[m++] = (char)(0x80 | (c & 0x3F));
        }
    }
    o[m] = 0;
    return 1;
}

/* ---- output buffer ---- */

typedef struct { uint32_t *p; int n, cap, err; } x_lb;

static inline void x_put(x_lb *d, uint32_t c) { if (d->n < d->cap) d->p[d->n++] = c; else d->err = 1; }
static inline void x_puts8(x_lb *d, const char *s) {
    uint32_t c;
    int l;
    while ((l = x_dec1(s, &c)) > 0) { x_put(d, c); s += l; }
}
static inline void x_putn(x_lb *d, const uint32_t *s, int n) { for (int i = 0; i < n; i++) x_put(d, s[i]); }

static inline int x_tail_is(const x_lb *d, int start, const char *k) { /* the text since start ends with k */
    uint32_t b[24];
    int m = x_u8_decode(k, b, 24);
    if (d->n - start < m) return 0;
    for (int i = 0; i < m; i++) if (d->p[d->n - m + i] != b[i]) return 0;
    return 1;
}

/* ---- character classes (Python re, str patterns) ---- */

static inline int x_letter(uint32_t c) { return c != '_' && vtts_u_word(c) && vtts_u_digit(c) < 0; } /* [^\W\d_] */
static inline int x_upper_az(uint32_t c) { return c >= 'A' && c <= 'Z'; }
static inline int x_mark(uint32_t c) { return c == ',' || c == '.' || c == '?' || c == '!' || c == ';' || c == ':'; }

#define X_IN(i) ((i) >= 0 && (i) < n)
#define X_W(i) (X_IN(i) && vtts_u_word(s[i]))
#define X_DG(i) (X_IN(i) && vtts_u_digit(s[i]) >= 0)
#define X_SP(i) (X_IN(i) && vtts_u_space(s[i]))
#define X_AT(i, c) (X_IN(i) && s[i] == (uint32_t)(c))
#define X_WDC(i) (X_W(i) || X_AT(i, '.') || X_AT(i, ','))
#define X_LT(i) (X_IN(i) && x_letter(s[i]))

static inline int x_drun(const uint32_t *s, int n, int i) {
    int j = i;
    while (X_IN(j) && vtts_u_digit(s[j]) >= 0) j++;
    return j - i;
}

static inline int x_val(const uint32_t *s, int i, int len) {
    int v = 0;
    for (int k = 0; k < len; k++) v = v * 10 + vtts_u_digit(s[i + k]);
    return v;
}

static inline int x_key_at(const uint32_t *s, int n, int i, const char *k) { /* UTF-8 key at s[i]: length or 0 */
    int m = 0, l;
    uint32_t c;
    while ((l = x_dec1(k, &c)) > 0) {
        if (!X_IN(i + m) || s[i + m] != c) return 0;
        m++;
        k += l;
    }
    return m;
}

/* significant digits of s[0..n): count, *st the first (other code points are separators) */
static inline int x_sig(const uint32_t *s, int n, int *st) {
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

static inline uint64_t x_value(const uint32_t *s, int n, int st) {
    uint64_t v = 0;
    for (int i = st; i < n; i++) { int x = vtts_u_digit(s[i]); if (x >= 0) v = v * 10 + (uint64_t)x; }
    return v;
}

/* digits(): the name of every digit of s[from..n), joined by spaces */
static inline void x_digit_words(x_lb *d, const char *const *names, const uint32_t *s, int n, int from) {
    int first = 1;
    for (int i = from; i < n; i++) {
        int v = vtts_u_digit(s[i]);
        if (v < 0) continue;
        if (!first) x_put(d, ' ');
        x_puts8(d, names[v]);
        first = 0;
    }
}

/* latin_norm.parse_number of s[0..n): integer part [0, *ie), decimal part [*f0, n) or -1, mark */
static inline int x_groups_full(const uint32_t *s, int n, uint32_t g, uint32_t dm, int *ie, int *f0) {
    int r = x_drun(s, n, 0), i, groups = 0;
    if (r < 1 || r > 3) return 0;
    for (i = r; X_AT(i, g) && X_DG(i + 1) && X_DG(i + 2) && X_DG(i + 3); i += 4) groups++;
    if (!groups) return 0;
    if (i == n) { *ie = n; *f0 = -1; return 1; }
    if (X_AT(i, dm) && i + 1 < n && x_drun(s, n, i + 1) == n - i - 1) { *ie = i; *f0 = i + 1; return 1; }
    return 0;
}

static inline void x_parse_number(const uint32_t *s, int n, int *ie, int *f0, uint32_t *mark) {
    if (x_groups_full(s, n, '.', ',', ie, f0)) { *mark = ','; return; }
    if (x_groups_full(s, n, ',', '.', ie, f0)) { *mark = '.'; return; }
    for (int m = 0; m < 2; m++) {
        uint32_t c = m ? '.' : ',';
        for (int i = 0; i < n; i++)
            if (s[i] == c) { *ie = i; *f0 = i + 1; *mark = c; return; }
    }
    *ie = n;
    *f0 = -1;
    *mark = 0;
}

typedef int (*x_end_ok)(const uint32_t *s, int n, int end, void *u);

/* (?:[.,]\d+)? at b, then ok() */
static inline int x_try_dec(const uint32_t *s, int n, int b, x_end_ok ok, void *u) {
    if ((X_AT(b, '.') || X_AT(b, ',')) && X_DG(b + 1))
        for (int k = x_drun(s, n, b + 1); k >= 1; k--) if (ok(s, n, b + 1 + k, u)) return b + 1 + k;
    return ok(s, n, b, u) ? b : -1;
}

/* NUM = \d{1,3}(?:[.,]\d{3})+(?:[.,]\d+)?|\d+(?:[.,]\d+)? at j: the first end, in the regex's
 * order, that ok() accepts; -1 if none */
static inline int x_num_match(const uint32_t *s, int n, int j, x_end_ok ok, void *u) {
    if (!X_DG(j)) return -1;
    int r = x_drun(s, n, j), e;
    if (r <= 3) {
        int p = j + r, g = 0;
        while ((X_AT(p, '.') || X_AT(p, ',')) && X_DG(p + 1) && X_DG(p + 2) && X_DG(p + 3)) { p += 4; g++; }
        for (; g >= 1; g--) if ((e = x_try_dec(s, n, j + r + 4 * g, ok, u)) >= 0) return e;
    }
    for (int k = r; k >= 1; k--) if ((e = x_try_dec(s, n, j + k, ok, u)) >= 0) return e;
    return -1;
}

static inline int x_ok_always(const uint32_t *s, int n, int e, void *u) { (void)s; (void)n; (void)e; (void)u; return 1; }
static inline int x_ok_nodigit(const uint32_t *s, int n, int e, void *u) { (void)u; return !X_DG(e); }

static inline int x_is_dash(uint32_t c) { return c == 0x2014 || c == 0x2013 || c == '-'; }

/* apply_abbreviations, one key: (?<![\w])KEY[(?![\w])] -> " reading " (+ "." at the end of the text) */
static inline void x_abbrev(const char *key, const char *reading, const uint32_t *s, int n, x_lb *d) {
    int dot = key[strlen(key) - 1] == '.';
    for (int i = 0; i < n;) {
        int m;
        if (!X_W(i - 1) && (m = x_key_at(s, n, i, key)) && (dot || !X_W(i + m))) {
            int end = dot;
            for (int q = i + m; q < n && end; q++) end = vtts_u_space(s[q]);
            x_put(d, ' ');
            x_puts8(d, reading);
            x_put(d, ' ');
            if (end) x_put(d, '.');
            i += m;
            continue;
        }
        x_put(d, s[i++]);
    }
}

/* PAUSE = …+|\.{3,}|\s[—–-]+\s|—+|–+ -> " , " */
static inline void x_pause(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n;) {
        int e = -1;
        uint32_t c = s[i];
        if (c == 0x2026 || c == 0x2014 || c == 0x2013) { e = i; while (X_AT(e, c)) e++; }
        else if (c == '.') { e = i; while (X_AT(e, '.')) e++; if (e - i < 3) e = -1; }
        else if (X_SP(i) && X_IN(i + 1) && x_is_dash(s[i + 1])) {
            int j = i + 1;
            while (X_IN(j) && x_is_dash(s[j])) j++;
            if (X_SP(j)) e = j + 1;
        }
        if (e >= 0) { x_puts8(d, " , "); i = e; continue; }
        x_put(d, s[i++]);
    }
}

/* finish(): findall([^\W\d_]+(?:'[^\W\d_]+)*|[,.?!;:]) joined by spaces, a mark after a mark dropped
 * (the text is already lower case) */
static inline void x_words(const uint32_t *s, int n, x_lb *d) {
    int any = 0, last_mark = 0;
    for (int i = 0; i < n;) {
        if (x_letter(s[i])) {
            int j = i;
            while (X_IN(j) && x_letter(s[j])) j++;
            while (X_AT(j, '\'') && X_IN(j + 1) && x_letter(s[j + 1])) { j++; while (X_IN(j) && x_letter(s[j])) j++; }
            if (any) x_put(d, ' ');
            x_putn(d, s + i, j - i);
            any = 1;
            last_mark = 0;
            i = j;
            continue;
        }
        if (x_mark(s[i]) && !(any && last_mark)) {
            if (any) x_put(d, ' ');
            x_put(d, s[i]);
            any = last_mark = 1;
        }
        i++;
    }
}

/* ---- latin.py ---- */

static inline int x_camel(const uint32_t *w, int n) {
    for (int i = 0; i + 1 < n; i++) if (w[i] >= 'a' && w[i] <= 'z' && x_upper_az(w[i + 1])) return 1;
    return 0;
}

/* lang._is_plain_latin: ASCII letters, - and ', at least one letter */
static inline int x_plain_latin(const uint32_t *w, int n) {
    int alpha = 0;
    for (int i = 0; i < n; i++) {
        uint32_t c = w[i];
        int az = c < 0x80 && (c | 32) >= 'a' && (c | 32) <= 'z';
        if (!(az || c == '-' || c == '\'')) return 0;
        alpha |= az;
    }
    return n > 0 && alpha;
}

static inline int x_has_sub(const char *w, int n, const char *f) {
    int fl = (int)strlen(f);
    for (int i = 0; i + fl <= n; i++) if (memcmp(w + i, f, (size_t)fl) == 0) return 1;
    return 0;
}

/* in-place str.replace(from, to) with len(to) <= len(from) */
static inline int x_replace_all(char *w, int n, const char *from, const char *to) {
    int fl = (int)strlen(from), tl = (int)strlen(to), m = 0;
    for (int i = 0; i < n;) {
        if (i + fl <= n && memcmp(w + i, from, (size_t)fl) == 0) { memcpy(w + m, to, (size_t)tl); m += tl; i += fl; }
        else w[m++] = w[i++];
    }
    w[m] = 0;
    return m;
}

typedef struct {
    const char *vowels;
    const char *const *onsets; int n_onsets;
    const char *const *codas; int n_codas;
    const char *const *finals; int n_finals;
} x_clusters_t;

/* latin.consonant_runs (y never a vowel) + clusters_fit */
static inline int x_clusters(const x_clusters_t *T, const char *w, int n) {
#define X_ISV(k) (strchr(T->vowels, w[k]) != NULL)
    int any = 0;
    for (int k = 0; k < n; k++) any |= X_ISV(k);
    if (!any) return 0;
    for (int k = 0; k < n;) {
        if (X_ISV(k)) { k++; continue; }
        int j = k;
        while (j < n && !X_ISV(j)) j++;
        const char *r = w + k;
        int len = j - k, start = k == 0, end = j == n;
        if (start && !(len == 1 || x_in_list(T->onsets, T->n_onsets, r, len))) return 0;
        if (end && !x_in_list(T->finals, T->n_finals, r, len)) return 0;
        if (!start && !end) {
            int ok = 0;
            for (int sp = 0; sp < len && !ok; sp++)
                ok = (sp == 0 || x_in_list(T->codas, T->n_codas, r, sp)) &&
                     (len - sp == 1 || x_in_list(T->onsets, T->n_onsets, r + sp, len - sp));
            if (!ok) return 0;
        }
        k = j;
    }
    return 1;
#undef X_ISV
}

#endif
