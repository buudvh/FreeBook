/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_ar.c -- Arabic front-end of the device (token set ar-en): vowel restoration (spelling
 * table, the word's own marks, the word table with clitics and endings, word patterns, the default
 * reading), the pausal reading and stress (mirrors src/vtts/frontend/ar/g2p_ar.py), and
 * normalization (mirrors src/vtts/frontend/ar/normalize_ar.py). All tables are in the generated
 * vtts_text_ar_tables.h; no blob is needed. Compiled only when VTTS_ENABLE_AR is 1. */
#include "vtts_langs.h"
#if VTTS_ENABLE_AR /* else an empty unit (vtts_langs.h) */

#include "vtts_text.h"

#include "vtts_text_ar.h"

#include <string.h>

#include "vtts_text_ar_tables.h"
#include "vtts_text_en.h"
#include "vtts_text_lt.h"
#include "vtts_text_tables.h"

#define FATHA 0x064Eu
#define DAMMA 0x064Fu
#define KASRA 0x0650u
#define SUKUN 0x0652u
#define SHADDA 0x0651u
#define FATHATAN 0x064Bu
#define DAMMATAN 0x064Cu
#define KASRATAN 0x064Du
#define DAGGER 0x0670u
#define TATWEEL 0x0640u
#define ALIF 0x0627u
#define LAM 0x0644u
#define WAW 0x0648u
#define YA 0x064Au
#define TA 0x062Au
#define TA_MARBUTA 0x0629u
#define ALIF_MAQSURA 0x0649u
#define ALIF_MADDA 0x0622u
#define HAMZA_A 0x0623u
#define HAMZA_I 0x0625u

/* ======================= character classes ======================= */

static const uint8_t *cinfo(uint32_t c) { return c >= 0x600 && c <= 0x6FF ? VTTS_AR_CHARS[c - 0x600] : NULL; }
static int flag(uint32_t c, int f) { const uint8_t *t = cinfo(c); return t && (t[0] & f); }

static int ext_bit(const uint8_t *bits, uint32_t c) { /* bits over VTTS_AR_EXT ranges (multiples of 8) */
    int off = 0;
    for (int r = 0; r < 4; r++) {
        uint32_t a = VTTS_AR_EXT[r][0], b = VTTS_AR_EXT[r][1];
        if (c >= a && c <= b) return bits[off + ((c - a) >> 3)] >> ((c - a) & 7) & 1;
        off += (int)((b - a + 1) >> 3);
    }
    return 0;
}

static int is_letter_ar(uint32_t c) { /* g2p_ar.is_arabic_letter */
    if (c >= 0x600 && c <= 0x6FF) return flag(c, VTTS_AR_F_LO) != 0;
    return ext_bit(VTTS_AR_EXT_LO, c);
}

static int wcls(uint32_t c) { /* the [AR] class of normalize_ar */
    if (c >= 0x600 && c <= 0x6FF) return flag(c, VTTS_AR_F_WORDCLS) != 0;
    return ext_bit(VTTS_AR_EXT_WCLS, c);
}

int vtts_ar_has_arabic(const uint32_t *w, int n) {
    for (int i = 0; i < n; i++) if (is_letter_ar(w[i])) return 1;
    return 0;
}

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

static int dec(const char *s, uint32_t *o, int cap) { /* a whole UTF-8 string */
    int m = 0, l;
    uint32_t c;
    while ((l = dec1(s, &c)) > 0 && m < cap) { o[m++] = c; s += l; }
    return m;
}

static int equals(const uint32_t *w, int n, const char *k) {
    int m = 0, l;
    uint32_t c;
    while ((l = dec1(k, &c)) > 0) {
        if (m >= n || w[m] != c) return 0;
        m++;
        k += l;
    }
    return m == n;
}

int vtts_ar_latin_word(const uint32_t *w, int n) {
    for (int k = 0; k < VTTS_AR_N_LATIN_WORDS; k++) if (equals(w, n, VTTS_AR_LATIN_WORDS[k])) return 1;
    return 0;
}

/* ======================= NFC (the Arabic part) ======================= */

static int ccc(uint32_t c) {
    if (c >= 0x600 && c <= 0x6FF) return VTTS_AR_CHARS[c - 0x600][3];
    if (c < 0x300) return 0;
    for (int k = 0; k < VTTS_AR_N_CCC_EXT; k++) if (VTTS_AR_CCC_EXT[k][0] == c) return VTTS_AR_CCC_EXT[k][1];
    return 0;
}

static uint32_t singleton(uint32_t c) { /* NFC singleton decompositions (as vtts_text_hi.c) */
    switch (c) {
    case 0x0340: return 0x0300;
    case 0x0341: return 0x0301;
    case 0x0343: return 0x0313;
    case 0x037E: return ';';
    case 0x0387: return 0x00B7;
    case 0x2000: return 0x2002;
    case 0x2001: return 0x2003;
    case 0x2126: return 0x03A9;
    case 0x212A: return 'K';
    case 0x212B: return 0x00C5;
    default: return c;
    }
}

/* unicodedata.normalize("NFC") for Arabic: the letters with hamza or madda are decomposed, the marks
 * put in canonical order and the pairs composed again. Other scripts are copied (Latin letters with
 * separate combining marks are not composed). Returns the length, or -1 when cap is too small. */
static int ar_nfc(const uint32_t *s, int n, uint32_t *o, int cap) {
    int m = 0;
    for (int i = 0; i < n; i++) {
        uint32_t c = singleton(s[i]);
        int k = 0;
        if (c >= 0x622 && c <= 0x6D3)
            for (; k < VTTS_AR_N_COMPOSE && VTTS_AR_COMPOSE[k][0] != c; k++) {}
        if (c >= 0x622 && c <= 0x6D3 && k < VTTS_AR_N_COMPOSE) {
            if (m + 2 > cap) return -1;
            o[m++] = VTTS_AR_COMPOSE[k][1];
            o[m++] = VTTS_AR_COMPOSE[k][2];
            continue;
        }
        if (m >= cap) return -1;
        o[m++] = c;
    }
    for (int i = 1; i < m; i++) { /* canonical ordering: stable insertion sort of each run of marks */
        int cc = ccc(o[i]);
        if (!cc) continue;
        for (int j = i; j > 0 && ccc(o[j - 1]) > cc; j--) { uint32_t t = o[j]; o[j] = o[j - 1]; o[j - 1] = t; }
    }
    int w = 0, starter = -1;
    for (int i = 0; i < m; i++) {
        uint32_t c = o[i];
        int cc = ccc(c);
        if (starter >= 0 && cc && (w - 1 == starter || (ccc(o[w - 1]) && ccc(o[w - 1]) < cc))) {
            int k = 0;
            for (; k < VTTS_AR_N_COMPOSE; k++)
                if (VTTS_AR_COMPOSE[k][1] == o[starter] && VTTS_AR_COMPOSE[k][2] == c) break;
            if (k < VTTS_AR_N_COMPOSE) { o[starter] = VTTS_AR_COMPOSE[k][0]; continue; }
        }
        if (!cc) starter = w;
        o[w++] = c;
    }
    return w;
}

/* ======================= words ======================= */

typedef struct { uint32_t *p; int n, cap; } sb_t;

static void sb_put(sb_t *b, uint32_t c) { if (b->n < b->cap) b->p[b->n++] = c; }
static void sb_utf8(sb_t *b, const char *s) {
    uint32_t c;
    int l;
    while ((l = dec1(s, &c)) > 0) { sb_put(b, c); s += l; }
}
static void sb_cps(sb_t *b, const uint32_t *s, int n) { for (int i = 0; i < n; i++) sb_put(b, s[i]); }
static void sb_val(sb_t *b, const uint8_t *e) { /* the vowelled value of a table entry */
    const uint8_t *v = e + 1 + e[0];
    for (int i = 0; i < v[0]; i++) sb_put(b, 0x600u + v[1 + i]);
}

static int final_vowel(uint32_t c) {
    return c == FATHA || c == DAMMA || c == KASRA || c == SUKUN || c == FATHATAN || c == DAMMATAN || c == KASRATAN;
}
static void strip_final(sb_t *b, int start) { while (b->n > start && final_vowel(b->p[b->n - 1])) b->n--; }

static int ends_with(const uint32_t *w, int n, const char *s, int *len) {
    uint32_t k[8];
    int m = dec(s, k, 8);
    *len = m;
    if (m > n) return 0;
    for (int i = 0; i < m; i++) if (w[n - m + i] != k[i]) return 0;
    return 1;
}

/* ---- the tables: letters as code point - 0x600 (spelling: [klen][key][vlen][value]) ---- */

static int key_cmp(const uint32_t *w, int n, const uint8_t *k, int kl, int unseat) {
    for (int i = 0; i < n && i < kl; i++) {
        int a = w[i] < 0x600 ? -1 : w[i] > 0x6FF ? 256 : (int)(w[i] - 0x600);
        int b = unseat && i == 0 ? (int)(ALIF - 0x600) : k[i];
        if (a != b) return a < b ? -1 : 1;
    }
    return n < kl ? -1 : n > kl ? 1 : 0;
}

static const uint8_t *find(const uint8_t *blob, const uint16_t *off, int n, const uint32_t *w, int len) {
    int lo = 0, hi = n - 1;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        const uint8_t *e = blob + off[mid];
        int c = key_cmp(w, len, e + 1, e[0], 0);
        if (!c) return e;
        if (c > 0) lo = mid + 1; else hi = mid - 1;
    }
    return NULL;
}

/* the word table: entry k (blocks of VTTS_AR_LEX_BLOCK entries) and binary search over the keys
 * (or over the unseated keys of VTTS_AR_UNSEATED) */
static const uint8_t *lex_entry(int k) {
    const uint8_t *e = VTTS_AR_LEX_BLOB + VTTS_AR_LEX_BLOCKS[k / VTTS_AR_LEX_BLOCK];
    for (int i = 0; i < k % VTTS_AR_LEX_BLOCK; i++) e += 1 + 2 * e[0];
    return e;
}

static const uint8_t *lex_find(const uint32_t *w, int len, int unseat) {
    int lo = 0, hi = (unseat ? VTTS_AR_N_UNSEATED : VTTS_AR_N_LEX) - 1;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        const uint8_t *e = lex_entry(unseat ? VTTS_AR_UNSEATED[mid] : mid);
        int c = key_cmp(w, len, e + 1, e[0], unseat);
        if (!c) return e;
        if (c > 0) lo = mid + 1; else hi = mid - 1;
    }
    return NULL;
}

static const uint8_t *lookup(const uint32_t *w, int n) { /* _lookup: exact, else the unseated key */
    const uint8_t *e = lex_find(w, n, 0);
    if (!e && n && w[0] == ALIF) e = lex_find(w, n, 1);
    return e;
}

static void sb_lex(sb_t *b, const uint8_t *e) { /* the vowelled value of a word-table entry */
    static const uint32_t MARK[10] = {0, 0x064B, 0x064C, 0x064D, 0x064E, 0x064F, 0x0650, 0x0651, 0x0652, 0x0670};
    for (int i = 0; i < e[0]; i++) {
        uint8_t m = e[1 + e[0] + i];
        sb_put(b, 0x600u + e[1 + i]);
        if (m & 15) sb_put(b, MARK[m & 15]);
        if (m >> 4) sb_put(b, MARK[m >> 4]);
    }
}

static const uint8_t *spelling(const uint32_t *w, int n) {
    return find(VTTS_AR_SPELL_BLOB, VTTS_AR_SPELL_OFF, VTTS_AR_N_SPELL, w, n);
}

/* ---- clitics ---- */

typedef struct { uint32_t pre[8]; int pl, letters, off, art; } split_t;
#define MAX_SPLITS 32

static void pre_add(split_t *s, const char *v) {
    uint32_t c;
    int l;
    while ((l = dec1(v, &c)) > 0) {
        if (s->pl < 8) s->pre[s->pl++] = c;
        s->letters += c != FATHA && c != KASRA;
        v += l;
    }
}

static const char *proclitic(uint32_t c) {
    uint32_t k;
    for (int i = 0; i < VTTS_AR_N_PROCLITICS; i++)
        if (dec1(VTTS_AR_PROCLITICS[i][0], &k) && k == c) return VTTS_AR_PROCLITICS[i][1];
    return "";
}

/* _proclitic_splits: (vowelled proclitics, rest = w + off, has article), most proclitics first */
static int splits(const uint32_t *w, int n, split_t *out) {
    static const uint32_t CONJ[3] = {WAW, 0x0641u, 0}, PREP[4] = {0x0628u, 0x0643u, LAM, 0};
    int m = 0;
    for (int ci = 0; ci < 3; ci++) {
        uint32_t conj = CONJ[ci];
        int cl = conj != 0;
        if (cl && !(n > 0 && w[0] == conj)) continue;
        int o0 = cl;
        if (n - o0 > 3 && w[o0] == LAM && w[o0 + 1] == LAM) {
            split_t s = {{0}, 0, 0, o0 + 2, 1};
            if (cl) pre_add(&s, proclitic(conj));
            pre_add(&s, VTTS_AR_STR_LIL);
            out[m++] = s;
        }
        for (int pi = 0; pi < 4; pi++) {
            uint32_t prep = PREP[pi];
            int pl = prep != 0;
            if (pl && !(o0 < n && w[o0] == prep)) continue;
            int r = o0 + pl;
            split_t s = {{0}, 0, 0, r, 0};
            if (cl) pre_add(&s, proclitic(conj));
            if (pl) pre_add(&s, proclitic(prep));
            if (n - r > 3 && w[r] == ALIF && w[r + 1] == LAM) {
                split_t a = s;
                pre_add(&a, VTTS_AR_STR_AL);
                a.off = r + 2;
                a.art = 1;
                out[m++] = a;
            }
            if (cl || pl) out[m++] = s;
        }
    }
    split_t s = {{0}, 0, 0, 0, 0};
    out[m++] = s;
    return m;
}

/* _with_ending: a stem of the table, directly or with one of ENDINGS; appended to o */
static int with_ending(const uint32_t *stem, int n, sb_t *o, uint32_t *tmp) {
    const uint8_t *e = lookup(stem, n);
    if (e) { sb_lex(o, e); return 1; }
    for (int k = 0; k < VTTS_AR_N_ENDINGS; k++) {
        int le, lb;
        uint32_t be[2];
        lb = dec(VTTS_AR_ENDINGS[k][1], be, 2);
        if (!ends_with(stem, n, VTTS_AR_ENDINGS[k][0], &le) || n - le < 3 - lb) continue;
        int bn = n - le;
        memcpy(tmp, stem, sizeof *tmp * (size_t)bn);
        if (lb) tmp[bn++] = be[0];
        e = lookup(tmp, bn);
        if (!e) continue;
        int start = o->n;
        sb_lex(o, e);
        strip_final(o, start);
        if (lb) {
            if (!(o->n > start && o->p[o->n - 1] == TA_MARBUTA)) { o->n = start; continue; }
            while (o->n > start && o->p[o->n - 1] == TA_MARBUTA) o->n--;
            strip_final(o, start);
        }
        sb_utf8(o, VTTS_AR_ENDINGS[k][2]);
        return 1;
    }
    return 0;
}

/* _attach: a vowelled stem (in o from start) + a pronoun suffix */
static void attach(sb_t *o, int start, const char *pron) {
    uint32_t last = o->n > start ? o->p[o->n - 1] : 0;
    if (!(last == SUKUN || last == FATHA)) {
        strip_final(o, start);
        if (o->n > start && o->p[o->n - 1] == TA_MARBUTA) o->p[o->n - 1] = TA;
        last = o->n > start ? o->p[o->n - 1] : 0;
        if (!(last == ALIF || last == ALIF_MAQSURA || last == YA || last == WAW)) sb_put(o, VTTS_AR_LINK);
        else if (last == ALIF_MAQSURA) o->p[o->n - 1] = ALIF;
    }
    int n = o->n - start;
    uint32_t a = n >= 1 ? o->p[o->n - 1] : 0, b = n >= 2 ? o->p[o->n - 2] : 0;
    if (a == KASRA || a == YA || (a == SUKUN && b == YA))
        for (int k = 0; k < VTTS_AR_N_HI; k++)
            if (strcmp(VTTS_AR_HI[k][0], pron) == 0) { pron = VTTS_AR_HI[k][1]; break; }
    sb_utf8(o, pron);
}

/* lexicon_vocalize: the whole word, else the split with the longest stem in the table (fewer
 * proclitic characters first); written to o. tmp, cand: scratch of at least n + 8. */
static int lexicon_vocalize(const uint32_t *w, int n, sb_t *o, uint32_t *tmp, uint32_t *stem2, sb_t *cand) {
    const uint8_t *e = lookup(w, n);
    if (e) { sb_lex(o, e); return 1; }
    split_t sp[MAX_SPLITS];
    int ns = splits(w, n, sp), best_size = -1, best_pl = 0, start = o->n;
    for (int s = 0; s < ns; s++) {
        const uint32_t *rest = w + sp[s].off;
        int rn = n - sp[s].off;
        if (rn < 2) continue;
        for (int c = -1; c < 2 * VTTS_AR_N_PRONOUNS; c++) { /* -1: the rest; then each pronoun (ة, plain) */
            const uint32_t *stem = rest;
            int sn = rn;
            const char *pron = NULL;
            if (c >= 0) {
                if (sp[s].art) break;
                int k = c / 2, ls;
                if (!ends_with(rest, rn, VTTS_AR_PRONOUNS[k][0], &ls) || rn - ls < 2) continue;
                sn = rn - ls;
                pron = VTTS_AR_PRONOUNS[k][1];
                if (c % 2 == 0) {
                    if (rest[sn - 1] != TA) continue;
                    memcpy(stem2, rest, sizeof *stem2 * (size_t)sn);
                    stem2[sn - 1] = TA_MARBUTA;
                    stem = stem2;
                }
            }
            if (!(sn > best_size || (sn == best_size && -sp[s].pl > -best_pl))) continue;
            cand->n = 0;
            if (!with_ending(stem, sn, cand, tmp)) continue;
            best_size = sn;
            best_pl = sp[s].pl;
            o->n = start;
            sb_cps(o, sp[s].pre, sp[s].pl);
            int vs = o->n;
            sb_cps(o, cand->p, cand->n);
            if (pron) attach(o, vs, pron);
        }
    }
    return best_size >= 0;
}

/* ---- patterns ---- */

static int el_ok(uint16_t el, uint32_t c) {
    switch (el) {
    case 1: return !(c == ALIF || c == WAW || c == YA || c == ALIF_MAQSURA || c == TA_MARBUTA || c == ALIF_MADDA);
    case 2: return !(c == ALIF || c == ALIF_MAQSURA || c == TA_MARBUTA || c == ALIF_MADDA);
    case 3: return c == ALIF || c == HAMZA_I;
    default: return c == el;
    }
}

static int template(const uint32_t *w, int n, sb_t *o) {
    for (int k = 0; k < VTTS_AR_N_PATTERNS; k++) {
        const vtts_ar_pattern *p = &VTTS_AR_PATTERNS[k];
        if (p->n != n) continue;
        uint32_t g[8];
        int ng = 0, i = 0;
        for (; i < n && el_ok(p->el[i], w[i]); i++) if (p->el[i] == 1 || p->el[i] == 2) g[ng++] = w[i];
        if (i < n) continue;
        uint32_t c;
        int l;
        for (const char *t = p->tpl; (l = dec1(t, &c)) > 0; t += l)
            sb_put(o, c >= '1' && c <= '5' && (int)(c - '1') < ng ? g[c - '1'] : c);
        return 1;
    }
    return 0;
}

static int stem_vocalize(const uint32_t *w, int n, sb_t *o) {
    for (int k = 0; k < VTTS_AR_N_FALLBACK_ENDINGS; k++) {
        int le;
        if (ends_with(w, n, VTTS_AR_FALLBACK_ENDINGS[k][0], &le) && n - le >= 3) {
            int start = o->n;
            if (template(w, n - le, o)) { sb_utf8(o, VTTS_AR_FALLBACK_ENDINGS[k][1]); return 1; }
            o->n = start;
        }
    }
    return template(w, n, o);
}

static int lvowel(uint32_t c) { return c == ALIF || c == ALIF_MAQSURA || c == TA_MARBUTA; }

static void default_vocalize(const uint32_t *s, int n, sb_t *o) {
    for (int k = 0; k < n;) {
        uint32_t ch = s[k];
        sb_put(o, ch);
        if (ch == ALIF || ch == ALIF_MAQSURA || ch == TA_MARBUTA || ch == ALIF_MADDA) { k++; continue; }
        uint32_t nxt = k + 1 < n ? s[k + 1] : 0, after = k + 2 < n ? s[k + 2] : 0;
        if ((nxt == WAW || nxt == YA) && !lvowel(after)) {
            sb_put(o, nxt == WAW ? DAMMA : KASRA);
            sb_put(o, nxt);
            k += 2;
            continue;
        }
        if ((nxt == WAW || nxt == YA) && after == ALIF && k + 3 == n) sb_put(o, SUKUN);
        else if (lvowel(nxt)) sb_put(o, FATHA);
        else if (nxt && k > 0 && (after == ALIF || after == WAW || after == YA) && s[k - 1] != WAW) sb_put(o, SUKUN);
        else if (nxt) sb_put(o, FATHA);
        k++;
    }
}

static void pattern_vocalize(const uint32_t *w, int n, sb_t *o) {
    split_t sp[MAX_SPLITS];
    int ns = splits(w, n, sp);
    for (int s = 0; s < ns; s++) {
        if (!sp[s].art || n - sp[s].off < 2) continue;
        sb_cps(o, sp[s].pre, sp[s].pl);
        if (!stem_vocalize(w + sp[s].off, n - sp[s].off, o)) default_vocalize(w + sp[s].off, n - sp[s].off, o);
        return;
    }
    if (stem_vocalize(w, n, o)) return;
    for (int s = 0; s < ns; s++) {
        if (!(sp[s].pl && n - sp[s].off >= 3 && sp[s].letters == 1)) continue;
        int start = o->n;
        sb_cps(o, sp[s].pre, sp[s].pl);
        if (stem_vocalize(w + sp[s].off, n - sp[s].off, o)) return;
        o->n = start;
    }
    default_vocalize(w, n, o);
}

/* strip_marks of an NFC word: FOLD, without marks, tatweel and Quranic signs */
static int strip(const uint32_t *w, int n, uint32_t *o) {
    int m = 0;
    for (int i = 0; i < n; i++) {
        const uint8_t *t = cinfo(w[i]);
        if (t && (t[0] & VTTS_AR_F_STRIP)) continue;
        o[m++] = t ? 0x600u + t[2] : w[i];
    }
    return m;
}

static int spelling_vocalize(const uint32_t *w, int n, sb_t *o) {
    const uint8_t *e = spelling(w, n);
    if (e) { sb_val(o, e); return 1; }
    split_t sp[MAX_SPLITS];
    int ns = splits(w, n, sp);
    for (int s = 0; s < ns; s++) {
        if (sp[s].art || !sp[s].pl) continue;
        e = spelling(w + sp[s].off, n - sp[s].off);
        if (e) { sb_cps(o, sp[s].pre, sp[s].pl); sb_val(o, e); return 1; }
    }
    return 0;
}

/* ======================= reading (read_vocalized) and stress ======================= */

enum { M_FATHA = 1, M_DAMMA = 2, M_KASRA = 4, M_SUKUN = 8, M_FATHATAN = 16, M_DAMMATAN = 32, M_KASRATAN = 64,
       M_DAGGER = 128, M_SHADDA = 256 };
enum { VM_NONE, VM_AA, VM_A, VM_U, VM_I, VM_AN, VM_UN, VM_IN, VM_SUK };

static int mark_bit(uint32_t c) {
    switch (c) {
    case FATHA: return M_FATHA;
    case DAMMA: return M_DAMMA;
    case KASRA: return M_KASRA;
    case SUKUN: return M_SUKUN;
    case FATHATAN: return M_FATHATAN;
    case DAMMATAN: return M_DAMMATAN;
    case KASRATAN: return M_KASRATAN;
    case DAGGER: return M_DAGGER;
    case SHADDA: return M_SHADDA;
    default: return 0;
    }
}

static int vowel_of(int m) { /* _vowel: the first mark in the order of the Python table */
    if (m & M_DAGGER) return VM_AA;
    if (m & M_FATHA) return VM_A;
    if (m & M_DAMMA) return VM_U;
    if (m & M_KASRA) return VM_I;
    if (m & M_FATHATAN) return VM_AN;
    if (m & M_DAMMATAN) return VM_UN;
    if (m & M_KASRATAN) return VM_IN;
    if (m & M_SUKUN) return VM_SUK;
    return VM_NONE;
}

#define PA (VTTS_AR_V0 + 0)
#define PI (VTTS_AR_V0 + 1)
#define PU (VTTS_AR_V0 + 2)
#define PAA (VTTS_AR_V0 + 3)
#define PII (VTTS_AR_V0 + 4)
#define PUU (VTTS_AR_V0 + 5)
static int is_vowel(int p) { return p >= VTTS_AR_V0 && p < VTTS_AR_V0 + 6; }
static int is_short(int p) { return p >= PA && p <= PU; }
static int is_long(int p) { return p >= PAA && p <= PUU; }
static int short_of(int vm) { return vm == VM_A || vm == VM_AN ? PA : vm == VM_U || vm == VM_UN ? PU : PI; }
static int is_short_vm(int vm) { return vm == VM_A || vm == VM_U || vm == VM_I; }
static int cons(uint32_t b) { const uint8_t *t = cinfo(b); return t ? t[1] : 255; }

/* letters with their marks (_letters): NFC'd input, FOLD, letters and marks kept */
static int letters_of(const uint32_t *w, int n, uint32_t *base, int *mask, int cap) {
    int m = 0;
    for (int i = 0; i < n; i++) {
        const uint8_t *t = cinfo(w[i]);
        uint32_t c = t ? 0x600u + t[2] : w[i];
        if (flag(c, VTTS_AR_F_LETTER)) {
            if (m < cap) { base[m] = c; mask[m] = 0; m++; }
        } else if (flag(c, VTTS_AR_F_MARK) && m) {
            mask[m - 1] |= mark_bit(c);
        }
    }
    return m;
}

static void article(const uint32_t *base, const int *mask, int n, int *alif, int *lam) {
    int k = 0;
    *alif = *lam = -1;
    while (k < 2 && k < n && (base[k] == WAW || base[k] == 0x0641u || base[k] == 0x0628u || base[k] == 0x0643u ||
                              base[k] == LAM) &&
           (vowel_of(mask[k]) == VM_A || vowel_of(mask[k]) == VM_I)) {
        if (base[k] == LAM && k + 2 < n && base[k + 1] == LAM &&
            (vowel_of(mask[k + 1]) == VM_NONE || vowel_of(mask[k + 1]) == VM_SUK)) {
            *lam = k + 1;
            return;
        }
        k++;
    }
    if (k + 2 < n && base[k] == ALIF && vowel_of(mask[k]) == VM_NONE && base[k + 1] == LAM) {
        int v = vowel_of(mask[k + 1]);
        if (v == VM_NONE || v == VM_SUK || (v == VM_I && base[k + 2] == ALIF)) { *alif = k; *lam = k + 1; }
    }
}

/* read_vocalized (pausal): phoneme indices into out; returns the count */
static int read_vocalized(const uint32_t *base, const int *mask, int L, int *out, int cap) {
    int n = 0, alif, lam, geminate = 0, last_mark_vowel = 0;
#define OUT(p) do { if (n < cap) out[n++] = (p); } while (0)
    article(base, mask, L, &alif, &lam);
    for (int i = 0; i < L; i++) {
        uint32_t b = base[i];
        int m = mask[i], v = vowel_of(m), prev = n ? out[n - 1] : -1;
        int prev_sukun = i > 0 && (mask[i - 1] & M_SUKUN);
        last_mark_vowel = 0;
        if (i == alif) {
            if (i == 0) OUT(PA);
            continue;
        }
        if (i == lam) {
            if (v == VM_I) { OUT(VTTS_AR_PH_L); OUT(PI); }
            else if (i + 1 < L && flag(base[i + 1], VTTS_AR_F_SUN)) geminate = !(mask[i + 1] & M_SHADDA);
            else OUT(VTTS_AR_PH_L);
            continue;
        }
        if (b == ALIF) {
            if (i == 0) OUT(is_short_vm(v) ? short_of(v) : L > 1 && base[1] == LAM ? PA : PI);
            else if (is_short_vm(v) && prev >= 0 && !is_vowel(prev)) OUT(short_of(v));
            else if (prev == PA) out[n - 1] = PAA;
            else if (prev >= 0 && !is_vowel(prev)) OUT(PAA);
            continue;
        }
        if (b == ALIF_MADDA) { OUT(VTTS_AR_PH_GLOTTAL); OUT(PAA); continue; }
        if (b == ALIF_MAQSURA) {
            if (prev == PA) out[n - 1] = PAA;
            else if (prev == PI) out[n - 1] = PII;
            else if (prev >= 0 && !is_vowel(prev)) OUT(PAA);
            continue;
        }
        if (b == TA_MARBUTA) {
            if (prev >= 0 && !is_vowel(prev)) OUT(PA);
            if (i + 1 < L) OUT(VTTS_AR_PH_T);
            continue;
        }
        if ((b == WAW || b == YA) && i > 0 && !(m & M_SHADDA) && (v == VM_NONE || v == VM_SUK)) {
            int sh = b == WAW ? PU : PI, lg = b == WAW ? PUU : PII;
            if (prev == sh) { out[n - 1] = lg; continue; }
            if (prev == PA || v == VM_SUK || prev_sukun || is_long(prev)) { OUT(cons(b)); continue; }
            if (prev >= 0) { OUT(lg); continue; }
        }
        int c = cons(b);
        if (v == VM_NONE && (b == HAMZA_A || b == HAMZA_I) && !(i + 1 < L && base[i + 1] == ALIF))
            v = b == HAMZA_A ? VM_A : VM_I;
        OUT(c);
        if ((m & M_SHADDA) || geminate) OUT(c);
        geminate = 0;
        if (is_short_vm(v)) { OUT(short_of(v)); last_mark_vowel = 1; }
        else if (v == VM_AA) OUT(PAA);
        else if (v == VM_AN || v == VM_UN || v == VM_IN) { OUT(short_of(v)); last_mark_vowel = 1; }
    }
    if (last_mark_vowel && n && is_short(out[n - 1])) {
        int tanwin = L && (mask[L - 1] & (M_FATHATAN | M_DAMMATAN | M_KASRATAN));
        if (L >= 3 || tanwin) n--;
    }
    int ya = cons(YA);
    if (n >= 3 && out[n - 3] == PI && out[n - 2] == ya && out[n - 1] == ya) { out[n - 3] = PII; n -= 2; }
#undef OUT
    return n;
}

static void stress(int *ph, int n, int *nuc) { /* nuc: scratch for the nuclei (at most n) */
    int ns = 0, wt[3];
    for (int k = 0; k < n; k++) if (is_vowel(ph[k])) nuc[ns++] = k;
    if (ns < 2) return;
    for (int q = 0; q < 3; q++) { /* weights of the last three syllables: 0 L, 1 H, 2 S */
        int j = ns - 3 + q;
        wt[q] = 0;
        if (j < 0) continue;
        int k = nuc[j], coda;
        if (j + 1 < ns) { coda = nuc[j + 1] - k - 2; if (coda < 0) coda = 0; }
        else coda = n - k - 1;
        int lg = is_long(ph[k]);
        wt[q] = (lg && coda >= 1) || coda >= 2 ? 2 : lg || coda == 1 ? 1 : 0;
    }
    int j = wt[2] == 2 ? ns - 1 : (wt[1] != 0 || ns == 2) ? ns - 2 : ns - 3;
    if (j == 0 && nuc[0] == 0) j = 1;
    ph[nuc[j]] += 6; /* the stressed vowel follows the six plain ones */
}

int vtts_ar_word_ids(const uint32_t *w, int n, uint32_t *sa, uint32_t *sb, uint8_t *out, int cap) {
    enum { W = VTTS_AR_MAXW };
    if (n > W) n = W;
    /* sa: wn | wb | bare | tmp (letters) | stem2 | mask | phonemes (9W + 16); sb: voc | cand | nfc | nuclei (10W) */
    uint32_t *wn = sa, *wb = sa + W, *bare = sa + 2 * W, *tmp = sa + 3 * W, *stem2 = sa + 4 * W + 8;
    sb_t voc = {sb, 0, 3 * W}, cand = {sb + 3 * W, 0, 3 * W};
    int m = ar_nfc(w, n, wb, W);
    if (m < 0) return 0;
    int k = 0;
    for (int i = 0; i < m; i++) if (wb[i] != TATWEEL) wn[k++] = wb[i]; /* NFC, then tatweel removed */
    m = ar_nfc(wn, k, wb, W);
    if (m < 0) return 0;
    int nb = strip(wb, m, bare), vowelled = 0;
    for (int i = 0; i < k; i++) vowelled |= flag(wn[i], VTTS_AR_F_VOWEL_MARK) != 0;
    if (!spelling_vocalize(bare, nb, &voc)) {
        if (vowelled) {
            sb_cps(&voc, wn, k);
        } else if (!lexicon_vocalize(bare, nb, &voc, tmp, stem2, &cand)) {
            int ok = 0;
            if (nb > 2 && bare[nb - 1] == ALIF_MAQSURA) {
                bare[nb - 1] = YA;
                voc.n = 0;
                ok = lexicon_vocalize(bare, nb, &voc, tmp, stem2, &cand);
                bare[nb - 1] = ALIF_MAQSURA;
            }
            if (!ok) { voc.n = 0; pattern_vocalize(bare, nb, &voc); }
        }
    }
    /* read: NFC of the vowelled word, its letters and marks, phonemes, stress */
    uint32_t *nfc = sb + 6 * W;
    m = ar_nfc(voc.p, voc.n, nfc, 3 * W);
    if (m < 0) return 0;
    uint32_t *base = tmp;
    int *mask = (int *)(sa + 5 * W + 16), *ph = (int *)(sa + 6 * W + 16), *nuc = (int *)(sb + 9 * W);
    int L = letters_of(nfc, m, base, mask, W);
    int np = read_vocalized(base, mask, L, ph, 3 * W);
    stress(ph, np, nuc);
    int r = 0;
    for (int i = 0; i < np && r < cap; i++) out[r++] = (uint8_t)(VTTS_AREN_AR0 + ph[i]);
    return r;
}

/* ======================= normalization (normalize_ar) =======================
 * Each regex pass of the Python normalizer is one function from buffer s (n code points) to buffer
 * d; matches are found left to right without overlap, like re.sub, and lookarounds look at the
 * pass's input. Where backtracking can change a match, the candidates are tried in the order the
 * regex engine tries them. */

typedef struct { uint32_t *p; int n, cap, err; } kb_t;
typedef struct { uint32_t *a, *b; int cap; char *out; int out_cap; } scratch_t;

static void put(kb_t *d, uint32_t c) { if (d->n < d->cap) d->p[d->n++] = c; else d->err = 1; }
static void put_utf8(kb_t *d, const char *s) {
    uint32_t c;
    int l;
    while ((l = dec1(s, &c)) > 0) { put(d, c); s += l; }
}
static void put_cps(kb_t *d, const uint32_t *s, int n) { for (int i = 0; i < n; i++) put(d, s[i]); }

static int DG(const uint32_t *s, int n, int i) { return i >= 0 && i < n && s[i] >= '0' && s[i] <= '9'; }
static int W(const uint32_t *s, int n, int i) { return i >= 0 && i < n && vtts_u_word(s[i]); }
static int AR(const uint32_t *s, int n, int i) { return i >= 0 && i < n && wcls(s[i]); }
static int SP(const uint32_t *s, int n, int i) { return i >= 0 && i < n && vtts_u_space(s[i]); }
static int AT(const uint32_t *s, int n, int i, uint32_t c) { return i >= 0 && i < n && s[i] == c; }
static int UP(const uint32_t *s, int n, int i) { return i >= 0 && i < n && s[i] >= 'A' && s[i] <= 'Z'; }
static int digit_run(const uint32_t *s, int n, int i) { int j = i; while (DG(s, n, j)) j++; return j - i; }
static int no_wdc(const uint32_t *s, int n, int i) { return !W(s, n, i) && !AT(s, n, i, '.') && !AT(s, n, i, ','); }

static int key_at(const uint32_t *s, int n, int i, const char *k) { /* its length in code points, or 0 */
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

static void ones(kb_t *d, int v, int gen) { put_utf8(d, gen && v == 2 ? VTTS_AR_ONE_GEN2 : VTTS_AR_ONES[v]); }

static void part(kb_t *d, int *first) { /* parts after the first are joined with " وَ" */
    if (!*first) { put(d, ' '); put_utf8(d, VTTS_AR_AND); }
    *first = 0;
}

static void card_ll(kb_t *d, long long v, int gen);

static const char *form(long long q, const char *const *f) { /* _form: f = one, two, 3-10, 11-99, 100+ */
    int r = (int)(q % 100);
    if (q == 1 || q == 2) return f[q - 1];
    if (r >= 3 && r <= 10) return f[2];
    if (r >= 11) return f[3];
    return f[4];
}

static void below_1000(kb_t *d, int v, int gen, int *first) {
    int h = v / 100, r = v % 100;
    if (h) { part(d, first); put_utf8(d, gen && h == 2 ? VTTS_AR_HUNDRED_GEN2 : VTTS_AR_HUNDREDS[h]); }
    if (!r) return;
    part(d, first);
    if (r <= 10) { ones(d, r, gen); return; }
    if (r < 20) {
        if (r == 11) put_utf8(d, VTTS_AR_TEEN11);
        else if (r == 12) put_utf8(d, gen ? VTTS_AR_TEEN12_GEN : VTTS_AR_TEEN12);
        else { put_utf8(d, VTTS_AR_ONES[r - 10]); put_utf8(d, VTTS_AR_TEEN_TAIL); }
        return;
    }
    int t = r / 10, u = r % 10;
    if (u) { ones(d, u, gen); part(d, first); }
    put_utf8(d, gen ? VTTS_AR_TENS_GEN[t] : VTTS_AR_TENS[t]);
}

static void card_ll(kb_t *d, long long v, int gen) { /* cardinal(), v < 10**12 */
    static const long long SC[3] = {1000000000LL, 1000000LL, 1000LL};
    if (v <= 10) { ones(d, (int)v, gen); return; }
    int first = 1;
    for (int k = 0; k < 3; k++) {
        long long q = v / SC[k];
        v %= SC[k];
        if (!q) continue;
        part(d, &first);
        const char *const *s = VTTS_AR_SCALES[k];
        if (q == 1) put_utf8(d, s[0]);
        else if (q == 2) put_utf8(d, gen ? s[2] : s[1]);
        else {
            const char *f[5] = {s[0], s[1], s[3], s[4], s[5]};
            card_ll(d, q, gen);
            put(d, ' ');
            put_utf8(d, form(q, f));
        }
    }
    if (v) below_1000(d, (int)v, gen, &first);
}

static void digit_names(kb_t *d, const uint32_t *s, int n) {
    int first = 1;
    for (int i = 0; i < n; i++) {
        if (s[i] < '0' || s[i] > '9') continue;
        if (!first) put(d, ' ');
        put_utf8(d, VTTS_AR_ONES[s[i] - '0']);
        first = 0;
    }
}

/* cardinal(int(s)) for ASCII digits (commas skipped); >= 10**12 digit by digit (str(int)) */
static void card_span(kb_t *d, const uint32_t *s, int n, int gen) {
    int i = 0, len = 0;
    while (i < n && (s[i] == '0' || s[i] == ',')) i++;
    for (int k = i; k < n; k++) len += s[k] != ',';
    if (len > 12) { digit_names(d, s + i, n - i); return; }
    long long v = 0;
    for (int k = i; k < n; k++) if (s[k] != ',') v = v * 10 + (s[k] - '0');
    card_ll(d, v, gen);
}

static long long span_value(const uint32_t *s, int n, int *big) { /* int(s) capped at 10**12 */
    long long v = 0;
    *big = 0;
    for (int i = 0; i < n; i++) {
        if (s[i] < '0' || s[i] > '9') continue;
        v = v * 10 + (s[i] - '0');
        if (v >= 1000000000000LL) { *big = 1; v %= 1000000000000LL; }
    }
    return v;
}

/* number(): '-' is سالب, commas dropped, the decimals after فاصلة digit by digit */
static void number(kb_t *d, const uint32_t *s, int n, int gen) {
    int i = 0;
    if (n && s[0] == '-') { put_utf8(d, VTTS_AR_SALIB); i = 1; }
    int dot = i;
    while (dot < n && s[dot] != '.') dot++;
    card_span(d, s + i, dot - i, gen);
    if (dot < n) {
        put_utf8(d, VTTS_AR_FASILA);
        digit_names(d, s + dot + 1, n - dot - 1);
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
        int k = i + r, g = 0;
        while (AT(s, n, k, ',') && DG(s, n, k + 1) && DG(s, n, k + 2) && DG(s, n, k + 3)) { k += 4; g++; }
        for (; g >= 1; g--, k -= 4) if ((e = try_frac(s, n, k, ok, u)) >= 0) return e;
    }
    for (int k = r; k >= 1; k--) if ((e = try_frac(s, n, i + k, ok, u)) >= 0) return e;
    return -1;
}

static int always(const uint32_t *s, int n, int end, void *u) { (void)s; (void)n; (void)end; (void)u; return 1; }
static int not_digit(const uint32_t *s, int n, int end, void *u) { (void)u; return !DG(s, n, end); }

/* ---- passes, in the order of normalize_ar ---- */

static void p_translate(const uint32_t *s, int n, kb_t *d) { /* DIGITS, then PUNCT (tatweel deleted) */
    for (int i = 0; i < n; i++) {
        uint32_t c = s[i];
        if (c >= 0x660 && c <= 0x669) c = '0' + (c - 0x660);
        else if (c >= 0x6F0 && c <= 0x6F9) c = '0' + (c - 0x6F0);
        else if (c == 0x60C || c == 0x66C) c = ',';
        else if (c == 0x61B) c = ';';
        else if (c == 0x61F) c = '?';
        else if (c == 0x6D4 || c == 0x66B) c = '.';
        else if (c == 0x66A) c = '%';
        else if (c == TATWEEL) continue;
        put(d, c);
    }
}

/* one abbreviation: (?<![AR\w])key(?![AR]) (no lookahead for a key ending with '.') */
static void p_abbrev(const uint32_t *s, int n, kb_t *d, int k) {
    const char *key = VTTS_AR_ABBREV[k][0];
    int dot = key[strlen(key) - 1] == '.';
    for (int i = 0; i < n;) {
        if (!AR(s, n, i - 1) && !W(s, n, i - 1)) {
            int l = key_at(s, n, i, key);
            if (l && (dot || !AR(s, n, i + l))) {
                put(d, ' ');
                put_utf8(d, VTTS_AR_ABBREV[k][1]);
                put(d, ' ');
                i += l;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static void p_drop(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n; i++) {
        uint32_t c = s[i];
        for (int k = 0; k < VTTS_AR_N_DROP; k++) if (VTTS_AR_DROP[k] == c) { c = ' '; break; }
        put(d, c);
    }
}

static int small_value(const uint32_t *s, int n) {
    int v = 0;
    for (int i = 0; i < n; i++) if (s[i] >= '0' && s[i] <= '9') { v = v * 10 + (int)(s[i] - '0'); if (v > 100000) v = 100000; }
    return v;
}

/* _date: " d month year(gen) ", or 0 for an invalid day or month */
static int date_out(kb_t *d, int dd, int mm, const uint32_t *y, int yl) {
    if (!(dd >= 1 && dd <= 31 && mm >= 1 && mm <= 12)) return 0;
    put(d, ' ');
    card_ll(d, dd, 0);
    put(d, ' ');
    put_utf8(d, VTTS_AR_MONTHS[mm]);
    put(d, ' ');
    card_span(d, y, yl, 1);
    put(d, ' ');
    return 1;
}

static int iso_sep(const uint32_t *s, int n, int i) { return AT(s, n, i, '-') || AT(s, n, i, '/'); }

/* (?<![\d-])(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?![\d-]) */
static void p_date_iso(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (!DG(s, n, i - 1) && !AT(s, n, i - 1, '-') && digit_run(s, n, i) == 4 && iso_sep(s, n, i + 4)) {
            int m0 = i + 5, ml = digit_run(s, n, m0), d0 = m0 + ml + 1, dl = digit_run(s, n, d0);
            if (ml >= 1 && ml <= 2 && iso_sep(s, n, m0 + ml) && dl >= 1 && dl <= 2 && !AT(s, n, d0 + dl, '-')) {
                int end = d0 + dl;
                if (!date_out(d, small_value(s + d0, dl), small_value(s + m0, ml), s + i, 4)) put_cps(d, s + i, end - i);
                i = end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int dmy_sep(uint32_t c) { return c == '/' || c == '.' || c == '-'; }

/* (?<![\d/.-])(\d{1,2})([/.-])(\d{1,2})\2(\d{4})(?![\d/.-]) */
static void p_date_dmy(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i) && !DG(s, n, i - 1) && !(i > 0 && dmy_sep(s[i - 1]))) {
            int r1 = digit_run(s, n, i), p = i + r1;
            if (r1 <= 2 && p < n && dmy_sep(s[p])) {
                uint32_t sep = s[p];
                int r2 = digit_run(s, n, p + 1), q = p + 1 + r2;
                if (r2 >= 1 && r2 <= 2 && AT(s, n, q, sep)) {
                    int r3 = digit_run(s, n, q + 1), end = q + 1 + r3;
                    if (r3 == 4 && !(end < n && dmy_sep(s[end]))) {
                        if (!date_out(d, small_value(s + i, r1), small_value(s + p + 1, r2), s + q + 1, r3))
                            put_cps(d, s + i, end - i);
                        i = end;
                        continue;
                    }
                }
            }
        }
        put(d, s[i++]);
    }
}

static int two(const uint32_t *s, int i) { return (int)(s[i] - '0') * 10 + (int)(s[i + 1] - '0'); }
static int not_dc(const uint32_t *s, int n, int i) { return !DG(s, n, i) && !AT(s, n, i, ':'); }
static int d05(const uint32_t *s, int n, int i) { return i >= 0 && i < n && s[i] >= '0' && s[i] <= '5'; }

/* (?<![\d:.])([01]?\d|2[0-4]):([0-5]\d)(?::([0-5]\d))?(?![\d:])(?:\s*(ص|م|صباحا|مساء)(?![AR]))? -> _time */
static void p_time(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i) && !DG(s, n, i - 1) && !AT(s, n, i - 1, ':') && !AT(s, n, i - 1, '.')) {
            int hl[3], nh = 0, done = 0;
            if ((s[i] == '0' || s[i] == '1') && DG(s, n, i + 1)) hl[nh++] = 2;
            hl[nh++] = 1;
            if (s[i] == '2' && i + 1 < n && s[i + 1] >= '0' && s[i + 1] <= '4') hl[nh++] = 2;
            for (int c = 0; c < nh && !done; c++) {
                int j = i + hl[c];
                if (!(AT(s, n, j, ':') && d05(s, n, j + 1) && DG(s, n, j + 2))) continue;
                int k = j + 3, sec = -1, end = -1;
                if (AT(s, n, k, ':') && d05(s, n, k + 1) && DG(s, n, k + 2) && not_dc(s, n, k + 3)) {
                    sec = two(s, k + 1);
                    end = k + 3;
                } else if (not_dc(s, n, k)) {
                    end = k;
                }
                if (end < 0) continue;
                int e2 = end, part_k = -1;
                while (SP(s, n, e2)) e2++;
                for (int q = 0; q < 4 && part_k < 0; q++) {
                    int l = key_at(s, n, e2, VTTS_AR_TIME_PARTS[q]);
                    if (l && !AR(s, n, e2 + l)) { part_k = q; end = e2 + l; }
                }
                int h = hl[c] == 2 ? two(s, i) : (int)(s[i] - '0'), mi = two(s, j + 1);
                put(d, ' ');
                card_ll(d, h, 0);
                if (mi == 15) put_utf8(d, VTTS_AR_RUB3);
                else if (mi == 30) put_utf8(d, VTTS_AR_NISF);
                else if (mi) { put(d, ' '); put_utf8(d, VTTS_AR_AND); card_ll(d, mi, 0); put_utf8(d, VTTS_AR_DAQIQA); }
                if (sec > 0) { put(d, ' '); put_utf8(d, VTTS_AR_AND); card_ll(d, sec, 0); put_utf8(d, VTTS_AR_THANIYA); }
                if (part_k >= 0) put_utf8(d, part_k == 0 || part_k == 2 ? VTTS_AR_SABAHAN : VTTS_AR_MASAAN);
                put(d, ' ');
                i = end;
                done = 1;
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

/* (?<![\d.,])(\d{3,4})\s*(هـ|ه|م)(?![AR]) -> " year(gen) era " */
static void p_era(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i) && !DG(s, n, i - 1) && !AT(s, n, i - 1, '.') && !AT(s, n, i - 1, ',')) {
            int r = digit_run(s, n, i);
            if (r == 3 || r == 4) {
                int j = i + r, hit = -1, end = 0;
                while (SP(s, n, j)) j++;
                for (int q = 0; q < 3 && hit < 0; q++) {
                    int l = key_at(s, n, j, VTTS_AR_ERAS[q]);
                    if (l && !AR(s, n, j + l)) { hit = q; end = j + l; }
                }
                if (hit >= 0) {
                    put(d, ' ');
                    card_span(d, s + i, r, 1);
                    put(d, ' ');
                    put_utf8(d, hit == 2 ? VTTS_AR_MILADI : VTTS_AR_HIJRI);
                    put(d, ' ');
                    i = end;
                    continue;
                }
            }
        }
        put(d, s[i++]);
    }
}

/* ((?<![AR])(?:[وب]?ال)?(?:عام|سنة)\s+)(\d{3,4})(?![\d]|[.,]\d) -> group 1 + year(gen) + " " */
static void p_year_after(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        int end = -1, ds = 0, dl = 0;
        if (!AR(s, n, i - 1)) {
            for (int v = 0; v < 3 && end < 0; v++) {
                int j = i;
                if (v == 0) { if (!(AT(s, n, j, WAW) || AT(s, n, j, 0x0628u))) continue; j++; }
                if (v <= 1) { if (!(AT(s, n, j, ALIF) && AT(s, n, j + 1, LAM))) continue; j += 2; }
                int l = 0;
                for (int q = 0; q < 2 && !l; q++) l = key_at(s, n, j, VTTS_AR_YEAR_WORDS[q]);
                if (!l || !SP(s, n, j + l)) continue;
                j += l;
                while (SP(s, n, j)) j++;
                int r = digit_run(s, n, j);
                if ((r == 3 || r == 4) && !((AT(s, n, j + r, '.') || AT(s, n, j + r, ',')) && DG(s, n, j + r + 1))) {
                    end = j + r;
                    ds = j;
                    dl = r;
                }
            }
        }
        if (end >= 0) {
            put_cps(d, s + i, ds - i);
            card_span(d, s + ds, dl, 1);
            put(d, ' ');
            i = end;
            continue;
        }
        put(d, s[i++]);
    }
}

/* _money(num, currency k) */
static void money_out(kb_t *d, const uint32_t *num, int nn, int k) {
    const vtts_ar_currency *c = &VTTS_AR_CURRENCY[k];
    const char *const *forms = VTTS_AR_CUR_FORMS[c->kind];
    int dot = 0;
    while (dot < nn && num[dot] != '.') dot++;
    int frac_nz = 0;
    for (int i = dot + 1; i < nn; i++) frac_nz |= num[i] > '0' && num[i] <= '9';
    put(d, ' ');
    if (frac_nz) {
        number(d, num, nn, 0);
        put(d, ' ');
        put_utf8(d, forms[4]);
    } else {
        int big;
        long long v = span_value(num, dot, &big);
        if (big) v += 1000000000000LL; /* only the form matters: not 1 or 2 */
        const char *name = form(v, forms);
        if (v == 1 || v == 2) put_utf8(d, name);
        else { card_span(d, num, dot, 0); put(d, ' '); put_utf8(d, name); }
    }
    if (c->adj[0]) { put(d, ' '); put_utf8(d, c->adj); }
    put(d, ' ');
}

/* (?<![\w AR])(currency)\s?(NUM) */
static void p_money_before(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (!W(s, n, i - 1) && !AR(s, n, i - 1)) {
            int done = 0;
            for (int k = 0; k < VTTS_AR_N_CURRENCY && !done; k++) {
                int l = key_at(s, n, i, VTTS_AR_CURRENCY[k].key);
                if (!l) continue;
                int j = i + l, ns = j, e = -1;
                if (SP(s, n, j)) { ns = j + 1; e = num_match(s, n, ns, always, NULL); }
                if (e < 0) { ns = j; e = num_match(s, n, ns, always, NULL); }
                if (e < 0) continue;
                money_out(d, s + ns, e - ns, k);
                i = e;
                done = 1;
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

typedef struct { int key, end; } cur_m;

static int cur_ok(const uint32_t *s, int n, int end, void *u) { /* \s?(currency)(?![\w AR]) */
    cur_m *m = u;
    for (int sp = SP(s, n, end); sp >= 0; sp--)
        for (int k = 0; k < VTTS_AR_N_CURRENCY; k++) {
            int p = end + sp, l = key_at(s, n, p, VTTS_AR_CURRENCY[k].key);
            if (l && !W(s, n, p + l) && !AR(s, n, p + l)) { m->key = k; m->end = p + l; return 1; }
        }
    return 0;
}

/* (?<![\w.,])(NUM)\s?(currency)(?![\w AR]) */
static void p_money_after(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (no_wdc(s, n, i - 1)) {
            cur_m m;
            int e = num_match(s, n, i, cur_ok, &m);
            if (e >= 0) {
                money_out(d, s + i, e - i, m.key);
                i = m.end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int phone_sep(const uint32_t *s, int n, int i) { return SP(s, n, i) || AT(s, n, i, '-'); }

static int phone_tail(const uint32_t *s, int n, int e) { /* (?:[\s-]\d{2,5}){0,3}(?![\d.,]) */
    int ends[4], m = 0;
    ends[0] = e;
    while (m < 3 && phone_sep(s, n, ends[m])) {
        int r = digit_run(s, n, ends[m] + 1);
        if (r < 2 || r > 5) break;
        ends[m + 1] = ends[m] + 1 + r;
        m++;
    }
    for (; m >= 0; m--)
        if (!DG(s, n, ends[m]) && !AT(s, n, ends[m], '.') && !AT(s, n, ends[m], ',')) return ends[m];
    return -1;
}

/* (?<![\d.,])(?:\+\d{1,3}[\s-]?)?\d{2,12}(?:[\s-]\d{2,5}){0,3}(?![\d.,]) -> _phone */
static void p_phone(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        int end = -1;
        if (!DG(s, n, i - 1) && !AT(s, n, i - 1, '.') && !AT(s, n, i - 1, ',')) {
            if (AT(s, n, i, '+')) {
                int r0 = digit_run(s, n, i + 1);
                for (int c = r0 < 3 ? r0 : 3; c >= 1 && end < 0; c--) {
                    int p = i + 1 + c;
                    if (c == r0 && phone_sep(s, n, p)) {
                        int l = digit_run(s, n, p + 1);
                        if (l >= 2 && l <= 12) end = phone_tail(s, n, p + 1 + l);
                        if (end >= 0) break;
                    }
                    int l = c < r0 ? r0 - c : 0;
                    if (l >= 2 && l <= 12) end = phone_tail(s, n, p + l);
                }
            } else if (DG(s, n, i)) {
                int l = digit_run(s, n, i);
                if (l >= 2 && l <= 12) end = phone_tail(s, n, i + l);
            }
        }
        if (end >= 0) {
            int nd = 0;
            for (int k = i; k < end; k++) nd += DG(s, n, k);
            if (nd < 10 && s[i] != '+') {
                put_cps(d, s + i, end - i);
            } else {
                put(d, ' ');
                if (s[i] == '+') put_utf8(d, VTTS_AR_ZAID);
                digit_names(d, s + i, end - i);
                put(d, ' ');
            }
            i = end;
            continue;
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

static void p_percent(const uint32_t *s, int n, kb_t *d) { /* (?<![\w.,])(-?)(NUM)\s?% */
    for (int i = 0; i < n;) {
        if (no_wdc(s, n, i - 1)) {
            int j = i + AT(s, n, i, '-'), pe = 0;
            int e = num_match(s, n, j, pct_ok, &pe);
            if (e >= 0) {
                put(d, ' ');
                number(d, s + i, e - i, 0);
                put_utf8(d, VTTS_AR_PERCENT);
                i = pe;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

typedef struct { int unit, end; } unit_m;

static int unit_ok(const uint32_t *s, int n, int end, void *u) { /* \s?(units)(?![\w AR]) */
    unit_m *m = u;
    for (int sp = SP(s, n, end); sp >= 0; sp--) {
        int p = end + sp;
        for (int k = 0; k < VTTS_AR_N_UNITS; k++) {
            int l = key_at(s, n, p, VTTS_AR_UNITS[k][0]);
            if (l && !W(s, n, p + l) && !AR(s, n, p + l)) { m->unit = k; m->end = p + l; return 1; }
        }
    }
    return 0;
}

static void p_unit(const uint32_t *s, int n, kb_t *d) { /* (?<![\w.,])(-?)(NUM)\s?(units)(?![\w AR]) */
    for (int i = 0; i < n;) {
        if (no_wdc(s, n, i - 1)) {
            int j = i + AT(s, n, i, '-');
            unit_m m;
            int e = num_match(s, n, j, unit_ok, &m);
            if (e >= 0) {
                put(d, ' ');
                number(d, s + i, e - i, 0);
                put(d, ' ');
                put_utf8(d, VTTS_AR_UNITS[m.unit][1]);
                put(d, ' ');
                i = m.end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int dash(const uint32_t *s, int n, int i) { return AT(s, n, i, '-') || AT(s, n, i, 0x2013); }

/* (\d+)\s?[-–]\s?(\d+)(?![\w]) at i (after the lookbehind): the end, *b0 and *rb the second number */
static int range_at(const uint32_t *s, int n, int i, int *b0, int *rb) {
    if (!DG(s, n, i)) return -1;
    int ra = digit_run(s, n, i), j = i + ra, k = -1;
    if (SP(s, n, j) && dash(s, n, j + 1)) k = j + 2;
    else if (dash(s, n, j)) k = j + 1;
    if (k < 0) return -1;
    if (SP(s, n, k) && DG(s, n, k + 1)) {
        *rb = digit_run(s, n, k + 1);
        if (!W(s, n, k + 1 + *rb)) { *b0 = k + 1; return k + 1 + *rb; }
    } else if (DG(s, n, k)) {
        *rb = digit_run(s, n, k);
        if (!W(s, n, k + *rb)) { *b0 = k; return k + *rb; }
    }
    return -1;
}

/* ((?<![AR])من\s+)?(?<![\w.,])(\d+)\s?[-–]\s?(\d+)(?![\w]) -> " من a إلى b " (genitive) */
static void p_range(const uint32_t *s, int n, kb_t *d) {
    static const uint32_t MIN_[2] = {0x0645u, 0x0646u};
    for (int i = 0; i < n;) {
        int a = -1, end = -1, b0 = 0, rb = 0;
        if (!AR(s, n, i - 1) && AT(s, n, i, MIN_[0]) && AT(s, n, i + 1, MIN_[1]) && SP(s, n, i + 2)) {
            int j = i + 2;
            while (SP(s, n, j)) j++;
            if (no_wdc(s, n, j - 1) && (end = range_at(s, n, j, &b0, &rb)) >= 0) a = j;
        }
        if (end < 0 && no_wdc(s, n, i - 1) && (end = range_at(s, n, i, &b0, &rb)) >= 0) a = i;
        if (end >= 0) {
            put_utf8(d, VTTS_AR_MIN);
            card_span(d, s + a, digit_run(s, n, a), 1);
            put_utf8(d, VTTS_AR_ILA);
            card_span(d, s + b0, rb, 1);
            put(d, ' ');
            i = end;
            continue;
        }
        put(d, s[i++]);
    }
}

static int pause_dash(const uint32_t *s, int n, int i) { return dash(s, n, i) || AT(s, n, i, 0x2014); }

static void p_pause(const uint32_t *s, int n, kb_t *d) { /* …+ | \.{3,} | \s[—–-]+\s | —+ | –+ -> " , " */
    for (int i = 0; i < n;) {
        uint32_t c = s[i];
        int end = -1;
        if (c == 0x2026 || c == 0x2014 || c == 0x2013 || c == '.') {
            int j = i;
            while (j < n && s[j] == c) j++;
            if (c != '.' || j - i >= 3) end = j;
        } else if (SP(s, n, i)) {
            int j = i + 1;
            while (pause_dash(s, n, j)) j++;
            if (j > i + 1 && SP(s, n, j)) end = j + 1;
        }
        if (end >= 0) {
            put_utf8(d, " , ");
            i = end;
            continue;
        }
        put(d, s[i++]);
    }
}

/* (?<![\w])(?=[A-Z0-9]*[A-Z])(?=[A-Z0-9]*[0-9])[A-Z0-9]+(?![\w]) -> letters by their Arabic names */
static void p_code(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (!W(s, n, i - 1) && (UP(s, n, i) || DG(s, n, i))) {
            int j = i, up = 0, dg = 0;
            while (UP(s, n, j) || DG(s, n, j)) { up |= UP(s, n, j); dg |= DG(s, n, j); j++; }
            if (up && dg && !W(s, n, j)) {
                put(d, ' ');
                for (int k = i; k < j; k++) {
                    if (k > i) put(d, ' ');
                    put_utf8(d, UP(s, n, k) ? VTTS_AR_LETTERS[s[k] - 'A'] : VTTS_AR_ONES[s[k] - '0']);
                }
                put(d, ' ');
                i = j;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static void p_number(const uint32_t *s, int n, kb_t *d) { /* (?<![\w.,])(-?)(NUM)(?![\d]) */
    for (int i = 0; i < n;) {
        if (no_wdc(s, n, i - 1)) {
            int j = i + AT(s, n, i, '-');
            int e = num_match(s, n, j, not_digit, NULL);
            if (e >= 0) {
                put(d, ' ');
                number(d, s + i, e - i, 0);
                put(d, ' ');
                i = e;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int lat(const uint32_t *s, int n, int i) { /* [A-Za-zÀ-ɏ] */
    if (i < 0 || i >= n) return 0;
    uint32_t c = s[i];
    return ((c | 32) >= 'a' && (c | 32) <= 'z') || (c >= 0xC0 && c <= 0x24F);
}

/* [A-Za-zÀ-ɏ](?:[A-Za-zÀ-ɏ'-]*[A-Za-zÀ-ɏ])? -> " " + normalize_en(ASCII of its NFKD form) + " " */
static void p_latin(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    const int half = x->cap / 2;
    for (int i = 0; i < n;) {
        if (lat(s, n, i)) {
            int j = i + 1, e = i + 1, f = 0;
            while (j < n && (lat(s, n, j) || s[j] == '\'' || s[j] == '-')) { j++; if (lat(s, n, j - 1)) e = j; }
            for (int k = i; k < e; k++) {
                uint32_t c = s[k];
                if (c < 0x80) {
                    if (f < x->cap) x->b[f++] = c;
                    continue;
                }
                for (const char *p = VTTS_HI_FOLD[c - 0xC0]; *p; p++) if (f < x->cap) x->b[f++] = (uint8_t)*p;
            }
            int m = vtts_en_normalize(x->b, f, x->a, x->a + half, half, x->out, x->out_cap);
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

static void p_symbols(const uint32_t *s, int n, kb_t *d) { /* SYMBOLS in order, then - and – -> space */
    for (int i = 0; i < n; i++) {
        uint32_t c = s[i], k0;
        int k = 0;
        for (; k < VTTS_AR_N_SYMBOLS; k++) if (dec1(VTTS_AR_SYMBOLS[k][0], &k0) && k0 == c) break;
        if (k < VTTS_AR_N_SYMBOLS) put_utf8(d, VTTS_AR_SYMBOLS[k][1]);
        else put(d, c == '-' || c == 0x2013 ? ' ' : c);
    }
}

static int is_mark(uint32_t c) { return c == ',' || c == '.' || c == '?' || c == '!' || c == ';' || c == ':'; }
static int alpha(uint32_t c) { return vtts_u_word(c) && vtts_u_digit(c) < 0 && c != '_'; } /* [^\W\d_] */

/* findall([AR]+|[^\W\d_]+(?:'[^\W\d_]+)*|[,.?!;:]) over t.lower(), joined by single spaces; a mark
 * after a mark is dropped */
static void p_words(const uint32_t *s, int n, kb_t *d) {
    int any = 0, last_mark = 0;
    for (int i = 0; i < n;) {
        int j = i;
        uint32_t c = vtts_u_lower(s[i]);
        if (wcls(c)) {
            while (j < n && wcls(vtts_u_lower(s[j]))) j++;
        } else if (alpha(c)) {
            while (j < n && alpha(vtts_u_lower(s[j]))) j++;
            while (j + 1 < n && s[j] == '\'' && alpha(vtts_u_lower(s[j + 1]))) {
                j++;
                while (j < n && alpha(vtts_u_lower(s[j]))) j++;
            }
        } else if (is_mark(c)) {
            if (!any || !last_mark) {
                if (any) put(d, ' ');
                put(d, c);
                any = last_mark = 1;
            }
            i++;
            continue;
        } else {
            i++;
            continue;
        }
        if (any) put(d, ' ');
        for (int k = i; k < j; k++) put(d, vtts_u_lower(s[k]));
        any = 1;
        last_mark = 0;
        i = j;
    }
}

int vtts_ar_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, uint32_t *ea, uint32_t *eb,
                      int ecap, char *eout, int eout_cap, const uint32_t **out) {
    kb_t x = {a, 0, cap, 0}, y = {b, 0, cap, 0};
    scratch_t e = {ea, eb, ecap, eout, eout_cap};
    int m = ar_nfc(in, n, ea, ecap); /* in may share memory with a and b */
    if (m < 0) return -1;
    p_translate(ea, m, &x);
    if (x.err) return -1;
#define PASS(call) do { y.n = 0; call; if (y.err) return -1; kb_t t_ = x; x = y; y = t_; } while (0)
    for (int k = 0; k < VTTS_AR_N_ABBREV; k++) PASS(p_abbrev(x.p, x.n, &y, k));
    PASS(p_drop(x.p, x.n, &y));
    PASS(p_date_iso(x.p, x.n, &y));
    PASS(p_date_dmy(x.p, x.n, &y));
    PASS(p_time(x.p, x.n, &y));
    PASS(p_era(x.p, x.n, &y));
    PASS(p_year_after(x.p, x.n, &y));
    PASS(p_money_before(x.p, x.n, &y));
    PASS(p_money_after(x.p, x.n, &y));
    PASS(p_phone(x.p, x.n, &y));
    PASS(p_percent(x.p, x.n, &y));
    PASS(p_unit(x.p, x.n, &y));
    PASS(p_range(x.p, x.n, &y));
    PASS(p_pause(x.p, x.n, &y));
    PASS(p_code(x.p, x.n, &y));
    PASS(p_number(x.p, x.n, &y));
    PASS(p_latin(x.p, x.n, &y, &e));
    PASS(p_symbols(x.p, x.n, &y));
    PASS(p_words(x.p, x.n, &y));
#undef PASS
    *out = x.p;
    return x.n;
}

#endif /* VTTS_ENABLE_AR */
