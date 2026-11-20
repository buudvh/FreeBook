/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_tr.c -- Turkish device front-end (token set tr-en). Mirrors src/vtts/frontend/tr/
 * (normalize_tr.py pass by pass, g2p_tr.py), the Turkish rules of latin.py (latin_word_lang,
 * split_elision) and latin_norm.py. All tables are in the generated vtts_text_tr_tables.h; no
 * blob. Compiled only with VTTS_ENABLE_TR. */
#include "vtts_langs.h"
#if VTTS_ENABLE_TR /* else an empty unit (vtts_langs.h) */

#include "vtts_text_tr.h"

#include <string.h>

#include "vtts_text_ltx.h"
#include "vtts_text_tr_tables.h"

#define N_OF(a) ((int)(sizeof(a) / sizeof((a)[0])))
#define IN X_IN
#define W X_W
#define DG X_DG
#define SP X_SP
#define AT X_AT
#define WDC X_WDC

static int tr_vowel(uint32_t c) { return x_in_u8(c, VTTS_TR_VOWELS); }

/* ======================= numbers (normalize_tr) ======================= */

static void card_v(x_lb *d, uint64_t v) { /* cardinal(v), 0 < v < 10**15 */
    static const uint64_t SC[3] = {1000000000000ull, 1000000000ull, 1000000ull};
    static const char *const NAMES[3] = {"trilyon", "milyar", "milyon"};
    int any = 0;
#define SEPA() do { if (any) x_put(d, ' '); any = 1; } while (0)
    for (int k = 0; k < 3; k++) {
        uint64_t q = v / SC[k];
        v %= SC[k];
        if (!q) continue;
        SEPA();
        card_v(d, q);
        x_put(d, ' ');
        x_puts8(d, NAMES[k]);
    }
    int th = (int)(v / 1000), r = (int)(v % 1000);
    if (th) {
        SEPA();
        if (th > 1) { card_v(d, (uint64_t)th); x_put(d, ' '); }
        x_puts8(d, "bin");
    }
    int h = r / 100, t = r % 100 / 10, u = r % 10;
    if (h) { SEPA(); if (h > 1) { x_puts8(d, VTTS_TR_ONES[h]); x_put(d, ' '); } x_puts8(d, "yüz"); }
    if (t) { SEPA(); x_puts8(d, VTTS_TR_TENS[t]); }
    if (u) { SEPA(); x_puts8(d, VTTS_TR_ONES[u]); }
#undef SEPA
}

static void card(x_lb *d, const uint32_t *s, int n) {
    int st, nd = x_sig(s, n, &st);
    if (!nd) { x_puts8(d, VTTS_TR_ONES[0]); return; }
    if (nd > 15) { x_digit_words(d, VTTS_TR_DIGITS, s, n, st); return; }
    card_v(d, x_value(s, n, st));
}

static void card_i(x_lb *d, int v) {
    if (!v) { x_puts8(d, VTTS_TR_ONES[0]); return; }
    card_v(d, (uint64_t)v);
}

static void read_number(x_lb *d, const uint32_t *s, int n) {
    int ie, f0;
    uint32_t mark;
    x_parse_number(s, n, &ie, &f0, &mark);
    card(d, s, ie);
    if (f0 < 0) return;
    x_put(d, ' ');
    x_puts8(d, mark == ',' ? VTTS_TR_COMMA : VTTS_TR_PERIOD);
    x_put(d, ' ');
    if (f0 < n && n - f0 <= 2 && s[f0] != '0') card(d, s + f0, n - f0);
    else x_digit_words(d, VTTS_TR_DIGITS, s, n, f0);
}

static void number(x_lb *d, const uint32_t *s, int n, int neg) {
    if (neg) x_puts8(d, "eksi ");
    read_number(d, s, n);
}

/* tr_lower of one code point into d (I -> ı, İ -> i; i + U+0307 handled by the caller) */
static void lower_put(x_lb *d, uint32_t c) {
    if (c == 'I') x_put(d, 0x131);
    else if (c == 0x130) x_put(d, 'i');
    else x_put(d, vtts_u_lower(c));
}

/* join_suffix(words since st, suffix s[a..b)): dört + vowel -> dörd; the suffix in Turkish lower case */
static void join_suffix(x_lb *d, int st, const uint32_t *s, int a, int b) {
    if (b <= a) return;
    if (x_tail_is(d, st, "dört") && tr_vowel(s[a])) d->p[d->n - 1] = 'd'; /* suffix[0] as written */
    int last_i = 0;
    for (int i = a; i < b; i++) {
        if (s[i] == 0x307 && last_i) { last_i = 0; continue; } /* "i̇" -> "i" */
        lower_put(d, s[i]);
        last_i = d->n && d->p[d->n - 1] == 'i';
    }
}

/* (?:'([^\W\d_]+))? at p: the end of the letters (or p) and the letters [*a, *b) */
static int suffix_at(const uint32_t *s, int n, int p, int *a, int *b) {
    *a = *b = p;
    if (AT(p, '\'') && X_LT(p + 1)) {
        int q = p + 1;
        while (X_LT(q)) q++;
        *a = p + 1;
        *b = q;
        return q;
    }
    return p;
}

/* ordinal(int(s)): the last number word takes -(I)ncI by vowel harmony (dört -> dördüncü) */
static void ordinal(x_lb *d, const uint32_t *s, int n) {
    int st = d->n;
    card(d, s, n);
    int ls = d->n;
    while (ls > st && d->p[ls - 1] != ' ') ls--;
    if (x_tail_is(d, ls, "dört")) d->p[d->n - 1] = 'd';
    uint32_t v = 'e';
    for (int i = d->n - 1; i >= ls; i--) if (tr_vowel(d->p[i])) { v = d->p[i]; break; }
    uint32_t h = v == 'a' || v == 0x131 ? 0x131 : v == 'e' || v == 'i' ? 'i' : v == 'o' || v == 'u' ? 'u' : 0xFC;
    if (!(d->n > ls && tr_vowel(d->p[d->n - 1]))) x_put(d, h);
    x_put(d, 'n');
    x_put(d, 'c');
    x_put(d, h);
}

/* ======================= normalization passes ======================= */

typedef void (*pass_fn)(const uint32_t *s, int n, x_lb *d);

static void p_apostrophe(const uint32_t *s, int n, x_lb *d) { for (int i = 0; i < n; i++) x_put(d, s[i] == 0x2019 ? '\'' : s[i]); }

static void p_drop(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n; i++) x_put(d, x_in_u8(s[i], VTTS_TR_DROP) ? ' ' : s[i]);
}

/* _date(d, m, y, suffix): " out " or the original text */
static int date_out(x_lb *d, int dd, int mm, const uint32_t *y, int yl, const uint32_t *s, int sa, int sb) {
    if (!(dd >= 1 && dd <= 31 && mm >= 1 && mm <= 12)) return 0;
    x_put(d, ' ');
    card_i(d, dd);
    x_put(d, ' ');
    x_puts8(d, VTTS_TR_MONTHS[mm]);
    x_put(d, ' ');
    int st = d->n;
    card_i(d, x_val(y, 0, yl));
    join_suffix(d, st, s, sa, sb);
    x_put(d, ' ');
    return 1;
}

/* (?<![\d-])(\d{4})-(\d{1,2})-(\d{1,2})(?![\d-])(?:'(letters))? */
static void p_date_iso(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !DG(i - 1) && !AT(i - 1, '-') && DG(i + 1) && DG(i + 2) && DG(i + 3) && AT(i + 4, '-')) {
            int m0 = i + 5, ml = x_drun(s, n, m0);
            if (ml >= 1 && ml <= 2 && AT(m0 + ml, '-')) {
                int d0 = m0 + ml + 1, dl = x_drun(s, n, d0);
                if (dl >= 1 && dl <= 2 && !AT(d0 + dl, '-')) {
                    int sa, sb, e = suffix_at(s, n, d0 + dl, &sa, &sb);
                    if (!date_out(d, x_val(s, d0, dl), x_val(s, m0, ml), s + i, 4, s, sa, sb)) x_putn(d, s + i, e - i);
                    i = e;
                    continue;
                }
            }
        }
        x_put(d, s[i++]);
    }
}

/* (?<![\d/.])(\d{1,2})[/.](\d{1,2})[/.](\d{4})(?![\d/]|\.\d)(?:'(letters))? */
static void p_date_dmy(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !DG(i - 1) && !AT(i - 1, '/') && !AT(i - 1, '.')) {
            int r1 = x_drun(s, n, i);
            if (r1 <= 2 && (AT(i + r1, '/') || AT(i + r1, '.'))) {
                int m0 = i + r1 + 1, r2 = x_drun(s, n, m0);
                if (r2 >= 1 && r2 <= 2 && (AT(m0 + r2, '/') || AT(m0 + r2, '.'))) {
                    int y0 = m0 + r2 + 1, ry = x_drun(s, n, y0), e = y0 + ry;
                    if (ry == 4 && !AT(e, '/') && !(AT(e, '.') && DG(e + 1))) {
                        int sa, sb, e2 = suffix_at(s, n, e, &sa, &sb);
                        if (!date_out(d, x_val(s, i, r1), x_val(s, m0, r2), s + y0, 4, s, sa, sb)) x_putn(d, s + i, e2 - i);
                        i = e2;
                        continue;
                    }
                }
            }
        }
        x_put(d, s[i++]);
    }
}

static int hours(const uint32_t *s, int n, int i, int hl[3]) {
    int k = 0;
    if ((AT(i, '0') || AT(i, '1')) && DG(i + 1)) hl[k++] = 2;
    if (DG(i)) hl[k++] = 1;
    if (AT(i, '2') && IN(i + 1) && s[i + 1] >= '0' && s[i + 1] <= '4') hl[k++] = 2;
    return k;
}

static int m05(const uint32_t *s, int n, int j) { return IN(j) && s[j] >= '0' && s[j] <= '5' && DG(j + 1); }

/* _time(h, mi, sec, suffix) */
static void time_out(x_lb *d, int h, int mi, int sec, const uint32_t *s, int sa, int sb) {
    x_put(d, ' ');
    int st = d->n;
    card_i(d, h);
    if (mi) { x_put(d, ' '); card_i(d, mi); }
    if (sec > 0) { x_put(d, ' '); card_i(d, sec); }
    join_suffix(d, st, s, sa, sb);
    x_put(d, ' ');
}

/* (?<![\d:])H:M(?::S)?(?![\d:])(?:'(letters))? */
static void p_time(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n;) {
        int hl[3], nh = DG(i) && !DG(i - 1) && !AT(i - 1, ':') ? hours(s, n, i, hl) : 0, end = -1;
        for (int c = 0; c < nh && end < 0; c++) {
            int j = i + hl[c];
            if (!(AT(j, ':') && m05(s, n, j + 1))) continue;
            int k = j + 3, has = AT(k, ':') && m05(s, n, k + 1);
            for (int sv = has; sv >= 0 && end < 0; sv--) {
                int k2 = sv ? k + 3 : k;
                if (!DG(k2) && !AT(k2, ':')) {
                    int sa, sb;
                    end = suffix_at(s, n, k2, &sa, &sb);
                    time_out(d, x_val(s, i, hl[c]), x_val(s, j + 1, 2), sv ? x_val(s, k + 1, 2) : 0, s, sa, sb);
                }
            }
        }
        if (end >= 0) { i = end; continue; }
        x_put(d, s[i++]);
    }
}

/* \b(saat|Saat)\s+H\.M(?![\d.,])(?:'(letters))? -> keyword + _time */
static void p_time_dot(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n;) {
        int end = -1;
        if (!W(i - 1) && (AT(i, 's') || AT(i, 'S')) && x_key_at(s, n, i + 1, "aat") && SP(i + 4)) {
            int p = i + 4;
            while (SP(p)) p++;
            int hl[3], nh = hours(s, n, p, hl);
            for (int c = 0; c < nh && end < 0; c++) {
                int j = p + hl[c];
                if (AT(j, '.') && m05(s, n, j + 1) && !DG(j + 3) && !AT(j + 3, '.') && !AT(j + 3, ',')) {
                    int sa, sb;
                    end = suffix_at(s, n, j + 3, &sa, &sb);
                    x_putn(d, s + i, 4);
                    time_out(d, x_val(s, p, hl[c]), x_val(s, j + 1, 2), 0, s, sa, sb);
                }
            }
        }
        if (end >= 0) { i = end; continue; }
        x_put(d, s[i++]);
    }
}

static int sep(const uint32_t *s, int n, int i) { return SP(i) || AT(i, '-'); }

/* \(?0?\d{3}\)?[\s-]\d{3}[\s-]\d{2}[\s-]\d{2}(?![\d]) at p: the end or -1 */
static int phone_body(const uint32_t *s, int n, int p) {
    int q0 = p + AT(p, '(');
    for (int zero = AT(q0, '0'); zero >= 0; zero--) {
        int q = q0 + zero;
        if (!(DG(q) && DG(q + 1) && DG(q + 2))) continue;
        int e = q + 3;
        for (int paren = AT(e, ')'); paren >= 0; paren--) {
            int f = e + paren;
            if (!sep(s, n, f) || x_drun(s, n, f + 1) != 3) continue;
            f += 4;
            if (!sep(s, n, f) || x_drun(s, n, f + 1) != 2) continue;
            f += 3;
            if (!sep(s, n, f) || x_drun(s, n, f + 1) != 2) continue;
            return f + 3;
        }
    }
    return -1;
}

/* (?<![\d])(?:\+\d{1,3}[\s-])?BODY | (?<![\d.,])0\d{10}(?![\d]) -> phone_digits */
static void p_phone(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n;) {
        int e = -1;
        if (!DG(i - 1)) {
            for (int pre = AT(i, '+'); pre >= 0 && e < 0; pre--) {
                int p = i;
                if (pre) {
                    int r = x_drun(s, n, i + 1);
                    if (!(r >= 1 && r <= 3 && sep(s, n, i + 1 + r))) continue;
                    p = i + 2 + r;
                }
                e = phone_body(s, n, p);
            }
        }
        if (e < 0 && AT(i, '0') && !DG(i - 1) && !AT(i - 1, '.') && !AT(i - 1, ',') && x_drun(s, n, i) == 11) e = i + 11;
        if (e >= 0) {
            int cnt = 0;
            for (int q = i; q < e; q++) cnt += vtts_u_digit(s[q]) >= 0;
            if (cnt < 7 && s[i] != '0') x_putn(d, s + i, e - i);
            else {
                x_put(d, ' ');
                if (s[i] == '+') x_puts8(d, "artı ");
                x_digit_words(d, VTTS_TR_DIGITS, s, e, i);
                x_put(d, ' ');
            }
            i = e;
            continue;
        }
        x_put(d, s[i++]);
    }
}

/* _money(num, cur, suffix) */
static void money_out(x_lb *d, const uint32_t *num, int nn, int k, const uint32_t *s, int sa, int sb) {
    const char *name = VTTS_TR_CURRENCY[k][1], *cents = NULL;
    for (int q = 0; q < VTTS_TR_CENTS_N; q++) if (!strcmp(VTTS_TR_CENTS[q][0], name)) cents = VTTS_TR_CENTS[q][1];
    int ie, f0;
    uint32_t mark;
    x_parse_number(num, nn, &ie, &f0, &mark);
    x_put(d, ' ');
    int st = d->n;
    if (f0 >= 0 && nn - f0 == 2 && cents) {
        int c = x_val(num, f0, 2);
        card(d, num, ie);
        x_put(d, ' ');
        x_puts8(d, name);
        if (c) { x_put(d, ' '); card_i(d, c); x_put(d, ' '); x_puts8(d, cents); }
    } else {
        number(d, num, nn, 0);
        x_put(d, ' ');
        x_puts8(d, name);
    }
    join_suffix(d, st, s, sa, sb);
    x_put(d, ' ');
}

typedef struct { const char *const (*keys)[3]; int nk, key, end; } keys_m;

static int ok_keys(const uint32_t *s, int n, int e, void *u) { /* \s?(KEY)(?![\w]) */
    keys_m *m = u;
    for (int sp = SP(e); sp >= 0; sp--)
        for (int k = 0; k < m->nk; k++) {
            int l = x_key_at(s, n, e + sp, m->keys[k][0]);
            if (l && !W(e + sp + l)) { m->key = k; m->end = e + sp + l; return 1; }
        }
    return 0;
}

/* (CUR)\s?(NUM)(?:'(letters))? */
static void p_money_before(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n;) {
        int e = -1, j = 0, k;
        for (k = 0; k < VTTS_TR_CURRENCY_N && e < 0; k++) {
            int l = x_key_at(s, n, i, VTTS_TR_CURRENCY[k][0]);
            if (!l) continue;
            for (int sp = SP(i + l); sp >= 0 && e < 0; sp--) {
                j = i + l + sp;
                e = x_num_match(s, n, j, x_ok_always, NULL);
            }
        }
        if (e >= 0) {
            int sa, sb, end = suffix_at(s, n, e, &sa, &sb);
            money_out(d, s + j, e - j, k - 1, s, sa, sb);
            i = end;
            continue;
        }
        x_put(d, s[i++]);
    }
}

/* (?<![\w.,])(NUM)\s?(CUR)(?![\w])(?:'(letters))? */
static void p_money_after(const uint32_t *s, int n, x_lb *d) {
    keys_m m = {VTTS_TR_CURRENCY, VTTS_TR_CURRENCY_N, 0, 0};
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int e = x_num_match(s, n, i, ok_keys, &m);
            if (e >= 0) {
                int sa, sb, end = suffix_at(s, n, m.end, &sa, &sb);
                money_out(d, s + i, e - i, m.key, s, sa, sb);
                i = end;
                continue;
            }
        }
        x_put(d, s[i++]);
    }
}

static void percent_out(x_lb *d, const uint32_t *s, int n, int j, int e, int p) {
    int sa, sb;
    (void)suffix_at(s, n, p, &sa, &sb);
    x_puts8(d, " yüzde ");
    int st = d->n;
    number(d, s + j, e - j, 0);
    join_suffix(d, st, s, sa, sb);
    x_put(d, ' ');
}

/* %\s?(NUM)(?:'(letters))? */
static void p_percent_before(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n;) {
        if (AT(i, '%')) {
            int e = -1, j = -1;
            for (int sp = SP(i + 1); sp >= 0 && e < 0; sp--) {
                j = i + 1 + sp;
                e = x_num_match(s, n, j, x_ok_always, NULL);
            }
            if (e >= 0) {
                int sa, sb, end = suffix_at(s, n, e, &sa, &sb);
                percent_out(d, s, n, j, e, e);
                i = end;
                continue;
            }
        }
        x_put(d, s[i++]);
    }
}

static int ok_pct(const uint32_t *s, int n, int e, void *u) { /* \s?% */
    int *end = u;
    if (SP(e) && AT(e + 1, '%')) { *end = e + 2; return 1; }
    if (AT(e, '%')) { *end = e + 1; return 1; }
    return 0;
}

/* (?<![\w.,])(NUM)\s?%(?:'(letters))? */
static void p_percent_after(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int pe = 0, e = x_num_match(s, n, i, ok_pct, &pe);
            if (e >= 0) {
                int sa, sb, end = suffix_at(s, n, pe, &sa, &sb);
                percent_out(d, s, n, i, e, pe);
                i = end;
                continue;
            }
        }
        x_put(d, s[i++]);
    }
}

/* (?<![\w.,])(-?)(NUM)\s?(UNITS)(?![\w])(?:'(letters))? -> _unit */
static void p_unit(const uint32_t *s, int n, x_lb *d) {
    keys_m m = {VTTS_TR_UNITS, VTTS_TR_UNITS_N, 0, 0};
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int j = i + AT(i, '-'), e = x_num_match(s, n, j, ok_keys, &m);
            if (e >= 0) {
                int sa, sb, end = suffix_at(s, n, m.end, &sa, &sb), speed = VTTS_TR_UNITS[m.key][2][0] != 0;
                x_puts8(d, speed ? " saatte " : " ");
                int st = d->n;
                number(d, s + j, e - j, j > i);
                x_put(d, ' ');
                x_puts8(d, speed ? "kilometre" : VTTS_TR_UNITS[m.key][1]);
                join_suffix(d, st, s, sa, sb);
                x_put(d, ' ');
                i = end;
                continue;
            }
        }
        x_put(d, s[i++]);
    }
}

static int tr_lower_letter(uint32_t c) {
    return (c >= 'a' && c <= 'z') || c == 0xE7 || c == 0x11F || c == 0x131 || c == 0xF6 || c == 0x15F || c == 0xFC ||
           c == 0xE2 || c == 0xEE || c == 0xFB;
}

/* (?<![\w.,])(\d+)\.(?=\s+[a-zçğıöşü]) -> ordinal */
static void p_ordinal(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !WDC(i - 1)) {
            int r = x_drun(s, n, i), p = i + r;
            if (AT(p, '.') && SP(p + 1)) {
                int q = p + 1;
                while (SP(q)) q++;
                if (IN(q) && tr_lower_letter(s[q]) && s[q] != 0xE2 && s[q] != 0xEE && s[q] != 0xFB) {
                    x_put(d, ' ');
                    ordinal(d, s + i, r);
                    x_put(d, ' ');
                    i = p + 1;
                    continue;
                }
            }
        }
        x_put(d, s[i++]);
    }
}

/* (?<![\w.,])(\d+)\s?[-–]\s?(\d+)(?![\w']) -> " a ile b " */
static void p_range(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !WDC(i - 1)) {
            int r1 = x_drun(s, n, i), p = i + r1, q = -1;
            if (SP(p)) { if (AT(p + 1, '-') || AT(p + 1, 0x2013)) q = p + 2; }
            else if (AT(p, '-') || AT(p, 0x2013)) q = p + 1;
            if (q >= 0) {
                int b0 = SP(q) && DG(q + 1) ? q + 1 : DG(q) ? q : -1;
                if (b0 >= 0) {
                    int r2 = x_drun(s, n, b0);
                    if (!W(b0 + r2) && !AT(b0 + r2, '\'')) {
                        x_put(d, ' ');
                        card(d, s + i, r1);
                        x_puts8(d, " ile ");
                        card(d, s + b0, r2);
                        x_put(d, ' ');
                        i = b0 + r2;
                        continue;
                    }
                }
            }
        }
        x_put(d, s[i++]);
    }
}

static void p_pause(const uint32_t *s, int n, x_lb *d) { x_pause(s, n, d); }

static const char *letter_name(uint32_t c) {
    for (int k = 0; k < VTTS_TR_LETTERS_N; k++) if (VTTS_TR_LETTERS[k].cp == c) return VTTS_TR_LETTERS[k].s;
    return NULL;
}

static void p_code(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n;) {
        if ((x_upper_az(s[i]) || (s[i] >= '0' && s[i] <= '9')) && !W(i - 1)) {
            int j = i, up = 0, dg = 0;
            while (IN(j) && (x_upper_az(s[j]) || (s[j] >= '0' && s[j] <= '9'))) { up |= x_upper_az(s[j]); dg |= !x_upper_az(s[j]); j++; }
            if (up && dg && !W(j)) {
                x_put(d, ' ');
                for (int k = i; k < j; k++) {
                    if (k > i) x_put(d, ' ');
                    if (x_upper_az(s[k])) x_puts8(d, letter_name(s[k] + 32));
                    else x_puts8(d, VTTS_TR_DIGITS[s[k] - '0']);
                }
                x_put(d, ' ');
                i = j;
                continue;
            }
        }
        x_put(d, s[i++]);
    }
}

/* (?<![\w.,])(-?)(NUM)(?![\d])(?:'(letters))? -> " join_suffix(number) " */
static void p_number(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int j = i + AT(i, '-'), e = x_num_match(s, n, j, x_ok_nodigit, NULL);
            if (e >= 0) {
                int sa, sb, end = suffix_at(s, n, e, &sa, &sb);
                x_put(d, ' ');
                int st = d->n;
                number(d, s + j, e - j, j > i);
                join_suffix(d, st, s, sa, sb);
                x_put(d, ' ');
                i = end;
                continue;
            }
        }
        x_put(d, s[i++]);
    }
}

static void p_symbols(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n; i++) {
        const char *r = NULL;
        for (int k = 0; k < VTTS_TR_SYMBOLS_N && !r; k++) if (VTTS_TR_SYMBOLS[k].cp == s[i]) r = VTTS_TR_SYMBOLS[k].s;
        if (r) x_puts8(d, r);
        else x_put(d, s[i] == '-' ? ' ' : s[i]);
    }
}

static void p_acronym(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n;) {
        if (x_upper_az(s[i]) && !W(i - 1)) {
            int j = i;
            while (IN(j) && x_upper_az(s[j])) j++;
            if (j - i >= 2 && j - i <= 5 && !W(j)) {
                char low[8];
                for (int k = i; k < j; k++) low[k - i] = (char)(s[k] + 32);
                low[j - i] = 0;
                if (x_in_sorted(VTTS_TR_ACRONYM_WORDS, VTTS_TR_ACRONYM_WORDS_N, low)) {
                    for (int k = i; k < j; k++) x_put(d, s[k] + 32);
                } else {
                    for (int k = i; k < j; k++) {
                        if (k > i) x_put(d, ' ');
                        x_puts8(d, letter_name(s[k] + 32));
                    }
                }
                i = j;
                continue;
            }
        }
        x_put(d, s[i++]);
    }
}

/* SUFFIX_START (?<![^\W\d_])'(?=[^\W\d_]) -> U+02BC */
static void p_suffix_start(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n; i++) x_put(d, s[i] == '\'' && !X_LT(i - 1) && X_LT(i + 1) ? 0x2BC : s[i]);
}

/* tr_lower, then finish()'s lower() (idempotent after tr_lower) */
static void p_lower(const uint32_t *s, int n, x_lb *d) {
    int last_i = 0;
    for (int i = 0; i < n; i++) {
        if (s[i] == 0x307 && last_i) { last_i = 0; continue; }
        lower_put(d, s[i]);
        last_i = d->n && d->p[d->n - 1] == 'i';
    }
}

static void p_words(const uint32_t *s, int n, x_lb *d) { x_words(s, n, d); }

int vtts_tr_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, const uint32_t **out) {
    x_lb p = {a, 0, cap, 0}, q = {b, 0, cap, 0};
    x_putn(&p, in, n);
    if (p.err) return -1;
#define SWAP() do { if (q.err) return -1; x_lb t_ = p; p = q; q = t_; q.n = 0; } while (0)
    p_apostrophe(p.p, p.n, &q);
    SWAP();
    for (int k = 0; k < VTTS_TR_ABBREV_N; k++) {
        x_abbrev(VTTS_TR_ABBREV[k][0], VTTS_TR_ABBREV[k][1], p.p, p.n, &q);
        SWAP();
    }
    static const pass_fn PASSES[] = {p_drop, p_date_iso, p_date_dmy, p_time, p_time_dot, p_phone, p_money_before,
                                     p_money_after, p_percent_before, p_percent_after, p_unit, p_ordinal, p_range,
                                     p_pause, p_code, p_number, p_symbols, p_acronym, p_suffix_start, p_lower,
                                     p_words};
    for (int k = 0; k < N_OF(PASSES); k++) {
        PASSES[k](p.p, p.n, &q);
        SWAP();
    }
#undef SWAP
    *out = p.p;
    return p.n;
}

/* ======================= tagging ======================= */

static int ascii_low(const uint32_t *w, int n, char *o, int cap) {
    if (n >= cap) return 0;
    for (int i = 0; i < n; i++) {
        if (w[i] >= 0x80) return 0;
        o[i] = (char)(w[i] >= 'A' && w[i] <= 'Z' ? w[i] + 32 : w[i]);
    }
    o[n] = 0;
    return 1;
}

static const x_clusters_t CLUSTERS = {"aeiou", VTTS_TR_ONSETS, VTTS_TR_ONSETS_N, VTTS_TR_FINALS, VTTS_TR_FINALS_N,
                                      VTTS_TR_FINALS, VTTS_TR_FINALS_N};

static int valid_spelling(const char *w, int n) {
    for (int k = 0; k < VTTS_TR_FOREIGN_N; k++) if (x_has_sub(w, n, VTTS_TR_FOREIGN[k])) return 0;
    for (int i = 0; i + 1 < n; i++) if (w[i] == w[i + 1] && strchr("eouy", w[i])) return 0;
    return x_clusters(&CLUSTERS, w, n);
}

/* latin.latin_word_lang(core, "tr") of a plain Latin word: 1 Turkish, 0 English */
static int latin_lang(const uint32_t *w, int n) {
    char low[128], part[128];
    if (n <= 0) return 1;
    for (int i = 0; i < n; i++) if (x_in_u8(w[i], VTTS_TR_OWN)) return 1;
    if (n < (int)sizeof low) {
        ascii_low(w, n, low, (int)sizeof low);
        if (x_in_sorted(VTTS_TR_NATIVE, VTTS_TR_NATIVE_N, low) || x_in_sorted(VTTS_TR_TABLE_KEYS, VTTS_TR_TABLE_KEYS_N, low))
            return 1;
        if (vtts_lt_english_word(low)) return 0;
    }
    int stem = 0; /* the part before the first apostrophe */
    while (stem < n && w[stem] != '\'') stem++;
    int all_caps = 1, all_valid = 1;
    for (int a = 0; a < stem;) {
        int b = a;
        while (b < stem && w[b] != '-') b++;
        if (b > a) {
            int len = b - a, caps = len >= 2 && len <= 5;
            if (x_camel(w + a, len)) return 0;
            for (int k = a; k < b; k++) caps &= x_upper_az(w[k]);
            all_caps &= caps;
            if (all_valid) {
                if (len >= (int)sizeof part) all_valid = 0;
                else {
                    ascii_low(w + a, len, part, (int)sizeof part);
                    all_valid = x_in_sorted(VTTS_TR_NATIVE, VTTS_TR_NATIVE_N, part) || valid_spelling(part, len);
                }
            }
        }
        a = b + 1;
    }
    if (n == 1 || all_caps) return 1;
    return all_valid;
}

int vtts_tr_word_lang(const uint32_t *w, int n) {
    if (n <= 0) return -1;
    for (int i = 0; i < n; i++) if (x_in_u8(w[i], VTTS_TR_OWN)) return 1;
    if (!x_plain_latin(w, n)) return -1;
    return latin_lang(w, n);
}

static int is_edge(uint32_t c) { return c && (c < 0x80 ? strchr(".,;:!?\"'()[]{}", (int)c) != NULL : x_in_u8(c, "…“”‘’«»–—")); }

int vtts_tr_split(const uint32_t *w, int n) {
    int ap = 0;
    while (ap < n && w[ap] != '\'') ap++;
    if (ap >= n) return 0;
    int a = 0, r0 = ap + 1, r1 = n;
    while (a < ap && is_edge(w[a])) a++;
    while (r0 < r1 && is_edge(w[r0])) r0++;
    while (r1 > r0 && is_edge(w[r1 - 1])) r1--;
    if (a >= ap || r0 >= r1) return 0;
    for (int i = r0; i < r1; i++) /* latin.SUFFIX_LETTERS */
        if (!x_in_u8(w[i], VTTS_TR_SUFFIX_LETTERS)) return 0;
    if (!x_plain_latin(w + a, ap - a)) return 0;
    return latin_lang(w + a, ap - a) == 0 ? ap : 0;
}

/* ======================= g2p (g2p_tr.phonemes) ======================= */

typedef struct { char kind; uint8_t lng; char ph[3]; } seg_t;

typedef struct { uint8_t *out; int n, cap; } emit_t;

static void emit(emit_t *e, const char *name) {
    for (int k = 0; k < VTTS_TR_TOKENS_N; k++)
        if (strcmp(VTTS_TR_TOKENS[k], name) == 0) {
            if (e->n < e->cap) e->out[e->n++] = (uint8_t)(VTTS_TREN_TOK0 + k);
            return;
        }
}

static uint32_t fold1(uint32_t c) {
    if (c < 0x80) return c == 'I' ? 0x131 : c >= 'A' && c <= 'Z' ? c + 32 : (c >= 'a' && c <= 'z' ? c : 0);
    int lo = 0, hi = VTTS_TR_FOLD_N - 1, k = -1;
    while (lo <= hi) {
        int m = (lo + hi) / 2;
        if (VTTS_TR_FOLD[m].start <= c) { k = m; lo = m + 1; } else hi = m - 1;
    }
    if (k < 0 || c - VTTS_TR_FOLD[k].start >= VTTS_TR_FOLD[k].count) return 0;
    return VTTS_TR_FOLD[k].first + (c - VTTS_TR_FOLD[k].start) * VTTS_TR_FOLD[k].step;
}

static int fold_word(const uint32_t *w, int n, uint32_t *o) {
    int m = 0;
    for (int i = 0; i < n && m < VTTS_TR_MAXW; i++) {
        uint32_t f = fold1(w[i]);
        if (f) o[m++] = f;
    }
    return m;
}

static const char *phoneme_of(uint32_t c) {
    for (int k = 0; k < VTTS_TR_PHONEME_N; k++) if (VTTS_TR_PHONEME[k].cp == c) return VTTS_TR_PHONEME[k].s;
    return NULL;
}

static uint32_t long_base(uint32_t c) {
    uint32_t a[4], b[4];
    int na = x_u8_decode(VTTS_TR_LONG, a, 4);
    x_u8_decode(VTTS_TR_LONG_BASE, b, 4);
    for (int k = 0; k < na; k++) if (a[k] == c) return b[k];
    return 0;
}

#define STRESS_MARK 0x2C8

static void seg(seg_t *S, int *ns, char kind, const char *ph) {
    if (*ns >= 2 * VTTS_TR_MAXW) return;
    seg_t *s = &S[(*ns)++];
    memset(s, 0, sizeof *s);
    s->kind = kind;
    s->ph[0] = ph[0];
    s->ph[1] = ph[0] ? ph[1] : 0;
}

/* _segments: returns the count; *marked the index of a marked stressed vowel or -1 */
static int segments(const uint32_t *w, int n, seg_t *S, int *marked) {
    int ns = 0, mk = -1;
    for (int i = 0; i < n; i++) {
        uint32_t c = w[i], nxt = i + 1 < n ? w[i + 1] : 0, lb;
        if (c == STRESS_MARK) mk = ns;
        else if (tr_vowel(c)) seg(S, &ns, 'V', phoneme_of(c));
        else if ((lb = long_base(c))) {
            if (ns && S[ns - 1].kind == 'C' && !strcmp(S[ns - 1].ph, "k") && c != 0xEE) strcpy(S[ns - 1].ph, "ky");
            else if (ns && S[ns - 1].kind == 'C' && !strcmp(S[ns - 1].ph, "g") && c != 0xEE) strcpy(S[ns - 1].ph, "gy");
            char v[2] = {(char)lb, 0};
            seg(S, &ns, 'V', v);
            S[ns - 1].lng = 1;
        } else if (c == 0x11F) { /* ğ */
            if (ns && S[ns - 1].kind == 'V') {
                seg_t *prev = &S[ns - 1];
                if (nxt && tr_vowel(nxt)) {
                    if (x_in_u8(w[i - 1], VTTS_TR_FRONT) && x_in_u8(nxt, VTTS_TR_FRONT)) seg(S, &ns, 'C', "y");
                    else {
                        prev->lng = 1;
                        if (!strcmp(phoneme_of(nxt), prev->ph)) i++; /* ağaç */
                    }
                } else prev->lng = 1;
            }
        } else if (c == 'x') { seg(S, &ns, 'C', "k"); seg(S, &ns, 'C', "s"); }
        else {
            const char *p = phoneme_of(c);
            char one[2] = {(char)c, 0};
            seg(S, &ns, 'C', p ? p : one);
        }
    }
    if (mk >= 0) {
        while (mk < ns && S[mk].kind != 'V') mk++;
        if (mk >= ns) mk = -1;
    }
    *marked = mk;
    return ns;
}

static int in_set(uint32_t c, const char *set) { return x_in_u8(c, set); }

#define V4 "ıiuü"

/* QUESTION ^m[ıiuü](y[ıiuü]m|s[ıiuü]n|y[ıiuü]z|s[ıiuü]n[ıiuü]z|l[ae]r|yd[ıiuü](m|n|k|n[ıiuü]z|l[ae]r)?|ym[ıiuü]ş|ys[ae])?$ */
static int question(const uint32_t *w, int n) {
    if (n < 2 || w[0] != 'm' || !in_set(w[1], V4)) return 0;
    const uint32_t *r = w + 2;
    int m = n - 2;
    if (!m) return 1;
#define C4(k) (k < m && in_set(r[k], V4))
    if (m == 3 && r[0] == 'y' && C4(1) && (r[2] == 'm' || r[2] == 'z')) return 1;
    if (m == 3 && r[0] == 's' && C4(1) && r[2] == 'n') return 1;
    if (m == 5 && r[0] == 's' && C4(1) && r[2] == 'n' && C4(3) && r[4] == 'z') return 1;
    if (m == 3 && r[0] == 'l' && (r[1] == 'a' || r[1] == 'e') && r[2] == 'r') return 1;
    if (m >= 3 && r[0] == 'y' && r[1] == 'd' && C4(2)) {
        int k = m - 3;
        const uint32_t *t = r + 3;
        if (k == 0) return 1;
        if (k == 1 && (t[0] == 'm' || t[0] == 'n' || t[0] == 'k')) return 1;
        if (k == 3 && t[0] == 'n' && in_set(t[1], V4) && t[2] == 'z') return 1;
        if (k == 3 && t[0] == 'l' && (t[1] == 'a' || t[1] == 'e') && t[2] == 'r') return 1;
        return 0;
    }
    if (m == 4 && r[0] == 'y' && r[1] == 'm' && C4(2) && r[3] == 0x15F) return 1;
    if (m == 3 && r[0] == 'y' && r[1] == 's' && (r[2] == 'a' || r[2] == 'e')) return 1;
#undef C4
    return 0;
}

static int unstressed(const uint32_t *w, int n) {
    char u[32];
    return x_to_u8(w, n, u, (int)sizeof u) && x_in_sorted(VTTS_TR_UNSTRESSED, VTTS_TR_UNSTRESSED_N, u);
}

static int vowels_before(const uint32_t *w, int k) {
    int c = 0;
    for (int i = 0; i < k; i++) c += tr_vowel(w[i]) || long_base(w[i]);
    return c;
}

/* the start of the first match of pre-stressing pattern p (0 NEG_YOR, 1 NEG_PAST, 2 YOR, 3 COPULA,
 * 4 WITH) or -1; *offset is added to the vowels before it */
static int prestress(const uint32_t *w, int n, int p, int *offset) {
    static const char *const VOW = "aeıioöuü";
    *offset = p == 2 ? 0 : -1;
    if (p == 0) {
        for (int i = 1; i + 4 < n; i++) /* (?<=[^aeıioöuü])m[ıiuü]yor */
            if (!in_set(w[i - 1], VOW) && w[i] == 'm' && in_set(w[i + 1], V4) && w[i + 2] == 'y' && w[i + 3] == 'o' &&
                w[i + 4] == 'r')
                return i;
    } else if (p == 1) {
        for (int i = 1; i + 3 < n; i++) /* (?<=[consonants])m[ae]d[ıi] */
            if (in_set(w[i - 1], "bcçdfgğhjklmnprsştvyz") && w[i] == 'm' && (w[i + 1] == 'a' || w[i + 1] == 'e') &&
                w[i + 2] == 'd' && (w[i + 3] == 0x131 || w[i + 3] == 'i'))
                return i;
    } else if (p == 2) {
        for (int i = 0; i + 3 < n; i++) /* [ıiuü]yor */
            if (in_set(w[i], V4) && w[i + 1] == 'y' && w[i + 2] == 'o' && w[i + 3] == 'r') return i;
    } else if (p == 3) {
        if (n >= 4 && in_set(w[n - 2], V4) && w[n - 1] == 'r') {
            int i = n - 3;
            if ((w[i] == 't' && in_set(w[i - 1], "çfhkpsşt")) || (w[i] == 'd' && in_set(w[i - 1], "aeıioöuüâîûbcdgğjlmnrvyz")))
                return i;
        }
    } else if (n >= 4 && w[n - 3] == 'y' && w[n - 2] == 'l' && (w[n - 1] == 'a' || w[n - 1] == 'e') && in_set(w[n - 4], VOW))
        return n - 3;
    return -1;
}

/* _read(w, stressed): w may hold the stress mark */
static void read_word(emit_t *e, const uint32_t *w, int n, int stressed, seg_t *S, uint32_t *bare) {
    int marked, ns = segments(w, n, S, &marked), st = -1;
    if (stressed) {
        int bn = 0;
        for (int i = 0; i < n; i++) if (w[i] != STRESS_MARK) bare[bn++] = w[i];
        int nn = 0, last = -1;
        for (int k = 0; k < ns; k++) if (S[k].kind == 'V') { nn++; last = k; }
        if (nn && !unstressed(bare, bn) && !question(bare, bn)) {
            if (marked >= 0) st = marked;
            else if (nn == 1) st = last;
            else {
                st = last;
                for (int p = 0, found = 0; p < 5 && !found; p++) {
                    int off, i = prestress(bare, bn, p, &off);
                    if (i < 0) continue;
                    int k = vowels_before(bare, i) + off;
                    if (k < 0 || k >= nn) continue;
                    for (int q = 0, c = 0; q < ns; q++)
                        if (S[q].kind == 'V' && c++ == k) { st = q; break; }
                    found = 1;
                }
            }
        }
    }
    for (int k = 0; k < ns; k++) {
        char b[4] = {S[k].ph[0], S[k].ph[1], 0, 0};
        if (S[k].kind == 'V' && k == st) strcat(b, "1");
        emit(e, b);
        if (S[k].kind == 'V' && S[k].lng) emit(e, "long");
    }
}

/* SUFFIX ^(l[ıiuü])?(l[ae]r)?(alternatives)?$ of the rest after an override stem */
static int suffix_alt(const uint32_t *r, int m) {
    /* each alternative: atoms, '?' after an atom makes it optional; I = [ıiuü], A = [ae], T = [dt] */
    static const char *const ALT[] = {"y?Im?", "n?In", "sIn?", "y?A", "n?TAn?", "n?TAki", "y?lA", "ImIz", "InIz",
                                      "nIn", "y?dIr"};
    if (!m) return 1;
    for (int a = 0; a < N_OF(ALT); a++) {
        /* small backtracking matcher over the pattern */
        const char *p = ALT[a];
        int stack_p[16], stack_i[16], sp = 0, pi = 0, i = 0;
        for (;;) {
            if (!p[pi]) {
                if (i == m) return 1;
            } else {
                char at = p[pi];
                int opt = p[pi + 1] == '?';
                int ok = i < m && (at == 'I' ? in_set(r[i], V4) : at == 'A' ? (r[i] == 'a' || r[i] == 'e')
                                    : at == 'T' ? (r[i] == 'd' || r[i] == 't') : r[i] == (uint32_t)at);
                if (opt && sp < 16) { stack_p[sp] = pi + 2; stack_i[sp] = i; sp++; } /* skip branch later */
                if (ok) { pi += opt ? 2 : 1; i++; continue; }
            }
            if (!sp) break;
            sp--;
            pi = stack_p[sp];
            i = stack_i[sp];
        }
    }
    return 0;
}

static int suffix_ok(const uint32_t *r, int m) {
    for (int a = 1; a >= 0; a--) { /* (l[ıiuü])? */
        if (a && !(m >= 2 && r[0] == 'l' && in_set(r[1], V4))) continue;
        const uint32_t *r2 = r + 2 * a;
        int m2 = m - 2 * a;
        for (int b = 1; b >= 0; b--) { /* (l[ae]r)? */
            if (b && !(m2 >= 3 && r2[0] == 'l' && (r2[1] == 'a' || r2[1] == 'e') && r2[2] == 'r')) continue;
            if (suffix_alt(r2 + 3 * b, m2 - 3 * b)) return 1;
        }
    }
    return 0;
}

static const char *override(const uint32_t *w, int n) {
    char u[256];
    if (!x_to_u8(w, n, u, (int)sizeof u)) return NULL;
    int lo = 0, hi = VTTS_TR_OVERRIDES_N - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2, c = strcmp(VTTS_TR_OVERRIDES[m][0], u);
        if (!c) return VTTS_TR_OVERRIDES[m][1];
        if (c < 0) lo = m + 1; else hi = m - 1;
    }
    return NULL;
}

/* _with_override(w) into t; returns the length */
static int with_override(const uint32_t *w, int n, uint32_t *t) {
    const char *r = override(w, n);
    if (r) return x_u8_decode(r, t, VTTS_TR_MAXW);
    for (int k = n - 1; k > 2; k--) {
        r = override(w, k);
        if (r && suffix_ok(w + k, n - k)) {
            int m = x_u8_decode(r, t, VTTS_TR_MAXW);
            for (int i = k; i < n && m < VTTS_TR_MAXW; i++) t[m++] = w[i];
            return m;
        }
    }
    memcpy(t, w, (size_t)n * sizeof *w);
    return n;
}

static void phonemes(emit_t *e, const uint32_t *word, int wn, uint32_t *f, uint32_t *t, uint32_t *bare, seg_t *S) {
    int ap = 0;
    while (ap < wn && word[ap] != '\'' && word[ap] != 0x2019) ap++;
    int hn = fold_word(word, ap, f);
    int sn = ap < wn ? fold_word(word + ap + 1, wn - ap - 1, f + hn) : 0;
    const uint32_t *suf = f + hn;
    if (!hn) {
        if (sn) read_word(e, suf, sn, 0, S, bare);
        return;
    }
    int tn = with_override(f, hn, t);
    int n0 = e->n;
    read_word(e, t, tn, 1, S, bare);
    if (sn) {
        static const uint32_t DORT[4] = {'d', 0xF6, 'r', 't'};
        if (hn == 4 && !memcmp(f, DORT, sizeof DORT) && tr_vowel(suf[0]) && e->n > n0) {
            uint8_t d0 = 0;
            emit_t de = {&d0, 0, 1};
            emit(&de, "d");
            e->out[e->n - 1] = d0;
        }
        read_word(e, suf, sn, 0, S, bare);
    }
}

int vtts_tr_word_ids(const uint32_t *w, int n, uint32_t *scratch, uint8_t *out, int cap) {
    uint32_t *f = scratch, *t = scratch + 2 * VTTS_TR_MAXW, *bare = scratch + 3 * VTTS_TR_MAXW;
    uint32_t *spelled = scratch + 7 * VTTS_TR_MAXW; /* a letter name */
    seg_t *S = (seg_t *)(void *)(scratch + 4 * VTTS_TR_MAXW); /* 2 * VTTS_TR_MAXW segments */
    emit_t e = {out, 0, cap};
    if (n > VTTS_TR_MAXW) n = VTTS_TR_MAXW;
    if (n && w[0] == 0x2BC) { /* ʼda: a suffix after an English word */
        int m = fold_word(w, n, f);
        read_word(&e, f, m, 0, S, bare);
        return e.n;
    }
    int m = 0, vowel = 0;
    for (int i = 0; i < n && m < VTTS_TR_MAXW; i++) {
        if (w[i] == '\'' || w[i] == 0x2019) continue;
        uint32_t c = fold1(w[i]);
        if (c) f[m++] = c;
    }
    for (int i = 0; i < m; i++) vowel |= tr_vowel(f[i]) || long_base(f[i]);
    if (m && !vowel) { /* spelled letter by letter */
        for (int i = 0; i < m; i++) {
            const char *name = letter_name(f[i]);
            while (name && *name) {
                while (*name == ' ') name++;
                const char *sp = strchr(name, ' ');
                size_t l = sp ? (size_t)(sp - name) : strlen(name);
                uint32_t pc[32];
                char piece[64];
                if (!l || l >= sizeof piece) break;
                memcpy(piece, name, l);
                piece[l] = 0;
                int pn = x_u8_decode(piece, pc, 32);
                phonemes(&e, pc, pn, spelled, t, bare, S);
                name += l;
            }
        }
        return e.n;
    }
    phonemes(&e, w, n, f, t, bare, S);
    return e.n;
}

#endif
