/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_my.c -- Burmese front-end of the device (token set my-en): Zawgyi detection and
 * conversion, canonical mark order (mirrors src/vtts/frontend/my/zawgyi.py), syllables, onsets, rhymes
 * and tones (mirrors my/g2p_my.py), and the normalizer spec of my/normalize_my.py on the shared engine
 * (vtts_text_nsp.c). All tables are in the generated vtts_text_my_tables.h; no blob. */
#include "vtts_text_my.h"

#include "vtts_langs.h"

#if VTTS_ENABLE_MY

#include <string.h>

#include "vtts_text_my_tables.h"
#include "vtts_text_nsp.h"

enum {
    ASAT = 0x103A, VIRAMA = 0x1039, DOT = 0x1037, VISARGA = 0x1038, NGA = 0x1004, AA = 0x102C, TALL_AA = 0x102B,
    I_ = 0x102D, II = 0x102E, U_ = 0x102F, UU = 0x1030, E_ = 0x1031, AI = 0x1032, ANUSVARA = 0x1036,
    YA_PIN = 0x103B, YA_YIT = 0x103C, WA_HSWE = 0x103D, HA_HTO = 0x103E, WA = 0x101D
};

int vtts_my_is_burmese(uint32_t c) { return (c >= 0x1000 && c <= 0x103F) || (c >= 0x104C && c <= 0x104F); }

int vtts_my_has_burmese(const uint32_t *w, int n) { /* lang._has_burmese: U+1000..U+109F, not 1040..104B */
    for (int i = 0; i < n; i++) if (w[i] >= 0x1000 && w[i] <= 0x109F && !(w[i] >= 0x1040 && w[i] <= 0x104B)) return 1;
    return 0;
}

static unsigned FL(uint32_t c) { return c >= 0x1000 && c < 0x10A0 ? VTTS_MY_LETTERS[c - 0x1000].flags : 0; }
static int RANK(uint32_t c) { return c >= 0x1000 && c < 0x10A0 ? VTTS_MY_LETTERS[c - 0x1000].rank : 0; }
static int is_cons(uint32_t c) { return (FL(c) & VTTS_MY_CONS) != 0; }
static int is_indep(uint32_t c) { return (FL(c) & VTTS_MY_INDEP) != 0; }
static int is_mark(uint32_t c) { return RANK(c) || c == VIRAMA; }

static int dec1(const char *s, uint32_t *c) {
    const unsigned char *p = (const unsigned char *)s;
    if (!p[0]) return 0;
    if (p[0] < 0x80) { *c = p[0]; return 1; }
    int extra = (p[0] >> 5) == 6 ? 1 : (p[0] >> 4) == 14 ? 2 : 3;
    uint32_t v = p[0] & (0x3Fu >> extra);
    for (int k = 1; k <= extra; k++) v = (v << 6) | (p[k] & 0x3F);
    *c = v;
    return extra + 1;
}

/* UTF-8 key at s[i] (code points): its length, or 0 */
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

typedef vtts_nsp_buf buf_t;
#define PUT(d, c) vtts_nsp_put((d), (c))

/* ======================= canonical order and Zawgyi (zawgyi.py) ======================= */

typedef struct { int seg, rank, pos; uint32_t a, b; } mark_t;

/* canonical_order of s[0..n) appended to d */
static void canonical(const uint32_t *s, int n, buf_t *d) {
    mark_t mk[128];
    uint32_t body[300];
    for (int i = 0; i < n;) {
        uint32_t ch = s[i];
        if (i + 3 < n && s[i] == NGA && s[i + 1] == ASAT && s[i + 2] == VIRAMA && is_cons(s[i + 3])) {
            PUT(d, NGA); PUT(d, ASAT); PUT(d, VIRAMA);
            i += 3;
            continue;
        }
        if (!is_cons(ch) && !is_indep(ch)) { PUT(d, ch); i++; continue; }
        int j = i + 1, nm = 0, seg = 0;
        while (j < n) {
            uint32_t x = s[j];
            if (x == VIRAMA && j + 1 < n && is_cons(s[j + 1])) {
                if (nm < 128) { mk[nm].seg = seg; mk[nm].rank = 1; mk[nm].pos = nm; mk[nm].a = x; mk[nm].b = s[j + 1]; nm++; }
                j += 2;
            } else if (RANK(x)) {
                int dup = 0;
                for (int k = 0; k < nm; k++) if (!mk[k].b && mk[k].a == x) dup = 1;
                if (!dup && nm < 128) {
                    int back = x == DOT && nm && !mk[nm - 1].b && mk[nm - 1].a == ASAT;
                    mk[nm].seg = seg - back; mk[nm].rank = RANK(x); mk[nm].pos = nm; mk[nm].a = x; mk[nm].b = 0; nm++;
                    seg += x == ASAT;
                }
                j++;
            } else if (x == VIRAMA) {
                j++;
            } else {
                break;
            }
        }
        for (int a = 1; a < nm; a++) { /* insertion sort by (seg, rank, pos) */
            mark_t t = mk[a];
            int b = a - 1;
            while (b >= 0 && (mk[b].seg > t.seg || (mk[b].seg == t.seg && (mk[b].rank > t.rank ||
                                                    (mk[b].rank == t.rank && mk[b].pos > t.pos))))) {
                mk[b + 1] = mk[b];
                b--;
            }
            mk[b + 1] = t;
        }
        int nb = 0;
        for (int k = 0; k < nm; k++) {
            body[nb++] = mk[k].a;
            if (mk[k].b) body[nb++] = mk[k].b;
        }
        /* body.replace("္စျ", "္ဈ") */
        int w = 0;
        for (int r = 0; r < nb;) {
            if (r + 2 < nb && body[r] == VIRAMA && body[r + 1] == 0x1005 && body[r + 2] == YA_PIN) {
                body[w++] = VIRAMA; body[w++] = 0x1008; r += 3;
            } else {
                body[w++] = body[r++];
            }
        }
        nb = w;
        int skip = 0;
        if (ch == 0x1025 && nb && (body[0] == ASAT || body[0] == AA || body[0] == VIRAMA)) ch = 0x1009;
        else if (ch == 0x1025 && nb && body[0] == II) { ch = 0x1026; skip = 1; }
        else if (ch == 0x1005 && nb && body[0] == YA_PIN) { ch = 0x1008; skip = 1; }
        PUT(d, ch);
        for (int k = skip; k < nb; k++) PUT(d, body[k]);
        i = j;
    }
}

static int is_zawgyi(const uint32_t *t, int n) {
    int zg = 0, uni = 0;
    uint32_t prev = 0;
    for (int k = 0; k < n; k++) {
        uint32_t ch = t[k], nxt = k + 1 < n ? t[k + 1] : 0;
        if (ch == 0x1033 || ch == 0x1034 || (ch >= 0x105A && ch <= 0x1097)) zg++;
        else if ((ch == E_ || ch == YA_PIN) && nxt && is_cons(nxt) && !(prev && (is_cons(prev) || is_mark(prev)))) zg++;
        else if (ch == VIRAMA && !(nxt && is_cons(nxt))) zg++;
        else if (ch == HA_HTO || ch == 0x103F) uni++;
        else if (ch == VIRAMA && prev == ASAT && k >= 2 && t[k - 2] == NGA) uni++;
        else if (ch == 0x104E && nxt == NGA) uni++;
        prev = ch;
    }
    return zg > uni;
}

static const char *zg_map(uint32_t c) {
    int lo = 0, hi = VTTS_MY_N_ZG - 1;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        if (VTTS_MY_ZG[mid].cp == c) return VTTS_MY_ZG[mid].u;
        if (VTTS_MY_ZG[mid].cp < c) lo = mid + 1; else hi = mid - 1;
    }
    return NULL;
}

#define CL_CAP 300
typedef struct { uint32_t c[CL_CAP]; int n, on; } cl_buf;

static void cl_flush(cl_buf *cur, buf_t *d) {
    if (cur->on) canonical(cur->c, cur->n, d);
    cur->on = 0;
    cur->n = 0;
}
static void cl_add(cl_buf *cur, uint32_t c) { if (cur->n < CL_CAP) cur->c[cur->n++] = c; }

static void zawgyi_to_unicode(const uint32_t *t, int n, buf_t *d) {
    uint32_t pre[64];
    int npre = 0, kinzi = 0;
    cl_buf cur = {{0}, 0, 0};
    uint32_t marks[CL_CAP];
    int nmarks = 0;
    uint32_t base = 0;
#define FLUSH() do { if (cur.on) { cur.n = 0; if (kinzi) { cl_add(&cur, NGA); cl_add(&cur, ASAT); cl_add(&cur, VIRAMA); } \
        cl_add(&cur, base); for (int q_ = 0; q_ < nmarks; q_++) cl_add(&cur, marks[q_]); cl_flush(&cur, d); } } while (0)
    for (int k = 0; k < n; k++) {
        uint32_t ch = t[k], prv = k ? t[k - 1] : 0, nxt = k + 1 < n ? t[k + 1] : 0;
        if (ch == 0x1040 && !(prv >= 0x1040 && prv <= 0x1049) && !(nxt >= 0x1040 && nxt <= 0x1049)) ch = WA;
        else if (ch == 0x1044 && nxt == NGA) ch = 0x104E;
        else if (ch == ' ' && (nxt == DOT || nxt == 0x1094 || nxt == 0x1095) && cur.on) continue;
        uint32_t m[8];
        int nmv = 0, lt = 0, gt = 0;
        const char *u = zg_map(ch);
        if (ch == 0x104E && nxt != NGA) u = "\xe1\x81\x8e\xe1\x80\x84\xe1\x80\xba\xe1\x80\xb8"; /* ၎င်း */
        if (u) {
            uint32_t c;
            int l;
            if (*u == '<') { lt = 1; u++; } else if (*u == '>') { gt = 1; u++; }
            while ((l = dec1(u, &c)) > 0 && nmv < 8) { m[nmv++] = c; u += l; }
        } else {
            m[nmv++] = ch;
        }
        if (lt) {
            FLUSH();
            cur.on = 0;
            for (int q = 0; q < nmv && npre < 64; q++) pre[npre++] = m[q];
            continue;
        }
        if (gt) {
            if (cur.on) {
                kinzi = 1;
                for (int q = 0; q < nmv && nmarks < CL_CAP; q++) marks[nmarks++] = m[q];
            }
            continue;
        }
        if (is_cons(m[0]) || is_indep(m[0])) {
            FLUSH();
            cur.on = 1;
            kinzi = 0;
            base = m[0];
            nmarks = 0;
            for (int q = 0; q < npre && nmarks < CL_CAP; q++) marks[nmarks++] = pre[q];
            for (int q = 1; q < nmv && nmarks < CL_CAP; q++) marks[nmarks++] = m[q];
            npre = 0;
            continue;
        }
        int all = 1;
        for (int q = 0; q < nmv; q++) if (!is_mark(m[q]) && !is_cons(m[q])) all = 0;
        if (cur.on && all) {
            for (int q = 0; q < nmv && nmarks < CL_CAP; q++) marks[nmarks++] = m[q];
            continue;
        }
        FLUSH();
        cur.on = 0;
        for (int q = 0; q < npre; q++) PUT(d, pre[q]);
        npre = 0;
        for (int q = 0; q < nmv; q++) PUT(d, m[q]);
    }
    FLUSH();
    for (int q = 0; q < npre; q++) PUT(d, pre[q]);
#undef FLUSH
}

/* ======================= normalization (normalize_my) ======================= */

static int my_pre(const uint32_t *in, int n, buf_t *d, buf_t *tmp) {
    tmp->n = 0;
    for (int i = 0; i < n; i++) {
        uint32_t c = in[i];
        if (c == 0x200B || c == 0x200C || c == 0x200D || c == 0x2060 || c == 0xFEFF) continue;
        PUT(tmp, c);
    }
    if (tmp->err) return -1;
    if (is_zawgyi(tmp->p, tmp->n)) zawgyi_to_unicode(tmp->p, tmp->n, d);
    else canonical(tmp->p, tmp->n, d);
    if (d->err) return -1;
    uint32_t *o = d->p;
    int m = d->n;
    for (int k = 0; k < m; k++) if (o[k] >= 0x1090 && o[k] <= 0x1099) o[k] = '0' + (o[k] - 0x1090); /* Shan digits */
    /* _zero_wa */
    for (int k = 1; k < m; k++) {
        if (o[k] != WA) continue;
        uint32_t p = o[k - 1];
        if (!((p >= '0' && p <= '9') || (p >= 0x1040 && p <= 0x1049))) continue;
        if (k + 1 < m && o[k + 1] >= 0x102B && o[k + 1] <= 0x103E) continue;
        if (k + 2 < m && o[k + 1] >= 0x1000 && o[k + 1] <= 0x1021 && o[k + 2] == ASAT) continue;
        o[k] = 0x1040;
    }
    return 0;
}

static int my_letter(uint32_t c) { return (FL(c) & VTTS_MY_LETTER) != 0; }
static int my_word(uint32_t c) {
    if (c >= 0x1000 && c < 0x10A0) return (VTTS_MY_LETTERS[c - 0x1000].flags & VTTS_MY_WORD) != 0;
    return -1;
}

static void my_below_million(buf_t *d, int v) {
    static const int PL[5] = {100000, 10000, 1000, 100, 10};
    for (int k = 0; k < 5; k++) {
        int dg = v / PL[k];
        v %= PL[k];
        if (dg) {
            vtts_nsp_put_utf8(d, VTTS_MY_DIGITS[dg]);
            vtts_nsp_put_utf8(d, v ? VTTS_MY_CREAKY[k + 1] : VTTS_MY_PLACES[k + 1]);
        }
    }
    if (v) vtts_nsp_put_utf8(d, VTTS_MY_DIGITS[v]);
}

static void my_date(const vtts_nsp_spec *sp, buf_t *d, int day, int month, const uint32_t *y, int ny) {
    if (ny == 4) vtts_nsp_cardinal_u(sp, d, y, ny);
    else vtts_nsp_digits(sp, d, y, ny);
    vtts_nsp_put_utf8(d, "ခုနှစ် ");
    vtts_nsp_put_utf8(d, VTTS_MY_MONTHS[month]);
    vtts_nsp_put_utf8(d, "လ ");
    vtts_nsp_cardinal_i(sp, d, day);
    vtts_nsp_put_utf8(d, "ရက်");
}

static void my_time(const vtts_nsp_spec *sp, buf_t *d, int h, int m, int s) {
    vtts_nsp_cardinal_i(sp, d, h);
    vtts_nsp_put_utf8(d, "နာရီ");
    if (m) { vtts_nsp_cardinal_i(sp, d, m); vtts_nsp_put_utf8(d, "မိနစ်"); }
    if (s) { vtts_nsp_cardinal_i(sp, d, s); vtts_nsp_put_utf8(d, "စက္ကန့်"); }
}

static const vtts_nsp_spec MY_SPEC = {
    my_letter, my_word, 0x1040, my_pre, my_below_million, VTTS_MY_MILLION, VTTS_MY_DIGITS,
    VTTS_MY_POINT, VTTS_MY_MINUS, VTTS_MY_TO, VTTS_MY_PERCENT,
    VTTS_MY_CURRENCY, VTTS_MY_N_CURRENCY, VTTS_MY_UNITS, VTTS_MY_N_UNITS, NULL, 0,
    VTTS_MY_PUNCT, VTTS_MY_N_PUNCT, VTTS_MY_SYMBOLS, my_date, my_time, 0, 0, NULL, 0,
};

int vtts_my_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, uint32_t *ea,
                      uint32_t *eb, int ecap, char *eout, int eout_cap, const uint32_t **out) {
    return vtts_nsp_normalize(&MY_SPEC, in, n, a, b, cap, ea, eb, ecap, eout, eout_cap, out);
}

/* ======================= syllables and readings (g2p_my.py) ======================= */

/* replace every non-overlapping occurrence of key by val (str.replace) from s into d */
static int replace(const uint32_t *s, int n, const char *key, const char *val, uint32_t *d, int cap) {
    int m = 0;
    for (int i = 0; i < n;) {
        int l = key_at(s, n, i, key);
        if (l) {
            const char *v = val;
            uint32_t c;
            int lv;
            while ((lv = dec1(v, &c)) > 0) { if (m < cap) d[m++] = c; v += lv; }
            i += l;
            continue;
        }
        if (m < cap) d[m++] = s[i];
        i++;
    }
    return m;
}

/* prepare(): respellings, independent vowels, ါ, ဿ, kinzi, virama, a doubled asat */
static int prepare(uint32_t *w, int n, uint32_t *t, int cap) {
    for (int k = 0; k < VTTS_MY_N_RESPELL; k++) {
        n = replace(w, n, VTTS_MY_RESPELL[k][0], VTTS_MY_RESPELL[k][1], t, cap);
        memcpy(w, t, (size_t)n * sizeof *w);
    }
    int m = 0;
    for (int i = 0; i < n; i++) {
        const char *rep = NULL;
        uint32_t c;
        for (int k = 0; k < VTTS_MY_N_INDEP_VOWELS && !rep; k++) if (dec1(VTTS_MY_INDEP_VOWELS[k][0], &c) && c == w[i]) rep = VTTS_MY_INDEP_VOWELS[k][1];
        if (rep) {
            int l;
            while ((l = dec1(rep, &c)) > 0) { if (m < cap) t[m++] = c; rep += l; }
        } else if (w[i] == TALL_AA) {
            if (m < cap) t[m++] = AA;
        } else if (w[i] == 0x103F) { /* ဿ = သ်သ */
            if (m + 3 <= cap) { t[m++] = 0x101E; t[m++] = ASAT; t[m++] = 0x101E; }
        } else if (m < cap) {
            t[m++] = w[i];
        }
    }
    n = replace(t, m, "\xe1\x80\x84\xe1\x80\xba\xe1\x80\xb9", "\xe1\x80\x84\xe1\x80\xba", w, cap); /* င်္ -> င် */
    for (int i = 0; i < n; i++) if (w[i] == VIRAMA) w[i] = ASAT;
    return replace(w, n, "\xe1\x80\xba\xe1\x80\xba", "\xe1\x80\xba", t, cap); /* ်် -> ် */
}

static int onset_letter(uint32_t c) { return (FL(c) & VTTS_MY_ONSET) != 0; }

static int is_final(const uint32_t *w, int n, int j) {
    if (j >= n || !onset_letter(w[j])) return 0;
    int k = j + 1;
    if (k < n && w[k] == DOT) k++;
    return k < n && w[k] == ASAT;
}

#define TXT 16 /* the spelling of a syllable, for the exception tables (longer: no key matches) */
typedef struct {
    uint32_t base, final;
    uint32_t medials[8], vowel[12], txt[TXT];
    int nmed, nvowel, ntxt, dot, visarga, asat, special; /* special: index + 1 */
} syl_t;

static void txt_add(syl_t *s, const uint32_t *w, int a, int b) {
    for (int k = a; k < b; k++) { if (s->ntxt < TXT) s->txt[s->ntxt] = w[k]; s->ntxt++; }
}

static int has(const uint32_t *a, int n, uint32_t c) {
    for (int k = 0; k < n; k++) if (a[k] == c) return 1;
    return 0;
}

/* vowel signs without ံ equal to the UTF-8 literal v */
static int veq(const syl_t *s, const char *v) {
    uint32_t c;
    int l, k = 0;
    for (int q = 0; q < s->nvowel; q++) {
        if (s->vowel[q] == ANUSVARA) continue;
        if ((l = dec1(v, &c)) <= 0 || c != s->vowel[q]) return 0;
        v += l;
        k++;
    }
    (void)k;
    return *v == 0;
}

static int in_set(uint32_t c, const char *set) {
    uint32_t x;
    int l;
    while ((l = dec1(set, &x)) > 0) { if (x == c) return 1; set += l; }
    return 0;
}

static uint8_t tone(uint8_t def, const syl_t *s) { return s->dot ? VTTS_MY_T3 : s->visarga ? VTTS_MY_T2 : def; }

/* rhyme(): ids of vowel [final] tone; *takes_w when the rhyme takes ွ; 0 ids: no vowel sign */
static int rhyme(const syl_t *s, uint8_t *o, int *takes_w) {
    const uint32_t f = s->final;
    const int nasal = has(s->vowel, s->nvowel, ANUSVARA), w = has(s->medials, s->nmed, WA_HSWE);
    const int v0 = veq(s, ""), va = veq(s, "ာ");
    *takes_w = 0;
#define R3(a, b, c) do { o[0] = (a); o[1] = (b); o[2] = (c); return 3; } while (0)
#define R2(a, b) do { o[0] = (a); o[1] = (b); return 2; } while (0)
    if (f) {
        if (v0 || va) {
            if (in_set(f, "ကဂ") && v0) R3(VTTS_MY_V_E, VTTS_MY_F_Q, VTTS_MY_T4);
            if (in_set(f, "ငဉ")) R3(VTTS_MY_V_I, VTTS_MY_F_N, tone(VTTS_MY_T1, s));
            if (f == 0x1005) R3(VTTS_MY_V_I, VTTS_MY_F_Q, VTTS_MY_T4);
            if (f == 0x101A) R2(VTTS_MY_V_E, tone(VTTS_MY_T1, s));
            if (f == 0x100A) R2(VTTS_MY_V_i, tone(VTTS_MY_T1, s));
            if (in_set(f, "ဏနမ")) {
                if (w && v0 && f != 0x1019) { *takes_w = 1; R3(VTTS_MY_V_U, VTTS_MY_F_N, tone(VTTS_MY_T1, s)); }
                R3(VTTS_MY_V_a, VTTS_MY_F_N, tone(VTTS_MY_T1, s));
            }
            if (in_set(f, "ဋဌတထဒပဗဘဝသ")) {
                if (w && v0 && in_set(f, "ဋတ")) { *takes_w = 1; R3(VTTS_MY_V_U, VTTS_MY_F_Q, VTTS_MY_T4); }
                R3(VTTS_MY_V_a, VTTS_MY_F_Q, VTTS_MY_T4);
            }
            R2(VTTS_MY_V_a, tone(VTTS_MY_T1, s));
        }
        if (veq(s, "ိ")) {
            if (in_set(f, "ကဂစဋတဒပသ")) R3(VTTS_MY_V_ei, VTTS_MY_F_Q, VTTS_MY_T4);
            if (in_set(f, "ငဏနမ")) R3(VTTS_MY_V_ei, VTTS_MY_F_N, tone(VTTS_MY_T1, s));
            R2(VTTS_MY_V_i, tone(VTTS_MY_T3, s));
        }
        if (veq(s, "ု")) {
            if (in_set(f, "ကဂစဋတဒပသ")) R3(VTTS_MY_V_ou, VTTS_MY_F_Q, VTTS_MY_T4);
            if (in_set(f, "ဉဏနမ")) R3(VTTS_MY_V_ou, VTTS_MY_F_N, tone(VTTS_MY_T1, s));
            R2(VTTS_MY_V_u, tone(VTTS_MY_T3, s));
        }
        if (veq(s, "ို")) {
            if (in_set(f, "ကဋတ")) R3(VTTS_MY_V_ai, VTTS_MY_F_Q, VTTS_MY_T4);
            if (in_set(f, "ငဏ")) R3(VTTS_MY_V_ai, VTTS_MY_F_N, tone(VTTS_MY_T1, s));
            R2(VTTS_MY_V_o, tone(VTTS_MY_T1, s));
        }
        if (veq(s, "ေ")) {
            if (in_set(f, "တသ")) R3(VTTS_MY_V_I, VTTS_MY_F_Q, VTTS_MY_T4);
            if (f == 0x100A) R2(VTTS_MY_V_i, tone(VTTS_MY_T1, s));
        }
        if (veq(s, "ော")) {
            if (f == 0x1000) R3(VTTS_MY_V_au, VTTS_MY_F_Q, VTTS_MY_T4);
            if (in_set(f, "ငဏ")) R3(VTTS_MY_V_au, VTTS_MY_F_N, tone(VTTS_MY_T1, s));
        }
    }
    if (nasal) {
        if (veq(s, "ိ")) R3(VTTS_MY_V_ei, VTTS_MY_F_N, tone(VTTS_MY_T1, s));
        if (veq(s, "ု")) R3(VTTS_MY_V_ou, VTTS_MY_F_N, tone(VTTS_MY_T1, s));
        if (w && v0) { *takes_w = 1; R3(VTTS_MY_V_U, VTTS_MY_F_N, tone(VTTS_MY_T1, s)); }
        R3(VTTS_MY_V_a, VTTS_MY_F_N, tone(VTTS_MY_T1, s));
    }
    static const struct { const char *v; uint8_t vowel, tone; } OPEN[] = {
        {"ာ", VTTS_MY_V_a, VTTS_MY_T1}, {"ိ", VTTS_MY_V_i, VTTS_MY_T3}, {"ီ", VTTS_MY_V_i, VTTS_MY_T1},
        {"ု", VTTS_MY_V_u, VTTS_MY_T3}, {"ူ", VTTS_MY_V_u, VTTS_MY_T1}, {"ေ", VTTS_MY_V_e, VTTS_MY_T1},
        {"ဲ", VTTS_MY_V_E, VTTS_MY_T2}, {"ော", VTTS_MY_V_O, VTTS_MY_T2}, {"ို", VTTS_MY_V_o, VTTS_MY_T1},
        {"ိူ", VTTS_MY_V_o, VTTS_MY_T1}, {"ီု", VTTS_MY_V_o, VTTS_MY_T1}};
    for (unsigned k = 0; k < sizeof OPEN / sizeof OPEN[0]; k++)
        if (veq(s, OPEN[k].v)) {
            uint8_t t = OPEN[k].tone;
            if (k == 7 && s->asat) t = VTTS_MY_T1; /* ော် */
            R2(OPEN[k].vowel, tone(t, s));
        }
    return 0;
#undef R3
#undef R2
}

static int onset(const syl_t *s, int takes_w, uint8_t *o) {
    const int ha = has(s->medials, s->nmed, HA_HTO);
    int y = has(s->medials, s->nmed, YA_PIN), r = has(s->medials, s->nmed, YA_YIT);
    const int w = has(s->medials, s->nmed, WA_HSWE);
    uint8_t ini;
    const vtts_my_letter *L = &VTTS_MY_LETTERS[s->base - 0x1000];
    if (ha) {
        if (s->base == NGA && r) { ini = VTTS_MY_I_HNY; r = 0; }
        else if ((s->base == 0x101C || s->base == 0x101E) && y) { ini = VTTS_MY_I_S; y = 0; }
        else ini = L->ha;
    } else if (s->base == NGA && r) {
        ini = VTTS_MY_I_NY;
        r = 0;
    } else {
        ini = L->onset;
    }
    int n = 0;
    o[n++] = ini;
    if (y || r) o[n++] = VTTS_MY_G_Y;
    if (w && !takes_w) o[n++] = VTTS_MY_G_W;
    return n;
}

static int text_eq(const syl_t *s, const char *k) {
    if (s->ntxt > TXT) return 0;
    int l = key_at(s->txt, s->ntxt, 0, k);
    return l && l == s->ntxt;
}

static int particle(const syl_t *s) {
    for (int k = 0; k < VTTS_MY_N_PARTICLES; k++) if (text_eq(s, VTTS_MY_PARTICLES[k])) return 1;
    return 0;
}

typedef struct { vtts_my_syl_cb cb; void *user; int count; } my_ctx_t;

static void emit_ids(my_ctx_t *c, const uint8_t *ids, int n) {
    if (n <= 0) return;
    c->cb(c->user, ids, n);
    c->count++;
}

/* syllable_phones -> ids, then emitted per syllable (special words may have several) */
static void emit_syl(my_ctx_t *c, const syl_t *s, int last, int after_full) {
    uint8_t o[24];
    const char *ids = NULL;
    if (s->special) ids = VTTS_MY_SPECIAL[s->special - 1].ids;
    for (int k = 0; k < VTTS_MY_N_SYLLABLES && !ids; k++) if (text_eq(s, VTTS_MY_SYLLABLES[k].key)) ids = VTTS_MY_SYLLABLES[k].ids;
    if (ids) {
        int n = 0;
        for (const char *p = ids;; p++) {
            if (!*p || (uint8_t)*p == 0xFF) {
                emit_ids(c, o, n);
                n = 0;
                if (!*p) break;
                continue;
            }
            if (n < (int)sizeof o) o[n++] = (uint8_t)*p;
        }
        return;
    }
    int n = 0;
    if (s->base == WA && ((s->nvowel == 1 && s->vowel[0] == ANUSVARA) || (!s->nvowel && s->final && in_set(s->final, "ဋတနဏ")))) {
        o[n++] = VTTS_MY_I_W;
        o[n++] = VTTS_MY_V_U;
        if (s->final && in_set(s->final, "ဋတ")) { o[n++] = VTTS_MY_F_Q; o[n++] = VTTS_MY_T4; }
        else { o[n++] = VTTS_MY_F_N; o[n++] = tone(VTTS_MY_T1, s); }
        emit_ids(c, o, n);
        return;
    }
    uint8_t rh[4];
    int takes_w, nr = rhyme(s, rh, &takes_w);
    if (!nr) {
        if (s->dot || s->visarga || last || (particle(s) && after_full)) { rh[0] = VTTS_MY_V_a; rh[1] = tone(VTTS_MY_T3, s); nr = 2; }
        else { rh[0] = VTTS_MY_V_SCHWA; nr = 1; }
    }
    n = onset(s, takes_w, o);
    for (int k = 0; k < nr; k++) o[n++] = rh[k];
    emit_ids(c, o, n);
}

static int full(const syl_t *s) { return s->nvowel || s->final || s->special; }

/* syllables(): streamed with one syllable of delay (a final may still close the last one) */
static void read_run(my_ctx_t *c, const uint32_t *w, int n) {
    syl_t prev, cur;
    int have = 0, prev_full = 0, k_index = 0;
    for (int i = 0; i < n;) {
        int sp = -1, spl = 0;
        for (int k = 0; k < VTTS_MY_N_SPECIAL && sp < 0; k++) {
            int l = key_at(w, n, i, VTTS_MY_SPECIAL[k].key);
            if (l) { sp = k; spl = l; }
        }
        if (sp >= 0) {
            memset(&cur, 0, sizeof cur);
            cur.special = sp + 1;
            txt_add(&cur, w, i, i + spl);
            i += spl;
        } else {
            uint32_t ch = w[i];
            if (!onset_letter(ch)) { i++; continue; }
            if (is_final(w, n, i) && have && !prev.special && !prev.final) {
                int j = i + 1;
                prev.final = ch;
                prev.asat = 1;
                while (j < n && (w[j] == DOT || w[j] == ASAT || w[j] == VISARGA)) {
                    prev.dot |= w[j] == DOT;
                    prev.visarga |= w[j] == VISARGA;
                    j++;
                }
                txt_add(&prev, w, i, j); /* s.text += w[i:j] */
                i = j;
                continue;
            }
            memset(&cur, 0, sizeof cur);
            cur.base = ch;
            int j = i + 1;
            while (j < n) {
                uint32_t x = w[j];
                unsigned f = FL(x);
                if (f & VTTS_MY_MEDIAL) { if (cur.nmed < 8) cur.medials[cur.nmed++] = x; }
                else if (f & VTTS_MY_VSIGN) { if (cur.nvowel < 12) cur.vowel[cur.nvowel++] = x; }
                else if (x == DOT) cur.dot = 1;
                else if (x == VISARGA) cur.visarga = 1;
                else if (x == ASAT) cur.asat = 1;
                else if (is_final(w, n, j) && !cur.final) { cur.final = x; j++; continue; }
                else if (cur.final && is_final(w, n, j)) { j++; continue; }
                else break;
                j++;
            }
            txt_add(&cur, w, i, j);
            i = j;
        }
        if (have) {
            emit_syl(c, &prev, 0, k_index > 0 && prev_full);
            prev_full = full(&prev);
            k_index++;
        }
        prev = cur;
        have = 1;
    }
    if (have) emit_syl(c, &prev, 1, k_index > 0 && prev_full);
}

int vtts_my_read(const char *utf8, void *scratch, size_t size, vtts_my_syl_cb cb, void *user) {
    typedef struct { uint32_t w[VTTS_MY_MAX_RUN * 3 + 8], t[VTTS_MY_MAX_RUN * 3 + 8]; } sc_t;
    if (!utf8 || !scratch || size < sizeof(sc_t) || !cb) return -1;
    sc_t *s = scratch;
    my_ctx_t c = {cb, user, 0};
    const char *p = utf8;
    while (*p) {
        int n = 0, l;
        uint32_t cp;
        while (n < VTTS_MY_MAX_RUN && (l = dec1(p, &cp)) > 0) { s->w[n++] = cp; p += l; }
        int m = prepare(s->w, n, s->t, VTTS_MY_MAX_RUN * 3 + 8);
        read_run(&c, s->t, m);
    }
    return c.count;
}

#else
typedef int vtts_text_my_unused;
#endif
