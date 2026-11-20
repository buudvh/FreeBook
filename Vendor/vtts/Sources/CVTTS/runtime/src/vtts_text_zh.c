/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_zh.c -- Mandarin front-end of the device (token set zh-en): ZLEX reader, readings by
 * forward maximum matching (mirrors src/vtts/frontend/zh/g2p_zh.py) and normalization (mirrors
 * src/vtts/frontend/zh/normalize_zh.py). */
#include "vtts_langs.h"
#if VTTS_ENABLE_ZH /* else an empty unit (vtts_langs.h) */

#include "vtts_text_zh.h"

#include <string.h>

#include "vtts_text_en.h"
#include "vtts_text_tables.h"

#define HAN0 0x4E00u
#define HAN1 0x9FFFu
#define MAX_PHRASE 4
#define NUM_DIGITS 512 /* digits of one number (Python reads any length; longer numbers fail) */

int vtts_zh_is_han(uint32_t cp) { return cp >= HAN0 && cp <= HAN1; }

static uint16_t rd16(const uint8_t *p) { return (uint16_t)(p[0] | p[1] << 8); }
static uint32_t rd32(const uint8_t *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

/* one UTF-8 sequence at p (NUL terminated): code point in *c, returns its length (0 at NUL) */
static int dec1(const char *s, uint32_t *c) {
    const unsigned char *p = (const unsigned char *)s;
    if (!p[0]) return 0;
    if (p[0] < 0x80) { *c = p[0]; return 1; }
    int extra = (p[0] >> 5) == 6 ? 1 : (p[0] >> 4) == 14 ? 2 : (p[0] >> 3) == 30 ? 3 : 0;
    if (!extra) { *c = 0xFFFD; return 1; }
    uint32_t v = p[0] & (0x3Fu >> extra);
    for (int k = 1; k <= extra; k++) {
        if ((p[k] & 0xC0) != 0x80) { *c = 0xFFFD; return k; }
        v = (v << 6) | (p[k] & 0x3F);
    }
    *c = v;
    return extra + 1;
}

/* ======================= ZLEX reader and readings ======================= */

int vtts_zlex_init(vtts_zlex *z, const uint8_t *blob, size_t size) {
    if (!z || !blob || size < 48 || memcmp(blob, "ZLEX", 4) != 0 || rd16(blob + 4) != 1 || rd16(blob + 6) != 48)
        return -1;
    memset(z, 0, sizeof *z);
    z->blob = blob;
    z->size = size;
    z->n_syl = rd32(blob + 8);
    z->n_chars = rd32(blob + 12);
    uint64_t need[5];
    need[0] = 4ull * z->n_syl;
    need[1] = 4ull * z->n_chars;
    for (int k = 0; k < 3; k++) {
        z->n_phr[k] = rd32(blob + 16 + 4 * k);
        need[2 + k] = 4ull * (uint64_t)(k + 2) * z->n_phr[k];
    }
    const uint8_t **ptr[5] = {&z->syl, &z->chars, &z->phr[0], &z->phr[1], &z->phr[2]};
    for (int k = 0; k < 5; k++) {
        uint32_t off = rd32(blob + 28 + 4 * k);
        if (off < 48 || off > size || need[k] > size - off) return -2;
        *ptr[k] = blob + off;
    }
    if (z->n_syl == 0 || z->n_syl >= 0xFFFF) return -2;
    for (uint32_t i = 0; i < z->n_syl; i++) {
        const uint8_t *e = z->syl + 4 * i;
        if (e[0] > VTTS_ZH_N_INITIALS || e[1] >= VTTS_ZH_N_FINALS || e[2] < 1 || e[2] > VTTS_ZH_N_TONES) return -3;
    }
    return 0;
}

/* syllable index of one character (key = code point - 0x4E00), -1 if it has no reading */
static int char_syl(const vtts_zlex *z, uint16_t key) {
    uint32_t lo = 0, hi = z->n_chars;
    while (lo < hi) {
        uint32_t mid = lo + (hi - lo) / 2;
        uint16_t k = rd16(z->chars + 2 * mid);
        if (k == key) return rd16(z->chars + 2 * (size_t)z->n_chars + 2 * mid);
        if (k < key) lo = mid + 1; else hi = mid;
    }
    return -1;
}

/* record of the phrase keys[0..n) (n = 2..4), NULL if absent; its readings follow the keys */
static const uint8_t *find_phrase(const vtts_zlex *z, const uint16_t *keys, int n) {
    const uint8_t *tab = z->phr[n - 2];
    uint32_t lo = 0, hi = z->n_phr[n - 2], rec = 4u * (uint32_t)n;
    while (lo < hi) {
        uint32_t mid = lo + (hi - lo) / 2;
        const uint8_t *r = tab + (size_t)rec * mid;
        int cmp = 0;
        for (int k = 0; k < n && !cmp; k++) {
            uint16_t v = rd16(r + 2 * k);
            cmp = v < keys[k] ? -1 : v > keys[k] ? 1 : 0;
        }
        if (!cmp) return r;
        if (cmp < 0) lo = mid + 1; else hi = mid;
    }
    return NULL;
}

static int emit_syl(const vtts_zlex *z, uint32_t idx, vtts_zh_unit_cb cb, void *user) {
    if (idx >= z->n_syl) return 0;
    const uint8_t *e = z->syl + 4 * idx;
    uint8_t ids[3];
    int n = 0;
    if (e[0]) ids[n++] = (uint8_t)(VTTS_ZHEN_ZI0 + e[0] - 1);
    ids[n++] = (uint8_t)(VTTS_ZHEN_ZF0 + e[1]);
    ids[n++] = (uint8_t)(VTTS_ZHEN_ZT1 + e[2] - 1);
    if (cb) cb(user, ids, n);
    return 1;
}

int vtts_zh_read_han(const vtts_zlex *z, const char *word, vtts_zh_unit_cb cb, void *user) {
    if (!z || !word) return 0;
    int count = 0;
    const char *p = word;
    while (*p) {
        /* window of up to MAX_PHRASE Han characters at p */
        uint16_t keys[MAX_PHRASE];
        int len[MAX_PHRASE], nw = 0;
        const char *q = p;
        uint32_t c = 0;
        while (nw < MAX_PHRASE) {
            int l = dec1(q, &c);
            if (!l || !vtts_zh_is_han(c)) break;
            keys[nw] = (uint16_t)(c - HAN0);
            len[nw++] = l;
            q += l;
        }
        if (!nw) { /* not a Han character: no reading */
            int l = dec1(p, &c);
            p += l ? l : 1;
            continue;
        }
        const uint8_t *rec = NULL;
        int n = nw;
        for (; n >= 2 && !rec; n--) rec = find_phrase(z, keys, n);
        if (rec) {
            n++; /* the loop decremented past the match */
            for (int k = 0; k < n; k++) {
                count += emit_syl(z, rd16(rec + 2 * (n + k)), cb, user);
                p += len[k];
            }
            continue;
        }
        int s = char_syl(z, keys[0]);
        if (s >= 0) count += emit_syl(z, (uint32_t)s, cb, user);
        p += len[0];
    }
    return count;
}

/* ======================= normalization (normalize_zh) =======================
 * Each regex pass of the Python normalizer is one function from buffer s (n code points) to
 * buffer d; matches are found left to right without overlap, like re.sub, and lookarounds look
 * at the pass's input. Backtracking is reproduced where it can change the result. */

typedef struct { uint32_t *p; int n, cap, err; } zb_t;

static void put(zb_t *d, uint32_t c) { if (d->n < d->cap) d->p[d->n++] = c; else d->err = 1; }
static void put_utf8(zb_t *d, const char *s) {
    uint32_t c;
    int l;
    while ((l = dec1(s, &c)) > 0) { put(d, c); s += l; }
}
static void put_cps(zb_t *d, const uint32_t *s, int n) { for (int i = 0; i < n; i++) put(d, s[i]); }

static int DG(const uint32_t *s, int n, int i) { return i >= 0 && i < n && s[i] >= '0' && s[i] <= '9'; }
static int AN(const uint32_t *s, int n, int i) { /* [A-Za-z0-9] */
    if (i < 0 || i >= n) return 0;
    uint32_t c = s[i];
    return (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}
static int SP(const uint32_t *s, int n, int i) { return i >= 0 && i < n && vtts_cp_is_space(s[i]); }
static int AT(const uint32_t *s, int n, int i, uint32_t c) { return i >= 0 && i < n && s[i] == c; }
static int HN(const uint32_t *s, int n, int i) { return i >= 0 && i < n && vtts_zh_is_han(s[i]); }
static int digit_run(const uint32_t *s, int n, int i) { int j = i; while (DG(s, n, j)) j++; return j - i; }

/* ---- numbers ---- */

static void digits_c(zb_t *d, const char *s, int n) { /* digits(): one numeral per digit */
    for (int i = 0; i < n; i++) if (s[i] >= '0' && s[i] <= '9') put_utf8(d, VTTS_ZH_DIGITS[s[i] - '0']);
}

static void digits_u(zb_t *d, const uint32_t *s, int n) {
    for (int i = 0; i < n; i++) if (s[i] >= '0' && s[i] <= '9') put_utf8(d, VTTS_ZH_DIGITS[s[i] - '0']);
}

/* _section(v), v = 1..9999; first: this section starts the number (cardinal drops a leading 一十 -> 十) */
static void section(zb_t *d, int v, int first) {
    static const int DIV[4] = {1000, 100, 10, 1};
    int any = 0, zero = 0;
    for (int k = 0; k < 4; k++) {
        int dg = v / DIV[k] % 10;
        if (dg == 0) { zero = any; continue; }
        if (zero) put_utf8(d, VTTS_ZH_DIGITS[0]);
        if (!(first && !any && k == 2 && dg == 1)) put_utf8(d, VTTS_ZH_DIGITS[dg]);
        put_utf8(d, VTTS_ZH_SECTION_UNITS[k]);
        zero = 0;
        any = 1;
    }
}

static int group_value(const char *s, int a, int b) {
    int v = 0;
    for (int i = a; i < b; i++) v = v * 10 + (s[i] - '0');
    return v;
}

/* cardinal(int(s)) for a string of ASCII digits */
static void cardinal_c(zb_t *d, const char *s, int n) {
    while (n > 0 && *s == '0') { s++; n--; }
    if (n == 0) { put_utf8(d, VTTS_ZH_DIGITS[0]); return; }
    int ng = (n + 3) / 4;
    if (ng > 4) { /* digits("".join(str(g) for g in groups)), least significant group first */
        for (int idx = 0; idx < ng; idx++) {
            int end = n - 4 * idx, start = end - 4 < 0 ? 0 : end - 4;
            while (start < end - 1 && s[start] == '0') start++;
            digits_c(d, s + start, end - start);
        }
        return;
    }
    int any = 0, gap = 0;
    for (int idx = ng - 1; idx >= 0; idx--) {
        int end = n - 4 * idx, start = end - 4 < 0 ? 0 : end - 4;
        int g = group_value(s, start, end);
        if (g == 0) { gap = any; continue; }
        if (any && (gap || g < 1000)) put_utf8(d, VTTS_ZH_DIGITS[0]);
        section(d, g, !any);
        put_utf8(d, VTTS_ZH_GROUP_UNITS[idx]);
        gap = 0;
        any = 1;
    }
}

static void cardinal_i(zb_t *d, int v) {
    char b[12];
    int n = 0;
    do { b[n++] = (char)('0' + v % 10); v /= 10; } while (v && n < 11);
    for (int i = 0; i < n / 2; i++) { char t = b[i]; b[i] = b[n - 1 - i]; b[n - 1 - i] = t; }
    cardinal_c(d, b, n);
}

static void cardinal_u(zb_t *d, const uint32_t *s, int n) {
    char b[NUM_DIGITS];
    if (n > NUM_DIGITS) { d->err = 1; return; }
    for (int i = 0; i < n; i++) b[i] = (char)s[i];
    cardinal_c(d, b, n);
}

/* number(s): commas dropped, a leading '-' is 负, "a.b" is cardinal(a) 点 digits(b) */
static void number_u(zb_t *d, const uint32_t *s, int n) {
    char a[NUM_DIGITS] = {0};
    int na = 0, i = 0, neg = 0;
    while (i < n && (s[i] == '-' || s[i] == ',')) { neg |= s[i] == '-'; i++; }
    for (; i < n && s[i] != '.'; i++) {
        if (s[i] == ',') continue;
        if (na >= NUM_DIGITS) { d->err = 1; return; }
        a[na++] = (char)s[i];
    }
    if (neg) put_utf8(d, "负");
    cardinal_c(d, a, na);
    if (i < n) { /* s[i] == '.' */
        put_utf8(d, "点");
        digits_u(d, s + i + 1, n - i - 1);
    }
}

/* ---- passes, in the order of normalize_zh ---- */

static void p_fullwidth(const uint32_t *s, int n, zb_t *d) {
    for (int i = 0; i < n; i++) {
        uint32_t c = s[i];
        if (c >= 0xFF01 && c < 0xFF5F) c -= 0xFEE0;
        else for (int k = 0; k < VTTS_ZH_N_FULLWIDTH; k++) if (VTTS_ZH_FULLWIDTH[k][0] == c) { c = VTTS_ZH_FULLWIDTH[k][1]; break; }
        put(d, c);
    }
}

static void p_pause(const uint32_t *s, int n, zb_t *d) { /* …+ | —+ | \.{3,} -> "," */
    for (int i = 0; i < n;) {
        uint32_t c = s[i];
        if (c == 0x2026 || c == 0x2014 || c == '.') {
            int j = i;
            while (j < n && s[j] == c) j++;
            if (c != '.' || j - i >= 3) { put(d, ','); i = j; continue; }
        }
        put(d, c);
        i++;
    }
}

static int key_at(const uint32_t *s, int n, int i, const char *k) { /* UTF-8 key at s[i]; its length or 0 */
    int m = 0;
    uint32_t c;
    int l;
    while ((l = dec1(k, &c)) > 0) {
        if (i + m >= n || s[i + m] != c) return 0;
        m++;
        k += l;
    }
    return m;
}

static void p_symbols(const uint32_t *s, int n, zb_t *d) {
    /* the str.replace calls in order; their outputs hold no key, so one pass is the same */
    for (int i = 0; i < n;) {
        int m = 0, k = 0;
        for (; k < VTTS_ZH_N_SYMBOLS && !m; k++) m = key_at(s, n, i, VTTS_ZH_SYMBOLS[k][0]);
        if (m) { put_utf8(d, VTTS_ZH_SYMBOLS[k - 1][1]); i += m; continue; }
        put(d, s[i++]);
    }
}

static void p_drop(const uint32_t *s, int n, zb_t *d) {
    for (int i = 0; i < n; i++) {
        uint32_t c = s[i];
        for (int k = 0; k < VTTS_ZH_N_DROP; k++) if (VTTS_ZH_DROP[k] == c) { c = ' '; break; }
        put(d, c);
    }
}

static int upper(uint32_t c) { return c >= 'A' && c <= 'Z'; }

/* (?<![A-Za-z0-9])(?=[A-Z0-9]*[A-Z])(?=[A-Z0-9]*[0-9])[A-Z0-9]+(?![A-Za-z0-9]) */
static void p_code(const uint32_t *s, int n, zb_t *d) {
    for (int i = 0; i < n;) {
        if (!AN(s, n, i - 1) && (upper(s[i]) || DG(s, n, i))) {
            int j = i, up = 0, dg = 0;
            while (j < n && (upper(s[j]) || DG(s, n, j))) { up |= upper(s[j]); dg |= DG(s, n, j); j++; }
            if (up && dg && !AN(s, n, j)) {
                put(d, ' ');
                for (int k = i; k < j;) {
                    if (upper(s[k])) { put(d, ' '); put(d, s[k] + 32); put(d, ' '); k++; continue; }
                    int e = k + digit_run(s, n, k);
                    digits_u(d, s + k, e - k);
                    k = e;
                }
                put(d, ' ');
                i = j;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int is_sep(uint32_t c) { return c == '-' || c == '/' || c == '.'; }

/* (?<![A-Za-z0-9])(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?!\d) */
static void p_iso_date(const uint32_t *s, int n, zb_t *d) {
    for (int i = 0; i < n;) {
        if (!AN(s, n, i - 1) && digit_run(s, n, i) == 4 && i + 4 < n && is_sep(s[i + 4])) {
            int m0 = i + 5, ml = digit_run(s, n, m0);
            int d0 = m0 + ml + 1, dl = ml >= 1 && ml <= 2 && m0 + ml < n && is_sep(s[m0 + ml]) ? digit_run(s, n, d0) : 0;
            if (dl >= 1 && dl <= 2) {
                int mo = 0, dd = 0;
                for (int k = 0; k < ml; k++) mo = mo * 10 + (int)(s[m0 + k] - '0');
                for (int k = 0; k < dl; k++) dd = dd * 10 + (int)(s[d0 + k] - '0');
                int end = d0 + dl;
                if (mo >= 1 && mo <= 12 && dd >= 1 && dd <= 31) {
                    digits_u(d, s + i, 4);
                    put_utf8(d, "年");
                    cardinal_i(d, mo);
                    put_utf8(d, "月");
                    cardinal_i(d, dd);
                    put_utf8(d, "日");
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

/* \d[\d,]*(?:\.\d+)? at i: end of the number, or -1 */
static int num_end(const uint32_t *s, int n, int i) {
    if (!DG(s, n, i)) return -1;
    int j = i + 1;
    while (DG(s, n, j) || AT(s, n, j, ',')) j++;
    if (AT(s, n, j, '.') && DG(s, n, j + 1)) {
        j += 2;
        while (DG(s, n, j)) j++;
    }
    return j;
}

static const char *currency(uint32_t c) {
    for (int k = 0; k < VTTS_ZH_N_CURRENCY; k++) if (VTTS_ZH_CURRENCY[k].cp == c) return VTTS_ZH_CURRENCY[k].name;
    return NULL;
}

/* ([¥$€£])\s?(\d[\d,]*(?:\.\d+)?) -> number + currency */
static void p_money(const uint32_t *s, int n, zb_t *d) {
    for (int i = 0; i < n;) {
        const char *name = currency(s[i]);
        if (name) {
            int j = i + 1;
            if (SP(s, n, j)) j++;
            int e = num_end(s, n, j);
            if (e > 0) {
                number_u(d, s + j, e - j);
                put_utf8(d, name);
                i = e;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* (-?\d[\d,]*(?:\.\d+)?)\s?% -> [负]百分之 + number */
static void p_percent(const uint32_t *s, int n, zb_t *d) {
    for (int i = 0; i < n;) {
        int neg = AT(s, n, i, '-'), j = i + neg;
        int e = num_end(s, n, j);
        if (e > 0) {
            int k = e;
            if (SP(s, n, k)) k++;
            if (AT(s, n, k, '%')) {
                if (neg) put_utf8(d, "负");
                put_utf8(d, "百分之");
                number_u(d, s + j, e - j);
                i = k + 1;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int two(const uint32_t *s, int i) { return (int)(s[i] - '0') * 10 + (int)(s[i + 1] - '0'); }
static int not_dc(const uint32_t *s, int n, int i) { return !DG(s, n, i) && !AT(s, n, i, ':'); }

/* (?<![\d:])([01]?\d|2[0-4]):([0-5]\d)(?::([0-5]\d))?(?![\d:]) */
static void p_time(const uint32_t *s, int n, zb_t *d) {
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
                cardinal_i(d, h);
                put_utf8(d, "点");
                if (mi || sec >= 0) {
                    if (mi < 10) { put_utf8(d, VTTS_ZH_DIGITS[0]); put_utf8(d, VTTS_ZH_DIGITS[mi]); }
                    else cardinal_i(d, mi);
                    put_utf8(d, "分");
                }
                if (sec > 0) { cardinal_i(d, sec); put_utf8(d, "秒"); }
                i = end;
                done = 1;
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

/* (?<!\d)(\d{4})(?=\s*年) -> digits */
static void p_year(const uint32_t *s, int n, zb_t *d) {
    for (int i = 0; i < n;) {
        if (!DG(s, n, i - 1) && DG(s, n, i) && DG(s, n, i + 1) && DG(s, n, i + 2) && DG(s, n, i + 3)) {
            int k = i + 4;
            while (SP(s, n, k)) k++;
            if (AT(s, n, k, 0x5E74)) { digits_u(d, s + i, 4); i += 4; continue; }
        }
        put(d, s[i++]);
    }
}

/* (?<=\d)\s?[~-]\s?(?=\d) -> 到 */
static void p_range(const uint32_t *s, int n, zb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i - 1)) {
            int j = i;
            if (SP(s, n, j)) j++;
            if (AT(s, n, j, '~') || AT(s, n, j, '-')) {
                j++;
                if (SP(s, n, j) && DG(s, n, j + 1)) j++;
                if (DG(s, n, j)) { put_utf8(d, "到"); i = j; continue; }
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![A-Za-z0-9])-(?=\d) -> 负 */
static void p_negative(const uint32_t *s, int n, zb_t *d) {
    for (int i = 0; i < n; i++) {
        if (s[i] == '-' && !AN(s, n, i - 1) && DG(s, n, i + 1)) put_utf8(d, "负");
        else put(d, s[i]);
    }
}

/* (?<![\d.])(\d+)\.(\d+)(?![\d.]) -> number */
static void p_decimal(const uint32_t *s, int n, zb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i) && !DG(s, n, i - 1) && !AT(s, n, i - 1, '.')) {
            int j = i + digit_run(s, n, i);
            if (AT(s, n, j, '.') && DG(s, n, j + 1)) {
                int k = j + 1 + digit_run(s, n, j + 1);
                if (!AT(s, n, k, '.')) { number_u(d, s + i, k - i); i = k; continue; }
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![\d,])\d{1,3}(?:,\d{3})+(?![\d,]) -> number */
static void p_grouped(const uint32_t *s, int n, zb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i) && !DG(s, n, i - 1) && !AT(s, n, i - 1, ',')) {
            int r = digit_run(s, n, i);
            if (r <= 3) {
                int k = i + r, groups = 0;
                while (AT(s, n, k, ',') && DG(s, n, k + 1) && DG(s, n, k + 2) && DG(s, n, k + 3)) { k += 4; groups++; }
                if (groups && !DG(s, n, k) && !AT(s, n, k, ',')) { number_u(d, s + i, k - i); i = k; continue; }
            }
        }
        put(d, s[i++]);
    }
}

/* \d{5,} -> digits, then \d+ -> cardinal */
static void p_digits(const uint32_t *s, int n, zb_t *d, int long_only) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i)) {
            int r = digit_run(s, n, i);
            if (long_only && r < 5) put_cps(d, s + i, r);
            else if (long_only) digits_u(d, s + i, r);
            else cardinal_u(d, s + i, r);
            i += r;
            continue;
        }
        put(d, s[i++]);
    }
}

static int az(uint32_t c) { return (c | 32) >= 'a' && (c | 32) <= 'z'; }

typedef struct { uint32_t *a, *b; int cap; char *out; int out_cap; } en_scratch_t;

/* [A-Za-z][A-Za-z']* -> " " + normalize_en(word) + " " */
static void p_latin(const uint32_t *s, int n, zb_t *d, const en_scratch_t *e) {
    for (int i = 0; i < n;) {
        if (az(s[i])) {
            int j = i + 1;
            while (j < n && (az(s[j]) || s[j] == '\'')) j++;
            int m = vtts_en_normalize(s + i, j - i, e->a, e->b, e->cap, e->out, e->out_cap);
            if (m < 0) { d->err = 1; return; }
            put(d, ' ');
            for (int k = 0; k < m; k++) put(d, (uint8_t)e->out[k]);
            put(d, ' ');
            i = j;
            continue;
        }
        put(d, s[i++]);
    }
}

/* (?<=[一-鿿])\s+(?=[一-鿿]) -> "" */
static void p_join_han(const uint32_t *s, int n, zb_t *d) {
    for (int i = 0; i < n;) {
        if (SP(s, n, i)) {
            int j = i;
            while (SP(s, n, j)) j++;
            if (!(HN(s, n, i - 1) && HN(s, n, j))) put_cps(d, s + i, j - i);
            i = j;
            continue;
        }
        put(d, s[i++]);
    }
}

static int is_mark(uint32_t c) { return c == ',' || c == '.' || c == '?' || c == '!' || c == ';' || c == ':'; }

/* findall([一-鿿]+|[a-z][a-z']*|[,.?!;:]) joined by single spaces; a mark after a mark is dropped */
static void p_words(const uint32_t *s, int n, zb_t *d) {
    int any = 0, last_mark = 0;
    for (int i = 0; i < n;) {
        int j = i;
        if (HN(s, n, i)) {
            while (HN(s, n, j)) j++;
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

int vtts_zh_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, uint32_t *ea,
                      uint32_t *eb, int ecap, char *eout, int eout_cap, const uint32_t **out) {
    zb_t x = {a, 0, cap, 0}, y = {b, 0, cap, 0};
    en_scratch_t e = {ea, eb, ecap, eout, eout_cap};
    p_fullwidth(in, n, &x);
    if (x.err) return -1;
#define PASS(call) do { y.n = 0; call; if (y.err) return -1; zb_t t_ = x; x = y; y = t_; } while (0)
    PASS(p_pause(x.p, x.n, &y));
    PASS(p_symbols(x.p, x.n, &y));
    PASS(p_drop(x.p, x.n, &y));
    PASS(p_code(x.p, x.n, &y));
    PASS(p_iso_date(x.p, x.n, &y));
    PASS(p_money(x.p, x.n, &y));
    PASS(p_percent(x.p, x.n, &y));
    PASS(p_time(x.p, x.n, &y));
    PASS(p_year(x.p, x.n, &y));
    PASS(p_range(x.p, x.n, &y));
    PASS(p_negative(x.p, x.n, &y));
    PASS(p_decimal(x.p, x.n, &y));
    PASS(p_grouped(x.p, x.n, &y));
    PASS(p_digits(x.p, x.n, &y, 1));
    PASS(p_digits(x.p, x.n, &y, 0));
    PASS(p_latin(x.p, x.n, &y, &e));
    PASS(p_join_han(x.p, x.n, &y));
    PASS(p_words(x.p, x.n, &y));
#undef PASS
    *out = x.p;
    return x.n;
}

#endif /* VTTS_ENABLE_ZH */
