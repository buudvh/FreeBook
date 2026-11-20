/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_it.c -- Italian device front-end (token set it-en). Mirrors src/vtts/frontend/it/
 * (normalize_it.py pass by pass, g2p_it.py), the Italian rules of latin.py (latin_word_lang,
 * split_elision) and latin_norm.py. All tables are in the generated vtts_text_it_tables.h; no
 * blob. Compiled only with VTTS_ENABLE_IT. */
#include "vtts_langs.h"
#if VTTS_ENABLE_IT /* else an empty unit (vtts_langs.h) */

#include "vtts_text_it.h"

#include <string.h>

#include "vtts_text_it_tables.h"
#include "vtts_text_ltx.h"

#define N_OF(a) ((int)(sizeof(a) / sizeof((a)[0])))
#define IN X_IN
#define W X_W
#define DG X_DG
#define SP X_SP
#define AT X_AT
#define WDC X_WDC

/* ======================= numbers (normalize_it) ======================= */

static void below_100(x_lb *d, int v) {
    if (v < 20) { x_puts8(d, VTTS_IT_ONES[v]); return; }
    int t = v / 10, u = v % 10;
    const char *tens = VTTS_IT_TENS[t];
    int tl = (int)strlen(tens);
    if (u == 1 || u == 8) tl--; /* ventuno, ventotto */
    for (int k = 0; k < tl; k++) x_put(d, (unsigned char)tens[k]);
    if (u == 3) x_puts8(d, "tré");
    else if (u) x_puts8(d, VTTS_IT_ONES[u]);
}

static void below_1000(x_lb *d, int v) {
    int h = v / 100, r = v % 100;
    if (h) { if (h > 1) x_puts8(d, VTTS_IT_ONES[h]); x_puts8(d, "cento"); }
    if (r) { if (h) x_put(d, ' '); below_100(d, r); }
}

static void card_v(x_lb *d, uint64_t v) { /* cardinal(v), 0 < v < 10**15 */
    static const uint64_t SC[3] = {1000000000000ull, 1000000000ull, 1000000ull};
    int any = 0;
    for (int k = 0; k < 3; k++) {
        uint64_t q = v / SC[k];
        v %= SC[k];
        if (!q) continue;
        if (any) x_put(d, ' ');
        if (q == 1) { x_puts8(d, "un "); x_puts8(d, VTTS_IT_SCALES[k][0]); }
        else { card_v(d, q); x_put(d, ' '); x_puts8(d, VTTS_IT_SCALES[k][1]); }
        any = 1;
    }
    int th = (int)(v / 1000), r = (int)(v % 1000);
    if (th) {
        if (any) x_put(d, ' ');
        if (th == 1) x_puts8(d, "mille");
        else { below_1000(d, th); x_puts8(d, "mila"); }
        any = 1;
    }
    if (r) { if (any) x_put(d, ' '); below_1000(d, r); }
}

/* cardinal(int(s)) of the decimal digits of s[0..n) (other code points are separators) */
static void card(x_lb *d, const uint32_t *s, int n) {
    int st, nd = x_sig(s, n, &st);
    if (!nd) { x_puts8(d, "zero"); return; }
    if (nd > 15) { x_digit_words(d, VTTS_IT_DIGITS, s, n, st); return; }
    card_v(d, x_value(s, n, st));
}

static void card_i(x_lb *d, int v) {
    if (!v) { x_puts8(d, "zero"); return; }
    card_v(d, (uint64_t)v);
}

/* the integer value is exactly 1 */
static int is_one(const uint32_t *s, int n) {
    int st, nd = x_sig(s, n, &st);
    return nd == 1 && vtts_u_digit(s[st]) == 1;
}

/* read_number of an unsigned number; before_word: a final "uno" loses its o when there is no
 * decimal part (number(s, before_word)). Returns 1 when there is a decimal part. */
static int read_number(x_lb *d, const uint32_t *s, int n, int before_word) {
    int ie, f0;
    uint32_t mark;
    x_parse_number(s, n, &ie, &f0, &mark);
    int st = d->n;
    card(d, s, ie);
    if (f0 < 0) {
        if (before_word && x_tail_is(d, st, "uno")) d->n--;
        return 0;
    }
    x_put(d, ' ');
    x_puts8(d, mark == ',' ? VTTS_IT_COMMA : VTTS_IT_PERIOD);
    x_put(d, ' ');
    if (f0 < n && n - f0 <= 2 && s[f0] != '0') card(d, s + f0, n - f0);
    else x_digit_words(d, VTTS_IT_DIGITS, s, n, f0);
    return 1;
}

static void number(x_lb *d, const uint32_t *s, int n, int neg, int before_word) {
    if (neg) x_puts8(d, "meno ");
    read_number(d, s, n, before_word);
}

/* ordinal(int(s), fem) */
static void ordinal(x_lb *d, const uint32_t *s, int n, int fem) {
    int st, nd = x_sig(s, n, &st);
    int v = nd <= 2 ? (int)x_value(s, n, st) : 100;
    if (!nd) { x_puts8(d, "zero"); return; }
    int s0 = d->n;
    if (v <= 10) x_puts8(d, VTTS_IT_ORD_SMALL[v]);
    else {
        card(d, s, n);
        int m = s0;
        for (int i = s0; i < d->n; i++) if (d->p[i] != ' ') d->p[m++] = d->p[i];
        d->n = m;
        if (x_tail_is(d, s0, "tré")) { d->n -= 3; x_puts8(d, "treesimo"); }
        else if (x_tail_is(d, s0, "sei")) x_puts8(d, "esimo");
        else { d->n--; x_puts8(d, "esimo"); }
    }
    if (fem) d->p[d->n - 1] = 'a';
}

/* ======================= normalization passes ======================= */

typedef void (*pass_fn)(const uint32_t *s, int n, x_lb *d);

static void p_apostrophe(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n; i++) x_put(d, s[i] == 0x2019 || s[i] == 0x2018 ? '\'' : s[i]);
}

static void p_drop(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n; i++) x_put(d, x_in_u8(s[i], VTTS_IT_DROP) ? ' ' : s[i]);
}

/* _date(d, m, y): " out " or the original text */
static void date_out(x_lb *d, int dd, int mm, const uint32_t *y, int yl, const uint32_t *orig, int on) {
    if (!(dd >= 1 && dd <= 31 && mm >= 1 && mm <= 12)) { x_putn(d, orig, on); return; }
    x_put(d, ' ');
    if (dd == 1) x_puts8(d, "primo"); else card_i(d, dd);
    x_put(d, ' ');
    x_puts8(d, VTTS_IT_MONTHS[mm]);
    if (y) { x_put(d, ' '); card_i(d, x_val(y, 0, yl) + (yl == 2 ? 2000 : 0)); }
    x_put(d, ' ');
}

/* (?<![\d-])(\d{4})-(\d{1,2})-(\d{1,2})(?![\d-]) */
static void p_date_iso(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !DG(i - 1) && !AT(i - 1, '-') && DG(i + 1) && DG(i + 2) && DG(i + 3) && AT(i + 4, '-')) {
            int m0 = i + 5, ml = x_drun(s, n, m0);
            if (ml >= 1 && ml <= 2 && AT(m0 + ml, '-')) {
                int d0 = m0 + ml + 1, dl = x_drun(s, n, d0);
                if (dl >= 1 && dl <= 2 && !AT(d0 + dl, '-')) {
                    date_out(d, x_val(s, d0, dl), x_val(s, m0, ml), s + i, 4, s + i, d0 + dl - i);
                    i = d0 + dl;
                    continue;
                }
            }
        }
        x_put(d, s[i++]);
    }
}

/* (?<![\d/.])(\d{1,2})[/.](\d{1,2})[/.](\d{4}|\d{2})(?![\d/]|\.\d) */
static void p_date_dmy(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !DG(i - 1) && !AT(i - 1, '/') && !AT(i - 1, '.')) {
            int r1 = x_drun(s, n, i);
            if (r1 <= 2 && (AT(i + r1, '/') || AT(i + r1, '.'))) {
                int m0 = i + r1 + 1, r2 = x_drun(s, n, m0);
                if (r2 >= 1 && r2 <= 2 && (AT(m0 + r2, '/') || AT(m0 + r2, '.'))) {
                    int y0 = m0 + r2 + 1, ry = x_drun(s, n, y0), e = y0 + ry;
                    if ((ry == 4 || ry == 2) && !AT(e, '/') && !(AT(e, '.') && DG(e + 1))) {
                        date_out(d, x_val(s, i, r1), x_val(s, m0, r2), s + y0, ry, s + i, e - i);
                        i = e;
                        continue;
                    }
                }
            }
        }
        x_put(d, s[i++]);
    }
}

/* ([01]?\d|2[0-4]) at i: the hour lengths in the order the regex tries them */
static int hours(const uint32_t *s, int n, int i, int hl[3]) {
    int k = 0;
    if ((AT(i, '0') || AT(i, '1')) && DG(i + 1)) hl[k++] = 2;
    if (DG(i)) hl[k++] = 1;
    if (AT(i, '2') && IN(i + 1) && s[i + 1] >= '0' && s[i + 1] <= '4') hl[k++] = 2;
    return k;
}

static int m05(const uint32_t *s, int n, int j) { return IN(j) && s[j] >= '0' && s[j] <= '5' && DG(j + 1); }

/* _time(h, mi, sec) */
static void time_out(x_lb *d, int h, int mi, int sec) {
    x_put(d, ' ');
    if (h == 1) x_puts8(d, "l'una"); else card_i(d, h);
    if (mi) { x_puts8(d, " e "); card_i(d, mi); }
    if (sec > 0) { x_puts8(d, " e "); card_i(d, sec); x_puts8(d, " secondi"); }
    x_put(d, ' ');
}

/* (?<![\d:])([01]?\d|2[0-4]):([0-5]\d)(?::([0-5]\d))?(?![\d:]) */
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
                    end = k2;
                    time_out(d, x_val(s, i, hl[c]), x_val(s, j + 1, 2), sv ? x_val(s, k + 1, 2) : 0);
                }
            }
        }
        if (end >= 0) { i = end; continue; }
        x_put(d, s[i++]);
    }
}

/* \b([Aa]lle|[Oo]re|[Dd]alle|[Ee]ntro|[Vv]erso)\s+([01]?\d|2[0-4])\.([0-5]\d)(?![\d.,]) -> keyword + _time */
static void p_time_dot(const uint32_t *s, int n, x_lb *d) {
    static const char *const KEYS[5] = {"lle", "re", "alle", "ntro", "erso"};
    static const char FIRST[5][2] = {{'A', 'a'}, {'O', 'o'}, {'D', 'd'}, {'E', 'e'}, {'V', 'v'}};
    for (int i = 0; i < n;) {
        int end = -1, kl = 0;
        if (!W(i - 1))
            for (int k = 0; k < 5 && end < 0; k++) {
                if (!(AT(i, FIRST[k][0]) || AT(i, FIRST[k][1]))) continue;
                int l = x_key_at(s, n, i + 1, KEYS[k]);
                if (!l || !SP(i + 1 + l)) continue;
                int p = i + 1 + l;
                while (SP(p)) p++;
                int hl[3], nh = hours(s, n, p, hl);
                for (int c = 0; c < nh && end < 0; c++) {
                    int j = p + hl[c];
                    if (AT(j, '.') && m05(s, n, j + 1) && !DG(j + 3) && !AT(j + 3, '.') && !AT(j + 3, ',')) {
                        end = j + 3;
                        kl = 1 + l;
                        x_putn(d, s + i, kl);
                        time_out(d, x_val(s, p, hl[c]), x_val(s, j + 1, 2), 0);
                    }
                }
            }
        if (end >= 0) { i = end; continue; }
        x_put(d, s[i++]);
    }
}

/* \d{lo,hi}(?:[\s-]\d{lo,hi}){gmin,gmax}(?![\d]) at q: the end or -1 */
static int phone_core(const uint32_t *s, int n, int q) {
    int r = x_drun(s, n, q), e = q + r, cnt = 0;
    if (r < 2 || r > 4) return -1;
    while (cnt < 4 && (SP(e) || AT(e, '-'))) {
        int r2 = x_drun(s, n, e + 1);
        if (r2 < 2 || r2 > 4) break;
        e += 1 + r2;
        cnt++;
    }
    return cnt >= 2 ? e : -1;
}

/* (?<![\d])(?:\+\d{1,3}[\s-])?\d{2,4}(?:[\s-]\d{2,4}){2,4}(?![\d])
 * | (?<![\d.,])0\d{5,}(?![\d]|[.,]\d) | (?<![\d.,])3\d{2}[\s-]?\d{6,7}(?![\d]) -> phone_digits */
static void p_phone(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n;) {
        int e = -1;
        if (!DG(i - 1) && (AT(i, '+') || DG(i))) {
            for (int pre = AT(i, '+'); pre >= 0 && e < 0; pre--) {
                int p = i;
                if (pre) {
                    int r = x_drun(s, n, i + 1);
                    if (!(r >= 1 && r <= 3 && (SP(i + 1 + r) || AT(i + 1 + r, '-')))) continue;
                    p = i + 2 + r;
                }
                e = phone_core(s, n, p);
            }
        }
        if (e < 0 && AT(i, '0') && !DG(i - 1) && !AT(i - 1, '.') && !AT(i - 1, ',')) {
            int r = x_drun(s, n, i), q = i + r;
            if (r >= 6 && !((AT(q, '.') || AT(q, ',')) && DG(q + 1))) e = q;
        }
        if (e < 0 && AT(i, '3') && !DG(i - 1) && !AT(i - 1, '.') && !AT(i - 1, ',') && DG(i + 1) && DG(i + 2)) {
            int q = i + 3;
            if (SP(q) || AT(q, '-')) {
                int r = x_drun(s, n, q + 1);
                if (r == 6 || r == 7) e = q + 1 + r;
            }
            if (e < 0) {
                int r = x_drun(s, n, q);
                if (r == 6 || r == 7) e = q + r;
            }
        }
        if (e >= 0) { /* phone_digits */
            int cnt = 0;
            for (int q = i; q < e; q++) cnt += vtts_u_digit(s[q]) >= 0;
            if (cnt < 7 && s[i] != '0') x_putn(d, s + i, e - i);
            else {
                x_put(d, ' ');
                if (s[i] == '+') x_puts8(d, "più ");
                x_digit_words(d, VTTS_IT_DIGITS, s, e, i);
                x_put(d, ' ');
            }
            i = e;
            continue;
        }
        x_put(d, s[i++]);
    }
}

/* \s?(KEY)[(?![\w])] after a number: the first key in the table's order */
typedef struct { const char *const (*keys)[3]; int nk, key, end; } keys_m;

static int ok_keys(const uint32_t *s, int n, int e, void *u) {
    keys_m *m = u;
    for (int sp = SP(e); sp >= 0; sp--)
        for (int k = 0; k < m->nk; k++) {
            int l = x_key_at(s, n, e + sp, m->keys[k][0]);
            if (l && !W(e + sp + l)) { m->key = k; m->end = e + sp + l; return 1; }
        }
    return 0;
}

/* _money(num, cur) */
static void money_out(x_lb *d, const uint32_t *num, int nn, int k) {
    const char *const *cur = VTTS_IT_CURRENCY[k];
    int ie, f0;
    uint32_t mark;
    x_parse_number(num, nn, &ie, &f0, &mark);
    x_put(d, ' ');
    int cents_ok = !strcmp(cur[0], "€") || !strcmp(cur[0], "EUR") || !strcmp(cur[0], "$") || !strcmp(cur[0], "US$");
    if (f0 >= 0 && nn - f0 == 2 && cents_ok) {
        int one = is_one(num, ie), st = d->n, c = x_val(num, f0, 2);
        card(d, num, ie);
        if (x_tail_is(d, st, "uno")) d->n--;
        x_put(d, ' ');
        x_puts8(d, one ? cur[1] : cur[2]);
        if (c) { x_puts8(d, " e "); card_i(d, c); x_puts8(d, c == 1 ? " centesimo" : " centesimi"); }
        x_put(d, ' ');
        return;
    }
    int frac = f0 >= 0, one = !frac && is_one(num, ie);
    read_number(d, num, nn, 1);
    x_put(d, ' ');
    x_puts8(d, one ? cur[1] : cur[2]);
    x_put(d, ' ');
}

/* (CUR)\s?(NUM) */
static void p_money_before(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n;) {
        int e = -1, j = 0, k;
        for (k = 0; k < VTTS_IT_CURRENCY_N && e < 0; k++) {
            int l = x_key_at(s, n, i, VTTS_IT_CURRENCY[k][0]);
            if (!l) continue;
            for (int sp = SP(i + l); sp >= 0 && e < 0; sp--) {
                j = i + l + sp;
                e = x_num_match(s, n, j, x_ok_always, NULL);
            }
        }
        if (e >= 0) { money_out(d, s + j, e - j, k - 1); i = e; continue; }
        x_put(d, s[i++]);
    }
}

/* (?<![\w.,])(NUM)\s?(CUR)(?![\w]) */
static void p_money_after(const uint32_t *s, int n, x_lb *d) {
    keys_m m = {VTTS_IT_CURRENCY, VTTS_IT_CURRENCY_N, 0, 0};
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int e = x_num_match(s, n, i, ok_keys, &m);
            if (e >= 0) { money_out(d, s + i, e - i, m.key); i = m.end; continue; }
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

/* (?<![\w.,])(-?)(NUM)\s?% -> " number per cento " */
static void p_percent(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int j = i + AT(i, '-'), end = 0, e = x_num_match(s, n, j, ok_pct, &end);
            if (e >= 0) {
                x_put(d, ' ');
                number(d, s + j, e - j, j > i, 0);
                x_puts8(d, " per cento ");
                i = end;
                continue;
            }
        }
        x_put(d, s[i++]);
    }
}

/* (?<![\w.,])(-?)(NUM)\s?(UNITS)(?![\w]) -> _unit */
static void p_unit(const uint32_t *s, int n, x_lb *d) {
    keys_m m = {VTTS_IT_UNITS, VTTS_IT_UNITS_N, 0, 0};
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int j = i + AT(i, '-'), e = x_num_match(s, n, j, ok_keys, &m);
            if (e >= 0) {
                int ie, f0;
                uint32_t mark;
                x_parse_number(s + j, e - j, &ie, &f0, &mark);
                int one = f0 < 0 && is_one(s + j, ie);
                x_put(d, ' ');
                number(d, s + j, e - j, j > i, 1);
                x_put(d, ' ');
                x_puts8(d, one ? VTTS_IT_UNITS[m.key][1] : VTTS_IT_UNITS[m.key][2]);
                x_put(d, ' ');
                i = m.end;
                continue;
            }
        }
        x_put(d, s[i++]);
    }
}

/* (?<![\w.,])(\d+)(º|ª|°(?!\s?C))(?![\w]) -> ordinal */
static void p_ordinal(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n;) {
        if (DG(i) && !WDC(i - 1)) {
            int r = x_drun(s, n, i), p = i + r;
            if (IN(p) && (s[p] == 0xBA || s[p] == 0xAA || s[p] == 0xB0) && !W(p + 1)) {
                int deg_c = s[p] == 0xB0 && (AT(p + 1, 'C') || (SP(p + 1) && AT(p + 2, 'C')));
                if (!deg_c) {
                    x_put(d, ' ');
                    ordinal(d, s + i, r, s[p] == 0xAA);
                    x_put(d, ' ');
                    i = p + 1;
                    continue;
                }
            }
        }
        x_put(d, s[i++]);
    }
}

/* (?<![\w.,])(\d+)\s?[-–]\s?(\d+)(?![\w]) -> " a a b " */
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
                    if (!W(b0 + r2)) {
                        x_put(d, ' ');
                        card(d, s + i, r1);
                        x_puts8(d, " a ");
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
    for (int k = 0; k < VTTS_IT_LETTERS_N; k++) if (VTTS_IT_LETTERS[k].cp == c) return VTTS_IT_LETTERS[k].s;
    return NULL;
}

/* PRODUCT_CODE -> letters by name, digits one by one */
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
                    else x_puts8(d, VTTS_IT_DIGITS[s[k] - '0']);
                }
                x_put(d, ' ');
                i = j;
                continue;
            }
        }
        x_put(d, s[i++]);
    }
}

/* the lower-case letters s[a..b) are a word of NOT_COUNTED */
static int not_counted(const uint32_t *s, int a, int b) {
    char u[128];
    uint32_t low[34];
    if (b - a > 16) return 0; /* longer than any word of the list */
    int m = 0;
    for (int i = a; i < b; i++) {
        if (s[i] == 0x130) { low[m++] = 'i'; low[m++] = 0x307; continue; }
        low[m++] = vtts_u_lower(s[i]);
    }
    if (!x_to_u8(low, m, u, (int)sizeof u)) return 0;
    return x_in_sorted(VTTS_IT_NOT_COUNTED, VTTS_IT_NOT_COUNTED_N, u);
}

/* (?<![\w.,])(-?)(NUM)(?![\d])(\s*)(?=([^\W\d_]+)?) -> " number(before_word=counted)" + spaces or " " */
static void p_number(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n;) {
        if (!WDC(i - 1)) {
            int j = i + AT(i, '-'), e = x_num_match(s, n, j, x_ok_nodigit, NULL);
            if (e >= 0) {
                int f = e;
                while (SP(f)) f++;
                int g = f;
                while (X_LT(g)) g++;
                x_put(d, ' ');
                number(d, s + j, e - j, j > i, g > f && !not_counted(s, f, g));
                if (f > e) x_putn(d, s + e, f - e); else x_put(d, ' ');
                i = f;
                continue;
            }
        }
        x_put(d, s[i++]);
    }
}

/* SYMBOLS (in order; no reading holds a key), then "-" -> " " */
static void p_symbols(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n; i++) {
        const char *r = NULL;
        for (int k = 0; k < VTTS_IT_SYMBOLS_N && !r; k++) if (VTTS_IT_SYMBOLS[k].cp == s[i]) r = VTTS_IT_SYMBOLS[k].s;
        if (r) x_puts8(d, r);
        else x_put(d, s[i] == '-' ? ' ' : s[i]);
    }
}

/* ACRONYM (?<![\w])[A-Z]{2,5}(?![\w]): spelled, or the lower-case word */
static void p_acronym(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n;) {
        if (x_upper_az(s[i]) && !W(i - 1)) {
            int j = i;
            while (IN(j) && x_upper_az(s[j])) j++;
            if (j - i >= 2 && j - i <= 5 && !W(j)) {
                char low[8];
                for (int k = i; k < j; k++) low[k - i] = (char)(s[k] + 32);
                low[j - i] = 0;
                if (x_in_sorted(VTTS_IT_ACRONYM_WORDS, VTTS_IT_ACRONYM_WORDS_N, low)) {
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

/* FINAL_APOSTROPHE (?<=[^\W\d_])'(?![^\W\d_]) -> U+02BC */
static void p_final_apostrophe(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n; i++) x_put(d, s[i] == '\'' && X_LT(i - 1) && !X_LT(i + 1) ? 0x2BC : s[i]);
}

static void p_lower(const uint32_t *s, int n, x_lb *d) {
    for (int i = 0; i < n; i++) {
        if (s[i] == 0x130) { x_put(d, 'i'); x_put(d, 0x307); }
        else x_put(d, vtts_u_lower(s[i]));
    }
}

static void p_words(const uint32_t *s, int n, x_lb *d) { x_words(s, n, d); }

int vtts_it_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, const uint32_t **out) {
    x_lb p = {a, 0, cap, 0}, q = {b, 0, cap, 0};
    x_putn(&p, in, n);
    if (p.err) return -1;
#define SWAP() do { if (q.err) return -1; x_lb t_ = p; p = q; q = t_; q.n = 0; } while (0)
    q.n = 0;
    p_apostrophe(p.p, p.n, &q);
    SWAP();
    for (int k = 0; k < VTTS_IT_ABBREV_N; k++) {
        x_abbrev(VTTS_IT_ABBREV[k][0], VTTS_IT_ABBREV[k][1], p.p, p.n, &q);
        SWAP();
    }
    static const pass_fn PASSES[] = {p_drop, p_date_iso, p_date_dmy, p_time, p_time_dot, p_phone, p_money_before,
                                     p_money_after, p_percent, p_unit, p_ordinal, p_range, p_pause, p_code,
                                     p_number, p_symbols, p_acronym, p_final_apostrophe, p_lower, p_words};
    for (int k = 0; k < N_OF(PASSES); k++) {
        PASSES[k](p.p, p.n, &q);
        SWAP();
    }
#undef SWAP
    *out = p.p;
    return p.n;
}

/* ======================= tagging (latin.latin_word_lang, split_elision) ======================= */

static int ascii_low(const uint32_t *w, int n, char *o, int cap) { /* lower-case ASCII copy; 0 if not ASCII */
    if (n >= cap) return 0;
    for (int i = 0; i < n; i++) {
        if (w[i] >= 0x80) return 0;
        o[i] = (char)(w[i] >= 'A' && w[i] <= 'Z' ? w[i] + 32 : w[i]);
    }
    o[n] = 0;
    return 1;
}

static int elided(const uint32_t *w, int n) {
    char low[16];
    return ascii_low(w, n, low, (int)sizeof low) && x_in_sorted(VTTS_IT_ELIDED, VTTS_IT_ELIDED_N, low);
}

static const x_clusters_t CLUSTERS = {"aeiou", VTTS_IT_ONSETS, VTTS_IT_ONSETS_N, VTTS_IT_CODAS, VTTS_IT_CODAS_N,
                                      VTTS_IT_FINALS, VTTS_IT_FINALS_N};

/* g2p_it.valid_spelling of a lower-case ASCII word (w is modified) */
static int valid_spelling(char *w, int n) {
    for (int k = 0; k < VTTS_IT_FOREIGN_N; k++) if (x_has_sub(w, n, VTTS_IT_FOREIGN[k])) return 0;
    for (int i = 0; i + 1 < n; i++)
        if (w[i] == w[i + 1] && !x_in_list(VTTS_IT_DOUBLES, VTTS_IT_DOUBLES_N, w + i, 2)) return 0;
    int m = 0; /* re.sub(r"([bcdfglmnprstvz])\1", r"\1", w) */
    for (int i = 0; i < n;) {
        if (i + 1 < n && w[i] == w[i + 1] && strchr("bcdfglmnprstvz", w[i])) { w[m++] = w[i]; i += 2; }
        else w[m++] = w[i++];
    }
    w[m] = 0;
    n = m;
    for (int k = 0; k < VTTS_IT_DIGRAPHS_N; k++) n = x_replace_all(w, n, VTTS_IT_DIGRAPHS[k][0], VTTS_IT_DIGRAPHS[k][1]);
    return x_clusters(&CLUSTERS, w, n);
}

/* latin.latin_word_lang(core, "it") of a plain Latin word: 1 Italian, 0 English */
static int latin_lang(const uint32_t *w, int n) {
    char low[128], part[128];
    if (n <= 0) return 1;
    for (int i = 0; i < n; i++) if (x_in_u8(w[i], VTTS_IT_OWN)) return 1;
    if (n < (int)sizeof low) {
        ascii_low(w, n, low, (int)sizeof low);
        if (x_in_sorted(VTTS_IT_NATIVE, VTTS_IT_NATIVE_N, low) || x_in_sorted(VTTS_IT_TABLE_KEYS, VTTS_IT_TABLE_KEYS_N, low) ||
            x_in_sorted(VTTS_IT_ELIDED, VTTS_IT_ELIDED_N, low))
            return 1;
        if (vtts_lt_english_word(low)) return 0;
    }
    int ap = 0;
    while (ap < n && w[ap] != '\'') ap++;
    if (ap < n && ap + 1 < n && elided(w, ap)) return latin_lang(w + ap + 1, n - ap - 1);
    int all_caps = 1, all_valid = 1;
    for (int a = 0; a < n;) {
        int b = a;
        while (b < n && w[b] != '-' && w[b] != '\'') b++;
        if (b > a) {
            int len = b - a, caps = len >= 2 && len <= 5;
            if (x_camel(w + a, len)) return 0;
            for (int k = a; k < b; k++) caps &= x_upper_az(w[k]);
            all_caps &= caps;
            if (all_valid) {
                if (len >= (int)sizeof part) all_valid = 0;
                else {
                    ascii_low(w + a, len, part, (int)sizeof part);
                    all_valid = x_in_sorted(VTTS_IT_NATIVE, VTTS_IT_NATIVE_N, part) || valid_spelling(part, len);
                }
            }
        }
        a = b + 1;
    }
    if (n == 1 || all_caps) return 1;
    return all_valid;
}

int vtts_it_word_lang(const uint32_t *w, int n) {
    if (n <= 0) return -1;
    for (int i = 0; i < n; i++) if (x_in_u8(w[i], VTTS_IT_OWN)) return 1;
    if (!x_plain_latin(w, n)) return -1;
    return latin_lang(w, n);
}

static int is_edge(uint32_t c) { return c < 0x80 ? strchr(".,;:!?\"'()[]{}", (int)c) != NULL && c : x_in_u8(c, "…“”‘’«»–—"); }

int vtts_it_split(const uint32_t *w, int n) {
    int ap = 0;
    while (ap < n && w[ap] != '\'') ap++;
    if (ap >= n) return 0;
    int a = 0, r0 = ap + 1, r1 = n;
    while (a < ap && is_edge(w[a])) a++;
    while (r0 < r1 && is_edge(w[r0])) r0++;
    while (r1 > r0 && is_edge(w[r1 - 1])) r1--;
    if (a >= ap || r0 >= r1) return 0;
    uint32_t low[16];
    if (ap - a > 15) return 0;
    for (int i = a; i < ap; i++) low[i - a] = w[i] == 0x130 ? 0 : vtts_u_lower(w[i]);
    if (!elided(low, ap - a) || !x_plain_latin(w + r0, r1 - r0)) return 0;
    return latin_lang(w + r0, r1 - r0) == 0 ? ap + 1 : 0;
}

/* ======================= g2p (g2p_it.phonemes) ======================= */

typedef struct { char kind; uint8_t acc; char ph[3]; } seg_t; /* kind 'V' 'C' 'G'; acc 0 none, 1 grave, 2 acute, 3 stress */

typedef struct { uint8_t *out; int n, cap; } emit_t;

static void emit(emit_t *e, const char *name) {
    for (int k = 0; k < VTTS_IT_TOKENS_N; k++)
        if (strcmp(VTTS_IT_TOKENS[k], name) == 0) {
            if (e->n < e->cap) e->out[e->n++] = (uint8_t)(VTTS_ITEN_TOK0 + k);
            return;
        }
}

static uint32_t fold1(uint32_t c) {
    if (c < 0x80) return c >= 'A' && c <= 'Z' ? c + 32 : (c >= 'a' && c <= 'z' ? c : 0);
    int lo = 0, hi = VTTS_IT_FOLD_N - 1, k = -1;
    while (lo <= hi) {
        int m = (lo + hi) / 2;
        if (VTTS_IT_FOLD[m].start <= c) { k = m; lo = m + 1; } else hi = m - 1;
    }
    if (k < 0 || c - VTTS_IT_FOLD[k].start >= VTTS_IT_FOLD[k].count) return 0;
    return VTTS_IT_FOLD[k].first + (c - VTTS_IT_FOLD[k].start) * VTTS_IT_FOLD[k].step;
}

static int fold_word(const uint32_t *w, int n, uint32_t *o) {
    int m = 0;
    for (int i = 0; i < n && m < VTTS_IT_MAXW; i++) {
        uint32_t f = fold1(w[i]);
        if (f) o[m++] = f;
    }
    return m;
}

static int base_of(uint32_t c, const char *acc, const char *base) { /* the base vowel of an accented letter or 0 */
    uint32_t x;
    int l, k = 0;
    while ((l = x_dec1(acc, &x)) > 0) {
        if (x == c) return base[k];
        acc += l;
        k++;
    }
    return 0;
}

static int vowel_letter(uint32_t c) {
    return c && (strchr("aeiou", (int)(c < 0x80 ? c : 1)) || base_of(c, VTTS_IT_GRAVE, VTTS_IT_GRAVE_BASE) ||
                 base_of(c, VTTS_IT_ACUTE, VTTS_IT_ACUTE_BASE));
}

static int front(uint32_t c) { return !c || x_in_u8(c, VTTS_IT_FRONT); } /* Python: "" in FRONT */

static int ends_with(const uint32_t *w, int n, const char *k) {
    uint32_t b[24];
    int m = x_u8_decode(k, b, 24);
    if (n < m) return 0;
    for (int i = 0; i < m; i++) if (w[n - m + i] != b[i]) return 0;
    return 1;
}

static int any_ends(const uint32_t *w, int n, const char *const *list, int nl, const char *suffix) {
    char k[32];
    for (int i = 0; i < nl; i++) {
        size_t a = strlen(list[i]), b = strlen(suffix);
        if (a + b >= sizeof k) continue;
        memcpy(k, list[i], a);
        memcpy(k + a, suffix, b + 1);
        if (ends_with(w, n, k)) return 1;
    }
    return 0;
}

/* NUMBER_SEI on w[0..n): (venti|...|novanta)s(ei|ette)?$ */
static int number_sei(const uint32_t *w, int n) {
    return any_ends(w, n, VTTS_IT_TEN_WORDS, VTTS_IT_TEN_WORDS_N, "s") ||
           any_ends(w, n, VTTS_IT_TEN_WORDS, VTTS_IT_TEN_WORDS_N, "sei") ||
           any_ends(w, n, VTTS_IT_TEN_WORDS, VTTS_IT_TEN_WORDS_N, "sette");
}

/* IZZARE.search(w): izz(a[rtvz]|ando|er(?![iì]a)) */
static int izzare(const uint32_t *w, int n) {
    for (int i = 0; i + 3 < n; i++) {
        if (!(w[i] == 'i' && w[i + 1] == 'z' && w[i + 2] == 'z')) continue;
        int j = i + 3;
        if (w[j] == 'a' && j + 1 < n && (w[j + 1] == 'r' || w[j + 1] == 't' || w[j + 1] == 'v' || w[j + 1] == 'z')) return 1;
        if (j + 3 < n && w[j] == 'a' && w[j + 1] == 'n' && w[j + 2] == 'd' && w[j + 3] == 'o') return 1;
        if (w[j] == 'e' && j + 1 < n && w[j + 1] == 'r') {
            int k = j + 2;
            if (!(k + 1 < n && (w[k] == 'i' || w[k] == 0xEC) && w[k + 1] == 'a')) return 1;
        }
    }
    return 0;
}

static int is_v(const uint32_t *w, int n, int k) { return k >= 0 && k < n && vowel_letter(w[k]); }
static int silent_i(const uint32_t *w, int n, int k) { return k >= 0 && k < n && w[k] == 'i' && is_v(w, n, k + 1); }

static void seg(seg_t *S, int *ns, char kind, const char *ph) {
    if (*ns >= 2 * VTTS_IT_MAXW) return;
    seg_t *s = &S[(*ns)++];
    memset(s, 0, sizeof *s);
    s->kind = kind;
    s->ph[0] = ph[0];
    s->ph[1] = ph[0] ? ph[1] : 0;
}

static int segments(const uint32_t *w, int n, seg_t *S) {
    int ns = 0;
#define AT_(k) ((k) >= 0 && (k) < n ? w[k] : 0)
    for (int i = 0; i < n;) {
        uint32_t c = w[i], nxt = AT_(i + 1), nxt2 = AT_(i + 2);
        int g = base_of(c, VTTS_IT_GRAVE, VTTS_IT_GRAVE_BASE), a = base_of(c, VTTS_IT_ACUTE, VTTS_IT_ACUTE_BASE);
        if (c < 0x80 && strchr("aeiou", (int)c)) { char v[2] = {(char)c, 0}; seg(S, &ns, 'V', v); i++; continue; }
        if (g || a) { char v[2] = {(char)(g ? g : a), 0}; seg(S, &ns, 'V', v); S[ns - 1].acc = g ? 1 : 2; i++; continue; }
        if (c == 'j' || c == 'y') { seg(S, &ns, 'V', "i"); i++; continue; }
        int dbl = nxt == c && c != 'h';
        if (c == 'c' && nxt == 'q') dbl = 1;
        if (dbl) { i++; c = w[i]; nxt = AT_(i + 1); nxt2 = AT_(i + 2); }
        int before = ns, step = 1;
        if (c == 'c') {
            if (nxt == 'h') { seg(S, &ns, 'C', "k"); step = 2; }
            else if (front(nxt)) { seg(S, &ns, 'C', "ch"); if (silent_i(w, n, i + 1)) step = 2; }
            else seg(S, &ns, 'C', "k");
        } else if (c == 'g') {
            if (nxt == 'h') { seg(S, &ns, 'C', "g"); step = 2; }
            else if (front(nxt)) { seg(S, &ns, 'C', "dj"); if (silent_i(w, n, i + 1)) step = 2; }
            else if (nxt == 'l' && (nxt2 == 'i' || nxt2 == 0xEC)) { seg(S, &ns, 'C', "ly"); step = silent_i(w, n, i + 2) ? 3 : 2; }
            else if (nxt == 'n') { seg(S, &ns, 'C', "ny"); step = 2; }
            else seg(S, &ns, 'C', "g");
        } else if (c == 's') {
            if (nxt == 'c' && front(nxt2)) { seg(S, &ns, 'C', "sh"); step = silent_i(w, n, i + 2) ? 3 : 2; }
            else if (nxt == 'c' && nxt2 == 'h') { seg(S, &ns, 'C', "s"); seg(S, &ns, 'C', "k"); step = 3; }
            else if ((nxt && nxt < 0x80 && strchr(VTTS_IT_VOICED, (int)nxt)) ||
                     (is_v(w, n, i - 1) && is_v(w, n, i + 1) && !dbl && !number_sei(w, i + 1)))
                seg(S, &ns, 'C', "z");
            else seg(S, &ns, 'C', "s");
        } else if (c == 'z') {
            int voiced = (i == 0 && !dbl) || (dbl && izzare(w, n));
            seg(S, &ns, 'C', voiced ? "dz" : "ts");
        } else if (c == 'q') {
            seg(S, &ns, 'C', "k");
            if (nxt == 'u') { seg(S, &ns, 'G', "w"); step = 2; }
        } else if (c == 'h') {
        } else if (c == 'x') { seg(S, &ns, 'C', "k"); seg(S, &ns, 'C', "s"); }
        else if (c == 'w') seg(S, &ns, 'C', "v");
        else { char one[2] = {(char)c, 0}; seg(S, &ns, 'C', one); }
        if (dbl && ns > before && ns < 2 * VTTS_IT_MAXW) {
            memmove(S + before + 1, S + before, (size_t)(ns - before) * sizeof *S);
            ns++;
        }
        i += step;
    }
#undef AT_
    /* intrinsically long consonants between vowels */
    static const char *const LONG[5] = {"ny", "ly", "sh", "ts", "dz"};
    for (int k = 1; k + 1 < ns && ns < 2 * VTTS_IT_MAXW; k++) {
        if (S[k].kind != 'C' || S[k - 1].kind != 'V' || (S[k + 1].kind != 'V' && S[k + 1].kind != 'G')) continue;
        int is_long = 0;
        for (int q = 0; q < 5; q++) is_long |= !strncmp(S[k].ph, LONG[q], 2);
        if (!is_long) continue;
        memmove(S + k + 1, S + k, (size_t)(ns - k) * sizeof *S);
        ns++;
        k++;
    }
    return ns;
}

/* _nuclei: marks nuclei in nuc[], turns other vowels into glides; returns the count */
static int nuclei(seg_t *S, int ns, int *nuc) {
    int nn = 0, nruns = 0;
    for (int k = 0; k < ns;) {
        if (S[k].kind != 'V') { k++; continue; }
        int j = k;
        while (j < ns && S[j].kind == 'V') j++;
        nruns++;
        k = j;
    }
    for (int k = 0; k < ns;) {
        if (S[k].kind != 'V') { k++; continue; }
        int j = k;
        while (j < ns && S[j].kind == 'V') j++;
        if (j - k == 1) { nuc[nn++] = k; k = j; continue; }
#define WEAK(q) ((S[q].ph[0] == 'i' || S[q].ph[0] == 'u') && !S[q].acc)
        if (nruns == 1 && j - k == 2 && WEAK(k) && !WEAK(k + 1) && !S[k + 1].acc) {
            nuc[nn++] = k;
            nuc[nn++] = k + 1;
            S[k].acc = 3; /* mio, via, due */
            k = j;
            continue;
        }
        uint8_t strong[64] = {0};
        int len = j - k < 64 ? j - k : 64, lone_first = -1, lone_last = -1;
        for (int q = 0; q < len; q++) strong[q] = !WEAK(k + q);
        for (int q = 0; q < len; q++) {
            if (strong[q]) continue;
            int left = q > 0 && strong[q - 1], right = q + 1 < len && strong[q + 1];
            if (!left && !right) { if (lone_first < 0) lone_first = q; lone_last = q; }
        }
        if (lone_first >= 0) strong[k + lone_last == ns - 1 ? lone_first : lone_last] = 1;
        for (int q = 0; q < len; q++) {
            if (strong[q]) nuc[nn++] = k + q;
            else { S[k + q].kind = 'G'; S[k + q].ph[0] = S[k + q].ph[0] == 'i' ? 'j' : 'w'; S[k + q].ph[1] = 0; }
        }
#undef WEAK
        k = j;
    }
    return nn;
}

static int unstressed(const uint32_t *w, int n) {
    char u[64];
    return x_to_u8(w, n, u, (int)sizeof u) && x_in_sorted(VTTS_IT_UNSTRESSED, VTTS_IT_UNSTRESSED_N, u);
}

static int one_of(uint32_t c, const char *set) { return c && c < 0x80 && strchr(set, (int)c); }

/* the ANTEPENULT patterns of g2p_it (each with at least three nuclei) */
static int antepenult(const uint32_t *w, int n) {
    static const char *const SUF[] = {"abile", "abili", "abila", "ibile", "ibili", "ibila", "evole", "evoli", "evola",
                                      "imo", "ima", "imi", "ime", "ico", "ica", "ici", "iche", "ologo", "ologa",
                                      "ologi", "ologhe", "ografo", "ografa", "ografi", "ografe", "fono", "foni",
                                      "metro", "metri", "erano", "arono", "erono", "irono", "avano", "evano", "ivano"};
    for (int k = 0; k < N_OF(SUF); k++) if (ends_with(w, n, SUF[k])) return 1;
    if (n >= 4 && w[n - 3] == 'o' && w[n - 2] == 'l' && one_of(w[n - 1], "oaie") && one_of(w[n - 4], "bcgptv")) return 1;
    if (n >= 4 && w[n - 3] == 'i' && w[n - 2] == 'n' && one_of(w[n - 1], "ei") && one_of(w[n - 4], "dgm")) return 1;
    if (n >= 4 && ends_with(w, n, "ere") && w[n - 4] != 'i') return 1;
    if (n >= 5 && ends_with(w, n, "ero") && w[n - 4] == w[n - 5] && one_of(w[n - 4], "bcdfglmnprstvz")) return 1;
    if (n >= 4 && ends_with(w, n, "ono") && !one_of(w[n - 4], "aeiou")) return 1;
    return 0;
}

static int stress_of(const uint32_t *w, int n, const seg_t *S, const int *nuc, int nn) {
    if (!nn || unstressed(w, n)) return -1;
    for (int k = nn - 1; k >= 0; k--) if (S[nuc[k]].acc) return nuc[k];
    if (nn == 1) return nuc[0];
    if (nn >= 3 && antepenult(w, n) && !any_ends(w, n, VTTS_IT_ERE_STEMS, VTTS_IT_ERE_STEMS_N, "ere")) return nuc[nn - 3];
    uint32_t last = w[n - 1];
    if (!vowel_letter(last) && last != 'j' && last != 'y') return nuc[nn - 1];
    return nuc[nn - 2];
}

static char quality(const uint32_t *w, int n, const seg_t *S, int k, const int *nuc, int nn) {
    char v = S[k].ph[0];
    if (v != 'e' && v != 'o') return v;
    if (S[k].acc == 1) return (char)(v - 32);
    if (S[k].acc == 2) return v;
    if (k > 0 && S[k - 1].kind == 'G' && S[k - 1].ph[0] == (v == 'e' ? 'j' : 'w')) return (char)(v - 32);
    if (nn >= 3 && k == nuc[nn - 3]) return (char)(v - 32);
    if (nn >= 2 && k == nuc[nn - 2]) {
        if (v == 'e') {
            static const char *const OE[] = {"enza", "enze", "ello", "ella", "elli", "elle", "esimo", "esima", "esimi", "esime"};
            int open = (ends_with(w, n, "ente") || ends_with(w, n, "enti")) && !(n >= 5 && w[n - 5] == 'm');
            for (int q = 0; q < N_OF(OE) && !open; q++) open = ends_with(w, n, OE[q]);
            if (open) return 'E';
        } else if (ends_with(w, n, "orio") || ends_with(w, n, "oria") || ends_with(w, n, "orie")) return 'O';
    }
    return v;
}

/* _read(w, stressed): emits the phonemes; S holds 2 * VTTS_IT_MAXW segments, nuc VTTS_IT_MAXW */
static void read_word(emit_t *e, const uint32_t *w, int n, int stressed, seg_t *S, int *nuc, int drop_last) {
    int ns = segments(w, n, S);
    int nn = nuclei(S, ns, nuc);
    int st = stressed ? stress_of(w, n, S, nuc, nn) : -1;
    if (drop_last && ns) ns--;
    for (int k = 0; k < ns; k++) {
        char b[4] = {S[k].ph[0], S[k].ph[1], 0, 0};
        if (S[k].kind == 'V' && k == st) { b[0] = quality(w, n, S, k, nuc, nn); b[1] = '1'; }
        emit(e, b);
    }
}

/* _mark_ia: galleria -> gallerìa, ventisei -> ventisèi (w is changed in place, same length) */
static void mark_ia(uint32_t *w, int n) {
    for (int i = 0; i < n; i++) if (base_of(w[i], VTTS_IT_GRAVE, VTTS_IT_GRAVE_BASE) || base_of(w[i], VTTS_IT_ACUTE, VTTS_IT_ACUTE_BASE)) return;
    if (number_sei(w, n) && ends_with(w, n, "sei")) { w[n - 2] = 0xE8; return; }
    for (int st = 0; st < n; st++) { /* leftmost match of the alternation, anchored at the end */
        int len = n - st, hit = -1;
        if (len == 4 && w[st] == 'e' && w[st + 1] == 'r' && w[st + 2] == 'i' && w[st + 3] == 'a' && st >= 2)
            for (int k = 0; k < VTTS_IT_IA_ERIA_AFTER_N && hit < 0; k++)
                if ((uint32_t)VTTS_IT_IA_ERIA_AFTER[k][0] == w[st - 2] && (uint32_t)VTTS_IT_IA_ERIA_AFTER[k][1] == w[st - 1]) hit = 3;
        for (int k = 0; k < VTTS_IT_IA_STEMS_N && hit < 0; k++) {
            int l = (int)strlen(VTTS_IT_IA_STEMS[k]);
            if (len != l + 1 || (w[n - 1] != 'a' && w[n - 1] != 'e')) continue;
            int ok = 1;
            for (int q = 0; q < l && ok; q++) ok = w[st + q] == (uint32_t)(unsigned char)VTTS_IT_IA_STEMS[k][q];
            if (ok) hit = l;
        }
        if (hit < 0 && len == 5 && w[st] == 'm' && w[st + 1] == 'a' && w[st + 2] == 'n' && w[st + 3] == 'i' && w[st + 4] == 'e') hit = 4;
        if (hit >= 0) { w[st + hit - 1] = 0xEC; return; }
    }
}

static const char *override(const uint32_t *w, int n) {
    char u[256];
    if (!x_to_u8(w, n, u, (int)sizeof u)) return NULL;
    int lo = 0, hi = VTTS_IT_OVERRIDES_N - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2, c = strcmp(VTTS_IT_OVERRIDES[m][0], u);
        if (!c) return VTTS_IT_OVERRIDES[m][1];
        if (c < 0) lo = m + 1; else hi = m - 1;
    }
    return NULL;
}

/* phonemes(word) */
static void phonemes(emit_t *e, const uint32_t *word, int wn, uint32_t *f, uint32_t *t, seg_t *S, int *nuc) {
    int n = fold_word(word, wn, f);
    const char *r = override(f, n);
    if (r) { /* the respelling is the only part: _read(_mark_ia(override_table().get(p, p))) */
        int m = x_u8_decode(r, t, VTTS_IT_MAXW);
        const char *r2 = override(t, m);
        if (r2) m = x_u8_decode(r2, t, VTTS_IT_MAXW);
        mark_ia(t, m);
        read_word(e, t, m, 1, S, nuc, 0);
        return;
    }
    /* parts: fold() of each piece between apostrophes (’ is '), empty ones dropped */
    int starts[VTTS_IT_MAXW / 2], lens[VTTS_IT_MAXW / 2], np = 0, m = 0;
    for (int i = 0; i <= wn && m < VTTS_IT_MAXW;) {
        int j = i;
        while (j < wn && word[j] != '\'' && word[j] != 0x2019) j++;
        int st = m;
        for (int q = i; q < j && m < VTTS_IT_MAXW; q++) { uint32_t c = fold1(word[q]); if (c) f[m++] = c; }
        if (m > st && np < VTTS_IT_MAXW / 2) { starts[np] = st; lens[np++] = m - st; }
        i = j + 1;
    }
    for (int k = 0; k < np; k++) {
        const uint32_t *p = f + starts[k];
        int pl = lens[k];
        if (k < np - 1) {
            uint32_t nx = f[starts[k + 1]];
            if ((p[pl - 1] == 'c' || p[pl - 1] == 'g') && front(nx)) {
                memcpy(t, p, (size_t)pl * sizeof *t);
                t[pl] = 'i';
                t[pl + 1] = nx;
                read_word(e, t, pl + 2, 0, S, nuc, 1);
            } else read_word(e, p, pl, 0, S, nuc, 0);
            continue;
        }
        const char *rr = override(p, pl);
        int tl = rr ? x_u8_decode(rr, t, VTTS_IT_MAXW) : pl;
        if (!rr) memcpy(t, p, (size_t)pl * sizeof *t);
        mark_ia(t, tl);
        read_word(e, t, tl, 1, S, nuc, 0);
    }
}

int vtts_it_word_ids(const uint32_t *w, int n, uint32_t *scratch, uint8_t *out, int cap) {
    uint32_t *f = scratch, *t = scratch + VTTS_IT_MAXW;
    int *nuc = (int *)(void *)(scratch + 2 * VTTS_IT_MAXW);
    seg_t *S = (seg_t *)(void *)(scratch + 3 * VTTS_IT_MAXW); /* 2 * VTTS_IT_MAXW segments */
    uint32_t *spelled = scratch + 7 * VTTS_IT_MAXW;              /* a letter name */
    emit_t e = {out, 0, cap};
    if (n > VTTS_IT_MAXW) n = VTTS_IT_MAXW;
    if (n && w[n - 1] == 0x2BC) { /* sullʼ, poʼ */
        int m = fold_word(w, n, f);
        read_word(&e, f, m, m == 2 && f[0] == 'p' && f[1] == 'o', S, nuc, 0);
        return e.n;
    }
    int m = fold_word(w, n, f), vowel = 0;
    for (int i = 0; i < m; i++) vowel |= vowel_letter(f[i]) || f[i] == 'j' || f[i] == 'y';
    if (m && !vowel) { /* spelled letter by letter */
        for (int i = 0; i < m; i++) {
            const char *name = f[i] < 0x80 ? letter_name(f[i]) : NULL;
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
                phonemes(&e, pc, pn, spelled, t, S, nuc);
                name += l;
            }
        }
        return e.n;
    }
    phonemes(&e, w, n, f, t, S, nuc);
    return e.n;
}

#endif
