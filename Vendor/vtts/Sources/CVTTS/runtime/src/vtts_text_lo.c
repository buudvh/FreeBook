/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_lo.c -- Lao front-end of the device (token set lo-en): word segmentation over the word
 * list, syllables by the lowest-cost split over the spelling patterns, consonant classes and the six
 * tones of Vientiane Lao (mirrors src/vtts/frontend/lo/g2p_lo.py), and normalization (mirrors
 * src/vtts/frontend/lo/normalize_lo.py, the passes of the Thai normalizer). All tables are in the
 * generated vtts_text_lo_tables.h (Lao letters coded as code point - 0x0E80); no blob is needed.
 * Compiled only with VTTS_ENABLE_LO (vtts_text_lo.h). */
#include "vtts_text_lo.h"

int vtts_lo_is_lao(uint32_t c) { return (c >= 0x0E81 && c <= 0x0ECD) || (c >= 0x0EDC && c <= 0x0EDF); }

int vtts_lo_has_lao(const uint32_t *w, int n) {
    for (int i = 0; i < n; i++) if (vtts_lo_is_lao(w[i])) return 1;
    return 0;
}

#if VTTS_ENABLE_LO

#include <string.h>

#include "vtts_text_en.h"
#include "vtts_text_lo_tables.h"
#include "vtts_text_lt.h"

/* ======================= spelling rules (g2p_lo.py) ======================= */

enum {
    L_NO = 0x19,      /* ນ */
    L_MO = 0x21,      /* ມ */
    L_WO = 0x27,      /* ວ */
    L_HO = 0x2B,      /* ຫ */
    L_MAI_KAN = 0x31, /* ັ */
    L_AA = 0x32,      /* າ */
    L_AM = 0x33,      /* ຳ */
    L_I = 0x34,       /* ິ */
    L_U = 0x38,       /* ຸ */
    L_VIRAMA = 0x3A,  /* ຺ */
    L_MAI_KON = 0x3B, /* ົ */
    L_SUB_LO = 0x3C,  /* ຼ */
    L_REPEAT = 0x46,  /* ໆ */
    L_EK = 0x48, L_THO = 0x49, L_TI = 0x4A, L_CATAWA = 0x4B,
    L_CANCEL = 0x4C,  /* ໌ */
    L_NIGGAHITA = 0x4D, /* ໍ */
    L_YAMAKKAN = 0x4E,
    L_HO_NO = 0x5C, L_HO_MO = 0x5D /* ໜ ໝ */
};
enum { CLS_M = 0, CLS_H = 1, CLS_L = 2 };
enum { KIND_X = 0, KIND_O = 1, KIND_A = 2 };

#define CLASS_BITS (VTTS_LO_MID | VTTS_LO_HIGH | VTTS_LO_LOW)

static int has(uint8_t c, unsigned flag) { return c < 0x80 && (VTTS_LO_LETTERS[c].flags & flag) != 0; }
static int is_class(uint8_t c) { return has(c, CLASS_BITS); }
static int cls_of(uint8_t c) { return has(c, VTTS_LO_MID) ? CLS_M : has(c, VTTS_LO_HIGH) ? CLS_H : CLS_L; }
static uint8_t ini_of(uint8_t c) { return VTTS_LO_LETTERS[c & 0x7F].initial; }
static uint8_t fin_of(uint8_t c) { return c < 0x80 ? VTTS_LO_LETTERS[c].final : 0; }
static int dep(uint8_t c) { return has(c, VTTS_LO_DEPENDENT); }
static int tone_mark(uint8_t c) { return has(c, VTTS_LO_TONE_MARK); }

typedef struct { uint8_t ini[2], nini, cls, vowel, fin, mark, shrt, kind; } syl_t; /* fin: index + 1 */

typedef struct { int16_t end, cost; syl_t s; } step_t;
#define MAX_STEPS 96

typedef struct { int32_t a; int16_t b, c; uint8_t f, valid; } dp_t;

typedef struct {
    uint8_t codes[VTTS_LO_MAX_RUN + 1];
    uint8_t w[VTTS_LO_MAX_RUN + 1];
    dp_t dp[VTTS_LO_MAX_RUN + 1];
    int16_t outer[VTTS_LO_MAX_RUN + 2], path[VTTS_LO_MAX_RUN + 1];
    step_t steps[MAX_STEPS];
} lo_scratch_t;

typedef struct {
    lo_scratch_t *t;
    syl_t *buf; /* the syllables of the last word (ໆ repeats them) */
    int cap;
    vtts_lo_syl_cb cb;
    void *user;
    int count;
} lo_ctx_t;

static syl_t mk(const uint8_t *ini, int nini, int cls, int vowel, int fin, int mark, int shrt, int kind) {
    syl_t s;
    s.ini[0] = ini[0];
    s.ini[1] = nini > 1 ? ini[1] : 0;
    s.nini = (uint8_t)nini;
    s.cls = (uint8_t)cls;
    s.vowel = (uint8_t)vowel;
    s.fin = (uint8_t)fin;
    s.mark = (uint8_t)mark;
    s.shrt = (uint8_t)shrt;
    s.kind = (uint8_t)kind;
    return s;
}

/* tone(): 1 low rising, 2 high rising, 3 mid, 4 low falling, 5 high falling, 6 mid rising */
static int tone_of(const syl_t *s) {
    int live = s->fin ? (VTTS_LO_LIVE_FINALS >> s->fin) & 1 : !s->shrt;
    switch (s->mark) {
    case L_EK: return 3;
    case L_THO: return s->cls == CLS_H ? 4 : 5;
    case L_TI: return 2;
    case L_CATAWA: return 1;
    default: break;
    }
    if (live) return s->cls == CLS_L ? 2 : 1;
    if (s->shrt) return s->cls == CLS_L ? 3 : 6;
    return s->cls == CLS_H ? 4 : 5;
}

static int syl_ids(const syl_t *s, uint8_t *out) {
    int n = 0;
    for (int k = 0; k < s->nini; k++) out[n++] = (uint8_t)(VTTS_LOEN_I0 + s->ini[k]);
    out[n++] = (uint8_t)(VTTS_LOEN_V0 + s->vowel);
    if (s->fin) out[n++] = (uint8_t)(VTTS_LOEN_F0 + s->fin - 1);
    out[n++] = (uint8_t)(VTTS_LOEN_T1 + tone_of(s) - 1);
    return n;
}

/* prepare() after the ligatures ໜ ໝ were written as ຫນ ຫມ (done when the text is decoded): ຺ and
 * ໎ dropped, ໍ + tone mark + າ -> tone mark + ຳ (each mark in turn), ໍາ -> ຳ, a consonant under ໌
 * (with ິ ຸ on it) dropped. In place; returns the new length. */
static int prepare(uint8_t *w, int n) {
    int m = 0;
    for (int i = 0; i < n; i++) if (w[i] != L_VIRAMA && w[i] != L_YAMAKKAN) w[m++] = w[i];
    n = m;
    for (uint8_t t = L_EK; t <= L_CATAWA; t++) { /* str.replace("ໍ" + t + "າ", t + "ຳ") */
        m = 0;
        for (int i = 0; i < n;) {
            if (i + 2 < n && w[i] == L_NIGGAHITA && w[i + 1] == t && w[i + 2] == L_AA) {
                w[m++] = t; w[m++] = L_AM; i += 3;
            } else w[m++] = w[i++];
        }
        n = m;
    }
    m = 0;
    for (int i = 0; i < n;) {
        if (i + 1 < n && w[i] == L_NIGGAHITA && w[i + 1] == L_AA) { w[m++] = L_AM; i += 2; }
        else w[m++] = w[i++];
    }
    n = m;
    m = 0;
    for (int i = 0; i < n; i++) {
        if (w[i] != L_CANCEL) { w[m++] = w[i]; continue; }
        if (m && (w[m - 1] == L_I || w[m - 1] == L_U)) m--;
        if (m && is_class(w[m - 1])) m--;
    }
    return m;
}

typedef struct { int end; uint8_t ini[2]; int nini, cls, extra; } init_t;

/* _initials: (end, sounds, class, extra cost) for the initial at w[k] */
static int initials(const uint8_t *w, int n, int k, init_t *o) {
    uint8_t c = w[k];
    int m = 0;
    memset(o, 0, 3 * sizeof *o);
    o[m].end = k + 1; o[m].ini[0] = ini_of(c); o[m].nini = 1; o[m].cls = cls_of(c); m++;
    if (k + 1 >= n) return m;
    uint8_t c2 = w[k + 1];
    if (c == L_HO && has(c2, VTTS_LO_LOW_SONORANT)) {
        o[m].end = k + 2; o[m].ini[0] = ini_of(c2); o[m].nini = 1; o[m].cls = CLS_H; m++;
    } else if (c2 == L_SUB_LO) {
        o[m].end = k + 2;
        if (c == L_HO) { o[m].ini[0] = VTTS_LO_I_l; o[m].nini = 1; o[m].cls = CLS_H; }
        else { o[m].ini[0] = ini_of(c); o[m].ini[1] = VTTS_LO_I_l; o[m].nini = 2; o[m].cls = cls_of(c); }
        m++;
    } else if (c2 == L_WO && c != L_WO) {
        o[m].end = k + 2; o[m].ini[0] = ini_of(c); o[m].ini[1] = VTTS_LO_I_w; o[m].nini = 2; o[m].cls = cls_of(c);
        o[m].extra = VTTS_LO_COST_CLUSTER_W; m++;
    } else if ((c2 == 0x23 || c2 == 0x25) && has(c, VTTS_LO_RL_FIRST)) { /* ຣ ລ */
        o[m].end = k + 2; o[m].ini[0] = ini_of(c); o[m].ini[1] = ini_of(c2); o[m].nini = 2; o[m].cls = cls_of(c);
        o[m].extra = VTTS_LO_COST_CLUSTER_RL; m++;
    }
    if (c == L_HO && has(c2, VTTS_LO_LOW_SONORANT) && k + 2 < n && w[k + 2] == L_WO) {
        o[m].end = k + 3; o[m].ini[0] = ini_of(c2); o[m].ini[1] = VTTS_LO_I_w; o[m].nini = 2; o[m].cls = CLS_H;
        o[m].extra = VTTS_LO_COST_CLUSTER_W; m++;
    }
    return m;
}

/* _take: letters at w[pos], one tone mark allowed after the initial or an above/below vowel */
static int take(const uint8_t *w, int n, int pos, const char *letters, uint8_t *mark) {
    if (!*mark && pos < n && tone_mark(w[pos])) *mark = w[pos++];
    for (const char *p = letters; *p; p++) {
        uint8_t ch = (uint8_t)*p;
        if (pos >= n || w[pos] != ch) return -1;
        pos++;
        if (has(ch, VTTS_LO_ABOVE_BELOW) && !*mark && pos < n && tone_mark(w[pos])) *mark = w[pos++];
    }
    return pos;
}

static int final_at(const uint8_t *w, int n, int pos) {
    if (pos >= n || !fin_of(w[pos])) return 0;
    if (pos + 1 < n && dep(w[pos + 1])) return 0;
    return fin_of(w[pos]);
}

static void push(step_t *st, int *m, int end, const syl_t *a, int cost) {
    if (*m >= MAX_STEPS) return;
    step_t *s = &st[(*m)++];
    s->end = (int16_t)end;
    s->cost = (int16_t)cost;
    s->s = *a;
}

/* syllables_at: every (end, syllable, cost) that can start at w[i], in the order of g2p_lo */
static int syllables_at(const uint8_t *w, int n, int i, step_t *st) {
    int m = 0;
    uint8_t pre = has(w[i], VTTS_LO_PREPOSED) ? w[i] : 0;
    int k = i + (pre != 0);
    if (k >= n || !is_class(w[k])) return 0;
    init_t in[3];
    int ni = initials(w, n, k, in);
    for (int q = 0; q < ni; q++) {
        const init_t *I = &in[q];
        for (int v = 0; v < VTTS_LO_N_VOWELS; v++) {
            if (VTTS_LO_VOWELS[v].pre != pre) continue;
            const char *letters = VTTS_LO_VOWELS[v].letters;
            uint8_t mark = 0;
            int pos = take(w, n, I->end, letters, &mark);
            if (pos < 0) continue;
            int shrt = VTTS_LO_VOWELS[v].shrt, vowel = VTTS_LO_VOWELS[v].vowel, kind = VTTS_LO_VOWELS[v].kind;
            int cost = VTTS_LO_COST_SYLLABLE + I->extra;
            syl_t s;
            if (kind == 3) {
                s = mk(I->ini, I->nini, I->cls, vowel, VTTS_LO_VOWELS[v].eq, mark, shrt, KIND_X);
                push(st, &m, pos, &s, cost);
                continue;
            }
            if (kind == 0 || kind == 2) {
                s = mk(I->ini, I->nini, I->cls, vowel, 0, mark, shrt, KIND_X);
                push(st, &m, pos, &s, cost);
            }
            if (kind == 1 || kind == 2) {
                int f = final_at(w, n, pos);
                int kon = letters[0] && !letters[1] && (uint8_t)letters[0] == L_MAI_KON;
                if (f && !(kon && f == VTTS_LO_F_w)) { /* ົວ is the vowel ua */
                    s = mk(I->ini, I->nini, I->cls, vowel, f, mark, shrt, KIND_X);
                    push(st, &m, pos + 1, &s, cost);
                }
            }
        }
        if (pre) continue;
        /* no written vowel: closed -> o, open -> a */
        int pos = I->end;
        uint8_t mark = 0;
        if (pos < n && tone_mark(w[pos])) mark = w[pos++];
        int f = final_at(w, n, pos);
        if (f) {
            syl_t s = mk(I->ini, I->nini, I->cls, VTTS_LO_V_o, f, mark, 1, KIND_O);
            push(st, &m, pos + 1, &s, VTTS_LO_COST_SYLLABLE + VTTS_LO_COST_UNWRITTEN_O + I->extra);
        }
        if (pos == I->end && (pos >= n || !dep(w[pos]))) {
            syl_t s = mk(I->ini, I->nini, I->cls, VTTS_LO_V_a, 0, 0, 1, KIND_A);
            push(st, &m, I->end, &s, VTTS_LO_COST_SYLLABLE + VTTS_LO_COST_UNWRITTEN_A + I->extra);
        }
    }
    return m;
}

/* parse_word: syllables of one word (prepared again) by the lowest-cost split, appended to out */
static int parse_word(lo_scratch_t *t, const uint8_t *src, int n, syl_t *out, int no, int cap) {
    uint8_t *w = t->w;
    dp_t *best = t->dp;
    memmove(w, src, (size_t)n);
    for (;;) {
        n = prepare(w, n);
        for (int j = 0; j <= n; j++) best[j].valid = 0;
        best[0].a = 0; best[0].b = -1; best[0].c = 0; best[0].f = 0; best[0].valid = 1;
        for (int i = 0; i < n; i++) {
            if (!best[i].valid) continue;
            int ns = syllables_at(w, n, i, t->steps);
            for (int k = 0; k < (ns ? ns : 1); k++) {
                int j = ns ? t->steps[k].end : i + 1, cost = ns ? t->steps[k].cost : 100;
                if (j < n && dep(w[j])) continue;
                if (j == n && ns && t->steps[k].s.kind == KIND_A && best[i].f) cost += VTTS_LO_COST_WORD_FINAL_A;
                int32_t total = best[i].a + cost;
                if (!best[j].valid || total < best[j].a) {
                    best[j].a = total; best[j].b = (int16_t)i; best[j].c = (int16_t)(ns ? k : -1);
                    best[j].f = (uint8_t)(best[i].f || ns > 0); best[j].valid = 1;
                }
            }
        }
        int ok = best[n].valid, end = n;
        if (!ok) { /* a dependent sign with nothing before it: skip it */
            end = 0;
            for (int i = 0; i < n; i++) if (best[i].valid) end = i;
        }
        int np = 0;
        for (int j = end; j > 0; j = best[j].b) t->path[np++] = (int16_t)j;
        for (int q = np - 1; q >= 0; q--) {
            int j = t->path[q], i = best[j].b, k = best[j].c;
            if (k < 0) continue; /* the fallback step: no syllable */
            syllables_at(w, n, i, t->steps);
            if (no < cap) out[no++] = t->steps[k].s;
        }
        if (ok || end + 1 >= n) return no;
        n -= end + 1;
        memmove(w, w + end + 1, (size_t)n);
    }
}

/* ---- word list and respellings ---- */

static int cmp_codes(const uint8_t *a, int la, const uint8_t *b, int lb) {
    int m = la < lb ? la : lb;
    for (int i = 0; i < m; i++) if (a[i] != b[i]) return a[i] < b[i] ? -1 : 1;
    return la < lb ? -1 : la > lb ? 1 : 0;
}

static int decode_word(int off, uint8_t *buf, int *len) {
    int p = VTTS_LO_WORDS[off++] & 0x7F;
    while (VTTS_LO_WORDS[off] < 0x80) buf[p++] = VTTS_LO_WORDS[off++];
    *len = p;
    return off;
}

static int lower_bound(const uint8_t *key, int lk, uint8_t *buf, int *len) {
    uint8_t tmp[VTTS_LO_MAX_WORD + 1];
    int lo = 0, hi = VTTS_LO_N_BLOCKS - 1, b = -1, lt;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        decode_word((int)VTTS_LO_BLOCKS[mid], tmp, &lt);
        if (cmp_codes(tmp, lt, key, lk) <= 0) { b = mid; lo = mid + 1; } else hi = mid - 1;
    }
    if (b < 0) { decode_word(0, buf, len); return 1; }
    int off = (int)VTTS_LO_BLOCKS[b];
    int end = b + 1 < VTTS_LO_N_BLOCKS ? (int)VTTS_LO_BLOCKS[b + 1] : VTTS_LO_WORDS_BYTES - 1;
    while (off < end) {
        off = decode_word(off, buf, len);
        if (cmp_codes(buf, *len, key, lk) >= 0) return 1;
    }
    if (b + 1 < VTTS_LO_N_BLOCKS) { decode_word((int)VTTS_LO_BLOCKS[b + 1], buf, len); return 1; }
    return 0;
}

static const char *find_override(const uint8_t *w, int n) {
    for (int k = 0; k < VTTS_LO_N_OVERRIDES; k++) {
        const char *key = VTTS_LO_OVERRIDES[k].word;
        if ((int)strlen(key) == n && memcmp(key, w, (size_t)n) == 0) return VTTS_LO_OVERRIDES[k].reading;
    }
    return NULL;
}

/* ends j of the listed words run[i:j] */
static int dict_ends(const uint8_t *run, int n, int i, int *ends) {
    uint8_t buf[VTTS_LO_MAX_WORD + 1];
    int lim = n - i < VTTS_LO_MAX_WORD ? n - i : VTTS_LO_MAX_WORD, len, m = 0;
    for (int l = 1; l <= lim; l++) {
        if (!lower_bound(run + i, l, buf, &len)) break;
        if (len < l || memcmp(buf, run + i, (size_t)l) != 0) break; /* no word starts with run[i:i+l] */
        if (len == l) ends[m++] = i + l;
    }
    return m;
}

/* segment: cut points (np + 1, ascending) of the words of run; returns np */
static int segment(lo_scratch_t *t, const uint8_t *run, int n, int16_t *cuts) {
    dp_t *best = t->dp; /* a: characters outside the list, b: pieces, c: start, f: piece is outside */
    for (int j = 0; j <= n; j++) best[j].valid = 0;
    best[0].a = 0; best[0].b = 0; best[0].c = 0; best[0].f = 0; best[0].valid = 1;
    int ends[VTTS_LO_MAX_WORD + MAX_STEPS + 2], us[VTTS_LO_MAX_WORD + MAX_STEPS + 2];
    for (int i = 0; i < n; i++) {
        if (!best[i].valid || dep(run[i])) continue;
        int32_t unk = best[i].a;
        int cnt = best[i].b, nc = dict_ends(run, n, i, ends), nu = nc;
        for (int q = 0; q < nc; q++) us[q] = 0;
        int ns = syllables_at(run, n, i, t->steps);
        if (!ns) { ends[nu] = i + 1; us[nu++] = 1; }
        for (int q = 0; q < ns && nu < (int)(sizeof ends / sizeof *ends); q++) { /* a lone consonant counts 3 */
            ends[nu] = t->steps[q].end;
            us[nu++] = t->steps[q].end - i + 2 * (t->steps[q].s.kind == KIND_A);
        }
        for (int q = 0; q < nu; q++) {
            int j = ends[q], u = q < nc ? 0 : us[q];
            if (j < n && dep(run[j])) continue;
            int32_t ka = unk + u;
            int kb = cnt + 1;
            if (!best[j].valid || ka < best[j].a || (ka == best[j].a && kb < best[j].b)) {
                best[j].a = ka; best[j].b = (int16_t)kb; best[j].c = (int16_t)i; best[j].f = (uint8_t)(u > 0);
                best[j].valid = 1;
            }
        }
    }
    if (!best[n].valid) { cuts[0] = 0; cuts[1] = (int16_t)n; return 1; }
    int np = 0, last_flag = 0; /* backwards: starts of the pieces; consecutive unknown pieces merge */
    cuts[np++] = (int16_t)n;
    for (int j = n; j > 0;) {
        int i = best[j].c, unknown = best[j].f;
        if (np > 1 && unknown && last_flag) cuts[np - 1] = (int16_t)i;
        else { cuts[np++] = (int16_t)i; last_flag = unknown; }
        j = i;
    }
    for (int a = 0, b = np - 1; a < b; a++, b--) { int16_t x = cuts[a]; cuts[a] = cuts[b]; cuts[b] = x; }
    return np - 1;
}

/* read_respelling: one syllable per piece (pieces separated by 0x7F) */
static int read_respelling(lo_scratch_t *t, const char *r, syl_t *out, int no, int cap) {
    uint8_t q[VTTS_LO_MAX_WORD + 1];
    while (*r) {
        const uint8_t *p = (const uint8_t *)r;
        int lp = 0;
        while (p[lp] && p[lp] != 0x7F) lp++;
        int lq = lp <= VTTS_LO_MAX_WORD ? lp : VTTS_LO_MAX_WORD;
        memcpy(q, p, (size_t)lq);
        lq = prepare(q, lq);
        int ns = lq ? syllables_at(q, lq, 0, t->steps) : 0, pick = -1;
        for (int k = 0; k < ns; k++) {
            if (t->steps[k].end != lq) continue;
            if (pick < 0 || (t->steps[pick].s.kind != KIND_X && t->steps[k].s.kind == KIND_X)) pick = k;
        }
        if (pick >= 0) { if (no < cap) out[no++] = t->steps[pick].s; }
        else no = parse_word(t, p, lp, out, no, cap);
        r += lp + (p[lp] == 0x7F);
    }
    return no;
}

static void emit(lo_ctx_t *c, const syl_t *s) {
    uint8_t ids[8];
    int n = syl_ids(s, ids);
    c->cb(c->user, ids, n);
    c->count++;
}

/* run_syllables over a prepared run: ໆ repeats the word before it */
static void read_run(lo_ctx_t *c, uint8_t *run, int n) {
    lo_scratch_t *t = c->t;
    int nlast = 0, piece = 0;
    n = prepare(run, n);
    for (int s = 0, p = 0; p <= n; p++) {
        if (p < n && run[p] != L_REPEAT) continue;
        if (piece++ > 0) for (int k = 0; k < nlast; k++) emit(c, &c->buf[k]);
        if (p > s) {
            int nw = segment(t, run + s, p - s, t->outer);
            for (int q = 0; q < nw; q++) {
                int a = s + t->outer[q], b = s + t->outer[q + 1];
                const char *r = find_override(run + a, b - a);
                nlast = r ? read_respelling(t, r, c->buf, 0, c->cap) : parse_word(t, run + a, b - a, c->buf, 0, c->cap);
                for (int k = 0; k < nlast; k++) emit(c, &c->buf[k]);
            }
        }
        s = p + 1;
    }
}

int vtts_lo_read(const char *utf8, void *sa, size_t na, void *sb, size_t nb, vtts_lo_syl_cb cb, void *user) {
    if (!utf8 || !sa || !sb || !cb || na < sizeof(lo_scratch_t) || nb < 64 * sizeof(syl_t)) return -1;
    lo_ctx_t c = {(lo_scratch_t *)sa, (syl_t *)sb, (int)(nb / sizeof(syl_t)), cb, user, 0};
    const unsigned char *p = (const unsigned char *)utf8;
    int n = 0;
    while (*p) { /* UTF-8 -> letter codes (ໜ ໝ written ຫນ ຫມ, the first step of prepare) */
        uint32_t cp = *p;
        int extra = cp < 0x80 ? 0 : (cp >> 5) == 6 ? 1 : (cp >> 4) == 14 ? 2 : (cp >> 3) == 30 ? 3 : 0;
        if (extra) cp &= 0x3Fu >> extra;
        p++;
        for (int k = 0; k < extra && (*p & 0xC0) == 0x80; k++) cp = (cp << 6) | (*p++ & 0x3F);
        if (!vtts_lo_is_lao(cp)) continue;
        uint8_t code = (uint8_t)(cp - 0x0E80);
        if (code == L_HO_NO || code == L_HO_MO) {
            c.t->codes[n++] = L_HO;
            code = code == L_HO_NO ? L_NO : L_MO;
        }
        c.t->codes[n++] = code;
        if (n >= VTTS_LO_MAX_RUN - 1) { /* a full buffer: cut before a preposed vowel or a consonant that a vowel
                                         * sign makes an initial (a syllable starts there) */
            uint8_t *w = c.t->codes;
            int cut = n;
            for (int p = n - 2; p > n / 2 && cut == n; p--)
                if (has(w[p], VTTS_LO_PREPOSED) ||
                    (is_class(w[p]) && dep(w[p + 1]) && !tone_mark(w[p + 1]) && w[p] != L_WO && w[p] != 0x23 &&
                     w[p] != 0x25 && w[p + 1] != L_SUB_LO && w[p - 1] != L_HO && !has(w[p - 1], VTTS_LO_PREPOSED)))
                    cut = p;
            uint8_t rest[VTTS_LO_MAX_RUN];
            int nr = n - cut;
            memcpy(rest, w + cut, (size_t)nr);
            read_run(&c, w, cut);
            memcpy(w, rest, (size_t)nr);
            n = nr;
        }
    }
    if (n) read_run(&c, c.t->codes, n);
    return c.count;
}

/* ======================= normalization (normalize_lo) =======================
 * Each regex pass of the Python normalizer is one function from buffer s (n code points) to buffer
 * d; matches are found left to right without overlap, like re.sub, and lookarounds look at the
 * pass's input. \d, \w and \s are Python's Unicode classes (vtts_u_digit / _word / _space). */

#define GLUE 0x01u /* number words: spaces next to them are dropped */

typedef struct { uint32_t *p; int n, cap, err; } kb_t;
typedef struct { uint32_t *a, *b; int cap; char *out; int out_cap; } scratch_t;

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

static int DG(const uint32_t *s, int n, int i) { return i >= 0 && i < n && vtts_u_digit(s[i]) >= 0; }
static int AZ(const uint32_t *s, int n, int i) { return i >= 0 && i < n && (s[i] | 32) >= 'a' && (s[i] | 32) <= 'z'; }
static int UP(const uint32_t *s, int n, int i) { return i >= 0 && i < n && s[i] >= 'A' && s[i] <= 'Z'; }
static int A9(const uint32_t *s, int n, int i) { return i >= 0 && i < n && s[i] >= '0' && s[i] <= '9'; } /* [0-9] */
static int AN(const uint32_t *s, int n, int i) { return A9(s, n, i) || AZ(s, n, i); } /* [A-Za-z0-9] */
static int SP(const uint32_t *s, int n, int i) { return i >= 0 && i < n && vtts_u_space(s[i]); }
static int AT(const uint32_t *s, int n, int i, uint32_t c) { return i >= 0 && i < n && s[i] == c; }
static int RG(const uint32_t *s, int n, int i, uint32_t lo, uint32_t hi) { return i >= 0 && i < n && s[i] >= lo && s[i] <= hi; }
static int LA(const uint32_t *s, int n, int i) { return i >= 0 && i < n && vtts_lo_is_lao(s[i]); }
static int W(const uint32_t *s, int n, int i) { return i >= 0 && i < n && vtts_u_word(s[i]); } /* Python \w */
static int dval(uint32_t c) { return vtts_u_digit(c); }
static int digit_run(const uint32_t *s, int n, int i) { int j = i; while (DG(s, n, j)) j++; return j - i; }
static int digits_at(const uint32_t *s, int n, int i, int k) { /* k digits at s[i] */
    for (int q = 0; q < k; q++) if (!DG(s, n, i + q)) return 0;
    return 1;
}

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

static void digits(kb_t *d, const uint32_t *s, int n) { /* digits(): non-digits skipped */
    for (int i = 0; i < n; i++) if (dval(s[i]) >= 0) put_utf8(d, VTTS_LO_DIGITS[dval(s[i])]);
}

/* _below_million(v, final_one=True), v = 1..999999: ສິບ for 1x, ຊາວ for 2x, ເອັດ for a final 1 */
static void below_million(kb_t *d, int v) {
    int ds[6], nd = 0, any = 0;
    for (int x = v; x; x /= 10) ds[nd++] = x % 10;
    for (int place = nd - 1; place >= 0; place--) {
        int dg = ds[place];
        if (!dg) continue;
        if (place == 1) {
            if (dg == 2) put_utf8(d, "ຊາວ");
            else {
                if (dg != 1) put_utf8(d, VTTS_LO_DIGITS[dg]);
                put_utf8(d, VTTS_LO_PLACES[1]);
            }
        } else if (place == 0) {
            put_utf8(d, dg == 1 && v > 1 && any ? "ເອັດ" : VTTS_LO_DIGITS[dg]);
        } else {
            put_utf8(d, VTTS_LO_DIGITS[dg]);
            put_utf8(d, VTTS_LO_PLACES[place]);
        }
        any = 1;
    }
}

static int group_value(const uint32_t *s, int a, int b) {
    int v = 0;
    for (int i = a; i < b; i++) v = v * 10 + dval(s[i]);
    return v;
}

/* cardinal(int(s)) for decimal digits: groups of six digits joined by ລ້ານ */
static void cardinal_u(kb_t *d, const uint32_t *s, int n) {
    while (n > 0 && dval(*s) == 0) { s++; n--; }
    if (!n) { put_utf8(d, VTTS_LO_DIGITS[0]); return; }
    int first = (n - 1) % 6 + 1;
    below_million(d, group_value(s, 0, first));
    for (int a = first; a < n; a += 6) {
        int v = group_value(s, a, a + 6);
        put_utf8(d, VTTS_LO_MILLION);
        if (v) {
            if (v > 1) below_million(d, v);
            else put_utf8(d, VTTS_LO_DIGITS[1]);
        }
    }
}

static void cardinal_i(kb_t *d, int v) {
    uint32_t b[12];
    int n = 0;
    do { b[n++] = (uint32_t)('0' + v % 10); v /= 10; } while (v && n < 11);
    for (int i = 0; i < n / 2; i++) { uint32_t t = b[i]; b[i] = b[n - 1 - i]; b[n - 1 - i] = t; }
    cardinal_u(d, b, n);
}

/* number(): commas dropped, leading '-' is ລົບ, "a.b" is cardinal(a) ຈຸດ digits(b) */
static void number(kb_t *d, const scratch_t *x, const uint32_t *s, int n) {
    int k = 0, i = 0, na = 0;
    while (k < n && s[k] == ',') k++;
    int neg = k < n && s[k] == '-';
    while (i < n && (s[i] == ',' || s[i] == '-')) i++;
    for (; i < n && s[i] != '.'; i++) {
        if (s[i] == ',') continue;
        if (na >= x->cap) { d->err = 1; return; }
        x->a[na++] = s[i];
    }
    if (neg) put_utf8(d, "ລົບ");
    cardinal_u(d, x->a, na);
    if (i < n) { /* s[i] == '.' */
        put_utf8(d, "ຈຸດ");
        digits(d, s + i + 1, n - i - 1);
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
        int k = i + r, m = 0;
        while (AT(s, n, k, ',') && DG(s, n, k + 1) && DG(s, n, k + 2) && DG(s, n, k + 3)) { k += 4; m++; }
        for (int g = m; g >= 1; g--) if ((e = try_frac(s, n, i + r + 4 * g, ok, u)) >= 0) return e;
    }
    for (int k = r; k >= 1; k--) if ((e = try_frac(s, n, i + k, ok, u)) >= 0) return e;
    return -1;
}

static int always(const uint32_t *s, int n, int end, void *u) { (void)s; (void)n; (void)end; (void)u; return 1; }
static int not_digit(const uint32_t *s, int n, int end, void *u) { (void)u; return !DG(s, n, end); }

/* ---- passes, in the order of normalize_lo ---- */

static void p_translate(const uint32_t *s, int n, kb_t *d) { /* Lao digits, full-width forms */
    for (int i = 0; i < n; i++) {
        uint32_t c = s[i];
        if (c >= 0x0ED0 && c <= 0x0ED9) c = '0' + (c - 0x0ED0);
        else if (c >= 0xFF01 && c < 0xFF5F) c -= 0xFEE0;
        put(d, c);
    }
}

static void p_pause(const uint32_t *s, int n, kb_t *d) { /* …+ | —+ | –(?!\d) | \.{3,} -> " , " */
    for (int i = 0; i < n;) {
        int j = i;
        if (s[i] == 0x2026 || s[i] == 0x2014) {
            while (j < n && s[j] == s[i]) j++;
        } else if (s[i] == 0x2013 && !DG(s, n, i + 1)) {
            j = i + 1;
        } else if (s[i] == '.') {
            while (j < n && s[j] == '.') j++;
            if (j - i < 3) j = i;
        }
        if (j > i) { put_utf8(d, " , "); i = j; continue; }
        put(d, s[i++]);
    }
}

static void p_drop(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n; i++) {
        uint32_t c = s[i];
        for (int k = 0; k < VTTS_LO_N_DROP; k++) if (VTTS_LO_DROP[k] == c) { c = ' '; break; }
        put(d, c);
    }
}

static void p_replace(const uint32_t *s, int n, kb_t *d, const char *key, const char *val) { /* str.replace */
    for (int i = 0; i < n;) {
        int l = key_at(s, n, i, key);
        if (l) { put_utf8(d, val); i += l; continue; }
        put(d, s[i++]);
    }
}

static void p_abbrev(const uint32_t *s, int n, kb_t *d) { /* (?<![LAO.])(ຄ.ສ.|...) -> glued */
    for (int i = 0; i < n;) {
        if (!LA(s, n, i - 1) && !AT(s, n, i - 1, '.')) {
            int l = 0, k = 0;
            for (; k < VTTS_LO_N_ABBREV && !l; k++) l = key_at(s, n, i, VTTS_LO_ABBREV[k][0]);
            if (l) {
                put(d, GLUE);
                put_utf8(d, VTTS_LO_ABBREV[k - 1][1]);
                put(d, GLUE);
                i += l;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static void p_drop_char(const uint32_t *s, int n, kb_t *d, uint32_t c) {
    for (int i = 0; i < n; i++) if (s[i] != c) put(d, s[i]);
}

static void p_repeat(const uint32_t *s, int n, kb_t *d) { /* \s*ໆ\s* -> ໆ */
    const uint32_t rep = 0x0EC6;
    for (int i = 0; i < n;) {
        int j = i;
        while (SP(s, n, j)) j++;
        if (AT(s, n, j, rep)) {
            put(d, rep);
            j++;
            while (SP(s, n, j)) j++;
            i = j;
            continue;
        }
        if (j > i) { put_cps(d, s + i, j - i); i = j; continue; }
        put(d, s[i++]);
    }
}

/* (?<![A-Za-z0-9])(?=[A-Z0-9]*[A-Z])(?=[A-Z0-9]*[0-9])[A-Z0-9]+(?![A-Za-z0-9]) -> letters in
 * English, digit runs one by one in Lao */
static void p_code(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (!AN(s, n, i - 1) && (UP(s, n, i) || A9(s, n, i))) {
            int j = i, up = 0, dg = 0;
            while (UP(s, n, j) || A9(s, n, j)) { up |= UP(s, n, j); dg |= A9(s, n, j); j++; }
            if (up && dg && !AN(s, n, j)) {
                put(d, ' ');
                for (int k = i; k < j;) {
                    if (UP(s, n, k)) { put(d, ' '); put(d, s[k] | 32); put(d, ' '); k++; continue; }
                    int r = k;
                    while (A9(s, n, r)) r++;
                    put(d, GLUE);
                    digits(d, s + k, r - k);
                    put(d, GLUE);
                    k = r;
                }
                put(d, ' ');
                i = j;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static void date_words(kb_t *d, int day, int month, const uint32_t *y, int ny) {
    put(d, GLUE);
    cardinal_i(d, day);
    put_utf8(d, VTTS_LO_MONTHS[month]);
    if (ny == 4) cardinal_u(d, y, ny);
    else digits(d, y, ny);
    put(d, GLUE);
}

/* (?<![\d/])(\d{1,2})/(\d{1,2})/(\d{4}|\d{2})(?![\d/]) -> day month year (unchanged when invalid) */
static void p_date_dmy(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i) && !DG(s, n, i - 1) && !AT(s, n, i - 1, '/')) {
            int r1 = digit_run(s, n, i), p = i + r1 + 1;
            int r2 = digit_run(s, n, p), q = p + r2 + 1;
            int r3 = digit_run(s, n, q);
            if (r1 <= 2 && AT(s, n, i + r1, '/') && r2 >= 1 && r2 <= 2 && AT(s, n, p + r2, '/') && (r3 == 2 || r3 == 4) &&
                !AT(s, n, q + r3, '/')) {
                int day = group_value(s, i, i + r1), month = group_value(s, p, p + r2);
                if (month >= 1 && month <= 12 && day >= 1 && day <= 31) date_words(d, day, month, s + q, r3);
                else put_cps(d, s + i, q + r3 - i);
                i = q + r3;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![\d-])(\d{4})-(\d{1,2})-(\d{1,2})(?![\d-]) */
static void p_date_iso(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i) && !DG(s, n, i - 1) && !AT(s, n, i - 1, '-')) {
            int r1 = digit_run(s, n, i), p = i + r1 + 1;
            int r2 = digit_run(s, n, p), q = p + r2 + 1;
            int r3 = digit_run(s, n, q);
            if (r1 == 4 && AT(s, n, i + 4, '-') && r2 >= 1 && r2 <= 2 && AT(s, n, p + r2, '-') && r3 >= 1 && r3 <= 2 &&
                !AT(s, n, q + r3, '-')) {
                int day = group_value(s, q, q + r3), month = group_value(s, p, p + r2);
                if (month >= 1 && month <= 12 && day >= 1 && day <= 31) date_words(d, day, month, s + i, 4);
                else put_cps(d, s + i, q + r3 - i);
                i = q + r3;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int two(const uint32_t *s, int i) { return dval(s[i]) * 10 + dval(s[i + 1]); }

/* (?<![\d:.])([01]?\d|2[0-4]):([0-5]\d)(?::([0-5]\d))?(?![\d:]) */
static void p_time(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i) && !DG(s, n, i - 1) && !AT(s, n, i - 1, ':') && !AT(s, n, i - 1, '.')) {
            int hl[3], nh = 0, done = 0;
            if ((s[i] == '0' || s[i] == '1') && DG(s, n, i + 1)) hl[nh++] = 2; /* [01]\d */
            hl[nh++] = 1;                                                    /* \d */
            if (s[i] == '2' && RG(s, n, i + 1, '0', '4')) hl[nh++] = 2;       /* 2[0-4] */
            for (int c = 0; c < nh && !done; c++) {
                int j = i + hl[c], end = -1, sec = -1;
                if (!(AT(s, n, j, ':') && RG(s, n, j + 1, '0', '5') && DG(s, n, j + 2))) continue;
                int k = j + 3;
                if (AT(s, n, k, ':') && RG(s, n, k + 1, '0', '5') && DG(s, n, k + 2) && !DG(s, n, k + 3) &&
                    !AT(s, n, k + 3, ':')) {
                    sec = two(s, k + 1);
                    end = k + 3;
                } else if (!DG(s, n, k) && !AT(s, n, k, ':')) {
                    end = k;
                }
                if (end < 0) continue;
                int h = hl[c] == 2 ? two(s, i) : dval(s[i]), mi = two(s, j + 1);
                put(d, GLUE);
                cardinal_i(d, h);
                put_utf8(d, "ໂມງ");
                if (mi) { cardinal_i(d, mi); put_utf8(d, "ນາທີ"); }
                if (sec > 0) { cardinal_i(d, sec); put_utf8(d, "ວິນາທີ"); }
                put(d, GLUE);
                i = end;
                done = 1;
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

/* ([₭$€£¥฿])\s?(NUM) -> glued number currency */
static void p_money(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        const char *name = NULL;
        for (int k = 0; k < VTTS_LO_N_CURRENCY; k++) if (VTTS_LO_CURRENCY[k].cp == s[i]) name = VTTS_LO_CURRENCY[k].name;
        if (name) {
            for (int sp = SP(s, n, i + 1); sp >= 0; sp--) {
                int j = i + 1 + sp, e = num_match(s, n, j, always, NULL);
                if (e < 0) continue;
                put(d, GLUE);
                number(d, x, s + j, e - j);
                put_utf8(d, name);
                put(d, GLUE);
                i = e;
                name = NULL;
                break;
            }
            if (!name) continue;
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

/* (-?)(NUM)\s?% -> glued [ລົບ] number ເປີເຊັນ */
static void p_percent(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        int pe = 0, e = -1, j = i;
        for (int neg = AT(s, n, i, '-'); neg >= 0 && e < 0; neg--) { j = i + neg; e = num_match(s, n, j, pct_ok, &pe); }
        if (e >= 0) {
            put(d, GLUE);
            if (j > i) put_utf8(d, "ລົບ");
            number(d, x, s + j, e - j);
            put_utf8(d, "ເປີເຊັນ");
            put(d, GLUE);
            i = pe;
            continue;
        }
        put(d, s[i++]);
    }
}

typedef struct { int end, unit; } unit_m;

static int unit_ok(const uint32_t *s, int n, int end, void *u) { /* \s?(units)(?![A-Za-z]) */
    unit_m *m = u;
    for (int sp = SP(s, n, end); sp >= 0; sp--) {
        int p = end + sp;
        for (int k = 0; k < VTTS_LO_N_UNITS; k++) {
            int l = key_at(s, n, p, VTTS_LO_UNITS[k][0]);
            if (l && !AZ(s, n, p + l)) { m->end = p + l; m->unit = k; return 1; }
        }
    }
    return 0;
}

/* (?<![\w.,])(-?)(NUM)\s?(km|kg|...)(?![A-Za-z]) -> glued [ລົບ] number unit */
static void p_unit(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        if (!W(s, n, i - 1) && !AT(s, n, i - 1, '.') && !AT(s, n, i - 1, ',')) {
            unit_m m = {0, 0};
            int e = -1, j = i;
            for (int neg = AT(s, n, i, '-'); neg >= 0 && e < 0; neg--) { j = i + neg; e = num_match(s, n, j, unit_ok, &m); }
            if (e >= 0) {
                put(d, GLUE);
                if (j > i) put_utf8(d, "ລົບ");
                number(d, x, s + j, e - j);
                put_utf8(d, VTTS_LO_UNITS[m.unit][1]);
                put(d, GLUE);
                i = m.end;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int sep_at(const uint32_t *s, int n, int i) { return SP(s, n, i) || AT(s, n, i, '-'); }

static int phone_rest(const uint32_t *s, int n, int p) { /* (?:[\s-]\d{3,4}){2}(?![\d-]) */
    for (int a = 4; a >= 3; a--) {
        if (!sep_at(s, n, p) || !digits_at(s, n, p + 1, a)) continue;
        int q = p + 1 + a;
        for (int b = 4; b >= 3; b--) {
            if (!sep_at(s, n, q) || !digits_at(s, n, q + 1, b)) continue;
            int e = q + 1 + b;
            if (!DG(s, n, e) && !AT(s, n, e, '-')) return e;
        }
    }
    return -1;
}

static int phone_core(const uint32_t *s, int n, int p) { /* 0?\d{1,2} + rest */
    for (int z = AT(s, n, p, '0'); z >= 0; z--)
        for (int k = 2; k >= 1; k--) {
            if (!digits_at(s, n, p + z, k)) continue;
            int e = phone_rest(s, n, p + z + k);
            if (e >= 0) return e;
        }
    return -1;
}

/* PHONE: (?:\+\d{1,3}[\s-]?)?0?\d{1,2}(?:[\s-]\d{3,4}){2}(?![\d-]) | 0\d{1,2}-\d{3,4}-?\d{0,4}(?![\d-]) */
static int phone_match(const uint32_t *s, int n, int i) {
    if (AT(s, n, i, '+'))
        for (int c = 3; c >= 1; c--) {
            if (!digits_at(s, n, i + 1, c)) continue;
            int q = i + 1 + c;
            for (int sp = sep_at(s, n, q); sp >= 0; sp--) {
                int e = phone_core(s, n, q + sp);
                if (e >= 0) return e;
            }
        }
    int e = phone_core(s, n, i);
    if (e >= 0) return e;
    if (!AT(s, n, i, '0')) return -1;
    for (int a = 2; a >= 1; a--) {
        if (!digits_at(s, n, i + 1, a) || !AT(s, n, i + 1 + a, '-')) continue;
        int p = i + 2 + a;
        for (int b = 4; b >= 3; b--) {
            if (!digits_at(s, n, p, b)) continue;
            int q = p + b;
            for (int h = AT(s, n, q, '-'); h >= 0; h--)
                for (int c = 4; c >= 0; c--) {
                    int r = q + h;
                    if (!digits_at(s, n, r, c)) continue;
                    if (!DG(s, n, r + c) && !AT(s, n, r + c, '-')) return r + c;
                }
        }
    }
    return -1;
}

static void p_phone(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if ((AT(s, n, i, '+') || DG(s, n, i)) && !DG(s, n, i - 1) && !AT(s, n, i - 1, '.') && !AT(s, n, i - 1, ',') &&
            !AT(s, n, i - 1, '-')) {
            int e = phone_match(s, n, i);
            if (e >= 0) {
                put(d, GLUE);
                digits(d, s + i, e - i);
                put(d, GLUE);
                i = e;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static int range_ok(const uint32_t *s, int n, int end, void *u) { /* \s?[-–]\s?(?=\d) */
    int *pe = u;
    for (int sp = SP(s, n, end); sp >= 0; sp--) {
        int k = end + sp;
        if (!(AT(s, n, k, '-') || AT(s, n, k, 0x2013))) continue;
        k++;
        if (SP(s, n, k) && DG(s, n, k + 1)) { *pe = k + 1; return 1; }
        if (DG(s, n, k)) { *pe = k; return 1; }
    }
    return 0;
}

/* (?<![\d.,])(NUM)\s?[-–]\s?(?=\d) -> glued number ຫາ */
static void p_range(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        if (!DG(s, n, i - 1) && !AT(s, n, i - 1, '.') && !AT(s, n, i - 1, ',')) {
            int pe = 0, e = num_match(s, n, i, range_ok, &pe);
            if (e >= 0) {
                put(d, GLUE);
                number(d, x, s + i, e - i);
                put_utf8(d, "ຫາ");
                put(d, GLUE);
                i = pe;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static void p_negative(const uint32_t *s, int n, kb_t *d) { /* (?<![\w\d])-(?=\d) -> glued ລົບ */
    for (int i = 0; i < n; i++) {
        if (s[i] == '-' && !W(s, n, i - 1) && !DG(s, n, i - 1) && DG(s, n, i + 1)) {
            put(d, GLUE);
            put_utf8(d, "ລົບ");
            put(d, GLUE);
            continue;
        }
        put(d, s[i]);
    }
}

static int long_ok(const uint32_t *s, int n, int e) { /* (?![\d.,]\d) */
    return !((DG(s, n, e) || AT(s, n, e, '.') || AT(s, n, e, ',')) && DG(s, n, e + 1));
}

/* (?<![\d.,])(?:0\d{2,}|\d{8,})(?![\d.,]\d) -> digits one by one */
static void p_long_digits(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i) && !DG(s, n, i - 1) && !AT(s, n, i - 1, '.') && !AT(s, n, i - 1, ',')) {
            int r = digit_run(s, n, i), e = -1;
            if (s[i] == '0') for (int k = r; k >= 3 && e < 0; k--) if (long_ok(s, n, i + k)) e = i + k;
            if (e < 0) for (int k = r; k >= 8 && e < 0; k--) if (long_ok(s, n, i + k)) e = i + k;
            if (e >= 0) {
                put(d, GLUE);
                digits(d, s + i, e - i);
                put(d, GLUE);
                i = e;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

/* (?<![\d.,])(NUM)(?![\d]) -> glued number */
static void p_number(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        if (!DG(s, n, i - 1) && !AT(s, n, i - 1, '.') && !AT(s, n, i - 1, ',')) {
            int e = num_match(s, n, i, not_digit, NULL);
            if (e >= 0) {
                put(d, GLUE);
                number(d, x, s + i, e - i);
                put(d, GLUE);
                i = e;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static void p_symbols(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n; i++) {
        int k = 0;
        while (k < VTTS_LO_N_SYMBOLS && VTTS_LO_SYMBOLS[k].cp != s[i]) k++;
        if (k == VTTS_LO_N_SYMBOLS) { put(d, s[i]); continue; }
        if (VTTS_LO_SYMBOLS[k].glue) put(d, GLUE);
        put_utf8(d, VTTS_LO_SYMBOLS[k].text);
        if (VTTS_LO_SYMBOLS[k].glue) put(d, GLUE);
    }
}

/* [A-Za-z][A-Za-z']* -> " " + normalize_en(word) + " " */
static void p_latin(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        if (AZ(s, n, i)) {
            int j = i + 1;
            while (AZ(s, n, j) || AT(s, n, j, '\'')) j++;
            int m = vtts_en_normalize(s + i, j - i, x->a, x->b, x->cap, x->out, x->out_cap);
            if (m < 0) { d->err = 1; return; }
            put(d, ' ');
            for (int k = 0; k < m; k++) put(d, (uint8_t)x->out[k]);
            put(d, ' ');
            i = j;
            continue;
        }
        put(d, s[i++]);
    }
}

static void p_glue_space(const uint32_t *s, int n, kb_t *d) { /* \s*\x01\s* -> \x01 */
    for (int i = 0; i < n;) {
        int j = i;
        while (SP(s, n, j)) j++;
        if (AT(s, n, j, GLUE)) {
            put(d, GLUE);
            j++;
            while (SP(s, n, j)) j++;
            i = j;
            continue;
        }
        if (j > i) { put_cps(d, s + i, j - i); i = j; continue; }
        put(d, s[i++]);
    }
}

static void p_lao_space(const uint32_t *s, int n, kb_t *d) { /* (?<=[LAO])\s+(?=[LAO]) -> " , " */
    for (int i = 0; i < n;) {
        if (SP(s, n, i) && LA(s, n, i - 1)) {
            int j = i;
            while (SP(s, n, j)) j++;
            if (LA(s, n, j)) { put_utf8(d, " , "); i = j; continue; }
        }
        put(d, s[i++]);
    }
}

static int is_mark(uint32_t c) { return c == ',' || c == '.' || c == '?' || c == '!' || c == ';' || c == ':'; }

/* findall([LAO]+|[a-z][a-z']*|[,.?!;:]) joined by single spaces; a mark after a mark is dropped */
static void p_words(const uint32_t *s, int n, kb_t *d) {
    int any = 0, last_mark = 0;
    for (int i = 0; i < n;) {
        int j = i;
        if (LA(s, n, i)) {
            while (LA(s, n, j)) j++;
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

int vtts_lo_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, uint32_t *ea,
                      uint32_t *eb, int ecap, char *eout, int eout_cap, const uint32_t **out) {
    kb_t x = {a, 0, cap, 0}, y = {b, 0, cap, 0};
    scratch_t e = {ea, eb, ecap, eout, eout_cap};
    p_translate(in, n, &x);
    if (x.err) return -1;
#define PASS(call) do { y.n = 0; call; if (y.err) return -1; kb_t t_ = x; x = y; y = t_; } while (0)
    PASS(p_pause(x.p, x.n, &y));
    PASS(p_drop(x.p, x.n, &y));
    for (int k = 0; k < VTTS_LO_N_ABBREV_PLAIN; k++)
        PASS(p_replace(x.p, x.n, &y, VTTS_LO_ABBREV_PLAIN[k][0], VTTS_LO_ABBREV_PLAIN[k][1]));
    PASS(p_abbrev(x.p, x.n, &y));
    PASS(p_drop_char(x.p, x.n, &y, 0x0EAF)); /* any other ຯ */
    PASS(p_repeat(x.p, x.n, &y));
    PASS(p_code(x.p, x.n, &y));
    PASS(p_date_dmy(x.p, x.n, &y));
    PASS(p_date_iso(x.p, x.n, &y));
    PASS(p_time(x.p, x.n, &y));
    PASS(p_money(x.p, x.n, &y, &e));
    PASS(p_percent(x.p, x.n, &y, &e));
    PASS(p_unit(x.p, x.n, &y, &e));
    PASS(p_phone(x.p, x.n, &y));
    PASS(p_range(x.p, x.n, &y, &e));
    PASS(p_negative(x.p, x.n, &y));
    PASS(p_long_digits(x.p, x.n, &y));
    PASS(p_number(x.p, x.n, &y, &e));
    PASS(p_symbols(x.p, x.n, &y));
    PASS(p_latin(x.p, x.n, &y, &e));
    PASS(p_glue_space(x.p, x.n, &y));
    PASS(p_lao_space(x.p, x.n, &y));
    PASS(p_drop_char(x.p, x.n, &y, GLUE));
    PASS(p_words(x.p, x.n, &y));
#undef PASS
    *out = x.p;
    return x.n;
}

#endif /* VTTS_ENABLE_LO */
