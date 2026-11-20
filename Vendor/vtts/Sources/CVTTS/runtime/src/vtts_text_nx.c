/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_nx.c -- the parts of the Dutch, Swedish and Norwegian device front-ends that do not
 * depend on the language: helpers, the scanner normalizer (src/vtts/frontend/scan_norm.py, step by
 * step), the sentence split (scan_norm.split_sentences) and the tagging of plain Latin words
 * (latin.latin_word_lang). The languages are in vtts_text_nx_nl.c and vtts_text_nx_sc.c. Compiled
 * only when one of VTTS_ENABLE_NL, VTTS_ENABLE_SV, VTTS_ENABLE_NO is non-zero. */
#include "vtts_text_nx.h"

#if VTTS_ENABLE_NX

#include <string.h>

#include "vtts_text_nx_int.h"
#include "vtts_text_nx_tables.h"

/* ======================= helpers ======================= */

int nx_dec1(const char *s, uint32_t *c) {
    const unsigned char *p = (const unsigned char *)s;
    if (!p[0]) return 0;
    if (p[0] < 0x80) { *c = p[0]; return 1; }
    int extra = (p[0] >> 5) == 6 ? 1 : (p[0] >> 4) == 14 ? 2 : 3;
    uint32_t v = p[0] & (0x3Fu >> extra);
    for (int k = 1; k <= extra; k++) v = (v << 6) | (p[k] & 0x3F);
    *c = v;
    return extra + 1;
}

int nx_u8_len(const char *s) {
    uint32_t c;
    int l, n = 0;
    while ((l = nx_dec1(s, &c)) > 0) { n++; s += l; }
    return n;
}

int nx_at_u8(const uint32_t *w, int n, int i, const char *k) {
    uint32_t c;
    int l, m = 0;
    if (!*k) return 0;
    while ((l = nx_dec1(k, &c)) > 0) {
        if (i + m >= n || w[i + m] != c) return 0;
        m++;
        k += l;
    }
    return m;
}

int nx_eq_u8(const uint32_t *w, int n, const char *k) {
    if (!*k) return n == 0;
    return n > 0 && nx_at_u8(w, n, 0, k) == n && nx_u8_len(k) == n;
}

int nx_ends_u8(const uint32_t *w, int n, const char *k) {
    int m = nx_u8_len(k);
    return n > m && nx_at_u8(w, n, n - m, k) == m;
}

int nx_index_u8(uint32_t c, const char *set) {
    uint32_t x;
    int l, k = 0;
    while ((l = nx_dec1(set, &x)) > 0) { if (x == c) return k; set += l; k++; }
    return -1;
}

int nx_in_u8(uint32_t c, const char *set) { return nx_index_u8(c, set) >= 0; }

int nx_in_sorted(const char *const *list, int n, const char *w) {
    int lo = 0, hi = n - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2, c = strcmp(list[m], w);
        if (!c) return 1;
        if (c < 0) lo = m + 1; else hi = m - 1;
    }
    return 0;
}

int nx_encode(uint32_t c, char *o) {
    if (c < 0x80) { o[0] = (char)c; return 1; }
    if (c < 0x800) { o[0] = (char)(0xC0 | (c >> 6)); o[1] = (char)(0x80 | (c & 0x3F)); return 2; }
    if (c < 0x10000) {
        o[0] = (char)(0xE0 | (c >> 12)); o[1] = (char)(0x80 | ((c >> 6) & 0x3F)); o[2] = (char)(0x80 | (c & 0x3F));
        return 3;
    }
    o[0] = (char)(0xF0 | (c >> 18)); o[1] = (char)(0x80 | ((c >> 12) & 0x3F));
    o[2] = (char)(0x80 | ((c >> 6) & 0x3F)); o[3] = (char)(0x80 | (c & 0x3F));
    return 4;
}

int nx_in_sorted_cp(const char *const *list, int n, const uint32_t *w, int len) {
    char b[4 * VTTS_NX_MAXW + 1];
    int k = 0;
    if (len > VTTS_NX_MAXW) return 0;
    for (int i = 0; i < len; i++) {
        if (!w[i]) return 0;
        k += nx_encode(w[i], b + k);
    }
    b[k] = 0;
    return nx_in_sorted(list, n, b);
}

void nx_cat(nx_buf *b, const char *s) {
    int l = (int)strlen(s);
    if (b->n + l + 1 > b->cap) { b->err = 1; return; }
    memcpy(b->p + b->n, s, (size_t)l);
    b->n += l;
    b->p[b->n] = 0;
}

void nx_word(nx_buf *b, const char *s) {
    if (b->n) nx_cat(b, " ");
    nx_cat(b, s);
}

static const nx_lang_t *lang_of(int lang) {
    switch (lang) {
#if VTTS_ENABLE_NL
    case VTTS_NX_NL: return &vtts_nx_nl;
#endif
#if VTTS_ENABLE_SV
    case VTTS_NX_SV: return &vtts_nx_sv;
#endif
#if VTTS_ENABLE_NO
    case VTTS_NX_NO: return &vtts_nx_no;
#endif
    default: return 0;
    }
}

int vtts_nx_enabled(int lang) { return lang_of(lang) != 0; }

/* ======================= scanner (scan_norm.normalize) ======================= */

#define IS_W(c) vtts_u_word(c)
#define IS_D(c) ((c) >= '0' && (c) <= '9')
#define IS_SP(c) vtts_u_space(c)
#define LOW(c) vtts_u_lower(c)
#define IS_UP(c) (vtts_u_lower(c) != (c))
#define IS_LETTER(c) (IS_W(c) && (c) != '_' && !IS_D(c))

typedef struct { char *p; int n, cap, err, items, last_mark; } nx_out;

static int is_mark(uint32_t c) { return c == ',' || c == '.' || c == '?' || c == '!' || c == ';' || c == ':'; }

static void out_item(nx_out *o, const char *s, int len) {
    int mark = len == 1 && is_mark((unsigned char)s[0]);
    if (mark && o->items && o->last_mark) return;
    int need = len + (o->items ? 1 : 0);
    if (o->n + need + 1 > o->cap) { o->err = 1; return; }
    if (o->items) o->p[o->n++] = ' ';
    memcpy(o->p + o->n, s, (size_t)len);
    o->n += len;
    o->p[o->n] = 0;
    o->items++;
    o->last_mark = mark;
}

static void out_words(nx_out *o, const char *t) { /* text.split(" "), empty parts skipped */
    while (*t) {
        const char *e = strchr(t, ' ');
        int l = e ? (int)(e - t) : (int)strlen(t);
        if (l) out_item(o, t, l);
        if (!e) break;
        t = e + 1;
    }
}

static void out_mark(nx_out *o, char m) { out_item(o, &m, 1); }

/* a run of code points, lower-cased (low() each), as one word item; prefix: an optional ASCII prefix */
static void out_lower(nx_out *o, const char *prefix, const uint32_t *s, int a, int b) {
    int need = (int)strlen(prefix) + (o->items ? 1 : 0), start = o->n;
    if (b <= a && !*prefix) return;
    if (o->n + need + 1 > o->cap) { o->err = 1; return; }
    if (o->items) o->p[o->n++] = ' ';
    for (const char *p = prefix; *p; p++) o->p[o->n++] = *p;
    for (int i = a; i < b; i++) {
        if (o->n + 5 > o->cap) { o->n = start; o->p[o->n] = 0; o->err = 1; return; }
        o->n += nx_encode(LOW(s[i]), o->p + o->n);
    }
    o->p[o->n] = 0;
    o->items++;
    o->last_mark = 0;
}

/* number words of a language reader into the output */
typedef struct { const nx_lang_t *L; const vtts_nx_spec *sp; const uint32_t *s; int n; nx_out *o; } scan_t;

static char g_tmp[4096];

static nx_buf tmp_buf(void) {
    nx_buf b = {g_tmp, 0, (int)sizeof g_tmp, 0};
    g_tmp[0] = 0;
    return b;
}

/* digits of a number (ASCII), at most this many */
#define NX_DIGITS 512 /* a longer run is cut (such numbers are read one by one) */
typedef struct { char d[NX_DIGITS]; int n; } digits_t;

static void read_digits(scan_t *x, nx_buf *b, const char *d, int n) {
    for (int i = 0; i < n; i++) nx_word(b, x->sp->digits[d[i] - '0']);
}

static uint64_t dval(const char *d, int n) {
    uint64_t v = 0;
    for (int i = 0; i < n; i++) v = v * 10 + (uint64_t)(d[i] - '0');
    return v;
}

/* read_int: a leading zero or more than 15 digits digit by digit; with year 1100-1999 as a year */
static void read_int(scan_t *x, nx_buf *b, const char *d, int n, int year) {
    if (n > 15 || (n > 1 && d[0] == '0')) { read_digits(x, b, d, n); return; }
    uint64_t v = dval(d, n);
    if (year && v >= 1100 && v <= 1999) { x->L->year(b, (int)v); return; }
    x->L->cardinal(b, v);
}

static void read_number(scan_t *x, nx_buf *b, const digits_t *ip, const digits_t *fr, uint32_t mark, int year) {
    read_int(x, b, ip->d, ip->n, year && !fr);
    if (fr) {
        nx_word(b, mark == ',' ? x->sp->comma : x->sp->point);
        if (fr->n <= 2 && fr->d[0] != '0') x->L->cardinal(b, dval(fr->d, fr->n));
        else read_digits(x, b, fr->d, fr->n);
    }
}

static int digits_end(const uint32_t *s, int n, int i) {
    while (i < n && IS_D(s[i])) i++;
    return i;
}

static void dcopy(digits_t *t, const uint32_t *s, int a, int b) {
    for (int i = a; i < b && t->n < NX_DIGITS; i++) t->d[t->n++] = (char)s[i];
}

static int is_thousands_sep(uint32_t c) { return c == '.' || c == ' ' || c == 0xA0 || c == 0x202F; }

/* scan_number: end; ip, fr (fr->n < 0: none), mark */
static int scan_number(const uint32_t *s, int n, int i, digits_t *ip, digits_t *fr, uint32_t *mark) {
    int j = digits_end(s, n, i), grouped = 0;
    ip->n = 0;
    fr->n = -1;
    *mark = 0;
    dcopy(ip, s, i, j);
    if (j - i <= 3 && s[i] != '0' && j < n && is_thousands_sep(s[j])) {
        uint32_t sep = s[j];
        int k = j;
        while (k + 3 < n && s[k] == sep && IS_D(s[k + 1]) && IS_D(s[k + 2]) && IS_D(s[k + 3]) &&
               !(k + 4 < n && IS_D(s[k + 4]))) {
            dcopy(ip, s, k + 1, k + 4);
            k += 4;
        }
        if (k > j) { j = k; grouped = 1; }
    }
    if (j + 1 < n && s[j] == ',' && IS_D(s[j + 1])) {
        int e = digits_end(s, n, j + 1);
        fr->n = 0;
        dcopy(fr, s, j + 1, e);
        *mark = ',';
        return e;
    }
    if (!grouped && j + 1 < n && s[j] == '.' && IS_D(s[j + 1])) {
        int e = digits_end(s, n, j + 1);
        fr->n = 0;
        dcopy(fr, s, j + 1, e);
        *mark = '.';
        return e;
    }
    return j;
}

static int last_is_w(const char *k) { /* is_w(k[-1]) */
    uint32_t c = 0, x;
    int l;
    while ((l = nx_dec1(k, &x)) > 0) { c = x; k += l; }
    return IS_W(c);
}

/* _match_key over a list of n keys (stride bytes apart, key first): index or -1, *len its length */
static int match_key(const uint32_t *s, int n, int i, const void *table, int count, size_t stride, int *len) {
    for (int k = 0; k < count; k++) {
        const char *key = *(const char *const *)((const char *)table + (size_t)k * stride);
        int m = nx_at_u8(s, n, i, key);
        if (!m) continue;
        int e = i + m;
        if (last_is_w(key) && e < n && IS_W(s[e])) continue;
        *len = m;
        return k;
    }
    return -1;
}

static int skip_space(const uint32_t *s, int n, int i) { return i < n && s[i] == ' ' ? i + 1 : i; }

static int rest_blank(const uint32_t *s, int n, int i) {
    for (; i < n; i++) if (!IS_SP(s[i])) return 0;
    return 1;
}

static int ival(const uint32_t *s, int a, int b) {
    int v = 0;
    for (int i = a; i < b; i++) v = v * 10 + (int)(s[i] - '0');
    return v;
}

/* _date: end or 0; d m y (y = -1: none) */
static int scan_date(const uint32_t *s, int n, int i, int *d, int *m, int64_t *y) {
    int j = digits_end(s, n, i);
    if (j - i == 4 && j < n && s[j] == '-') {
        int a = j + 1, b = digits_end(s, n, a);
        if (b - a >= 1 && b - a <= 2 && b < n && s[b] == '-') {
            int c = b + 1, e = digits_end(s, n, c);
            if (e - c >= 1 && e - c <= 2 && !(e < n && (s[e] == '-' || IS_W(s[e])))) {
                int dd = ival(s, c, e), mm = ival(s, a, b);
                if (dd >= 1 && dd <= 31 && mm >= 1 && mm <= 12) { *d = dd; *m = mm; *y = ival(s, i, j); return e; }
            }
        }
        return 0;
    }
    if (j - i >= 1 && j - i <= 2 && j < n && (s[j] == '.' || s[j] == '/' || s[j] == '-')) {
        uint32_t sep = s[j];
        int a = j + 1, b = digits_end(s, n, a);
        if (b - a >= 1 && b - a <= 2 && b < n && s[b] == sep) {
            int c = b + 1, e = digits_end(s, n, c);
            if ((e - c == 2 || e - c == 4) &&
                !(e < n && (IS_W(s[e]) || ((s[e] == '.' || s[e] == '/' || s[e] == '-') && e + 1 < n && IS_D(s[e + 1]))))) {
                int dd = ival(s, i, j), mm = ival(s, a, b);
                if (dd >= 1 && dd <= 31 && mm >= 1 && mm <= 12) {
                    int yy = ival(s, c, e);
                    *d = dd; *m = mm; *y = e - c == 2 ? yy + 2000 : yy;
                    return e;
                }
            }
        }
    }
    return 0;
}

static int time_before(const vtts_nx_spec *sp, const uint32_t *s, int i) {
    int j = i > 0 && s[i - 1] == ' ' ? i - 1 : i;
    for (int k = 0; k < sp->n_time_before; k++) {
        const char *key = sp->time_before[k];
        int m = nx_u8_len(key), a = j - m;
        if (a < 0) continue;
        int ok = 1, q = 0;
        uint32_t c;
        int l;
        const char *p = key;
        while ((l = nx_dec1(p, &c)) > 0) { if (LOW(s[a + q]) != c) { ok = 0; break; } q++; p += l; }
        if (ok && (a == 0 || !IS_W(s[a - 1]))) return 1;
    }
    return 0;
}

static int time_word_after(const vtts_nx_spec *sp, const uint32_t *s, int n, int after) { /* length or -1 */
    for (int k = 0; k < sp->n_time_after; k++) {
        int m = nx_at_u8(s, n, after, sp->time_after[k]);
        if (m && !(after + m < n && IS_W(s[after + m]))) return m;
    }
    return -1;
}

/* _time: end or 0; the reading into b */
static int scan_time(scan_t *x, int i, nx_buf *b) {
    const uint32_t *s = x->s;
    int n = x->n, j = digits_end(s, n, i);
    if (!(j - i >= 1 && j - i <= 2 && j + 2 < n && (s[j] == ':' || s[j] == '.') && IS_D(s[j + 1]) && IS_D(s[j + 2])))
        return 0;
    int h = ival(s, i, j), mi = ival(s, j + 1, j + 3), e = j + 3, sec = -1;
    if (h > 24 || mi > 59 || (e < n && IS_D(s[e]))) return 0;
    if (s[j] == ':' && e + 2 < n && s[e] == ':' && IS_D(s[e + 1]) && IS_D(s[e + 2]) && !(e + 3 < n && IS_D(s[e + 3])) &&
        ival(s, e + 1, e + 3) <= 59) {
        sec = ival(s, e + 1, e + 3);
        e += 3;
    }
    if (e < n && IS_W(s[e])) return 0;
    int after = skip_space(s, n, e), w = time_word_after(x->sp, s, n, after);
    if (s[j] == '.') {
        if (w >= 0) { x->L->time(b, h, mi, -1); return after + w; }
        if (!time_before(x->sp, s, i)) return 0;
        x->L->time(b, h, mi, -1);
        return e;
    }
    if (w >= 0) e = after + w;
    x->L->time(b, h, mi, sec);
    return e;
}

static int phone_sep(uint32_t c) { return c == ' ' || c == '-' || c == '/'; }

static int scan_phone(const uint32_t *s, int n, int i) { /* end or 0 */
    int j = i, plus = s[j] == '+';
    if (plus) j++;
    if (j >= n || !IS_D(s[j]) || (!plus && s[j] != '0')) return 0;
    int total = 0, e;
    for (;;) {
        e = digits_end(s, n, j);
        total += e - j;
        if (e + 1 < n && phone_sep(s[e]) && IS_D(s[e + 1])) { j = e + 1; continue; }
        break;
    }
    if (total < 8 || (e < n && IS_W(s[e]))) return 0;
    return e;
}

static void phone_digits(scan_t *x, nx_buf *b, int a, int e) {
    for (int k = a; k < e; k++) if (IS_D(x->s[k])) nx_word(b, x->sp->digits[x->s[k] - '0']);
}

static int dash_end(const uint32_t *s, int n, int e) {
    if (e + 1 < n && (s[e] == ',' || s[e] == '.' || s[e] == ':') && s[e + 1] == '-' && !(e + 2 < n && IS_W(s[e + 2])))
        return e + 2;
    return e;
}

static int is_one(const digits_t *ip) { return ip->n == 1 && ip->d[0] == '1'; }

/* money(sp, cur, int_s, frac) */
static void money(scan_t *x, nx_buf *b, const vtts_nx_cur *cur, const digits_t *ip, const digits_t *fr) {
    if (!fr || (fr->n == 2 && fr->d[0] == '0' && fr->d[1] == '0')) {
        read_int(x, b, ip->d, ip->n, 0);
        nx_word(b, is_one(ip) ? cur->one : cur->many);
        return;
    }
    if (fr->n == 2 && cur->sub_many[0]) {
        uint64_t cents = dval(fr->d, 2);
        const char *unit = is_one(ip) ? cur->one : cur->many, *sub = cents == 1 ? cur->sub_one : cur->sub_many;
        if (ip->n == 1 && ip->d[0] == '0') { x->L->cardinal(b, cents); nx_word(b, sub); return; }
        read_int(x, b, ip->d, ip->n, 0);
        nx_word(b, unit);
        nx_word(b, x->sp->and_w);
        x->L->cardinal(b, cents);
        nx_word(b, sub);
        return;
    }
    read_number(x, b, ip, fr, ',', 0);
    nx_word(b, cur->many);
}

/* _suffix: end or 0; kind 'w' (words in *w) or 'm' (*cur) */
static int suffix(scan_t *x, int i, const digits_t *ip, char *kind, const char **w, const vtts_nx_cur **cur) {
    const uint32_t *s = x->s;
    const vtts_nx_spec *sp = x->sp;
    int n = x->n, j = skip_space(s, n, i), len;
    if (j < n && s[j] == '%') { *kind = 'w'; *w = sp->percent; return j + 1; }
    if (j < n && s[j] == 0x2030) { *kind = 'w'; *w = sp->permille; return j + 1; }
    int k = match_key(s, n, j, sp->units, sp->n_units, sizeof *sp->units, &len);
    if (k >= 0) { *kind = 'w'; *w = is_one(ip) ? sp->units[k].one : sp->units[k].many; return j + len; }
    k = match_key(s, n, j, sp->cur, sp->n_cur, sizeof *sp->cur, &len);
    if (k >= 0) {
        int e = j + len;
        const char *key = sp->cur[k].key;
        if (key[strlen(key) - 1] == '.' && rest_blank(s, n, e)) e--;
        *kind = 'm';
        *cur = &sp->cur[k];
        return dash_end(s, n, e);
    }
    if (i + 1 < n && !(i + 2 < n && IS_W(s[i + 2]))) {
        for (int q = 0; q < sp->n_dash_money; q++)
            if (nx_at_u8(s, n, i, sp->dash_money[q]) == 2) {
                *kind = 'm';
                *cur = &sp->cur[sp->default_cur];
                return i + 2;
            }
    }
    return 0;
}

static int ordinal_suffix(const vtts_nx_spec *sp, const uint32_t *s, int n, int j) { /* length or 0 */
    for (int k = 0; k < sp->n_ord_suffixes; k++) {
        int m = nx_at_u8(s, n, j, sp->ord_suffixes[k]);
        if (m && !(j + m < n && IS_W(s[j + m]))) return m;
    }
    return 0;
}

static int month_at(const vtts_nx_spec *sp, const uint32_t *s, int n, int j) {
    for (int k = 1; k <= 12; k++) {
        const char *mo = sp->months[k];
        int m = nx_u8_len(mo), ok = j + m <= n, q = 0, l;
        uint32_t c;
        const char *p = mo;
        while (ok && (l = nx_dec1(p, &c)) > 0) { if (LOW(s[j + q]) != c) ok = 0; q++; p += l; }
        if (ok && !(j + m < n && IS_W(s[j + m]))) return 1;
    }
    return 0;
}

static void spell(scan_t *x, const uint32_t *s, int a, int b) {
    for (int i = a; i < b; i++) {
        uint32_t c = LOW(s[i]), k0 = 0;
        for (int k = 0; k < x->sp->n_letters; k++) {
            nx_dec1(x->sp->letters[k].key, &k0);
            if (k0 == c) { out_words(x->o, x->sp->letters[k].val); break; }
        }
    }
}

static void emit(scan_t *x, nx_buf *b) {
    if (b->err) x->o->err = 1;
    out_words(x->o, b->p);
}

/* _code: a run of letters and digits [a, b) */
static void code_run(scan_t *x, int a, int b) {
    const uint32_t *s = x->s;
    int caps = 0;
    for (int i = a; i < b; i++) caps |= IS_UP(s[i]);
    for (int k = a; k < b;) {
        int e = k;
        if (IS_D(s[k])) {
            while (e < b && IS_D(s[e])) e++;
            static digits_t d;
            d.n = 0;
            dcopy(&d, s, k, e);
            nx_buf t = tmp_buf();
            if (caps) read_digits(x, &t, d.d, d.n);
            else read_int(x, &t, d.d, d.n, 0);
            emit(x, &t);
        } else {
            while (e < b && !IS_D(s[e])) e++;
            if (caps || e - k == 1) spell(x, s, k, e);
            else out_lower(x->o, "", s, k, e);
        }
        k = e;
    }
}

/* _word: the run at s[i]; returns its end */
static int word_run(scan_t *x, int i) {
    const uint32_t *s = x->s;
    int n = x->n, j = i;
    while (j < n && ((IS_W(s[j]) && s[j] != '_') ||
                     (s[j] == '\'' && j > i && j + 1 < n && IS_LETTER(s[j + 1]) && IS_LETTER(s[j - 1]))))
        j++;
    int digit = 0, letters = 0, up = 1;
    for (int k = i; k < j; k++) {
        digit |= IS_D(s[k]);
        if (s[k] != '\'') { letters++; up &= IS_UP(s[k]); }
    }
    if (digit) { code_run(x, i, j); return j; }
    if (letters >= 2 && letters <= 5 && up) {
        uint32_t low[8];
        int m = 0;
        for (int k = i; k < j && m < 8; k++) low[m++] = LOW(s[k]);
        if (nx_in_sorted_cp(x->sp->acronym_words, x->sp->n_acronym_words, low, m)) out_lower(x->o, "", s, i, j);
        else spell(x, s, i, j);
        return j;
    }
    out_lower(x->o, "", s, i, j);
    return j;
}

static uint64_t small_val(const digits_t *d) { return d->n <= 18 ? dval(d->d, d->n) : (uint64_t)-1; }

/* _number_at: a digit at s[i] at a token start; returns the end */
static int number_at(scan_t *x, int i, int neg) {
    const uint32_t *s = x->s;
    const vtts_nx_spec *sp = x->sp;
    int n = x->n;
    nx_buf b = tmp_buf();
    if (!neg) {
        int d, m;
        int64_t y;
        int e = scan_date(s, n, i, &d, &m, &y);
        if (e) { x->L->date(&b, d, m, y); emit(x, &b); return e; }
        e = scan_time(x, i, &b);
        if (e) { emit(x, &b); return e; }
        e = scan_phone(s, n, i);
        if (e) { phone_digits(x, &b, i, e); emit(x, &b); return e; }
    }
    int j = digits_end(s, n, i);
    if ((j < n && IS_LETTER(s[j])) || (j + 1 < n && s[j] == ':' && IS_LETTER(s[j + 1]))) {
        int k = ordinal_suffix(sp, s, n, j);
        if (k && !neg) {
            static digits_t d;
            d.n = 0;
            dcopy(&d, s, i, j);
            if (j - i <= 6 && dval(d.d, d.n) > 0) x->L->ordinal(&b, dval(d.d, d.n));
            else read_int(x, &b, d.d, d.n, 0);
            emit(x, &b);
            return j + k;
        }
        if (IS_LETTER(s[j])) {
            int len, u = match_key(s, n, j, sp->units, sp->n_units, sizeof *sp->units, &len);
            if (u >= 0) {
                static digits_t d;
                d.n = 0;
                dcopy(&d, s, i, j);
                read_int(x, &b, d.d, d.n, 0);
                nx_word(&b, is_one(&d) ? sp->units[u].one : sp->units[u].many);
                emit(x, &b);
                return j + len;
            }
            int e = j;
            while (e < n && IS_W(s[e]) && s[e] != '_') e++;
            code_run(x, i, e);
            return e;
        }
    }
    static digits_t ip, fr, ip2, fr2;
    uint32_t mark, mark2;
    int e = scan_number(s, n, i, &ip, &fr, &mark);
    const digits_t *frp = fr.n >= 0 ? &fr : 0;
    if (!frp && e + 1 < n && (s[e] == '-' || s[e] == 0x2013) && IS_D(s[e + 1])) {
        int e2 = scan_number(s, n, e + 1, &ip2, &fr2, &mark2);
        if (fr2.n < 0 && !(e2 < n && (IS_LETTER(s[e2]) || s[e2] == '-' || s[e2] == 0x2013))) {
            read_int(x, &b, ip.d, ip.n, 0);
            nx_word(&b, sp->range);
            read_int(x, &b, ip2.d, ip2.n, 0);
            char kind = 0;
            const char *w = 0;
            const vtts_nx_cur *cur = 0;
            int end = suffix(x, e2, &ip2, &kind, &w, &cur);
            if (end && kind == 'w') { nx_word(&b, w); emit(x, &b); return end; }
            if (end) { nx_word(&b, is_one(&ip2) ? cur->one : cur->many); emit(x, &b); return end; }
            emit(x, &b);
            return e2;
        }
    }
    if (sp->ordinal_dot && !frp && !neg && e - i <= 3 && e + 2 < n && s[e] == '.' && s[e + 1] == ' ' &&
        IS_LETTER(s[e + 2]) && !IS_UP(s[e + 2]) && ip.d[0] != '0') {
        x->L->ordinal(&b, small_val(&ip));
        emit(x, &b);
        return e + 1;
    }
    if (sp->month_ordinal && !frp && !neg && e - i <= 2 && e + 1 < n && s[e] == ' ' && ip.d[0] != '0') {
        uint64_t v = small_val(&ip);
        if (v >= 1 && v <= 31 && month_at(sp, s, n, e + 1)) {
            x->L->ordinal(&b, v);
            emit(x, &b);
            return e;
        }
    }
    if (neg) nx_word(&b, sp->minus);
    char kind = 0;
    const char *w = 0;
    const vtts_nx_cur *cur = 0;
    int end = suffix(x, e, &ip, &kind, &w, &cur);
    if (!end) {
        read_number(x, &b, &ip, frp, mark, !neg);
        emit(x, &b);
        return e;
    }
    if (kind == 'm') money(x, &b, cur, &ip, frp);
    else { read_number(x, &b, &ip, frp, mark, 0); nx_word(&b, w); }
    emit(x, &b);
    return end;
}

/* _money_before: end or 0 */
static int money_before(scan_t *x, int i) {
    const uint32_t *s = x->s;
    const vtts_nx_spec *sp = x->sp;
    int n = x->n;
    for (int q = 0; q < sp->n_cur_before; q++) {
        const vtts_nx_cur *cur = &sp->cur[sp->cur_before[q]];
        int m = nx_at_u8(s, n, i, cur->key);
        if (!m || (last_is_w(cur->key) && i + m < n && IS_W(s[i + m]))) continue;
        int j = skip_space(s, n, i + m);
        if (!(j < n && IS_D(s[j]))) continue;
        static digits_t ip, fr;
        uint32_t mark;
        int e = scan_number(s, n, j, &ip, &fr, &mark);
        e = dash_end(s, n, e);
        if (e < n && IS_W(s[e])) continue;
        nx_buf b = tmp_buf();
        money(x, &b, cur, &ip, fr.n >= 0 ? &fr : 0);
        emit(x, &b);
        return e;
    }
    return 0;
}

int vtts_nx_normalize(int lang, const uint32_t *s, int n, char *out, int cap) {
    const nx_lang_t *L = lang_of(lang);
    if (!L || cap < 1) return -1;
    nx_out o = {out, 0, cap, 0, 0, 0};
    out[0] = 0;
    scan_t x = {L, (const vtts_nx_spec *)L->spec, s, n, &o};
    const vtts_nx_spec *sp = x.sp;
    int i = 0;
    while (i < n) {
        uint32_t c = s[i];
        int start = i == 0 || !IS_W(s[i - 1]);
        if (IS_SP(c)) { i++; continue; }
        if (start) {
            int e = money_before(&x, i);
            if (e) { i = e; continue; }
            int len, k = match_key(s, n, i, sp->abbrev, sp->n_abbrev, sizeof *sp->abbrev, &len);
            if (k >= 0) {
                const char *key = sp->abbrev[k].key;
                out_words(&o, sp->abbrev[k].val);
                i += len;
                if (key[strlen(key) - 1] == '.' && rest_blank(s, n, i)) out_mark(&o, '.');
                continue;
            }
        }
        if ((c == '-' || c == 0x2212) && i + 1 < n && IS_D(s[i + 1]) && (i == 0 || IS_SP(s[i - 1]))) {
            i = number_at(&x, i + 1, 1);
            continue;
        }
        if (c == '+' && start) {
            int p = scan_phone(s, n, i);
            if (p) {
                nx_buf b = tmp_buf();
                nx_word(&b, sp->plus);
                phone_digits(&x, &b, i, p);
                emit(&x, &b);
                i = p;
                continue;
            }
        }
        if (IS_D(c)) {
            i = start ? number_at(&x, i, 0) : word_run(&x, i);
            continue;
        }
        if ((IS_W(c) && c != '_') || (c == '\'' && sp->leading_apostrophe && start && i + 1 < n && IS_LETTER(s[i + 1]))) {
            if (c == '\'') {
                int j = ++i;
                while (j < n && IS_LETTER(s[j])) j++;
                out_lower(&o, "'", s, i, j);
                i = j;
                continue;
            }
            i = word_run(&x, i);
            continue;
        }
        if (is_mark(c)) {
            if (c == '.' && i + 2 < n && s[i + 1] == '.' && s[i + 2] == '.') {
                out_mark(&o, ',');
                while (i < n && s[i] == '.') i++;
                continue;
            }
            out_mark(&o, (char)c);
            i++;
            continue;
        }
        if (c == 0x2026 || c == 0x2013 || c == 0x2014) { out_mark(&o, ','); i++; continue; }
        if (c == '-') {
            if ((i == 0 || IS_SP(s[i - 1])) && (i + 1 >= n || IS_SP(s[i + 1]))) out_mark(&o, ',');
            i++;
            continue;
        }
        for (int k = 0; k < sp->n_symbols; k++) {
            uint32_t sc;
            nx_dec1(sp->symbols[k].key, &sc);
            if (sc == c) { out_words(&o, sp->symbols[k].val); break; }
        }
        i++;
    }
    return o.err ? -1 : o.n;
}

/* ======================= sentences (scan_norm.split_sentences) ======================= */

static int cjk_end(uint32_t c) {
    return c == 0x3002 || c == 0xFF01 || c == 0xFF1F || c == 0xFF1B || c == 0x0964 || c == 0x0965;
}

static const char *const FINAL_ABBREV[] = {"enz.", "etc.", "osv.", "m.m.", "mv.", "e.d.", "e.a.", "o.l."};

static int in_abbrev_keys(const vtts_nx_spec *sp, const uint32_t *w, int n) { /* w + "." is a key */
    for (int k = 0; k < sp->n_abbrev; k++) {
        const char *key = sp->abbrev[k].key;
        int m = nx_u8_len(key);
        if (m == n + 1 && nx_at_u8(w, n, 0, key) == 0 && key[strlen(key) - 1] == '.') {
            uint32_t buf[64];
            if (n + 1 > 64) continue;
            memcpy(buf, w, sizeof(uint32_t) * (size_t)n);
            buf[n] = '.';
            if (nx_eq_u8(buf, n + 1, key)) return 1;
        }
    }
    return 0;
}

static int keeps_dot(const vtts_nx_spec *sp, const uint32_t *s, int z, int i) {
    int a = i;
    while (a > 0 && !IS_SP(s[a - 1])) a--;
    int wn = i - a, j = i + 1;
    while (j < z && IS_SP(s[j])) j++;
    uint32_t nxt = j < z ? s[j] : 0;
    if (!wn) return 0;
    if (nxt && IS_UP(nxt) && wn < 63) {
        uint32_t buf[64];
        memcpy(buf, s + a, sizeof(uint32_t) * (size_t)wn);
        buf[wn] = '.';
        for (size_t k = 0; k < sizeof FINAL_ABBREV / sizeof *FINAL_ABBREV; k++)
            if (nx_eq_u8(buf, wn + 1, FINAL_ABBREV[k])) return 0;
    }
    if (in_abbrev_keys(sp, s + a, wn) || (wn == 1 && IS_LETTER(s[a]))) return 1;
    if (sp->ordinal_dot && wn >= 1 && wn <= 3 && nxt && IS_LETTER(nxt) && !IS_UP(nxt)) {
        int all = 1;
        for (int k = a; k < i; k++) all &= IS_D(s[k]);
        if (all) return 1;
    }
    return 0;
}

static int all_space(const uint32_t *t, int a, int b) {
    for (int k = a; k < b; k++) if (!IS_SP(t[k])) return 0;
    return 1;
}

/* the text is t[a0, z0) after strip(); st->start is the start of the current piece */
int vtts_nx_next_sentence(int lang, const uint32_t *t, int z, vtts_nx_split *st, int *s, int *e) {
    const nx_lang_t *L = lang_of(lang);
    if (!L) return 0;
    const vtts_nx_spec *sp = (const vtts_nx_spec *)L->spec;
    if (!st->init) {
        int a = 0, b = z;
        while (a < b && IS_SP(t[a])) a++;
        while (b > a && IS_SP(t[b - 1])) b--;
        st->start = st->i = a;
        st->end = b;
        st->init = 1;
    }
    int n = st->end;
    const uint32_t *base = t;
    while (st->i < n) {
        int i = st->i, cut = -1;
        uint32_t c = base[i];
        if (cjk_end(c)) cut = i + 1;
        else if ((c == '.' || c == '!' || c == '?' || c == ';') && i + 1 < n && IS_SP(base[i + 1]) &&
                 !(c == '.' && i > 0 && base[i - 1] >= 0x0E01 && base[i - 1] <= 0x0E4E)) {
            cut = i + 1;
            /* keeps_dot looks back over the whole stripped text (Python's s), so pass it as is */
            if (c == '.' && keeps_dot(sp, base, n, i)) cut = -1;
        }
        if (cut < 0) { st->i++; continue; }
        int ee = cut;
        while (ee < n && IS_SP(base[ee])) ee++;
        int ps = st->start;
        st->start = ee;
        st->i = ee;
        if (!all_space(base, ps, cut)) { *s = ps; *e = cut; return 1; }
    }
    if (st->start < n) {
        int ps = st->start;
        st->start = n;
        if (!all_space(base, ps, n)) { *s = ps; *e = n; return 1; }
    }
    return 0;
}

/* ======================= tagging (latin.latin_word_lang) ======================= */

static int plain_latin(const uint32_t *w, int n) { /* lang._is_plain_latin */
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
    for (int i = 0; i + 1 < n; i++) if (w[i] >= 'a' && w[i] <= 'z' && w[i + 1] >= 'A' && w[i + 1] <= 'Z') return 1;
    return 0;
}

int vtts_nx_word_lang(int lang, const uint32_t *w, int n) {
    const nx_lang_t *L = lang_of(lang);
    if (!L || n <= 0) return -1;
    const vtts_nx_spec *sp = (const vtts_nx_spec *)L->spec;
    for (int i = 0; i < n; i++) if (nx_in_u8(w[i], sp->own)) return 1;
    if (!plain_latin(w, n)) return -1;
    static char low[1025]; /* no list word is longer: a longer word is in no list */
    int ln = n < 1024 ? n : 1024;
    for (int i = 0; i < ln; i++) low[i] = (char)(w[i] >= 'A' && w[i] <= 'Z' ? w[i] + 32 : w[i]);
    low[ln] = 0;
    if (n <= 1024) {
        if (nx_in_sorted(sp->native, sp->n_native, low) || nx_in_sorted(sp->table_keys, sp->n_table_keys, low)) return 1;
        if (vtts_lt_english_word(low)) return 0;
    }
    int all_caps = 1, all_valid = 1;
    for (int a = 0; a < n;) {
        int b = a;
        while (b < n && w[b] != '-' && w[b] != '\'') b++;
        if (b > a) {
            int len = b - a, caps = len >= 2 && len <= 5;
            if (camel(w + a, len)) return 0;
            for (int k = a; k < b; k++) caps &= w[k] >= 'A' && w[k] <= 'Z';
            all_caps &= caps;
            if (all_valid) all_valid = b <= 1024 && L->valid_spelling(low + a, len);
        }
        a = b + 1;
    }
    if (n == 1 || all_caps) return 1;
    return all_valid ? 1 : 0;
}

/* ======================= words ======================= */

int vtts_nx_word_ids(int lang, const uint32_t *w, int n, void *scratch, uint8_t *out, int cap) {
    const nx_lang_t *L = lang_of(lang);
    if (!L || n <= 0) return 0;
    return L->word_ids(w, n, scratch, out, cap);
}

#endif /* VTTS_ENABLE_NX */
