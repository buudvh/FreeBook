/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_en.c -- English word -> token ids (set v2), mirroring src/vtts/frontend/en/g2p_en.py:
 * lexicon, hyphen split, CamelCase split, short acronyms spelled, lexicon or two-part compound,
 * inflections (-'s -s -es -ed -ing -er -ly) on a known base, learned letter-to-sound. */
#include "vtts_text_en.h"

#include <stdio.h>
#include <string.h>

#include "vtts_text_tables.h"

#define EN_WORD_MAX 128
#define S1 (VTTS_V2_S0 + 1)
#define S2 (VTTS_V2_S0 + 2)

static int is_lower(char c) { return c >= 'a' && c <= 'z'; }
static int is_upper(char c) { return c >= 'A' && c <= 'Z'; }
static int is_stress(uint8_t t) { return t >= VTTS_V2_S0 && t <= VTTS_V2_S0 + 2; }
static uint8_t ph(const char *name) {
    for (int i = 0; i < (int)(sizeof VTTS_ARPABET / sizeof *VTTS_ARPABET); i++)
        if (strcmp(VTTS_ARPABET[i], name) == 0) return (uint8_t)(VTTS_V2_EN0 + i);
    return 0;
}

typedef struct { uint8_t *t; int n, cap, err; } tb_t; /* token buffer */

static void tb_put(tb_t *b, uint8_t x) { if (b->n < b->cap) b->t[b->n++] = x; else b->err = 1; }
static int has_primary(const tb_t *b, int from) {
    for (int i = from; i < b->n; i++) if (b->t[i] == S1) return 1;
    return 0;
}
/* append part (already in b from `start`): demote its primaries if b had one before it */
static void join_part(tb_t *b, int start, int had_primary) {
    if (!had_primary) return;
    for (int i = start; i < b->n; i++) if (b->t[i] == S1) b->t[i] = S2;
}

static int lex_get(const vtts_lex *lx, const char *w, tb_t *b) {
    if (!lx) return 0;
    int k = vtts_lex_lookup(lx, w, b->t + b->n, b->cap - b->n);
    if (k < 0) { b->err = 1; return 0; }
    b->n += k;
    return k > 0;
}

static int in_lex(const vtts_lex *lx, const char *w) {
    uint8_t tmp[64];
    return lx && vtts_lex_lookup(lx, w, tmp, (int)sizeof tmp) != 0;
}

/* lexicon entry or two-part compound of lexicon words (each part >= 3 letters) */
static int known(const vtts_lex *lx, const char *w, tb_t *b) {
    if (lex_get(lx, w, b)) return 1;
    int n = (int)strlen(w);
    char a[EN_WORD_MAX];
    for (int i = n - 3; i > 2; i--) {
        memcpy(a, w, (size_t)i);
        a[i] = 0;
        if (in_lex(lx, a) && in_lex(lx, w + i)) {
            int s = b->n;
            lex_get(lx, a, b);
            int had = has_primary(b, s);
            int s2 = b->n;
            lex_get(lx, w + i, b);
            join_part(b, s2, had);
            return 1;
        }
    }
    return 0;
}

static int last_phone(const tb_t *b, int from) {
    for (int i = b->n - 1; i >= from; i--)
        if (!is_stress(b->t[i]) && b->t[i] >= VTTS_V2_EN0) return b->t[i];
    return 0;
}

static int ph_in(int p, const char *const *names) {
    for (; *names; names++) if (p == ph(*names)) return 1;
    return 0;
}
static const char *const SIBILANTS[] = {"S", "Z", "SH", "ZH", "CH", "JH", 0};
static const char *const VOICELESS[] = {"P", "T", "K", "F", "TH", 0};
static const char *const PAST_T[] = {"P", "T", "K", "F", "TH", "S", "SH", "CH", 0};

static void plural(tb_t *b, int from) {
    int last = last_phone(b, from);
    if (ph_in(last, SIBILANTS)) { tb_put(b, ph("IH")); tb_put(b, VTTS_V2_S0); tb_put(b, ph("Z")); }
    else tb_put(b, ph_in(last, VOICELESS) ? ph("S") : ph("Z"));
}
static void past(tb_t *b, int from) {
    int last = last_phone(b, from);
    if (last == ph("T") || last == ph("D")) { tb_put(b, ph("IH")); tb_put(b, VTTS_V2_S0); tb_put(b, ph("D")); }
    else tb_put(b, ph_in(last, PAST_T) ? ph("T") : ph("D"));
}

static int ends(const char *w, int n, const char *suf) {
    int k = (int)strlen(suf);
    return n >= k && memcmp(w + n - k, suf, (size_t)k) == 0;
}

/* known base with `cut` letters removed and `add` appended */
static int known_base(const vtts_lex *lx, const char *w, int n, int cut, const char *add, tb_t *b) {
    char base[EN_WORD_MAX];
    if (n - cut < 0 || n - cut + (int)strlen(add) >= EN_WORD_MAX) return 0;
    memcpy(base, w, (size_t)(n - cut));
    strcpy(base + n - cut, add);
    return known(lx, base, b);
}

static int inflected(const vtts_lex *lx, const char *w, tb_t *b) {
    int n = (int)strlen(w), s = b->n;
    if (ends(w, n, "'s") && known_base(lx, w, n, 2, "", b)) { plural(b, s); return 1; }
    if (ends(w, n, "es") && (ends(w, n - 2, "s") || ends(w, n - 2, "x") || ends(w, n - 2, "z") ||
                             ends(w, n - 2, "ch") || ends(w, n - 2, "sh")) && known_base(lx, w, n, 2, "", b)) {
        plural(b, s);
        return 1;
    }
    if (ends(w, n, "s") && !ends(w, n, "ss") && known_base(lx, w, n, 1, "", b)) { plural(b, s); return 1; }
    if (ends(w, n, "ed") && (known_base(lx, w, n, 2, "", b) || known_base(lx, w, n, 1, "", b))) { past(b, s); return 1; }
    if (ends(w, n, "ing") && (known_base(lx, w, n, 3, "", b) || known_base(lx, w, n, 3, "e", b))) {
        tb_put(b, ph("IH")); tb_put(b, VTTS_V2_S0); tb_put(b, ph("NG"));
        return 1;
    }
    if (ends(w, n, "er") && known_base(lx, w, n, 2, "", b)) { tb_put(b, ph("ER")); tb_put(b, VTTS_V2_S0); return 1; }
    if (ends(w, n, "ly") && known_base(lx, w, n, 2, "", b)) {
        tb_put(b, ph("L")); tb_put(b, ph("IY")); tb_put(b, VTTS_V2_S0);
        return 1;
    }
    return 0;
}

static int has_cased(const char *w) { for (; *w; w++) if (is_lower(*w) || is_upper(*w)) return 1; return 0; }

static void g2p(const vtts_lex *lx, const char *word, tb_t *b, int depth);

/* g2p of each part, joined keeping the first primary stress */
static void join_g2p(const vtts_lex *lx, const char *const *parts, int np, tb_t *b, int depth) {
    for (int i = 0; i < np; i++) {
        int had = has_primary(b, 0), s = b->n;
        g2p(lx, parts[i], b, depth + 1);
        join_part(b, s, had);
    }
}

static void g2p(const vtts_lex *lx, const char *word, tb_t *b, int depth) {
    char w[EN_WORD_MAX], low[EN_WORD_MAX];
    int n = (int)strlen(word);
    if (depth > 8 || n >= EN_WORD_MAX) return;
    int a = 0, z = n;
    while (a < z && word[a] == '\'') a++;  /* strip("'") */
    while (z > a && word[z - 1] == '\'') z--;
    if (a >= z || z - a >= EN_WORD_MAX) return;
    n = z - a;
    memcpy(w, word + a, (size_t)(z - a));
    w[z - a] = 0;
    for (int i = 0; i <= n; i++) low[i] = is_upper(w[i]) ? (char)(w[i] - 'A' + 'a') : w[i];
    if (lex_get(lx, low, b)) return;
    if (strchr(w, '-')) {
        char buf[EN_WORD_MAX];
        const char *parts[EN_WORD_MAX];
        int np = 0;
        strcpy(buf, w);
        for (char *p = strtok(buf, "-"); p; p = strtok(NULL, "-")) parts[np++] = p;
        join_g2p(lx, parts, np, b, depth);
        return;
    }
    { /* CamelCase: [A-Z]+(?![a-z]) | [A-Z]?[a-z]+ (findall), when the pieces cover the word */
        char pieces[EN_WORD_MAX * 2], joined[EN_WORD_MAX], noap[EN_WORD_MAX];
        const char *parts[EN_WORD_MAX];
        int np = 0, pp = 0, jn = 0, i = 0;
        while (i < n) {
            int len = 0;
            if (is_upper(w[i])) {
                int L = 0;
                while (i + L < n && is_upper(w[i + L])) L++;
                if (!(i + L < n && is_lower(w[i + L]))) len = L;
                else if (L >= 2) len = L - 1;
            }
            if (!len) {
                int j = i;
                if (is_upper(w[j]) && j + 1 < n && is_lower(w[j + 1])) j++;
                int k = j;
                while (k < n && is_lower(w[k])) k++;
                if (k > j) len = k - i;
            }
            if (!len) { i++; continue; }
            parts[np++] = pieces + pp;
            memcpy(pieces + pp, w + i, (size_t)len);
            pp += len;
            pieces[pp++] = 0;
            memcpy(joined + jn, w + i, (size_t)len);
            jn += len;
            i += len;
        }
        joined[jn] = 0;
        int m = 0;
        for (int k = 0; k < n; k++) if (w[k] != '\'') noap[m++] = w[k];
        noap[m] = 0;
        if (np > 1 && strcmp(joined, noap) == 0) { join_g2p(lx, parts, np, b, depth); return; }
    }
    { /* short all-caps acronym: isupper() and isalpha() and len <= 4 */
        int alpha = 1, lower = 0;
        for (int i = 0; i < n; i++) {
            if (!is_upper(w[i]) && !is_lower(w[i])) alpha = 0;
            if (is_lower(w[i])) lower = 1;
        }
        if (alpha && !lower && has_cased(w) && n <= 4) {
            for (int i = 0; i < n; i++) {
                const uint8_t *L = VTTS_EN_LETTERS[w[i] - 'A'];
                int had = has_primary(b, 0), s = b->n;
                for (int k = 0; k < L[0]; k++) tb_put(b, L[1 + k]);
                join_part(b, s, had);
            }
            return;
        }
    }
    if (known(lx, low, b) || inflected(lx, low, b)) return;
    if (!lx) return;
    int k = vtts_lex_predict(lx, low, b->t + b->n, b->cap - b->n);
    if (k < 0) b->err = 1; else b->n += k;
}

int vtts_en_g2p(const vtts_lex *lx, const char *word, uint8_t *out, int cap) {
    tb_t b = {out, 0, cap, 0};
    if (!word) return 0;
    g2p(lx, word, &b, 0);
    return b.err ? -1 : b.n;
}

/* ======================= English normalization (normalize_en) =======================
 * Each regex pass of the Python normalizer is one function from buffer s (n code points) to
 * buffer d; matches are found left to right without overlap, like re.sub. Backtracking is
 * reproduced where it can change the result (optional groups followed by a lookahead). */

typedef struct { uint32_t *p; int n, cap, err; } cb_t; /* code point buffer */

static void cb_put(cb_t *d, uint32_t c) { if (d->n < d->cap) d->p[d->n++] = c; else d->err = 1; }
static void cb_str(cb_t *d, const char *s) { while (*s) cb_put(d, (uint8_t)*s++); }
static void cb_cps(cb_t *d, const uint32_t *s, int n) { for (int i = 0; i < n; i++) cb_put(d, s[i]); }

static int W(const uint32_t *s, int n, int i) { return i >= 0 && i < n && vtts_cp_is_word(s[i]); }
static int D(const uint32_t *s, int n, int i) { return i >= 0 && i < n && s[i] >= '0' && s[i] <= '9'; }
static int SP(const uint32_t *s, int n, int i) { return i >= 0 && i < n && vtts_cp_is_space(s[i]); }
static int BND(const uint32_t *s, int n, int i) { return W(s, n, i - 1) != W(s, n, i); } /* \b before i */
static uint32_t lowc(uint32_t c) { return c >= 'A' && c <= 'Z' ? c + 32 : c; }

/* ---- numbers as words (strings of ASCII digits, any length) ---- */
typedef struct { char *p; int n, cap, err; } sb_t;
static void sb_str(sb_t *b, const char *s) {
    while (*s) { if (b->n + 1 < b->cap) b->p[b->n++] = *s; else b->err = 1; s++; }
    b->p[b->n < b->cap ? b->n : b->cap - 1] = 0;
}

static void cardinal_digits(sb_t *b, const char *d, int n);

static void cardinal_small(sb_t *b, unsigned v) { /* v < 1000 */
    if (v < 20) { sb_str(b, VTTS_EN_ONES[v]); return; }
    if (v < 100) {
        sb_str(b, VTTS_EN_TENS[v / 10]);
        if (v % 10) { sb_str(b, " "); sb_str(b, VTTS_EN_ONES[v % 10]); }
        return;
    }
    sb_str(b, VTTS_EN_ONES[v / 100]);
    sb_str(b, " hundred");
    if (v % 100) { sb_str(b, " "); cardinal_small(b, v % 100); }
}

/* cardinal(int(d)): n >= 10^12 recurses on "trillion" like Python, below that 9, 6, 3 digits */
static void cardinal_digits(sb_t *b, const char *d, int n) {
    while (n > 1 && *d == '0') { d++; n--; }
    if (n <= 3) {
        unsigned v = 0;
        for (int i = 0; i < n; i++) v = v * 10 + (unsigned)(d[i] - '0');
        cardinal_small(b, v);
        return;
    }
    static const struct { int digits; const char *name; } SC[] = {{12, "trillion"}, {9, "billion"}, {6, "million"}, {3, "thousand"}};
    for (int s = 0; s < 4; s++) {
        if (n <= SC[s].digits) continue;
        int hi = n - SC[s].digits;
        cardinal_digits(b, d, hi);
        sb_str(b, " ");
        sb_str(b, SC[s].name);
        const char *r = d + hi;
        int rn = SC[s].digits, nz = 0;
        for (int i = 0; i < rn; i++) nz |= r[i] != '0';
        if (nz) { sb_str(b, " "); cardinal_digits(b, r, rn); }
        return;
    }
}

static void cardinal_u(sb_t *b, unsigned long long v) {
    char d[24];
    int n = snprintf(d, sizeof d, "%llu", v);
    cardinal_digits(b, d, n);
}

static void ordinal_digits(sb_t *b, const char *d, int n) {
    int start = b->n;
    cardinal_digits(b, d, n);
    if (b->err) return;
    char *w = b->p + start, *last = strrchr(w, ' ');
    last = last ? last + 1 : w;
    for (int i = 0; i < VTTS_EN_N_ORD_IRREG; i++)
        if (strcmp(last, VTTS_EN_ORD_IRREG[i][0]) == 0) {
            b->n = (int)(last - b->p);
            sb_str(b, VTTS_EN_ORD_IRREG[i][1]);
            return;
        }
    size_t l = strlen(last);
    if (l && last[l - 1] == 'y') { b->n--; sb_str(b, "ieth"); }
    else sb_str(b, "th");
}

static void year_v(sb_t *b, unsigned v) {
    if (v >= 2000 && v <= 2009) { cardinal_u(b, v); return; }
    unsigned hi = v / 100, lo = v % 100;
    cardinal_u(b, hi);
    if (lo == 0) { sb_str(b, " hundred"); return; }
    sb_str(b, " ");
    if (lo < 10) { sb_str(b, "oh "); sb_str(b, VTTS_EN_ONES[lo]); }
    else cardinal_u(b, lo);
}

static void digits_words(sb_t *b, const char *d, int n) {
    for (int i = 0; i < n; i++) { if (i) sb_str(b, " "); sb_str(b, VTTS_EN_ONES[d[i] - '0']); }
}

/* number(s): commas dropped; "a.b" -> cardinal(a or 0) point digits(b) */
static void number_s(sb_t *b, const uint32_t *s, int n) {
    char d[512];
    int k = 0, dot = -1;
    for (int i = 0; i < n && k < (int)sizeof d - 1; i++) {
        if (s[i] == ',') continue;
        if (s[i] == '.' && dot < 0) dot = k;
        d[k++] = (char)s[i];
    }
    d[k] = 0;
    if (dot >= 0) {
        if (dot == 0) sb_str(b, "zero"); else cardinal_digits(b, d, dot);
        sb_str(b, " point");
        if (k - dot - 1 > 0) { sb_str(b, " "); digits_words(b, d + dot + 1, k - dot - 1); }
        return;
    }
    cardinal_digits(b, d, k);
}

static void put_sb(cb_t *d, sb_t *b) { cb_str(d, b->p); b->n = 0; b->p[0] = 0; }

/* ---- the passes ---- */
#define SBUF 4096
typedef struct { char buf[SBUF]; sb_t sb; } words_t;
static void wt_init(words_t *w) { w->sb.p = w->buf; w->sb.n = 0; w->sb.cap = SBUF; w->sb.err = 0; w->buf[0] = 0; }

static int is_code_ch(uint32_t c) { return (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'); }

/* (?<!\w)(?=[A-Z0-9]*[A-Z])(?=[A-Z0-9]*[0-9])[A-Z0-9]+(?!\w): digits -> " one " ... */
static void p_code(const uint32_t *s, int n, cb_t *d) {
    for (int i = 0; i < n;) {
        if (is_code_ch(s[i]) && !W(s, n, i - 1)) {
            int j = i, up = 0, dg = 0;
            while (j < n && is_code_ch(s[j])) { up |= s[j] >= 'A'; dg |= s[j] <= '9'; j++; }
            if (up && dg && !W(s, n, j)) {
                for (int k = i; k < j; k++)
                    if (s[k] <= '9') { cb_str(d, " "); cb_str(d, VTTS_EN_ONES[s[k] - '0']); cb_str(d, " "); }
                    else cb_put(d, s[k]);
                i = j;
                continue;
            }
        }
        cb_put(d, s[i++]);
    }
}

static int match_at(const uint32_t *s, int n, int i, const char *k) {
    for (; *k; k++, i++) if (i >= n || s[i] != (uint8_t)*k) return 0;
    return 1;
}

/* (?<![\w.])KEY -> " value " (one pass per key, in table order) */
static void p_abbrev(const uint32_t *s, int n, cb_t *d, const char *k, const char *v) {
    int kl = (int)strlen(k);
    for (int i = 0; i < n;) {
        if (!(i > 0 && (W(s, n, i - 1) || s[i - 1] == '.')) && match_at(s, n, i, k)) {
            cb_str(d, " "); cb_str(d, v); cb_str(d, " ");
            i += kl;
            continue;
        }
        cb_put(d, s[i++]);
    }
}

static int cur_idx(uint32_t c) {
    for (int i = 0; i < VTTS_EN_N_CURRENCY; i++) if (VTTS_EN_CURRENCY[i].cp == c) return i;
    return -1;
}
static int word_at(const uint32_t *s, int n, int i, const char *w) { return match_at(s, n, i, w); }

/* ([$€£])(\d[\d,]*)(?:\.(\d+))?(?:\s?(million|billion|thousand))? */
static void p_money(const uint32_t *s, int n, cb_t *d, words_t *wt) {
    static const char *const SCALE[] = {"million", "billion", "thousand"};
    for (int i = 0; i < n;) {
        int c = cur_idx(s[i]);
        if (c >= 0 && D(s, n, i + 1)) {
            int a = i + 1, j = a + 1;
            while (j < n && (D(s, n, j) || s[j] == ',')) j++;
            int ae = j, fs = -1, fe = -1;
            if (j < n && s[j] == '.' && D(s, n, j + 1)) { fs = j + 1; fe = fs; while (D(s, n, fe)) fe++; j = fe; }
            int sc = -1, end = j;
            for (int sp = 1; sp >= 0 && sc < 0; sp--) {
                if (sp && !SP(s, n, j)) continue;
                for (int k = 0; k < 3; k++)
                    if (word_at(s, n, j + sp, SCALE[k])) { sc = k; end = j + sp + (int)strlen(SCALE[k]); break; }
            }
            sb_t *b = &wt->sb;
            if (sc >= 0) {
                uint32_t tmp[600];
                int tn = 0;
                for (int k = a; k < ae && tn < 590; k++) tmp[tn++] = s[k];
                if (fs >= 0) { tmp[tn++] = '.'; for (int k = fs; k < fe && tn < 598; k++) tmp[tn++] = s[k]; }
                number_s(b, tmp, tn);
                sb_str(b, " "); sb_str(b, SCALE[sc]); sb_str(b, " "); sb_str(b, VTTS_EN_CURRENCY[c].many);
                put_sb(d, b);
            } else {
                char whole[512];
                int wn = 0, zero = 1;
                for (int k = a; k < ae && wn < 511; k++) if (s[k] != ',') { whole[wn++] = (char)s[k]; zero &= s[k] == '0'; }
                whole[wn] = 0;
                int cents = 0;
                if (fs >= 0) {
                    cents = (s[fs] - '0') * 10;
                    if (fe - fs > 1) cents += (int)(s[fs + 1] - '0');
                }
                int one = 0;
                { int k = 0; while (k < wn - 1 && whole[k] == '0') k++; one = wn - k == 1 && whole[k] == '1'; }
                cb_str(d, " ");
                int any = 0;
                if (!zero || !cents) {
                    cardinal_digits(b, whole, wn);
                    sb_str(b, " ");
                    sb_str(b, one ? VTTS_EN_CURRENCY[c].one : VTTS_EN_CURRENCY[c].many);
                    put_sb(d, b);
                    any = 1;
                }
                if (cents) {
                    if (any) cb_str(d, " ");
                    cardinal_u(b, (unsigned)cents);
                    sb_str(b, " ");
                    sb_str(b, cents == 1 ? VTTS_EN_CURRENCY[c].sub1 : VTTS_EN_CURRENCY[c].subn);
                    put_sb(d, b);
                }
                cb_str(d, " ");
            }
            i = end;
            continue;
        }
        cb_put(d, s[i++]);
    }
}

/* [AaPp]\.?[Mm]\.? followed by (?![\w]): the variants in backtracking order; returns the end or -1 */
static int ampm_end(const uint32_t *s, int n, int i, int (*ok)(const uint32_t *, int, int)) {
    if (i >= n || (lowc(s[i]) != 'a' && lowc(s[i]) != 'p')) return -1;
    for (int d1 = 1; d1 >= 0; d1--) {
        int j = i + 1;
        if (d1) { if (j < n && s[j] == '.') j++; else continue; }
        if (!(j < n && lowc(s[j]) == 'm')) continue;
        j++;
        for (int d2 = 1; d2 >= 0; d2--) {
            int e = j;
            if (d2) { if (e < n && s[e] == '.') e++; else continue; }
            if (ok(s, n, e)) return e;
        }
    }
    return -1;
}
static int not_w(const uint32_t *s, int n, int i) { return !W(s, n, i); }

/* \b(\d{1,2}):(\d{2})\s?([AaPp]\.?[Mm]\.?)?(?![\w]) */
static void p_time(const uint32_t *s, int n, cb_t *d, words_t *wt) {
    for (int i = 0; i < n;) {
        if (D(s, n, i) && BND(s, n, i)) {
            int hl = 0;
            for (int L = 2; L >= 1 && !hl; L--)
                if (D(s, n, i + L - 1) && (L == 1 || D(s, n, i)) && i + L < n && s[i + L] == ':' &&
                    D(s, n, i + L + 1) && D(s, n, i + L + 2) && (L == 1 || D(s, n, i + 1)))
                    hl = L;
            if (hl) {
                int m0 = i + hl + 1, after = m0 + 2, end = -1, as = -1, ae = -1;
                for (int sp = 1; sp >= 0 && end < 0; sp--) {
                    if (sp && !SP(s, n, after)) continue;
                    int e = ampm_end(s, n, after + sp, not_w);
                    if (e >= 0) { end = e; as = after + sp; ae = e; break; }
                    if (not_w(s, n, after + sp)) { end = after + sp; break; }
                }
                if (end >= 0) {
                    unsigned h = 0, mi = (s[m0] - '0') * 10 + (s[m0 + 1] - '0');
                    for (int k = i; k < i + hl; k++) h = h * 10 + (s[k] - '0');
                    sb_t *b = &wt->sb;
                    cardinal_u(b, h);
                    if (mi == 0 && as < 0) sb_str(b, " o'clock");
                    else if (mi == 0) {}
                    else if (mi < 10) { sb_str(b, " oh "); sb_str(b, VTTS_EN_ONES[mi]); }
                    else { sb_str(b, " "); cardinal_u(b, mi); }
                    if (as >= 0)
                        for (int k = as; k < ae; k++) if (s[k] != '.') { char t[3] = {' ', (char)lowc(s[k]), 0}; sb_str(b, t); }
                    cb_str(d, " "); put_sb(d, b); cb_str(d, " ");
                    i = end;
                    continue;
                }
            }
        }
        cb_put(d, s[i++]);
    }
}

/* \b(\d{1,2})/(\d{1,2})(?:/(\d{4}|\d{2}))?\b */
static void p_date(const uint32_t *s, int n, cb_t *d, words_t *wt) {
    for (int i = 0; i < n;) {
        int done = 0;
        if (D(s, n, i) && BND(s, n, i)) {
            for (int L1 = 2; L1 >= 1 && !done; L1--) {
                if (L1 == 2 && !D(s, n, i + 1)) continue;
                int sl = i + L1;
                if (!(sl < n && s[sl] == '/')) continue;
                for (int L2 = 2; L2 >= 1 && !done; L2--) {
                    int b0 = sl + 1;
                    if (!D(s, n, b0) || (L2 == 2 && !D(s, n, b0 + 1))) continue;
                    int e2 = b0 + L2, ye = -1, ys = -1;
                    /* optional year: \d{4} then \d{2}, each must be followed by \b */
                    if (e2 < n && s[e2] == '/') {
                        static const int YL[2] = {4, 2};
                        for (int y = 0; y < 2 && ye < 0; y++) {
                            int ok = 1;
                            for (int k = 0; k < YL[y]; k++) ok &= D(s, n, e2 + 1 + k);
                            if (ok && BND(s, n, e2 + 1 + YL[y])) { ys = e2 + 1; ye = e2 + 1 + YL[y]; }
                        }
                    }
                    int end = ye >= 0 ? ye : (BND(s, n, e2) ? e2 : -1);
                    if (end < 0) continue;
                    unsigned mo = 0, dd = 0;
                    for (int k = i; k < i + L1; k++) mo = mo * 10 + (s[k] - '0');
                    for (int k = b0; k < e2; k++) dd = dd * 10 + (s[k] - '0');
                    if (!(mo >= 1 && mo <= 12 && dd >= 1 && dd <= 31)) { cb_cps(d, s + i, end - i); }
                    else {
                        sb_t *b = &wt->sb;
                        char dg[4];
                        int dn = snprintf(dg, sizeof dg, "%u", dd);
                        sb_str(b, VTTS_EN_MONTHS[mo - 1]); sb_str(b, " ");
                        ordinal_digits(b, dg, dn);
                        if (ys >= 0) {
                            sb_str(b, " ");
                            unsigned y = 0;
                            for (int k = ys; k < ye; k++) y = y * 10 + (s[k] - '0');
                            if (ye - ys == 4) year_v(b, y); else cardinal_u(b, y);
                        }
                        cb_str(d, " "); put_sb(d, b); cb_str(d, " ");
                    }
                    i = end;
                    done = 1;
                }
            }
        }
        if (!done) cb_put(d, s[i++]);
    }
}

static int month_cap_at(const uint32_t *s, int n, int i) { /* Capitalized month name at i, then \b */
    for (int m = 0; m < 12; m++) {
        const char *w = VTTS_EN_MONTHS[m];
        int k = 0, ok = 1;
        for (; w[k]; k++) {
            uint32_t want = k == 0 ? (uint32_t)(w[k] - 32) : (uint32_t)(uint8_t)w[k];
            if (i + k >= n || s[i + k] != want) { ok = 0; break; }
        }
        if (ok && BND(s, n, i + k)) return m * 100 + k; /* month index and length */
    }
    return -1;
}

/* \b(\d{1,2})\s+(Month)\b -> " the <ordinal> of <month> " */
static void p_day_month(const uint32_t *s, int n, cb_t *d, words_t *wt) {
    for (int i = 0; i < n;) {
        if (D(s, n, i) && BND(s, n, i)) {
            int done = 0;
            for (int L = 2; L >= 1 && !done; L--) {
                if (L == 2 && !D(s, n, i + 1)) continue;
                int j = i + L;
                if (!SP(s, n, j)) continue;
                while (SP(s, n, j)) j++;
                int mm = month_cap_at(s, n, j);
                if (mm < 0) continue;
                char dg[3] = {(char)s[i], L == 2 ? (char)s[i + 1] : 0, 0};
                sb_t *b = &wt->sb;
                sb_str(b, "the ");
                ordinal_digits(b, dg, L);
                sb_str(b, " of ");
                sb_str(b, VTTS_EN_MONTHS[mm / 100]);
                cb_str(d, " "); put_sb(d, b); cb_str(d, " ");
                i = j + mm % 100;
                done = 1;
            }
            if (done) continue;
        }
        cb_put(d, s[i++]);
    }
}

/* \b(Month)\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b(?!\d) -> " <month> <ordinal> " */
static void p_month_day(const uint32_t *s, int n, cb_t *d, words_t *wt) {
    static const char *const SUF[] = {"st", "nd", "rd", "th"};
    for (int i = 0; i < n;) {
        int mm = BND(s, n, i) ? -1 : -1;
        if (BND(s, n, i)) {
            /* the month itself must end at \b only through the following pattern, so match
             * the name without requiring \b after it */
            for (int m = 0; m < 12 && mm < 0; m++) {
                const char *w = VTTS_EN_MONTHS[m];
                int k = 0, ok = 1;
                for (; w[k]; k++) {
                    uint32_t want = k == 0 ? (uint32_t)(w[k] - 32) : (uint32_t)(uint8_t)w[k];
                    if (i + k >= n || s[i + k] != want) { ok = 0; break; }
                }
                if (ok) mm = m * 100 + k;
            }
        }
        if (mm >= 0) {
            int e0 = i + mm % 100, done = 0;
            for (int dot = 1; dot >= 0 && !done; dot--) {
                int j = e0;
                if (dot) { if (j < n && s[j] == '.') j++; else continue; }
                if (!SP(s, n, j)) continue;
                while (SP(s, n, j)) j++;
                for (int L = 2; L >= 1 && !done; L--) {
                    if (!D(s, n, j) || (L == 2 && !D(s, n, j + 1))) continue;
                    int e = j + L;
                    for (int sf = 0; sf <= 4 && !done; sf++) { /* each suffix, then none */
                        int ee = e;
                        if (sf < 4) {
                            if (!(ee + 1 < n && s[ee] == (uint8_t)SUF[sf][0] && s[ee + 1] == (uint8_t)SUF[sf][1])) continue;
                            ee += 2;
                        }
                        if (!BND(s, n, ee) || D(s, n, ee)) continue;
                        char dg[3] = {(char)s[j], L == 2 ? (char)s[j + 1] : 0, 0};
                        sb_t *b = &wt->sb;
                        sb_str(b, VTTS_EN_MONTHS[mm / 100]);
                        sb_str(b, " ");
                        ordinal_digits(b, dg, L);
                        cb_str(d, " "); put_sb(d, b); cb_str(d, " ");
                        i = ee;
                        done = 1;
                    }
                }
            }
            if (done) continue;
        }
        cb_put(d, s[i++]);
    }
}

/* \b(\d{1,2})\s?([AaPp])\.?[Mm]\.?(?![\w]) -> " <cardinal> <a|p> m " */
static void p_hour_ampm(const uint32_t *s, int n, cb_t *d, words_t *wt) {
    for (int i = 0; i < n;) {
        if (D(s, n, i) && BND(s, n, i)) {
            int done = 0;
            for (int L = 2; L >= 1 && !done; L--) {
                if (L == 2 && !D(s, n, i + 1)) continue;
                int j = i + L;
                for (int sp = 1; sp >= 0 && !done; sp--) {
                    if (sp && !SP(s, n, j)) continue;
                    int e = ampm_end(s, n, j + sp, not_w);
                    if (e < 0) continue;
                    unsigned h = 0;
                    for (int k = i; k < i + L; k++) h = h * 10 + (s[k] - '0');
                    sb_t *b = &wt->sb;
                    cardinal_u(b, h);
                    char t[6] = {' ', (char)lowc(s[j + sp]), ' ', 'm', 0};
                    sb_str(b, t);
                    cb_str(d, " "); put_sb(d, b); cb_str(d, " ");
                    i = e;
                    done = 1;
                }
            }
            if (done) continue;
        }
        cb_put(d, s[i++]);
    }
}

/* (\d[\d,]*(?:\.\d+)?): returns the end of the greedy number starting at i (s[i] is a digit) */
static int num_end(const uint32_t *s, int n, int i, int *frac_dot) {
    int j = i + 1;
    while (j < n && (D(s, n, j) || s[j] == ',')) j++;
    *frac_dot = -1;
    if (j < n && s[j] == '.' && D(s, n, j + 1)) { *frac_dot = j; j++; while (D(s, n, j)) j++; }
    return j;
}

/* (\d[\d,]*(?:\.\d+)?)\s?% -> " <number> percent " */
static void p_percent(const uint32_t *s, int n, cb_t *d, words_t *wt) {
    for (int i = 0; i < n;) {
        if (D(s, n, i)) {
            int fd, e = num_end(s, n, i, &fd), end = -1;
            if (SP(s, n, e) && e + 1 < n && s[e + 1] == '%') end = e + 2;
            else if (e < n && s[e] == '%') end = e + 1;
            if (end >= 0) {
                sb_t *b = &wt->sb;
                number_s(b, s + i, e - i);
                sb_str(b, " percent");
                cb_str(d, " "); put_sb(d, b); cb_str(d, " ");
                i = end;
                continue;
            }
        }
        cb_put(d, s[i++]);
    }
}

static int unit_at(const uint32_t *s, int n, int i) { /* longest-first, case-insensitive, then (?![\w]) */
    for (int u = 0; u < VTTS_EN_N_UNITS; u++) {
        const char *k = VTTS_EN_UNITS[u][0];
        int j = i, ok = 1;
        const unsigned char *p = (const unsigned char *)k;
        while (*p) {
            uint32_t want;
            if (*p == 0xC2 && p[1] == 0xB0) { want = 0xB0; p += 2; } /* "°" in UTF-8 */
            else want = *p++;
            if (j >= n || lowc(s[j]) != want) { ok = 0; break; }
            j++;
        }
        if (ok && !W(s, n, j)) return u * 256 + (j - i);
    }
    return -1;
}

/* (\d[\d,]*(?:\.\d+)?)\s?(UNITS)(?![\w]) -> " <number> <unit name> " */
static void p_units(const uint32_t *s, int n, cb_t *d, words_t *wt) {
    for (int i = 0; i < n;) {
        if (D(s, n, i)) {
            int fd, e = num_end(s, n, i, &fd), u = -1, end = -1;
            for (int sp = 1; sp >= 0 && u < 0; sp--) {
                if (sp && !SP(s, n, e)) continue;
                u = unit_at(s, n, e + sp);
                if (u >= 0) end = e + sp + u % 256;
            }
            if (u >= 0) {
                const char *name = VTTS_EN_UNITS[u / 256][1];
                char val[64];
                int vn = 0;
                for (int k = i; k < e && vn < 63; k++) if (s[k] != ',') val[vn++] = (char)s[k];
                val[vn] = 0;
                sb_t *b = &wt->sb;
                number_s(b, s + i, e - i);
                sb_str(b, " ");
                const char *sp1 = strchr(name, ' ');
                if (strcmp(val, "1") == 0 || strcmp(val, "1.0") == 0) {
                    char first[32];
                    int fl = sp1 ? (int)(sp1 - name) : (int)strlen(name);
                    memcpy(first, name, (size_t)fl);
                    first[fl] = 0;
                    const char *one = first;
                    for (int k = 0; k < VTTS_EN_N_UNIT_ONE; k++)
                        if (strcmp(first, VTTS_EN_UNIT_ONE[k][0]) == 0) one = VTTS_EN_UNIT_ONE[k][1];
                    sb_str(b, one);
                    if (sp1) sb_str(b, sp1);
                } else sb_str(b, name);
                cb_str(d, " "); put_sb(d, b); cb_str(d, " ");
                i = end;
                continue;
            }
        }
        cb_put(d, s[i++]);
    }
}

/* \b(\d+)(st|nd|rd|th)\b -> " <ordinal> " */
static void p_ordinal(const uint32_t *s, int n, cb_t *d, words_t *wt) {
    static const char *const SUF[] = {"st", "nd", "rd", "th"};
    for (int i = 0; i < n;) {
        if (D(s, n, i) && BND(s, n, i)) {
            int j = i;
            while (D(s, n, j)) j++;
            int hit = -1;
            for (int k = 0; k < 4 && hit < 0; k++)
                if (j + 1 < n && s[j] == (uint8_t)SUF[k][0] && s[j + 1] == (uint8_t)SUF[k][1] && BND(s, n, j + 2)) hit = k;
            if (hit >= 0) {
                char dg[512];
                int dn = 0;
                for (int k = i; k < j && dn < 511; k++) dg[dn++] = (char)s[k];
                sb_t *b = &wt->sb;
                ordinal_digits(b, dg, dn);
                cb_str(d, " "); put_sb(d, b); cb_str(d, " ");
                i = j + 2;
                continue;
            }
        }
        cb_put(d, s[i++]);
    }
}

/* (?<![\w.,])(1[1-9]\d\d|20\d\d)(?![\d,.]\d|\w) -> " <year> " */
static void p_year(const uint32_t *s, int n, cb_t *d, words_t *wt) {
    for (int i = 0; i < n;) {
        int prev_ok = !(i > 0 && (W(s, n, i - 1) || s[i - 1] == '.' || s[i - 1] == ','));
        if (prev_ok && D(s, n, i) && D(s, n, i + 1) && D(s, n, i + 2) && D(s, n, i + 3) &&
            ((s[i] == '1' && s[i + 1] >= '1') || (s[i] == '2' && s[i + 1] == '0'))) {
            int e = i + 4;
            int bad = W(s, n, e) || ((D(s, n, e) || (e < n && (s[e] == ',' || s[e] == '.'))) && D(s, n, e + 1));
            if (!bad) {
                unsigned y = (s[i] - '0') * 1000 + (s[i + 1] - '0') * 100 + (s[i + 2] - '0') * 10 + (s[i + 3] - '0');
                sb_t *b = &wt->sb;
                year_v(b, y);
                cb_str(d, " "); put_sb(d, b); cb_str(d, " ");
                i = e;
                continue;
            }
        }
        cb_put(d, s[i++]);
    }
}

/* (?<![\w])-(\d) -> " minus \1" */
static void p_minus(const uint32_t *s, int n, cb_t *d) {
    for (int i = 0; i < n;) {
        if (s[i] == '-' && !W(s, n, i - 1) && D(s, n, i + 1)) { cb_str(d, " minus "); cb_put(d, s[i + 1]); i += 2; continue; }
        cb_put(d, s[i++]);
    }
}

/* (\d)([A-Za-z]) -> "\1 \2" */
static void p_digit_letter(const uint32_t *s, int n, cb_t *d) {
    for (int i = 0; i < n;) {
        if (D(s, n, i) && i + 1 < n && ((s[i + 1] | 32) >= 'a' && (s[i + 1] | 32) <= 'z')) {
            cb_put(d, s[i]); cb_put(d, ' '); cb_put(d, s[i + 1]); i += 2;
            continue;
        }
        cb_put(d, s[i++]);
    }
}

/* \d(?:[\d,]*\d)?(?:\.\d+)? -> " <number> " */
static void p_numbers(const uint32_t *s, int n, cb_t *d, words_t *wt) {
    for (int i = 0; i < n;) {
        if (D(s, n, i)) {
            int j = i + 1, last = i;
            while (j < n && (D(s, n, j) || s[j] == ',')) { if (D(s, n, j)) last = j; j++; }
            int e = last + 1;
            if (e < n && s[e] == '.' && D(s, n, e + 1)) { e++; while (D(s, n, e)) e++; }
            sb_t *b = &wt->sb;
            number_s(b, s + i, e - i);
            cb_str(d, " "); put_sb(d, b); cb_str(d, " ");
            i = e;
            continue;
        }
        cb_put(d, s[i++]);
    }
}

static void p_symbols(const uint32_t *s, int n, cb_t *d) {
    for (int i = 0; i < n; i++) {
        if (s[i] == '&') cb_str(d, " and ");
        else if (s[i] == '+') cb_str(d, " plus ");
        else if (s[i] == '@') cb_str(d, " at ");
        else cb_put(d, s[i]);
    }
}

static int is_az(uint32_t c) { return (c | 32) >= 'a' && (c | 32) <= 'z'; }
static int is_pmark(uint32_t c) { return c == ',' || c == '.' || c == '?' || c == '!' || c == ';' || c == ':'; }

typedef struct { char *p; int n, cap, err, last_punct, any; } out_t;
static void out_word(out_t *o, const char *w, int len) {
    if (o->n + len + 2 > o->cap) { o->err = 1; return; }
    if (o->any) o->p[o->n++] = ' ';
    memcpy(o->p + o->n, w, (size_t)len);
    o->n += len;
    o->p[o->n] = 0;
    o->any = 1;
}

/* _spell_caps: split CamelCase, spell all-caps runs of <= 5 letters (word has letters and ') */
static void spell_caps(out_t *o, const uint32_t *w, int n) {
    int st[64], ln[64], np = 0, i = 0, cover = 1;
    while (i < n && np < 64) { /* [A-Z]+(?![a-z]) | [A-Z]?[a-z']+ | [a-z']+ */
        int len = 0;
        if (w[i] >= 'A' && w[i] <= 'Z') {
            int L = 0;
            while (i + L < n && w[i + L] >= 'A' && w[i + L] <= 'Z') L++;
            if (!(i + L < n && w[i + L] >= 'a' && w[i + L] <= 'z')) len = L;
            else if (L >= 2) len = L - 1;
        }
        if (!len) {
            int j = i;
            if (w[j] >= 'A' && w[j] <= 'Z' && j + 1 < n && ((w[j + 1] >= 'a' && w[j + 1] <= 'z') || w[j + 1] == '\'')) j++;
            int k = j;
            while (k < n && ((w[k] >= 'a' && w[k] <= 'z') || w[k] == '\'')) k++;
            if (k > j) len = k - i;
        }
        if (!len) { cover = 0; i++; continue; }
        st[np] = i; ln[np] = len; np++;
        i += len;
    }
    char buf[256];
    if (!np || !cover || i < n) {
        int k = 0;
        for (int j = 0; j < n && k < 255; j++) buf[k++] = (char)lowc(w[j]);
        out_word(o, buf, k);
        return;
    }
    for (int p = 0; p < np; p++) {
        const uint32_t *q = w + st[p];
        int L = ln[p], upper = 1, cased = 0;
        for (int j = 0; j < L; j++) {
            if (q[j] >= 'a' && q[j] <= 'z') upper = 0;
            if (is_az(q[j])) cased = 1;
        }
        if (upper && cased && L <= 5 && np + L > 2) {
            for (int j = 0; j < L; j++) { char c = (char)lowc(q[j]); out_word(o, &c, 1); }
        } else {
            int k = 0;
            for (int j = 0; j < L && k < 255; j++) buf[k++] = (char)lowc(q[j]);
            out_word(o, buf, k);
        }
    }
}

/* findall([A-Za-z][A-Za-z']*(?:-[A-Za-z']+)*|[,.?!;:]) and the word/punctuation assembly */
static void p_tokens(const uint32_t *s, int n, out_t *o) {
    for (int i = 0; i < n;) {
        if (is_pmark(s[i])) {
            if (o->any && !o->last_punct) { char c = (char)s[i]; out_word(o, &c, 1); o->last_punct = 1; }
            i++;
            continue;
        }
        if (is_az(s[i])) {
            int j = i + 1;
            while (j < n && (is_az(s[j]) || s[j] == '\'')) j++;
            while (j + 1 < n && s[j] == '-' && (is_az(s[j + 1]) || s[j + 1] == '\'')) {
                j++;
                while (j < n && (is_az(s[j]) || s[j] == '\'')) j++;
            }
            for (int a = i; a < j;) { /* tok.split("-") */
                int b = a;
                while (b < j && s[b] != '-') b++;
                if (b > a) { spell_caps(o, s + a, b - a); o->last_punct = 0; }
                a = b + 1;
            }
            i = j;
            continue;
        }
        i++;
    }
}

int vtts_en_normalize(const uint32_t *cp, int n, uint32_t *a, uint32_t *b, int cap, char *out, int out_cap) {
    static words_t wt; /* number words; one normalization at a time */
    wt_init(&wt);
    cb_t x = {a, 0, cap, 0}, y = {b, 0, cap, 0};
    cb_put(&x, ' ');
    cb_cps(&x, cp, n);
    cb_put(&x, ' ');
#define PASS(call) do { y.n = 0; call; if (y.err || wt.sb.err) return -1; cb_t t_ = x; x = y; y = t_; y.n = 0; } while (0)
    PASS(p_code(x.p, x.n, &y));
    for (int k = 0; k < VTTS_EN_N_ABBREV; k++) PASS(p_abbrev(x.p, x.n, &y, VTTS_EN_ABBREV[k][0], VTTS_EN_ABBREV[k][1]));
    PASS(p_money(x.p, x.n, &y, &wt));
    PASS(p_time(x.p, x.n, &y, &wt));
    PASS(p_date(x.p, x.n, &y, &wt));
    PASS(p_day_month(x.p, x.n, &y, &wt));
    PASS(p_month_day(x.p, x.n, &y, &wt));
    PASS(p_hour_ampm(x.p, x.n, &y, &wt));
    PASS(p_percent(x.p, x.n, &y, &wt));
    PASS(p_units(x.p, x.n, &y, &wt));
    PASS(p_ordinal(x.p, x.n, &y, &wt));
    PASS(p_year(x.p, x.n, &y, &wt));
    PASS(p_minus(x.p, x.n, &y));
    PASS(p_digit_letter(x.p, x.n, &y));
    PASS(p_numbers(x.p, x.n, &y, &wt));
    PASS(p_symbols(x.p, x.n, &y));
#undef PASS
    out_t o = {out, 0, out_cap, 0, 0, 0};
    if (out_cap > 0) out[0] = 0;
    p_tokens(x.p, x.n, &o);
    return o.err ? -1 : o.n;
}
