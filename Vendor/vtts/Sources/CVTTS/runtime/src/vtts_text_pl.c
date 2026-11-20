/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_pl.c -- Polish front-end of the device (token set pl-en): the Latin-script tagging of
 * latin.py for "pl", the spelling, nasal-vowel, voicing and stress rules (mirrors
 * src/vtts/frontend/pl/g2p_pl.py) and normalization (mirrors src/vtts/frontend/pl/normalize_pl.py).
 * The regex passes run the Python patterns themselves (parse trees in vtts_text_pl_tables.h, matched
 * by vtts_re.c); the replacement functions follow the Python ones line by line. */
#include "vtts_langs.h"
#if VTTS_ENABLE_PL /* else an empty unit (vtts_langs.h) */

#include "vtts_text_pl.h"

#include <string.h>

#include "vtts_re.h"
#include "vtts_text_lt.h"
#include "vtts_text_pl_tables.h"

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

static int u8len(const char *s) {
    int m = 0, l;
    uint32_t c;
    while ((l = dec1(s, &c)) > 0) { m++; s += l; }
    return m;
}

static int eq_u8(const uint32_t *w, int n, const char *k) {
    int m = 0, l;
    uint32_t c;
    while ((l = dec1(k, &c)) > 0) {
        if (m >= n || w[m] != c) return 0;
        m++;
        k += l;
    }
    return m == n;
}

static int starts_u8(const uint32_t *w, int n, const char *k) {
    int m = 0, l;
    uint32_t c;
    while ((l = dec1(k, &c)) > 0) {
        if (m >= n || w[m] != c) return 0;
        m++;
        k += l;
    }
    return 1;
}

static int ends_u8(const uint32_t *w, int n, const char *k) {
    int kl = u8len(k);
    return kl <= n && eq_u8(w + n - kl, kl, k);
}

static int in_list(const char *const *list, int n, const uint32_t *w, int wn) {
    for (int i = 0; i < n; i++) if (eq_u8(w, wn, list[i])) return 1;
    return 0;
}

static int in_u8(uint32_t c, const char *set) {
    uint32_t x;
    int l;
    while ((l = dec1(set, &x)) > 0) { if (x == c) return 1; set += l; }
    return 0;
}

typedef vtts_re_buf rb_t;

static void put(rb_t *d, uint32_t c) { if (d->n < d->cap) d->p[d->n++] = c; else d->err = 1; }
static void puts8(rb_t *d, const char *s) {
    uint32_t c;
    int l;
    while ((l = dec1(s, &c)) > 0) { put(d, c); s += l; }
}
static void putn(rb_t *d, const uint32_t *s, int n) { for (int i = 0; i < n; i++) put(d, s[i]); }

typedef struct { rb_t *d; int any; } wl_t;
static void wadd(wl_t *w, const char *s) {
    if (w->any) put(w->d, ' ');
    puts8(w->d, s);
    w->any = 1;
}

static uint32_t lower1(uint32_t c) { return vtts_u_lower(c); }

/* ======================= tagging (latin.latin_word_lang for "pl") ======================= */

static int upper_az(uint32_t c) { return c >= 'A' && c <= 'Z'; }

static int plain_latin(const uint32_t *w, int n) {
    int alpha = 0;
    for (int i = 0; i < n; i++) {
        uint32_t c = w[i];
        int az = c < 0x80 && (c | 32) >= 'a' && (c | 32) <= 'z';
        if (!(az || c == '-' || c == '\'')) return 0;
        alpha |= az;
    }
    return n > 0 && alpha;
}

static int in_sorted(const char *const *list, int n, const char *w) {
    int lo = 0, hi = n - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2, c = strcmp(list[m], w);
        if (!c) return 1;
        if (c < 0) lo = m + 1; else hi = m - 1;
    }
    return 0;
}

/* g2p_pl.valid_spelling of a lower-case ASCII word */
static int valid_spelling(const char *w, int n) {
    int vowel = 0;
    for (int i = 0; i < n; i++) vowel |= strchr("aeiouy", w[i]) != NULL;
    if (!n || !vowel) return 0;
    for (int k = 0; k < VTTS_N_PL_FOREIGN; k++) if (strstr(w, VTTS_PL_FOREIGN[k])) return 0;
    for (int i = 0; i + 1 < n; i++) if (w[i] == w[i + 1] && !strchr("nzji", w[i])) return 0;
    if (n > 3) {
        if (n >= 3 && !strcmp(w + n - 3, "ing")) return 0;
        if (!strcmp(w + n - 2, "ly") || !strcmp(w + n - 2, "gy")) return 0;
    }
    return 1;
}

int vtts_pl_word_lang(const uint32_t *w, int n) {
    char low[128], part[128];
    if (n <= 0) return -1;
    for (int i = 0; i < n; i++) if (in_u8(w[i], VTTS_PL_OWN)) return 1;
    if (!plain_latin(w, n)) return -1;
    if (n < (int)sizeof low) {
        for (int i = 0; i < n; i++) low[i] = (char)(upper_az(w[i]) ? w[i] + 32 : w[i]);
        low[n] = 0;
        if (in_sorted(VTTS_PL_NATIVE, VTTS_N_PL_NATIVE, low) || in_sorted(VTTS_PL_TABLE_KEYS, VTTS_N_PL_TABLE_KEYS, low))
            return 1;
        if (vtts_lt_english_word(low)) return 0;
    }
    int all_caps = 1, all_valid = 1;
    for (int a = 0; a < n;) {
        int b = a;
        while (b < n && w[b] != '-' && w[b] != '\'') b++;
        if (b > a) {
            int len = b - a, caps = len >= 2 && len <= 5;
            for (int i = a; i + 1 < b; i++) if (w[i] >= 'a' && w[i] <= 'z' && upper_az(w[i + 1])) return 0;
            for (int k = a; k < b; k++) caps &= upper_az(w[k]);
            all_caps &= caps;
            if (all_valid) {
                if (len >= (int)sizeof part) all_valid = 0;
                else {
                    for (int k = 0; k < len; k++) part[k] = (char)(w[a + k] | 32);
                    part[len] = 0;
                    all_valid = valid_spelling(part, len);
                }
            }
        }
        a = b + 1;
    }
    if (n == 1 || all_caps) return 1;
    return all_valid ? 1 : 0;
}

/* ======================= g2p (g2p_pl.py) ======================= */

static int is_vowel_letter(uint32_t c) { return in_u8(c, "aeiouyąęó"); }

static const char *fold_cp(uint32_t c) {
    int lo = 0, hi = VTTS_PL_N_FOLD - 1;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        if (VTTS_PL_FOLD[mid].cp == c) return VTTS_PL_FOLD[mid].to;
        if (VTTS_PL_FOLD[mid].cp < c) lo = mid + 1; else hi = mid - 1;
    }
    return NULL;
}

/* fold(): lower(), then each character kept (Polish letters + -), folded (VTTS_PL_FOLD) or dropped */
static int fold(const uint32_t *w, int n, uint32_t *o, int cap) {
    int m = 0;
    for (int i = 0; i < n; i++) {
        uint32_t c = w[i] == 0x130 ? 'i' : lower1(w[i]); /* İ lowers to i + U+0307 (dropped) */
        if ((c >= 'a' && c <= 'z') || in_u8(c, "ąćęłńóśźż") || c == '+' || c == '-') {
            if (m < cap) o[m++] = c;
            continue;
        }
        const char *f = fold_cp(c);
        if (!f) continue;
        uint32_t x;
        int l;
        while ((l = dec1(f, &x)) > 0) { if (m < cap) o[m++] = x; f += l; }
    }
    return m;
}

static const char *map2(const char *const (*t)[2], int n, const char *k) {
    for (int i = 0; i < n; i++) if (strcmp(t[i][0], k) == 0) return t[i][1];
    return NULL;
}
static const char *map2_inv(const char *const (*t)[2], int n, const char *v) {
    for (int i = 0; i < n; i++) if (strcmp(t[i][1], v) == 0) return t[i][0];
    return NULL;
}

static void cp_key(uint32_t c, char *k) { /* one code point as UTF-8 */
    if (c < 0x80) { k[0] = (char)c; k[1] = 0; return; }
    k[0] = (char)(0xC0 | (c >> 6));
    k[1] = (char)(0x80 | (c & 0x3F));
    k[2] = 0;
}

typedef struct { char kind; char ph[5]; uint8_t mark; } seg_t;

static void seg(seg_t *S, int *ns, int cap, char kind, const char *ph, int mark) {
    if (*ns >= cap) return;
    S[*ns].kind = kind;
    strncpy(S[*ns].ph, ph, 4);
    S[*ns].ph[4] = 0;
    S[*ns].mark = (uint8_t)mark;
    (*ns)++;
}

static int soft_value(const char *ph) {
    for (int i = 0; i < VTTS_N_PL_SOFTENABLE; i++) if (!strcmp(VTTS_PL_SOFTENABLE[i][1], ph)) return 1;
    return 0;
}

static int segments(const uint32_t *w, int n, seg_t *S, int cap) {
    int ns = 0, mark = 0, i = 0;
    while (i < n) {
        uint32_t c = w[i];
        if (c == '+') { mark = 1; i++; continue; }
        char key[4];
        cp_key(c, key);
        const char *vq = map2(VTTS_PL_VOWEL_OF, VTTS_N_PL_VOWEL_OF, key);
        if (vq) {
            if (c == 'i' && ns && S[ns - 1].kind == 'C' && i + 1 < n && is_vowel_letter(w[i + 1])) {
                if (soft_value(S[ns - 1].ph)) { i++; continue; }
                seg(S, &ns, cap, 'C', "j", 0);
                i++;
                continue;
            }
            if (c == 'u' && ns && S[ns - 1].kind == 'V' && (!strcmp(S[ns - 1].ph, "a") || !strcmp(S[ns - 1].ph, "e")) &&
                !S[ns - 1].mark && (ns == 1 || S[ns - 2].kind == 'C')) {
                int nod = 0;
                for (int k = 0; k < VTTS_N_PL_NO_DIPHTHONG; k++) nod |= starts_u8(w, n, VTTS_PL_NO_DIPHTHONG[k]);
                int m_end = i + 2 == n && w[i + 1] == 'm';
                int sz = i + 2 < n && w[i + 1] == 's' && w[i + 2] == 'z';
                if (!nod && !m_end && !sz) { seg(S, &ns, cap, 'C', "w", 0); i++; continue; }
            }
            seg(S, &ns, cap, 'V', vq, mark);
            mark = 0;
            i++;
            continue;
        }
        int step = 1;
        const char *ph = NULL;
        uint32_t c2 = i + 1 < n ? w[i + 1] : 0;
        if (c == 's' && i + 3 < n && w[i + 1] == 'z' && w[i + 2] == 'c' && w[i + 3] == 'z') {
            seg(S, &ns, cap, 'C', "sh", 0);
            seg(S, &ns, cap, 'C', "ch", 0);
            i += 4;
            continue;
        }
        if (c == 'c' && c2 == 'h') { ph = "x"; step = 2; }
        else if (c == 'c' && c2 == 'z') { ph = "ch"; step = 2; }
        else if (c == 's' && c2 == 'z') { ph = "sh"; step = 2; }
        else if (c == 'r' && c2 == 'z') { ph = "rz"; step = 2; }
        else if (c == 'd' && c2 == 0x17C) { ph = "dzh"; step = 2; }
        else if (c == 'd' && c2 == 0x17A) { ph = "dz'"; step = 2; }
        else if (c == 'd' && c2 == 'z') { ph = "dz"; step = 2; }
        else if (c == 'x') {
            seg(S, &ns, cap, 'C', "k", 0);
            seg(S, &ns, cap, 'C', "s", 0);
            i++;
            continue;
        } else {
            ph = map2(VTTS_PL_SIMPLE, VTTS_N_PL_SIMPLE, key);
        }
        if (!ph) { i += step; continue; }
        uint32_t after = i + step < n ? w[i + step] : 0;
        if (after == 'i') {
            const char *base = !strcmp(ph, "ts") ? "c" : !strcmp(ph, "s") ? "s" : !strcmp(ph, "z") ? "z"
                             : !strcmp(ph, "n") ? "n" : !strcmp(ph, "dz") ? "dz" : NULL;
            if (base) ph = map2(VTTS_PL_SOFTENABLE, VTTS_N_PL_SOFTENABLE, base);
        }
        seg(S, &ns, cap, 'C', ph, 0);
        i += step;
    }
    return ns;
}

static int nasals(const seg_t *S, int ns, seg_t *O, int cap) {
    int no = 0;
    for (int k = 0; k < ns; k++) {
        const seg_t *s = &S[k];
        if (s->kind == 'V' && (!strcmp(s->ph, "on") || !strcmp(s->ph, "en"))) {
            const seg_t *nx = k + 1 < ns ? &S[k + 1] : NULL;
            const char *oral = s->ph[0] == 'o' ? "o" : "e";
            if (!nx) {
                if (!strcmp(s->ph, "en")) { seg(O, &no, cap, 'V', "e", s->mark); continue; }
            } else if (nx->kind == 'C' && map2(VTTS_PL_NASAL_BEFORE, VTTS_N_PL_NASAL_BEFORE, nx->ph)) {
                seg(O, &no, cap, 'V', oral, s->mark);
                seg(O, &no, cap, 'C', map2(VTTS_PL_NASAL_BEFORE, VTTS_N_PL_NASAL_BEFORE, nx->ph), 0);
                continue;
            } else if (nx->kind == 'C' && (!strcmp(nx->ph, "l") || !strcmp(nx->ph, "w"))) {
                seg(O, &no, cap, 'V', oral, s->mark);
                continue;
            }
        }
        if (no < cap) O[no++] = *s;
    }
    return no;
}

typedef struct { char s[6]; } ph_t;

static int is_voiced(const char *p) { return map2(VTTS_PL_VOICED, VTTS_N_PL_VOICED, p) != NULL; }
static int is_voiceless(const char *p) { return map2_inv(VTTS_PL_VOICED, VTTS_N_PL_VOICED, p) != NULL; }
static int voiceless_set(const char *p) { return is_voiceless(p) || !strcmp(p, "x"); }

static void voicing(ph_t *p, int n) {
    for (int k = 0; k < n; k++) {
        if ((!strcmp(p[k].s, "v") || !strcmp(p[k].s, "rz")) && k && voiceless_set(p[k - 1].s))
            strcpy(p[k].s, !strcmp(p[k].s, "v") ? "f" : "sh");
        else if (!strcmp(p[k].s, "rz"))
            strcpy(p[k].s, "zh");
    }
    int target = 0; /* 0 voiceless, 1 voiced, -1 none */
    for (int k = n - 1; k >= 0; k--) {
        if (!(is_voiced(p[k].s) || voiceless_set(p[k].s))) { target = -1; continue; }
        if (target == 1 && is_voiceless(p[k].s)) strcpy(p[k].s, map2_inv(VTTS_PL_VOICED, VTTS_N_PL_VOICED, p[k].s));
        else if (target == 0 && is_voiced(p[k].s)) strcpy(p[k].s, map2(VTTS_PL_VOICED, VTTS_N_PL_VOICED, p[k].s));
        target = is_voiced(p[k].s);
    }
}

static int stressed_vowel(const uint32_t *w, int n, const seg_t *S, int ns) {
    int vow[3 * VTTS_PL_MAXW], nv = 0;
    for (int k = 0; k < ns; k++) if (S[k].kind == 'V') vow[nv++] = k;
    for (int i = 0; i < nv; i++) if (S[vow[i]].mark) return vow[i];
    if (!nv || in_list(VTTS_PL_UNSTRESSED, VTTS_N_PL_UNSTRESSED, w, n)) return -1;
    int back = 2;
    if (ends_u8(w, n, "byśmy") || ends_u8(w, n, "byście")) back = 4;
    else if (ends_u8(w, n, "liśmy") || ends_u8(w, n, "łyśmy") || ends_u8(w, n, "liście") || ends_u8(w, n, "łyście") ||
             in_list(VTTS_PL_ANTEPENULT, VTTS_N_PL_ANTEPENULT, w, n))
        back = 3;
    if (nv < 2) return vow[0];
    int k = nv - back;
    return vow[k < 0 ? 0 : k];
}

static int part(const uint32_t *w0, int n0, ph_t *out, int cap) {
    uint32_t w[2 * VTTS_PL_MAXW + 8], plain[2 * VTTS_PL_MAXW + 8];
    int n = 0, pn = 0;
    const char *ov = NULL;
    for (int k = 0; k < VTTS_N_PL_OVERRIDES; k++) if (eq_u8(w0, n0, VTTS_PL_OVERRIDES[k][0])) ov = VTTS_PL_OVERRIDES[k][1];
    if (ov) {
        uint32_t c;
        int l;
        while ((l = dec1(ov, &c)) > 0 && n < 2 * VTTS_PL_MAXW) { w[n++] = c; ov += l; }
    } else {
        for (int i = 0; i < n0 && n < 2 * VTTS_PL_MAXW; i++) w[n++] = w0[i];
    }
    for (int i = 0; i < n; i++) if (w[i] != '+') plain[pn++] = w[i];
    seg_t S[3 * VTTS_PL_MAXW], O[3 * VTTS_PL_MAXW];
    int ns = segments(w, n, S, 3 * VTTS_PL_MAXW);
    int no = nasals(S, ns, O, 3 * VTTS_PL_MAXW);
    int st = stressed_vowel(plain, pn, O, no), m = 0;
    for (int k = 0; k < no && m < cap; k++) {
        strcpy(out[m].s, O[k].ph);
        if (k == st) strcat(out[m].s, "1");
        m++;
    }
    return m;
}

static int ph_id(const char *p) {
    for (int i = 0; i < VTTS_N_PL_PHONEMES; i++) if (!strcmp(VTTS_PL_PHONEMES[i], p)) return VTTS_PL_FIRST_ID + i;
    return -1;
}

static int phoneme_ids(const uint32_t *f, int fn, uint8_t *out, int cap) {
    ph_t ph[3 * VTTS_PL_MAXW];
    int a = 0, b = fn, np = 0;
    while (a < b && f[a] == '-') a++;
    while (b > a && f[b - 1] == '-') b--;
    for (int i = a; i < b;) {
        int j = i;
        while (j < b && f[j] != '-') j++;
        if (j > i) np += part(f + i, j - i, ph + np, 3 * VTTS_PL_MAXW - np);
        i = j + 1;
    }
    voicing(ph, np);
    int k = 0;
    for (int i = 0; i < np && k < cap; i++) {
        int id = ph_id(ph[i].s);
        if (id >= 0) out[k++] = (uint8_t)id;
    }
    return k;
}

int vtts_pl_word_ids(const uint32_t *w, int n, uint8_t *out, int cap) {
    uint32_t f[VTTS_PL_MAXW];
    int fn = fold(w, n, f, VTTS_PL_MAXW);
    int m = 0, vowel = 0;
    for (int i = 0; i < fn; i++) if (f[i] != '+') f[m++] = f[i]; /* .replace("+", "") for the check */
    for (int i = 0; i < m; i++) vowel |= is_vowel_letter(f[i]);
    if (m && !vowel && !(m == 1 && (f[0] == 'w' || f[0] == 'z'))) {
        int k = 0;
        for (int i = 0; i < m && k < cap; i++) {
            char key[4];
            cp_key(f[i], key);
            const char *name = map2(VTTS_PL_LETTERS, VTTS_N_PL_LETTERS, key);
            if (!name) continue;
            while (*name) {
                const char *e = strchr(name, ' ');
                int len = e ? (int)(e - name) : (int)strlen(name);
                uint32_t pw[32];
                int pn = 0, l;
                uint32_t c;
                for (const char *q = name; q < name + len && pn < 32; q += l) { l = dec1(q, &c); pw[pn++] = c; }
                k += vtts_pl_word_ids(pw, pn, out + k, cap - k);
                name += len;
                while (*name == ' ') name++;
            }
        }
        return k;
    }
    fn = fold(w, n, f, VTTS_PL_MAXW); /* phonemes() reads the folded word with its + marks */
    return phoneme_ids(f, fn, out, cap);
}

/* ======================= normalization (normalize_pl.py) ======================= */

static int udig(uint32_t c) { return vtts_u_digit(c); }
static int sp(uint32_t c) { return vtts_u_space(c); }
static int is_mark(uint32_t c) { return c == ',' || c == '.' || c == '?' || c == '!' || c == ';' || c == ':'; }

typedef struct { uint64_t v; int big; const uint32_t *d; int nd; } num_t;

static num_t num_of(const uint32_t *s, int n) {
    num_t x = {0, 0, s, 0};
    int i = 0;
    while (i < n && udig(s[i]) <= 0) i++;
    x.d = s + i;
    for (; i < n; i++) {
        int v = udig(s[i]);
        if (v < 0) continue;
        if (x.nd < 18) x.v = x.v * 10 + (uint64_t)v; else x.big = 1;
        x.nd++;
    }
    if (x.v >= 1000000000000000ULL) x.big = 1;
    return x;
}
static num_t num_v(uint64_t v) { num_t x = {v, v >= 1000000000000000ULL, NULL, 0}; return x; }
static int is_one(const num_t *x) { return !x->big && x->v == 1; }
static int last2(const num_t *x) {
    if (!x->big || !x->d) return (int)(x->v % 100);
    int a = 0, b = 0, cnt = 0;
    for (int i = 0; cnt < x->nd; i++) { int v = udig(x->d[i]); if (v < 0) continue; a = b; b = v; cnt++; }
    return a * 10 + b;
}

static void digits_words(wl_t *w, const uint32_t *s, int n) {
    for (int i = 0; i < n; i++) { int v = udig(s[i]); if (v >= 0) wadd(w, VTTS_PL_ONES[v]); }
}
static void digits_of_num(wl_t *w, const num_t *x) {
    if (!x->big) {
        char buf[24];
        int k = 0;
        uint64_t v = x->v;
        do { buf[k++] = (char)('0' + v % 10); v /= 10; } while (v);
        while (k) wadd(w, VTTS_PL_ONES[buf[--k] - '0']);
        return;
    }
    int cnt = 0;
    for (int i = 0; cnt < x->nd; i++) { int v = udig(x->d[i]); if (v < 0) continue; wadd(w, VTTS_PL_ONES[v]); cnt++; }
}

static const char *plural_s(const num_t *x, const char *one, const char *few, const char *many) {
    if (is_one(x)) return one;
    int r = last2(x), u = r % 10;
    if (u >= 2 && u <= 4 && !(r >= 12 && r <= 14)) return few;
    return many;
}

static void below_1000(wl_t *w, int n, char gender) {
    int h = n / 100, r = n % 100;
    if (h) wadd(w, VTTS_PL_HUNDREDS[h]);
    if (r >= 20) { wadd(w, VTTS_PL_TENS[r / 10]); r %= 10; }
    if (r) {
        const char *word = VTTS_PL_ONES[r];
        if (r == 1 && n == 1 && gender != 'm') word = gender == 'f' ? VTTS_PL_L_JEDNA : VTTS_PL_L_JEDNO;
        else if (r == 2 && gender == 'f') word = VTTS_PL_L_DWIE;
        wadd(w, word);
    }
}

static uint64_t pow10u(int e) { uint64_t v = 1; while (e--) v *= 10; return v; }

static void card_v(wl_t *w, uint64_t n, char gender);
static void cardinal(wl_t *w, const num_t *x, char gender) {
    if (!x->big && x->v == 0) { wadd(w, VTTS_PL_L_ZERO); return; }
    if (x->big) { digits_of_num(w, x); return; }
    card_v(w, x->v, gender);
}
static void card_v(wl_t *w, uint64_t n, char gender) {
    if (n == 0) { wadd(w, VTTS_PL_L_ZERO); return; }
    if (n >= 1000000000000000ULL) { num_t x = num_v(n); digits_of_num(w, &x); return; }
    for (int k = 0; k < VTTS_PL_N_SCALES; k++) {
        uint64_t value = pow10u(VTTS_PL_SCALES[k].exp), q = n / value;
        n %= value;
        if (q) {
            if (q > 1) card_v(w, q, 'm');
            num_t qq = num_v(q);
            wadd(w, plural_s(&qq, VTTS_PL_SCALES[k].one, VTTS_PL_SCALES[k].few, VTTS_PL_SCALES[k].many));
        }
    }
    below_1000(w, (int)n, gender);
}

static void cardinal_gen_v(wl_t *w, uint64_t n) {
    if (n == 0) { wadd(w, VTTS_PL_L_ZERA); return; }
    for (int k = 0; k < VTTS_PL_N_SCALES; k++) {
        uint64_t value = pow10u(VTTS_PL_SCALES[k].exp), q = n / value;
        n %= value;
        if (q) {
            if (q > 1) cardinal_gen_v(w, q);
            wadd(w, q == 1 ? VTTS_PL_SCALES[k].gen_one : VTTS_PL_SCALES[k].gen_many);
        }
    }
    int h = (int)(n / 100), r = (int)(n % 100);
    if (h) wadd(w, VTTS_PL_HUNDREDS_GEN[h]);
    if (r >= 20) { wadd(w, VTTS_PL_TENS_GEN[r / 10]); r %= 10; }
    if (r) wadd(w, VTTS_PL_ONES_GEN[r]);
}
static void cardinal_gen(wl_t *w, const num_t *x) {
    if (x->big) { digits_of_num(w, x); return; }
    cardinal_gen_v(w, x->v);
}

static int case_index(const char *c) {
    for (int i = 0; i < VTTS_N_PL_CASES; i++) if (!strcmp(VTTS_PL_CASES[i], c)) return i;
    return 0;
}
static int cls_index(const char *c) { return c[0] == 'k' ? 1 : c[0] == 'c' ? 2 : 0; }

static void ord_word(wl_t *w, const char *stem, const char *cls, int ci) {
    wadd(w, stem);
    puts8(w->d, VTTS_PL_ENDINGS[cls_index(cls)][ci]);
}

static void ordinal(wl_t *w, const num_t *x, int ci) {
    if (x->big || x->v == 0 || x->v >= 1000000000ULL) { cardinal(w, x, 'm'); return; }
    uint64_t n = x->v;
    int r100 = (int)(n % 100);
    if (r100) {
        if (n >= 100) card_v(w, n - (uint64_t)r100, 'm');
        if (r100 < 20) {
            ord_word(w, VTTS_PL_ORD_ONES[r100][0], VTTS_PL_ORD_ONES[r100][1], ci);
        } else {
            int t = r100 / 10, u = r100 % 10;
            ord_word(w, VTTS_PL_ORD_TENS[t], "h", ci);
            if (u) ord_word(w, VTTS_PL_ORD_ONES[u][0], VTTS_PL_ORD_ONES[u][1], ci);
        }
        return;
    }
    if (n % 1000) {
        if (n >= 1000) card_v(w, n - n % 1000, 'm');
        ord_word(w, VTTS_PL_ORD_HUNDREDS[(n % 1000) / 100], "h", ci);
        return;
    }
    uint64_t q = n / 1000;
    const char *prefix = NULL;
    for (int k = 0; k < VTTS_N_PL_THOUSAND_PREFIX; k++) {
        uint64_t v = 0;
        for (const char *p = VTTS_PL_THOUSAND_PREFIX[k][0]; *p; p++) v = v * 10 + (uint64_t)(*p - '0');
        if (v == q) prefix = VTTS_PL_THOUSAND_PREFIX[k][1];
    }
    if (!prefix) { card_v(w, n, 'm'); return; }
    wadd(w, prefix);
    puts8(w->d, VTTS_PL_L_TYSIECZN);
    puts8(w->d, VTTS_PL_ENDINGS[0][ci]);
}

typedef struct { num_t n; const uint32_t *frac; int fn; int has_frac; } pnum_t;

static int is_space_num(uint32_t c) { return c == ' ' || c == 0xA0 || c == 0x202F; }
static int clean_num(const uint32_t *s, int n, uint32_t *o) {
    int m = 0;
    for (int i = 0; i < n; i++) if (!is_space_num(s[i])) o[m++] = s[i];
    return m;
}
static int clean_ws(const uint32_t *s, int n, uint32_t *o) { /* re.sub(r"\s", "", s) */
    int m = 0;
    for (int i = 0; i < n; i++) if (!sp(s[i])) o[m++] = s[i];
    return m;
}

static pnum_t parse_number(const uint32_t *s, int n) {
    pnum_t r;
    memset(&r, 0, sizeof r);
    while (n > 0 && s[0] == '+') { s++; n--; }
    vtts_re_match m;
    int dot = vtts_re_match_at(&VTTS_PL_RE_THOUSANDS_DOT, s, n, 0, &m);
    if (dot || vtts_re_match_at(&VTTS_PL_RE_THOUSANDS_COMMA, s, n, 0, &m)) {
        uint32_t frac_mark = dot ? ',' : '.';
        int k = 0;
        while (k < n && s[k] != frac_mark) k++;
        r.n = num_of(s, k);
        if (k + 1 < n) { r.frac = s + k + 1; r.fn = n - k - 1; r.has_frac = 1; }
        return r;
    }
    for (int mk = 0; mk < 2; mk++) {
        uint32_t mark = mk ? '.' : ',';
        for (int k = 0; k < n; k++)
            if (s[k] == mark) { r.n = num_of(s, k); r.frac = s + k + 1; r.fn = n - k - 1; r.has_frac = 1; return r; }
    }
    r.n = num_of(s, n);
    return r;
}

static void number(wl_t *w, const uint32_t *s0, int n0, char gender) {
    uint32_t s[128] = {0}; /* GCC -Wmaybe-uninitialized on RISC-V -O2 */
    if (n0 > 128) n0 = 128;
    int n = clean_num(s0, n0, s), neg = n && s[0] == '-';
    const uint32_t *p = s;
    int pn = n;
    while (pn && *p == '-') { p++; pn--; }
    pnum_t x = parse_number(p, pn);
    if (neg) wadd(w, VTTS_PL_L_MINUS);
    if (!x.has_frac) { cardinal(w, &x.n, gender); return; }
    if (x.fn <= 3) {
        cardinal(w, &x.n, 'm');
        wadd(w, VTTS_PL_L_I);
        num_t k = num_of(x.frac, x.fn);
        cardinal(w, &k, 'f');
        const char *const *fr = VTTS_PL_FRACTION[x.fn];
        wadd(w, plural_s(&k, fr[0], fr[1], fr[2]));
        return;
    }
    cardinal(w, &x.n, 'm');
    wadd(w, VTTS_PL_L_PRZECINEK);
    digits_words(w, x.frac, x.fn);
}

static const char *gen_sg(const char *one) {
    for (int i = 0; i < VTTS_N_PL_GEN_SG; i++) if (!strcmp(VTTS_PL_GEN_SG[i][0], one)) return VTTS_PL_GEN_SG[i][1];
    return one;
}

/* count(s, unit): unit = {key, gender, one, few, many} */
static void count(wl_t *w, const uint32_t *s0, int n0, const char *const *unit) {
    uint32_t s[128];
    if (n0 > 128) n0 = 128;
    int n = clean_num(s0, n0, s);
    const uint32_t *p = s;
    int pn = n;
    while (pn && *p == '-') { p++; pn--; }
    pnum_t x = parse_number(p, pn);
    number(w, s, n, unit[1][0]);
    wadd(w, x.has_frac ? gen_sg(unit[2]) : plural_s(&x.n, unit[2], unit[3], unit[4]));
}

static int prev_word(const uint32_t *s, int start, uint32_t *o, int cap) { /* lower-cased */
    int j = start;
    while (j > 0 && sp(s[j - 1])) j--;
    if (j == start || j == 0) return -1;
    int i = j;
    while (i > 0 && !sp(s[i - 1])) i--;
    int m = 0;
    for (int k = i; k < j && m + 1 < cap; k++) {
        if (s[k] == 0x130) { o[m++] = 'i'; o[m++] = 0x307; } else o[m++] = lower1(s[k]);
    }
    return m;
}
static int lower_in(const char *const *list, int n, const uint32_t *w, int wn) { return wn >= 0 && in_list(list, n, w, wn); }

static int gen_count(const uint32_t *s, const vtts_re_match *m, const uint32_t *num, int nn) {
    uint32_t pw[64], c[128];
    int pl = prev_word(s, m->start, pw, 64);
    if (!lower_in(VTTS_PL_GEN_COUNT, VTTS_N_PL_GEN_COUNT, pw, pl)) return 0;
    int cn = clean_ws(num, nn > 128 ? 128 : nn, c);
    return !parse_number(c, cn).has_frac;
}

#define G(m, i) (m)->gs[i]
#define GL(m, i) ((m)->ge[i] - (m)->gs[i])
#define GP(s, m, i) ((s) + (m)->gs[i])

static int small(const uint32_t *s, int i, int len) { num_t x = num_of(s + i, len); return x.big ? 1 << 30 : (int)(x.v > 100000 ? 100000 : x.v); }

static int rest_blank(const uint32_t *s, int n, int from) {
    for (int i = from; i < n; i++) if (!sp(s[i])) return 0;
    return 1;
}

static void sub_phone(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    wl_t w = {d, 0};
    put(d, ' ');
    if (s[m->start] == '+') wadd(&w, VTTS_PL_L_PLUS);
    digits_words(&w, s + m->start, m->end - m->start);
    put(d, ' ');
}

static void date_out(rb_t *d, int dd, int mm, const uint32_t *y, int yl) {
    wl_t w = {d, 0};
    put(d, ' ');
    num_t x = num_v((uint64_t)dd);
    ordinal(&w, &x, case_index("nom_m"));
    wadd(&w, VTTS_PL_MONTHS[mm]);
    if (y) {
        num_t yy = num_of(y, yl);
        ordinal(&w, &yy, case_index("gen_m"));
        wadd(&w, VTTS_PL_L_ROKU);
    }
    put(d, ' ');
}

static void sub_date_iso(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    int dd = small(s, G(m, 3), GL(m, 3)), mm = small(s, G(m, 2), GL(m, 2));
    if (!(dd >= 1 && dd <= 31 && mm >= 1 && mm <= 12)) { putn(d, s + m->start, m->end - m->start); return; }
    date_out(d, dd, mm, GP(s, m, 1), GL(m, 1));
}

static void sub_date_dmy(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    int dd = small(s, G(m, 1), GL(m, 1)), mm = small(s, G(m, 3), GL(m, 3));
    if (!(dd >= 1 && dd <= 31 && mm >= 1 && mm <= 12)) { putn(d, s + m->start, m->end - m->start); return; }
    date_out(d, dd, mm, GP(s, m, 4), GL(m, 4));
}

static void sub_year(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)u;
    uint32_t pw[64];
    int pl = prev_word(s, m->start, pw, 64);
    const uint32_t *noun = GP(s, m, 2);
    int nl = GL(m, 2), end = nl && noun[nl - 1] == '.' && rest_blank(s, n, m->end);
    num_t y = num_of(GP(s, m, 1), GL(m, 1));
    wl_t w = {d, 0};
    put(d, ' ');
    const char *cs = NULL;
    if (lower_in(VTTS_PL_LOC_PREPOSITIONS, VTTS_N_PL_LOC_PREPOSITIONS, pw, pl)) cs = "loc_m";
    else if (lower_in(VTTS_PL_GEN_COUNT, VTTS_N_PL_GEN_COUNT, pw, pl) || eq_u8(noun, nl, "r.")) cs = "gen_m";
    if (cs) {
        ordinal(&w, &y, case_index(cs));
        wadd(&w, VTTS_PL_L_ROKU);
        if (end) puts8(d, " .");
        put(d, ' ');
        return;
    }
    cs = "nom_m";
    for (int k = 0; k < VTTS_N_PL_YEAR_NOUN; k++) if (eq_u8(noun, nl, VTTS_PL_YEAR_NOUN[k][0])) cs = VTTS_PL_YEAR_NOUN[k][1];
    ordinal(&w, &y, case_index(cs));
    put(d, ' ');
    putn(d, noun, nl);
    put(d, ' ');
}

static int roman_v(uint32_t c) { return c == 'I' ? 1 : c == 'V' ? 5 : c == 'X' ? 10 : c == 'L' ? 50 : c == 'C' ? 100 : 0; }
static void ord_roman(wl_t *w, const uint32_t *s, int n, int ci) {
    int64_t total = 0;
    for (int i = 0; i < n; i++) {
        int v = roman_v(s[i]);
        total += (i + 1 < n && roman_v(s[i + 1]) > v) ? -v : v;
    }
    if (total <= 0) {
        if (total == 0) { wadd(w, VTTS_PL_L_ZERO); return; }
        wadd(w, VTTS_PL_L_MINUS);
        card_v(w, (uint64_t)(-total), 'm');
        return;
    }
    num_t x = num_v((uint64_t)total);
    ordinal(w, &x, ci);
}

static void sub_century(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    uint32_t pw[64];
    int pl = prev_word(s, m->start, pw, 64);
    const uint32_t *noun = GP(s, m, 2);
    int nl = GL(m, 2);
    const char *cs = "nom_m";
    for (int k = 0; k < VTTS_N_PL_CENTURY_NOUN; k++) if (eq_u8(noun, nl, VTTS_PL_CENTURY_NOUN[k][0])) cs = VTTS_PL_CENTURY_NOUN[k][1];
    if (lower_in(VTTS_PL_LOC_PREPOSITIONS, VTTS_N_PL_LOC_PREPOSITIONS, pw, pl) && eq_u8(noun, nl, VTTS_PL_L_WIEKU)) cs = "loc_m";
    wl_t w = {d, 0};
    put(d, ' ');
    ord_roman(&w, GP(s, m, 1), GL(m, 1), case_index(cs));
    put(d, ' ');
    if (eq_u8(noun, nl, "w.")) puts8(d, VTTS_PL_L_WIEK); else putn(d, noun, nl);
    put(d, ' ');
}

static void sub_abbr(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    const char *const *row = u;
    size_t kl = strlen(row[0]);
    put(d, ' ');
    puts8(d, row[1]);
    put(d, ' ');
    if (row[0][kl - 1] == '.' && rest_blank(s, n, m->end)) put(d, '.');
}

static void sub_day_month(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    int dd = small(s, G(m, 1), GL(m, 1));
    if (!(dd >= 1 && dd <= 31)) { putn(d, s + m->start, m->end - m->start); return; }
    wl_t w = {d, 0};
    put(d, ' ');
    num_t x = num_v((uint64_t)dd);
    ordinal(&w, &x, case_index("nom_m"));
    put(d, ' ');
    putn(d, GP(s, m, 2), GL(m, 2));
    put(d, ' ');
}

static void sub_time(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    uint32_t pw[64];
    int pl = prev_word(s, m->start, pw, 64);
    int h = small(s, G(m, 1), GL(m, 1)), mi = small(s, G(m, 2), GL(m, 2));
    const char *cs = lower_in(VTTS_PL_TIME_OBLIQUE, VTTS_N_PL_TIME_OBLIQUE, pw, pl) ? "gen_f" : "nom_f";
    wl_t w = {d, 0};
    put(d, ' ');
    if (h) { num_t x = num_v((uint64_t)h); ordinal(&w, &x, case_index(cs)); }
    else wadd(&w, VTTS_PL_L_ZERO);
    if (mi) {
        if (mi < 10) wadd(&w, VTTS_PL_L_ZERO);
        card_v(&w, (uint64_t)mi, 'm');
    }
    if (G(m, 3) >= 0) {
        int sec = small(s, G(m, 3), GL(m, 3));
        if (sec) {
            wadd(&w, VTTS_PL_L_I);
            card_v(&w, (uint64_t)sec, 'f');
            num_t x = num_v((uint64_t)sec);
            wadd(&w, plural_s(&x, VTTS_PL_L_SEKUNDA, VTTS_PL_L_SEKUNDY, VTTS_PL_L_SEKUND));
        }
    }
    put(d, ' ');
}

static const char *const *find_forms(const char *const (*t)[5], int n, const uint32_t *k, int kl) {
    for (int i = 0; i < n; i++) if (eq_u8(k, kl, t[i][0])) return t[i];
    return NULL;
}

static void sub_scaled(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    int exp = 3;
    for (int k = 0; k < VTTS_PL_N_SCALE_ABBR; k++) if (eq_u8(GP(s, m, 2), GL(m, 2), VTTS_PL_SCALE_ABBR[k].key)) exp = VTTS_PL_SCALE_ABBR[k].exp;
    const char *forms[5] = {"", "m", "", "", ""};
    for (int k = 0; k < VTTS_PL_N_SCALES; k++)
        if (VTTS_PL_SCALES[k].exp == exp) {
            forms[2] = VTTS_PL_SCALES[k].one;
            forms[3] = VTTS_PL_SCALES[k].few;
            forms[4] = VTTS_PL_SCALES[k].many;
        }
    wl_t w = {d, 0};
    put(d, ' ');
    count(&w, GP(s, m, 1), GL(m, 1), forms);
    if (G(m, 3) >= 0) {
        const char *const *cur = find_forms(VTTS_PL_CURRENCY, VTTS_N_PL_CURRENCY, GP(s, m, 3), GL(m, 3));
        if (cur) wadd(&w, cur[4]);
    }
    put(d, ' ');
}

static void money(rb_t *d, const uint32_t *num, int nl, const uint32_t *cur, int cl) {
    const char *const *unit = find_forms(VTTS_PL_CURRENCY, VTTS_N_PL_CURRENCY, cur, cl);
    uint32_t s[128];
    if (nl > 128) nl = 128;
    int sn = clean_num(num, nl, s);
    pnum_t x = parse_number(s, sn);
    wl_t w = {d, 0};
    put(d, ' ');
    const char *const *sub = NULL;
    if (unit) for (int k = 0; k < VTTS_N_PL_SUBUNIT; k++) if (!strcmp(VTTS_PL_SUBUNIT[k][0], unit[2])) sub = VTTS_PL_SUBUNIT[k];
    if (unit && x.has_frac && x.fn == 2 && sub) {
        cardinal(&w, &x.n, unit[1][0]); /* count(str(n), unit) */
        wadd(&w, plural_s(&x.n, unit[2], unit[3], unit[4]));
        num_t k = num_of(x.frac, x.fn);
        if (k.v) {
            cardinal(&w, &k, sub[1][0]);
            wadd(&w, plural_s(&k, sub[2], sub[3], sub[4]));
        }
        put(d, ' ');
        return;
    }
    if (unit) count(&w, num, nl, unit);
    put(d, ' ');
}

static void sub_money_before(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    money(d, GP(s, m, 2), GL(m, 2), GP(s, m, 1), GL(m, 1));
}
static void sub_money_after(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    money(d, GP(s, m, 1), GL(m, 1), GP(s, m, 2), GL(m, 2));
}

static void sub_percent(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    wl_t w = {d, 0};
    put(d, ' ');
    if (GL(m, 1)) wadd(&w, VTTS_PL_L_MINUS);
    number(&w, GP(s, m, 2), GL(m, 2), 'm');
    wadd(&w, VTTS_PL_L_PROCENT);
    put(d, ' ');
}

static void sub_unit(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    const char *const *forms = find_forms(VTTS_PL_UNITS, VTTS_N_PL_UNITS, GP(s, m, 3), GL(m, 3));
    wl_t w = {d, 0};
    put(d, ' ');
    if (!GL(m, 1) && gen_count(s, m, GP(s, m, 2), GL(m, 2))) {
        uint32_t c[128];
        int cn = clean_ws(GP(s, m, 2), GL(m, 2) > 128 ? 128 : GL(m, 2), c);
        pnum_t x = parse_number(c, cn);
        cardinal_gen(&w, &x.n);
        wadd(&w, is_one(&x.n) ? gen_sg(forms[2]) : forms[4]);
        put(d, ' ');
        return;
    }
    if (GL(m, 1)) wadd(&w, VTTS_PL_L_MINUS);
    count(&w, GP(s, m, 2), GL(m, 2), forms);
    put(d, ' ');
}

static void sub_range(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    wl_t w = {d, 0};
    put(d, ' ');
    wadd(&w, VTTS_PL_L_OD);
    num_t a = num_of(GP(s, m, 1), GL(m, 1)), b = num_of(GP(s, m, 2), GL(m, 2));
    cardinal_gen(&w, &a);
    wadd(&w, VTTS_PL_L_DO);
    cardinal_gen(&w, &b);
    put(d, ' ');
}

static void sub_pause(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)s; (void)n; (void)m; (void)u;
    puts8(d, " , ");
}

static void sub_code(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    wl_t w = {d, 0};
    put(d, ' ');
    for (int i = m->start; i < m->end; i++) {
        uint32_t c = s[i];
        if (c >= '0' && c <= '9') { wadd(&w, VTTS_PL_ONES[c - '0']); continue; }
        char k[4];
        cp_key(lower1(c), k);
        const char *name = map2(VTTS_PL_LETTERS, VTTS_N_PL_LETTERS, k);
        if (name) wadd(&w, name);
    }
    put(d, ' ');
}

static void sub_number(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    const uint32_t *num = GP(s, m, 2);
    int nl = GL(m, 2), sign = GL(m, 1) > 0;
    uint32_t c[128];
    int cn = clean_num(num, nl > 128 ? 128 : nl, c);
    pnum_t x = parse_number(c, cn);
    wl_t w = {d, 0};
    put(d, ' ');
    if (!sign && gen_count(s, m, num, nl)) {
        cardinal_gen(&w, &x.n);
        put(d, ' ');
        return;
    }
    char gender = 'm';
    if (G(m, 3) >= 0 && !x.has_frac && is_one(&x.n)) {
        const uint32_t *nw = GP(s, m, 3);
        int nwl = GL(m, 3);
        uint32_t last = lower1(nw[nwl - 1]), prev = nwl >= 2 ? lower1(nw[nwl - 2]) : 0;
        if (last == 'a') gender = 'f';
        else if (last == 'o' || last == 'e' || last == 0x119 || (prev == 'u' && last == 'm' && !sp(nw[nwl - 2]))) gender = 'n';
    }
    uint32_t full[130];
    int fl = 0;
    if (sign) full[fl++] = '-';
    for (int i = 0; i < nl && fl < 129; i++) full[fl++] = num[i];
    number(&w, full, fl, gender);
    put(d, ' ');
}

static void sub_acronym(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    uint32_t low[8];
    int l = m->end - m->start;
    for (int i = 0; i < l && i < 8; i++) low[i] = lower1(s[m->start + i]);
    if (in_list(VTTS_PL_ACRONYM_WORDS, VTTS_N_PL_ACRONYM_WORDS, low, l) && !in_list(VTTS_PL_SPELLED, VTTS_N_PL_SPELLED, low, l)) {
        putn(d, low, l);
        return;
    }
    wl_t w = {d, 0};
    put(d, ' ');
    for (int i = 0; i < l; i++) {
        char k[4];
        cp_key(low[i], k);
        const char *name = map2(VTTS_PL_LETTERS, VTTS_N_PL_LETTERS, k);
        if (name) wadd(&w, name);
    }
    put(d, ' ');
}

/* finish(): WORD.findall(t.lower()), a mark after a mark dropped; then _join_clitics (w z + a word
 * that is not a mark -> w-word) */
static void p_finish(const uint32_t *s0, int n0, rb_t *d, uint32_t *t, int cap) {
    int n = 0;
    for (int i = 0; i < n0 && n + 1 < cap; i++) {
        if (s0[i] == 0x130) { t[n++] = 'i'; t[n++] = 0x307; continue; }
        t[n++] = lower1(s0[i]);
    }
    int pos = 0, kept = 0, last_mark = 0, pending = 0;
    vtts_re_match m;
    while (pos < n && vtts_re_search(&VTTS_PL_RE_WORD, t, n, pos, &m)) {
        const uint32_t *w = t + m.start;
        int l = m.end - m.start, mark = l == 1 && is_mark(w[0]);
        pos = m.end > m.start ? m.end : m.start + 1;
        if (mark && kept && last_mark) continue;
        kept++;
        last_mark = mark;
        if (pending) {
            pending = 0;
            if (!mark) { put(d, '-'); putn(d, w, l); continue; }
        }
        if (d->n) put(d, ' ');
        putn(d, w, l);
        pending = l == 1 && (w[0] == 'w' || w[0] == 'z');
    }
}

int vtts_pl_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, uint32_t *t, int cap,
                      const uint32_t **out) {
    rb_t x = {a, 0, cap, 0}, y = {b, 0, cap, 0};
    putn(&x, in, n); /* in may be t */
    if (x.err) return -1;
#define PASS(re, fn, u) do { y.n = 0; vtts_re_sub(re, x.p, x.n, &y, fn, u); if (y.err) return -1; rb_t t_ = x; x = y; y = t_; } while (0)
    PASS(&VTTS_PL_RE_PHONE, sub_phone, NULL);
    PASS(&VTTS_PL_RE_DATE_ISO, sub_date_iso, NULL);
    PASS(&VTTS_PL_RE_DATE_DMY, sub_date_dmy, NULL);
    PASS(&VTTS_PL_RE_YEAR, sub_year, NULL);
    PASS(&VTTS_PL_RE_CENTURY, sub_century, NULL);
    for (int k = 0; k < VTTS_N_PL_ABBREVIATIONS; k++) PASS(VTTS_PL_ABBR_RE[k], sub_abbr, (void *)VTTS_PL_ABBREVIATIONS[k]);
    {
        y.n = 0;
        for (int i = 0; i < x.n; i++) put(&y, in_u8(x.p[i], VTTS_PL_DROP) ? ' ' : x.p[i]);
        if (y.err) return -1;
        rb_t t_ = x; x = y; y = t_;
    }
    PASS(&VTTS_PL_RE_DAY_MONTH, sub_day_month, NULL);
    PASS(&VTTS_PL_RE_TIME, sub_time, NULL);
    PASS(&VTTS_PL_RE_SCALED, sub_scaled, NULL);
    PASS(&VTTS_PL_RE_MONEY_BEFORE, sub_money_before, NULL);
    PASS(&VTTS_PL_RE_MONEY_AFTER, sub_money_after, NULL);
    PASS(&VTTS_PL_RE_PERCENT, sub_percent, NULL);
    PASS(&VTTS_PL_RE_UNIT, sub_unit, NULL);
    PASS(&VTTS_PL_RE_RANGE, sub_range, NULL);
    PASS(&VTTS_PL_RE_PAUSE, sub_pause, NULL);
    PASS(&VTTS_PL_RE_PRODUCT_CODE, sub_code, NULL);
    PASS(&VTTS_PL_RE_NUMBER, sub_number, NULL);
#undef PASS
    for (int k = 0; k < VTTS_N_PL_SYMBOLS; k++) { /* SYMBOLS in order (str.replace) */
        uint32_t key;
        dec1(VTTS_PL_SYMBOLS[k][0], &key);
        y.n = 0;
        for (int i = 0; i < x.n; i++) {
            if (x.p[i] == key) puts8(&y, VTTS_PL_SYMBOLS[k][1]);
            else put(&y, x.p[i]);
        }
        if (y.err) return -1;
        rb_t t_ = x; x = y; y = t_;
    }
    for (int i = 0; i < x.n; i++) if (x.p[i] == '-') x.p[i] = ' ';
    y.n = 0;
    vtts_re_sub(&VTTS_PL_RE_ACRONYM, x.p, x.n, &y, sub_acronym, NULL);
    if (y.err) return -1;
    { rb_t t_ = x; x = y; y = t_; }
    y.n = 0;
    p_finish(x.p, x.n, &y, t, cap);
    if (y.err) return -1;
    *out = y.p;
    return y.n;
}

#endif /* VTTS_ENABLE_PL */
