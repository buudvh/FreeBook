/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_th.c -- Thai front-end of the device (token set th-en): word segmentation over the
 * word list, syllables by the lowest-cost split over the spelling patterns, consonant classes and
 * tones (mirrors src/vtts/frontend/th/g2p_th.py), and normalization (mirrors
 * src/vtts/frontend/th/normalize_th.py). All tables are in the generated vtts_text_th_tables.h
 * (Thai letters coded as code point - 0x0E00); no blob is needed. */
#include "vtts_langs.h"
#if VTTS_ENABLE_TH /* else an empty unit (vtts_langs.h) */

#include "vtts_text_th.h"

#include <string.h>

#include "vtts_text_en.h"
#include "vtts_text_th_tables.h"

int vtts_th_is_thai(uint32_t c) { return c >= 0x0E01 && c <= 0x0E4E; }

int vtts_th_has_thai(const uint32_t *w, int n) {
    for (int i = 0; i < n; i++) if (vtts_th_is_thai(w[i])) return 1;
    return 0;
}

/* ======================= spelling rules (g2p_th.py) ======================= */

/* letter codes used by the rules */
enum {
    T_THO_THAN = 0x10, /* ฐ */
    T_THO = 0x17,      /* ท */
    T_BO = 0x1A,       /* บ */
    T_PHO = 0x1E,      /* พ */
    T_YO = 0x22,       /* ย */
    T_RO = 0x23,       /* ร */
    T_RUE = 0x24,      /* ฤ */
    T_LUE = 0x26,      /* ฦ */
    T_HO = 0x2B,       /* ห */
    T_O = 0x2D,        /* อ */
    T_SARA_A_HAT = 0x31, /* ั */
    T_SARA_I = 0x34,   /* ิ */
    T_SARA_II = 0x35,  /* ี */
    T_SARA_U = 0x38,   /* ุ */
    T_SARA_UU = 0x39,  /* ู */
    T_PHINTHU = 0x3A,  /* ฺ */
    T_SARA_E = 0x40,   /* เ */
    T_LAKKHANG = 0x45, /* ๅ */
    T_REPEAT = 0x46,   /* ๆ */
    T_EK = 0x48, T_THO_MARK = 0x49, T_TRI = 0x4A, T_CHATTAWA = 0x4B,
    T_THANTHAKHAT = 0x4C, /* ์ */
    T_YAMAKKAN = 0x4E  /* ๎ */
};
enum { CLS_M = 0, CLS_H = 1, CLS_L = 2 };
enum { KIND_X = 0, KIND_O = 1, KIND_A = 2 };

#define CLASS_BITS (VTTS_TH_MID | VTTS_TH_HIGH | VTTS_TH_LOW)

static int has(uint8_t c, unsigned flag) { return c < 0x80 && (VTTS_TH_LETTERS[c].flags & flag) != 0; }
static int is_class(uint8_t c) { return has(c, CLASS_BITS); }
static int cls_of(uint8_t c) { return has(c, VTTS_TH_MID) ? CLS_M : has(c, VTTS_TH_HIGH) ? CLS_H : CLS_L; }
static uint8_t ini_of(uint8_t c) { return VTTS_TH_LETTERS[c & 0x7F].initial; }
static uint8_t fin_of(uint8_t c) { return c < 0x80 ? VTTS_TH_LETTERS[c].final : 0; }
static int dep(uint8_t c) { return has(c, VTTS_TH_DEPENDENT); }
static int i_or_u(uint8_t c) { return c == T_SARA_I || c == T_SARA_U; }

typedef struct {
    uint8_t ini[2], nini, cls, vowel, fin, mark, shrt, kind, lone, coda;
} syl_t; /* fin: final code (index + 1, 0 none); lone, coda, mark: letter codes (0 none) */

typedef struct { int16_t end, cost; uint8_t n; syl_t s[2]; } step_t;
#define MAX_STEPS 64

typedef struct { int32_t a; int16_t b, c; uint8_t f, valid; } dp_t;

typedef struct {
    uint8_t codes[VTTS_TH_MAX_RUN + 1];
    uint8_t sil[VTTS_TH_MAX_RUN + 1];
    dp_t dp[VTTS_TH_MAX_RUN + 1];
    int16_t outer[VTTS_TH_MAX_RUN + 2], inner[VTTS_TH_MAX_RUN + 2], path[VTTS_TH_MAX_RUN + 1];
    step_t steps[MAX_STEPS];
} th_scratch_t;

typedef struct {
    th_scratch_t *t;
    syl_t *buf; /* the syllables of the last word (ๆ repeats them) */
    int cap;
    vtts_th_syl_cb cb;
    void *user;
    int count, have_out;
    uint8_t last_coda;
} th_ctx_t;

static syl_t mk(const uint8_t *ini, int nini, int cls, int vowel, int fin, int mark, int shrt, int kind, int lone,
                int coda) {
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
    s.lone = (uint8_t)lone;
    s.coda = (uint8_t)coda;
    return s;
}

static int tone_of(const syl_t *s) {
    int live = s->fin ? (VTTS_TH_LIVE_FINALS >> s->fin) & 1 : !s->shrt;
    switch (s->mark) {
    case T_EK: return s->cls == CLS_L ? 3 : 2;
    case T_THO_MARK: return s->cls == CLS_L ? 4 : 3;
    case T_TRI: return 4;
    case T_CHATTAWA: return 5;
    default: break;
    }
    if (s->cls == CLS_L) return live ? 1 : (s->shrt ? 4 : 3);
    if (!live) return 2;
    return s->cls == CLS_H ? 5 : 1;
}

static int syl_ids(const syl_t *s, uint8_t *out) {
    int n = 0;
    for (int k = 0; k < s->nini; k++) out[n++] = (uint8_t)(VTTS_THEN_I0 + s->ini[k]);
    out[n++] = (uint8_t)(VTTS_THEN_V0 + s->vowel);
    if (s->fin) out[n++] = (uint8_t)(VTTS_THEN_F0 + s->fin - 1);
    out[n++] = (uint8_t)(VTTS_THEN_T1 + tone_of(s) - 1);
    return n;
}

typedef struct { int end; uint8_t ini[2]; int nini, cls, has_lead, extra; syl_t lead; } init_t;

static int is_cluster(uint8_t a, uint8_t b) {
    for (int k = 0; k < VTTS_TH_N_CLUSTERS; k++)
        if ((uint8_t)VTTS_TH_CLUSTERS[2 * k] == a && (uint8_t)VTTS_TH_CLUSTERS[2 * k + 1] == b) return 1;
    return 0;
}

/* _initials: (end, sounds, class, syllable split off before, extra cost) for the initial at w[k] */
static int initials(const uint8_t *w, int n, int k, int split, init_t *o) {
    uint8_t c = w[k];
    int m = 0;
    memset(o, 0, 3 * sizeof *o);
    o[m].end = k + 1; o[m].ini[0] = ini_of(c); o[m].nini = 1; o[m].cls = cls_of(c); m++;
    if (k + 1 >= n || !is_class(w[k + 1])) return m;
    uint8_t c2 = w[k + 1];
    if (is_cluster(c, c2)) {
        o[m].end = k + 2; o[m].ini[0] = ini_of(c); o[m].ini[1] = ini_of(c2); o[m].nini = 2; o[m].cls = cls_of(c);
        o[m].extra = -1; m++;
    } else if (c2 == T_RO && has(c, VTTS_TH_SILENT_R)) {
        o[m].end = k + 2; o[m].ini[0] = ini_of(c); o[m].nini = 1; o[m].cls = cls_of(c); m++;
    } else if (c2 == T_RO && c == T_THO) {
        o[m].end = k + 2; o[m].ini[0] = VTTS_TH_I_s; o[m].nini = 1; o[m].cls = CLS_L; m++;
    }
    if (c == T_HO && has(c2, VTTS_TH_LOW_SONORANT)) {
        o[m].end = k + 2; o[m].ini[0] = ini_of(c2); o[m].nini = 1; o[m].cls = CLS_H; m++;
    } else if (split) { /* preposed vowel before a leading consonant: เสมอ = ส(a) + เมอ */
        uint8_t i1 = ini_of(c);
        o[m].lead = mk(&i1, 1, cls_of(c), VTTS_TH_V_a, 0, 0, 1, KIND_A, c, 0);
        o[m].has_lead = 1;
        o[m].cls = has(c2, VTTS_TH_LOW_SONORANT) && cls_of(c) != CLS_L ? cls_of(c) : cls_of(c2);
        o[m].end = k + 2; o[m].ini[0] = ini_of(c2); o[m].nini = 1;
        o[m].extra = VTTS_TH_COST_SYLLABLE + VTTS_TH_COST_UNWRITTEN_A + VTTS_TH_COST_SPLIT_LEAD;
        m++;
    }
    return m;
}

/* _take: letters at w[pos], one tone mark allowed after the initial or an above/below vowel */
static int take(const uint8_t *w, int n, int pos, const char *letters, uint8_t *mark) {
    if (!*mark && pos < n && has(w[pos], VTTS_TH_TONE_MARK)) *mark = w[pos++];
    for (const char *p = letters; *p; p++) {
        uint8_t ch = (uint8_t)*p;
        if (pos >= n || w[pos] != ch) return -1;
        pos++;
        if (has(ch, VTTS_TH_ABOVE_BELOW) && !*mark && pos < n && has(w[pos], VTTS_TH_TONE_MARK)) *mark = w[pos++];
    }
    return pos;
}

static int final_at(const uint8_t *w, int n, int pos) {
    if (pos >= n || !fin_of(w[pos])) return 0;
    if (pos + 1 < n && dep(w[pos + 1])) return 0;
    return fin_of(w[pos]);
}

static int closed_next(const uint8_t *w, int n, int pos, uint8_t pre) {
    if (pos + 1 >= n || !is_class(w[pos])) return 0;
    uint8_t c = w[pos + 1];
    return c == T_O || (pre == T_SARA_E && c == T_SARA_I) || (fin_of(c) && (pos + 2 >= n || !dep(w[pos + 2])));
}

static void push(step_t *st, int *m, int end, const syl_t *before, const syl_t *a, const syl_t *b, int cost) {
    if (*m >= MAX_STEPS) return;
    step_t *s = &st[(*m)++];
    s->end = (int16_t)end;
    s->cost = (int16_t)cost;
    s->n = 0;
    if (before) s->s[s->n++] = *before;
    s->s[s->n++] = *a;
    if (b && s->n < 2) s->s[s->n++] = *b; /* a lead and two syllables never occur together */
}

/* _rue: ฤ alone r + ue (ฤๅ: uue), after a consonant C + r + i (พฤ: ph + r + ue); ฦ: l + ue */
static int rue(const uint8_t *w, int n, int i, uint8_t head, step_t *st) {
    int m = 0, pos = i + 1;
    uint8_t letter = w[i], ini[2];
    int lng = pos < n && w[pos] == T_LAKKHANG, nini, cls, vowel;
    pos += lng;
    if (!head) {
        ini[0] = letter == T_RUE ? VTTS_TH_I_r : VTTS_TH_I_l;
        nini = 1; cls = CLS_L;
        vowel = lng ? VTTS_TH_V_uue : VTTS_TH_V_ue;
    } else {
        ini[0] = ini_of(head); ini[1] = VTTS_TH_I_r;
        nini = 2; cls = cls_of(head);
        vowel = head == T_PHO ? VTTS_TH_V_ue : VTTS_TH_V_i;
    }
    syl_t s = mk(ini, nini, cls, vowel, 0, 0, !lng, KIND_X, 0, 0);
    push(st, &m, pos, NULL, &s, NULL, VTTS_TH_COST_SYLLABLE);
    int f = final_at(w, n, pos);
    if (f && !lng) {
        s = mk(ini, nini, cls, vowel, f, 0, 1, KIND_X, 0, w[pos]);
        push(st, &m, pos + 1, NULL, &s, NULL, VTTS_TH_COST_SYLLABLE);
    }
    return m;
}

/* syllables_at: every (end, syllables, cost) that can start at w[i] */
static int syllables_at(const uint8_t *w, int n, int i, step_t *st) {
    int m = 0;
    uint8_t pre = has(w[i], VTTS_TH_PREPOSED) ? w[i] : 0;
    int k = i + (pre != 0);
    if (k >= n) return 0;
    if ((w[k] == T_RUE || w[k] == T_LUE) && !pre) return rue(w, n, i, 0, st);
    if (!is_class(w[k])) return 0;
    if (!pre && k + 1 < n && w[k + 1] == T_RUE) return rue(w, n, i + 1, w[k], st);
    init_t in[3];
    int ni = initials(w, n, k, pre != 0, in);
    for (int q = 0; q < ni; q++) {
        const init_t *I = &in[q];
        const syl_t *before = I->has_lead ? &I->lead : NULL;
        for (int v = 0; v < VTTS_TH_N_VOWELS; v++) {
            if (VTTS_TH_VOWELS[v].pre != pre) continue;
            const char *letters = VTTS_TH_VOWELS[v].letters;
            uint8_t mark = 0;
            int pos = take(w, n, I->end, letters, &mark);
            if (pos < 0) continue;
            int shrt = VTTS_TH_VOWELS[v].shrt, vowel = VTTS_TH_VOWELS[v].vowel, kind = VTTS_TH_VOWELS[v].kind;
            int cost = VTTS_TH_COST_SYLLABLE + I->extra, nl = (int)strlen(letters);
            if (kind == 3) {
                syl_t s = mk(I->ini, I->nini, I->cls, vowel, VTTS_TH_VOWELS[v].eq, mark, shrt, KIND_X, 0, 0);
                push(st, &m, pos, before, &s, NULL, cost);
                continue;
            }
            if (kind == 0 || kind == 2) {
                if (pre && !nl && closed_next(w, n, pos, pre)) cost += VTTS_TH_COST_OPEN_PREPOSED; /* เสมอ: not เส-มอ */
                syl_t s = mk(I->ini, I->nini, I->cls, vowel, 0, mark, shrt, KIND_X, 0, 0);
                push(st, &m, pos, before, &s, NULL, cost);
            }
            if (kind == 1 || kind == 2) {
                int hat = nl == 1 && (uint8_t)letters[0] == T_SARA_A_HAT;
                int f = final_at(w, n, pos);
                if (hat && f == VTTS_TH_F_w) f = 0; /* ัว is the vowel ua (ตัว), never a + w */
                if (f && !(pre == T_SARA_E && !nl && w[pos] == T_YO)) { /* เ-ย is ooe + j */
                    syl_t s = mk(I->ini, I->nini, I->cls, vowel, f, mark, shrt, KIND_X, 0, w[pos]);
                    push(st, &m, pos + 1, before, &s, NULL, cost);
                } else if (hat && pos + 2 < n && fin_of(w[pos]) && i_or_u(w[pos + 1]) && !dep(w[pos + 2])) {
                    uint8_t c = w[pos], ci = ini_of(c); /* บัติ inside a word: bat + ti (ปฏิบัติการ) */
                    syl_t s1 = mk(I->ini, I->nini, I->cls, vowel, fin_of(c), mark, shrt, KIND_X, 0, 0);
                    syl_t s2 = mk(&ci, 1, cls_of(c), w[pos + 1] == T_SARA_I ? VTTS_TH_V_i : VTTS_TH_V_u, 0, 0, 1,
                                  KIND_X, 0, 0);
                    push(st, &m, pos + 2, before, &s1, &s2, cost + VTTS_TH_COST_SYLLABLE);
                }
            }
        }
        if (pre) continue;
        /* no written vowel: closed -> o (oor before a final ร), open -> a */
        int pos = I->end;
        uint8_t mark = 0;
        if (pos < n && has(w[pos], VTTS_TH_TONE_MARK)) mark = w[pos++];
        int f = final_at(w, n, pos);
        if (f) {
            syl_t s = w[pos] == T_RO ? mk(I->ini, I->nini, I->cls, VTTS_TH_V_oor, VTTS_TH_F_n, mark, 0, KIND_O, 0, T_RO)
                                     : mk(I->ini, I->nini, I->cls, VTTS_TH_V_o, f, mark, 1, KIND_O, 0, w[pos]);
            push(st, &m, pos + 1, NULL, &s, NULL, VTTS_TH_COST_SYLLABLE + VTTS_TH_COST_UNWRITTEN_O + I->extra);
        }
        if (I->nini == 1 && I->end == k + 1 && !mark) {
            syl_t s = w[k] == T_BO ? mk(I->ini, 1, I->cls, VTTS_TH_V_oor, 0, 0, 0, KIND_A, 0, 0) /* บ alone is บอ */
                                   : mk(I->ini, 1, I->cls, VTTS_TH_V_a, 0, 0, 1, KIND_A, w[k], 0);
            push(st, &m, I->end, NULL, &s, NULL, VTTS_TH_COST_SYLLABLE + VTTS_TH_COST_UNWRITTEN_A);
        }
    }
    return m;
}

/* silence (in place): letters that are not pronounced; returns the new length */
static int silence(uint8_t *w, int n) {
    int m = 0, o = 0;
    for (int i = 0; i < n; i++) if (w[i] != T_PHINTHU && w[i] != T_YAMAKKAN) w[m++] = w[i];
    for (int i = 0; i < m; i++) {
        uint8_t ch = w[i];
        if (ch != T_THANTHAKHAT) { w[o++] = ch; continue; }
        if (o && i_or_u(w[o - 1])) o--;
        if (o && is_class(w[o - 1])) {
            uint8_t popped = w[--o];
            if (popped == T_RO && o >= 2 && is_class(w[o - 1]) && w[o - 1] != T_O && is_class(w[o - 2])) o--;
        }
    }
    n = o;
    if (n >= 3 && i_or_u(w[n - 1]) && fin_of(w[n - 2]) && w[n - 3] == T_SARA_A_HAT) n--; /* ปฏิบัติ */
    if (n >= 3 && w[n - 1] == T_RO && ((VTTS_TH_STOP_FINALS >> fin_of(w[n - 2])) & 1) && fin_of(w[n - 2]) &&
        (w[n - 3] == T_SARA_A_HAT || w[n - 3] == T_SARA_I || w[n - 3] == T_SARA_II || w[n - 3] == T_SARA_U ||
         w[n - 3] == T_SARA_UU || (n >= 4 && has(w[n - 4], VTTS_TH_PREPOSED))))
        n--; /* บุตร, เมตร */
    return n;
}

static int sonorant(uint8_t ini) { return (VTTS_TH_SONORANT_INITIALS >> ini) & 1; }

/* _link and _leading over out[start, no); returns the new count */
static int link_leading(syl_t *out, int start, int no, int cap) {
    int m = 0;
    for (int k = start; k + 1 < no; k++) m += out[k].coda && has(out[k].coda, VTTS_TH_LINKING);
    if (m && no + m <= cap) { /* a final ฐ ฒ ษ ศ ธ ฏ inside a word is also read as an initial with a */
        int dst = no + m - 1;
        for (int k = no - 1; k >= start; k--) {
            if (k + 1 < no && out[k].coda && has(out[k].coda, VTTS_TH_LINKING)) {
                uint8_t c = out[k].coda, ci = ini_of(c);
                out[dst--] = mk(&ci, 1, cls_of(c), VTTS_TH_V_a, 0, 0, 1, KIND_A, 0, 0);
            }
            out[dst--] = out[k];
        }
        no += m;
    }
    for (int k = start; k + 1 < no; k++) { /* leading consonant: สนุก, ขนม, อร่อย */
        syl_t *a = &out[k], *b = &out[k + 1];
        if (a->kind == KIND_A && a->lone && a->cls != CLS_L && b->cls == CLS_L && b->nini == 1 && sonorant(b->ini[0]))
            b->cls = a->cls;
    }
    return no;
}

/* parse_word: syllables of one word by the lowest-cost split, appended to out[no..cap) */
static int parse_word(th_scratch_t *t, const uint8_t *src, int n, syl_t *out, int no, int cap) {
    uint8_t *w = t->sil;
    dp_t *best = t->dp;
    memmove(w, src, (size_t)n);
    for (;;) {
        n = silence(w, n);
        for (int j = 0; j <= n; j++) best[j].valid = 0;
        best[0].a = 0; best[0].b = -1; best[0].c = 0; best[0].f = 0; best[0].valid = 1;
        for (int i = 0; i < n; i++) {
            if (!best[i].valid) continue;
            int ns = syllables_at(w, n, i, t->steps);
            step_t fb;
            memset(&fb, 0, sizeof fb);
            fb.end = (int16_t)(i + 1);
            fb.cost = 100;
            const step_t *st = ns ? t->steps : &fb;
            for (int k = 0; k < (ns ? ns : 1); k++) {
                int j = st[k].end, cost = st[k].cost;
                if (j < n && dep(w[j])) continue;
                if (j == n && st[k].n && st[k].s[st[k].n - 1].kind == KIND_A && (best[i].f || st[k].n > 1))
                    cost += VTTS_TH_COST_WORD_FINAL_A;
                int32_t total = best[i].a + cost;
                if (!best[j].valid || total < best[j].a) {
                    best[j].a = total; best[j].b = (int16_t)i; best[j].c = (int16_t)k;
                    best[j].f = (uint8_t)(best[i].f || st[k].n > 0); best[j].valid = 1;
                }
            }
        }
        int ok = best[n].valid, end = n;
        if (!ok) { /* a dependent sign with nothing before it: skip it */
            end = 0;
            for (int i = 0; i < n; i++) if (best[i].valid) end = i;
        }
        int np = 0, start = no;
        for (int j = end; j > 0; j = best[j].b) t->path[np++] = (int16_t)j;
        for (int q = np - 1; q >= 0; q--) {
            int j = t->path[q], i = best[j].b, k = best[j].c;
            int ns = syllables_at(w, n, i, t->steps);
            if (k >= ns) continue; /* the fallback step: no syllable */
            for (int s = 0; s < t->steps[k].n && no < cap; s++) out[no++] = t->steps[k].s[s];
        }
        if (ok) return link_leading(out, start, no, cap);
        if (end + 1 >= n) return no;
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

/* front-coded word at off into buf (which holds the previous word); returns the next offset */
static int decode_word(int off, uint8_t *buf, int *len) {
    int p = VTTS_TH_WORDS[off++] & 0x7F;
    while (VTTS_TH_WORDS[off] < 0x80) buf[p++] = VTTS_TH_WORDS[off++];
    *len = p;
    return off;
}

/* the smallest listed word >= key into buf; 0 when there is none */
static int lower_bound(const uint8_t *key, int lk, uint8_t *buf, int *len) {
    uint8_t tmp[VTTS_TH_MAX_WORD + 1];
    int lo = 0, hi = VTTS_TH_N_BLOCKS - 1, b = -1, lt;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        decode_word((int)VTTS_TH_BLOCKS[mid], tmp, &lt);
        if (cmp_codes(tmp, lt, key, lk) <= 0) { b = mid; lo = mid + 1; } else hi = mid - 1;
    }
    if (b < 0) { decode_word(0, buf, len); return 1; }
    int off = (int)VTTS_TH_BLOCKS[b];
    int end = b + 1 < VTTS_TH_N_BLOCKS ? (int)VTTS_TH_BLOCKS[b + 1] : VTTS_TH_WORDS_BYTES - 1;
    while (off < end) {
        off = decode_word(off, buf, len);
        if (cmp_codes(buf, *len, key, lk) >= 0) return 1;
    }
    if (b + 1 < VTTS_TH_N_BLOCKS) { decode_word((int)VTTS_TH_BLOCKS[b + 1], buf, len); return 1; }
    return 0;
}

static const char *find_override(const uint8_t *w, int n) {
    for (int k = 0; k < VTTS_TH_N_OVERRIDES; k++) {
        const char *key = VTTS_TH_OVERRIDES[k].word;
        if ((int)strlen(key) == n && memcmp(key, w, (size_t)n) == 0) return VTTS_TH_OVERRIDES[k].reading;
    }
    return NULL;
}

/* ends j of the listed words run[i:j] (dict 0: the word list and respelled words; 1: respelled words) */
static int dict_ends(const uint8_t *run, int n, int i, int dict, int *ends) {
    int m = 0;
    if (dict) {
        for (int k = 0; k < VTTS_TH_N_OVERRIDES && m < VTTS_TH_MAX_WORD; k++) {
            const char *key = VTTS_TH_OVERRIDES[k].word;
            int l = (int)strlen(key);
            if (l <= n - i && memcmp(key, run + i, (size_t)l) == 0) ends[m++] = i + l;
        }
        return m;
    }
    uint8_t buf[VTTS_TH_MAX_WORD + 1];
    int lim = n - i < VTTS_TH_MAX_WORD ? n - i : VTTS_TH_MAX_WORD, len;
    for (int l = 1; l <= lim; l++) {
        if (!lower_bound(run + i, l, buf, &len)) break;
        if (len < l || memcmp(buf, run + i, (size_t)l) != 0) break; /* no word starts with run[i:i+l] */
        if (len == l) ends[m++] = i + l;
    }
    return m;
}

/* _after_silent: j moved past letters silenced by ์ that follow it (การณ์, จันทร์) */
static int after_silent(const uint8_t *run, int n, int j) {
    for (int k = j + 1; k <= j + 3; k++) {
        if (k >= n || run[k] != T_THANTHAKHAT) continue;
        int all = 1;
        for (int q = j; q < k && all; q++) all = is_class(run[q]) || i_or_u(run[q]);
        if (all) return k + 1;
    }
    return j;
}

/* segment: cut points (np + 1, ascending) of the words of run; returns np */
static int segment(th_scratch_t *t, const uint8_t *run, int n, int dict, int16_t *cuts) {
    dp_t *best = t->dp; /* a: characters outside the list, b: pieces, c: start, f: piece is outside */
    for (int j = 0; j <= n; j++) best[j].valid = 0;
    best[0].a = 0; best[0].b = 0; best[0].c = 0; best[0].f = 0; best[0].valid = 1;
    int ends[VTTS_TH_MAX_WORD + MAX_STEPS + 2], us[VTTS_TH_MAX_WORD + MAX_STEPS + 2]; /* word ends, then syllables */
    for (int i = 0; i < n; i++) {
        if (!best[i].valid || dep(run[i])) continue;
        int32_t unk = best[i].a;
        int cnt = best[i].b, nc = dict_ends(run, n, i, dict, ends), nu = nc;
        for (int q = 0; q < nc; q++) us[q] = 0;
        int ns = syllables_at(run, n, i, t->steps);
        if (!ns) { ends[nu] = i + 1; us[nu++] = 1; }
        for (int q = 0; q < ns; q++) { /* a lone consonant outside the list counts 3: คาก is not คา + ก */
            int j = after_silent(run, n, t->steps[q].end);
            if (nu >= (int)(sizeof ends / sizeof *ends)) break;
            ends[nu] = j;
            us[nu++] = j - i + 2 * (t->steps[q].s[0].kind == KIND_A);
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
        int lone = unknown && j == i + 1 && is_class(run[i]);
        if (np > 1 && unknown && (last_flag || lone)) { cuts[np - 1] = (int16_t)i; last_flag = 1; }
        else { cuts[np++] = (int16_t)i; last_flag = unknown; }
        j = i;
    }
    for (int a = 0, b = np - 1; a < b; a++, b--) { int16_t x = cuts[a]; cuts[a] = cuts[b]; cuts[b] = x; }
    return np - 1;
}

/* read_respelling: one syllable per piece (pieces separated by 0x7F) */
static int read_respelling(th_scratch_t *t, const char *r, syl_t *out, int no, int cap) {
    while (*r) {
        const uint8_t *p = (const uint8_t *)r;
        int lp = 0;
        while (p[lp] && p[lp] != 0x7F) lp++;
        int ns = lp ? syllables_at(p, lp, 0, t->steps) : 0, pick = -1;
        for (int k = 0; k < ns; k++) {
            if (t->steps[k].end != lp || t->steps[k].n != 1) continue;
            if (pick < 0 || (t->steps[pick].s[0].kind != KIND_X && t->steps[k].s[0].kind == KIND_X)) pick = k;
        }
        if (pick >= 0) { if (no < cap) out[no++] = t->steps[pick].s[0]; }
        else no = parse_word(t, p, lp, out, no, cap);
        r += lp + (p[lp] == 0x7F);
    }
    return no;
}

/* word_syllables: a respelled word, or the rules with the respelled words inside it */
static int word_syllables(th_scratch_t *t, const uint8_t *w, int n, syl_t *out, int cap) {
    const char *r = find_override(w, n);
    if (r) return read_respelling(t, r, out, 0, cap);
    int np = segment(t, w, n, 1, t->inner);
    if (np == 1) return parse_word(t, w, n, out, 0, cap);
    int no = 0;
    for (int q = 0; q < np; q++) {
        int a = t->inner[q], b = t->inner[q + 1];
        r = find_override(w + a, b - a);
        no = r ? read_respelling(t, r, out, no, cap) : parse_word(t, w + a, b - a, out, no, cap);
    }
    return no;
}

static void emit(th_ctx_t *c, const syl_t *s) {
    uint8_t ids[8];
    int n = syl_ids(s, ids);
    c->cb(c->user, ids, n);
    c->count++;
    c->have_out = 1;
    c->last_coda = s->coda;
}

/* run_syllables over codes[0, n): ๆ repeats the word before it */
static void read_run(th_ctx_t *c, const uint8_t *run, int n) {
    th_scratch_t *t = c->t;
    int nlast = 0, piece = 0;
    for (int s = 0, p = 0; p <= n; p++) {
        if (p < n && run[p] != T_REPEAT) continue;
        if (piece++ > 0) for (int k = 0; k < nlast; k++) emit(c, &c->buf[k]);
        if (p > s) {
            int nw = segment(t, run + s, p - s, 0, t->outer);
            for (int q = 0; q < nw; q++) {
                if (c->have_out && c->last_coda == T_THO_THAN) { /* รัฐ + another word: rat-tha (รัฐสภา) */
                    uint8_t th = VTTS_TH_I_th;
                    syl_t x = mk(&th, 1, CLS_H, VTTS_TH_V_a, 0, 0, 1, KIND_A, 0, 0);
                    emit(c, &x);
                }
                int a = s + t->outer[q], b = s + t->outer[q + 1];
                nlast = word_syllables(t, run + a, b - a, c->buf, c->cap);
                for (int k = 0; k < nlast; k++) emit(c, &c->buf[k]);
            }
        }
        s = p + 1;
    }
}

int vtts_th_read(const char *utf8, void *sa, size_t na, void *sb, size_t nb, vtts_th_syl_cb cb, void *user) {
    if (!utf8 || !sa || !sb || !cb || na < sizeof(th_scratch_t) || nb < 64 * sizeof(syl_t)) return -1;
    th_ctx_t c = {(th_scratch_t *)sa, (syl_t *)sb, (int)(nb / sizeof(syl_t)), cb, user, 0, 0, 0};
    const unsigned char *p = (const unsigned char *)utf8;
    int n = 0;
    while (*p) { /* UTF-8 -> letter codes; a Thai word holds U+0E01..U+0E4E only */
        uint32_t cp = *p;
        int extra = cp < 0x80 ? 0 : (cp >> 5) == 6 ? 1 : (cp >> 4) == 14 ? 2 : (cp >> 3) == 30 ? 3 : 0;
        if (extra) cp &= 0x3Fu >> extra;
        p++;
        for (int k = 0; k < extra && (*p & 0xC0) == 0x80; k++) cp = (cp << 6) | (*p++ & 0x3F);
        if (!vtts_th_is_thai(cp)) continue;
        c.t->codes[n++] = (uint8_t)(cp - 0x0E00);
        if (n == VTTS_TH_MAX_RUN) { read_run(&c, c.t->codes, n); n = 0; }
    }
    if (n) read_run(&c, c.t->codes, n);
    return c.count;
}

/* ======================= normalization (normalize_th) =======================
 * Each regex pass of the Python normalizer is one function from buffer s (n code points) to buffer
 * d; matches are found left to right without overlap, like re.sub, and lookarounds look at the
 * pass's input. Where backtracking can change a match, the candidate ends are tried in the order
 * the regex engine tries them. */

#define GLUE 0x01u /* number words: spaces next to them are dropped */
#define TH_NO_NU 0x0E19u /* น */

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

static int DG(const uint32_t *s, int n, int i) { return i >= 0 && i < n && s[i] >= '0' && s[i] <= '9'; }
static int AZ(const uint32_t *s, int n, int i) { return i >= 0 && i < n && (s[i] | 32) >= 'a' && (s[i] | 32) <= 'z'; }
static int UP(const uint32_t *s, int n, int i) { return i >= 0 && i < n && s[i] >= 'A' && s[i] <= 'Z'; }
static int AN(const uint32_t *s, int n, int i) { return DG(s, n, i) || AZ(s, n, i); } /* [A-Za-z0-9] */
static int SP(const uint32_t *s, int n, int i) { return i >= 0 && i < n && vtts_cp_is_space(s[i]); }
static int AT(const uint32_t *s, int n, int i, uint32_t c) { return i >= 0 && i < n && s[i] == c; }
static int RG(const uint32_t *s, int n, int i, uint32_t lo, uint32_t hi) { return i >= 0 && i < n && s[i] >= lo && s[i] <= hi; }
static int TH(const uint32_t *s, int n, int i) { return i >= 0 && i < n && vtts_th_is_thai(s[i]); }
static int W(const uint32_t *s, int n, int i) { /* Python \w */
    if (i < 0 || i >= n) return 0;
    uint32_t c = s[i];
    if (c >= 0x0E00 && c < 0x0E80) return (VTTS_TH_LETTERS[c - 0x0E00].flags & VTTS_TH_WORD) != 0;
    return vtts_cp_is_word(c);
}
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
    for (int i = 0; i < n; i++) if (s[i] >= '0' && s[i] <= '9') put_utf8(d, VTTS_TH_DIGITS[s[i] - '0']);
}

/* _below_million(v, final_one=True), v = 1..999999 */
static void below_million(kb_t *d, int v) {
    int ds[6], nd = 0, any = 0;
    for (int x = v; x; x /= 10) ds[nd++] = x % 10;
    for (int place = nd - 1; place >= 0; place--) {
        int dg = ds[place];
        if (!dg) continue;
        if (place == 1) {
            if (dg == 2) put_utf8(d, "ยี่");
            else if (dg != 1) put_utf8(d, VTTS_TH_DIGITS[dg]);
            put_utf8(d, VTTS_TH_PLACES[1]);
        } else if (place == 0) {
            put_utf8(d, dg == 1 && v > 1 && any ? "เอ็ด" : VTTS_TH_DIGITS[dg]);
        } else {
            put_utf8(d, VTTS_TH_DIGITS[dg]);
            put_utf8(d, VTTS_TH_PLACES[place]);
        }
        any = 1;
    }
}

static int group_value(const uint32_t *s, int a, int b) {
    int v = 0;
    for (int i = a; i < b; i++) v = v * 10 + (int)(s[i] - '0');
    return v;
}

/* cardinal(int(s)) for ASCII digits: groups of six digits joined by ล้าน */
static void cardinal_u(kb_t *d, const uint32_t *s, int n) {
    while (n > 0 && *s == '0') { s++; n--; }
    if (!n) { put_utf8(d, VTTS_TH_DIGITS[0]); return; }
    int first = (n - 1) % 6 + 1;
    below_million(d, group_value(s, 0, first));
    for (int a = first; a < n; a += 6) {
        int v = group_value(s, a, a + 6);
        put_utf8(d, VTTS_TH_MILLION);
        if (v) {
            if (v > 1) below_million(d, v);
            else put_utf8(d, VTTS_TH_DIGITS[1]);
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

/* number(): commas dropped, leading '-' is ลบ, "a.b" is cardinal(a) จุด digits(b) */
static void number(kb_t *d, const scratch_t *x, const uint32_t *s, int n) {
    int k = 0, i = 0, na = 0;
    while (k < n && s[k] == ',') k++;
    int neg = k < n && s[k] == '-'; /* s.replace(",", "").startswith("-"), then lstrip("-") */
    while (i < n && (s[i] == ',' || s[i] == '-')) i++;
    for (; i < n && s[i] != '.'; i++) {
        if (s[i] == ',') continue;
        if (na >= x->cap) { d->err = 1; return; }
        x->a[na++] = s[i];
    }
    if (neg) put_utf8(d, "ลบ");
    cardinal_u(d, x->a, na);
    if (i < n) { /* s[i] == '.' */
        put_utf8(d, "จุด");
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
    if (r <= 3) { /* \d{1,3}(?:,\d{3})+ (a shorter first part would be followed by a digit) */
        int k = i + r, m = 0;
        while (AT(s, n, k, ',') && DG(s, n, k + 1) && DG(s, n, k + 2) && DG(s, n, k + 3)) { k += 4; m++; }
        for (int g = m; g >= 1; g--) if ((e = try_frac(s, n, i + r + 4 * g, ok, u)) >= 0) return e;
    }
    for (int k = r; k >= 1; k--) if ((e = try_frac(s, n, i + k, ok, u)) >= 0) return e;
    return -1;
}

static int always(const uint32_t *s, int n, int end, void *u) { (void)s; (void)n; (void)end; (void)u; return 1; }
static int not_digit(const uint32_t *s, int n, int end, void *u) { (void)u; return !DG(s, n, end); }

/* ---- passes, in the order of normalize_th ---- */

static void p_translate(const uint32_t *s, int n, kb_t *d) { /* Thai digits, full-width forms */
    for (int i = 0; i < n; i++) {
        uint32_t c = s[i];
        if (c >= 0x0E50 && c <= 0x0E59) c = '0' + (c - 0x0E50);
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
        for (int k = 0; k < VTTS_TH_N_DROP; k++) if (VTTS_TH_DROP[k] == c) { c = ' '; break; }
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

static void p_abbrev(const uint32_t *s, int n, kb_t *d) { /* (?<![ก-๎.])(พ.ศ.|...) -> glued */
    for (int i = 0; i < n;) {
        if (!TH(s, n, i - 1) && !AT(s, n, i - 1, '.')) {
            int l = 0, k = 0;
            for (; k < VTTS_TH_N_ABBREV && !l; k++) l = key_at(s, n, i, VTTS_TH_ABBREV[k][0]);
            if (l) {
                put(d, GLUE);
                put_utf8(d, VTTS_TH_ABBREV[k - 1][1]);
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

static void p_repeat(const uint32_t *s, int n, kb_t *d) { /* \s*ๆ\s* -> ๆ */
    const uint32_t mai = 0x0E46;
    for (int i = 0; i < n;) {
        int j = i;
        while (SP(s, n, j)) j++;
        if (AT(s, n, j, mai)) {
            put(d, mai);
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
 * English, digit runs one by one in Thai */
static void p_code(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (!AN(s, n, i - 1) && (UP(s, n, i) || DG(s, n, i))) {
            int j = i, up = 0, dg = 0;
            while (UP(s, n, j) || DG(s, n, j)) { up |= UP(s, n, j); dg |= DG(s, n, j); j++; }
            if (up && dg && !AN(s, n, j)) {
                put(d, ' ');
                for (int k = i; k < j;) {
                    if (UP(s, n, k)) { put(d, ' '); put(d, s[k] | 32); put(d, ' '); k++; continue; }
                    int r = digit_run(s, n, k);
                    put(d, GLUE);
                    digits(d, s + k, r);
                    put(d, GLUE);
                    k += r;
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
    put_utf8(d, VTTS_TH_MONTHS[month]);
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

static int two(const uint32_t *s, int i) { return (int)(s[i] - '0') * 10 + (int)(s[i + 1] - '0'); }

/* \s*น\. after a time at q: its end, or -1 */
static int nor_dot(const uint32_t *s, int n, int q) {
    while (SP(s, n, q)) q++;
    return AT(s, n, q, TH_NO_NU) && AT(s, n, q + 1, '.') ? q + 2 : -1;
}

/* (?<![\d:.])([01]?\d|2[0-4])(?::([0-5]\d)(?::([0-5]\d))?(?![\d:])(?:\s*น\.)?|\.([0-5]\d)\s*น\.) */
static void p_time(const uint32_t *s, int n, kb_t *d) {
    for (int i = 0; i < n;) {
        if (DG(s, n, i) && !DG(s, n, i - 1) && !AT(s, n, i - 1, ':') && !AT(s, n, i - 1, '.')) {
            int hl[3], nh = 0, done = 0;
            if ((s[i] == '0' || s[i] == '1') && DG(s, n, i + 1)) hl[nh++] = 2; /* [01]\d */
            hl[nh++] = 1;                                                    /* \d */
            if (s[i] == '2' && RG(s, n, i + 1, '0', '4')) hl[nh++] = 2;       /* 2[0-4] */
            for (int c = 0; c < nh && !done; c++) {
                int j = i + hl[c], end = -1, sec = -1;
                if (AT(s, n, j, ':') && RG(s, n, j + 1, '0', '5') && DG(s, n, j + 2)) {
                    int k = j + 3;
                    if (AT(s, n, k, ':') && RG(s, n, k + 1, '0', '5') && DG(s, n, k + 2) && !DG(s, n, k + 3) &&
                        !AT(s, n, k + 3, ':')) {
                        sec = two(s, k + 1);
                        end = k + 3;
                    } else if (!DG(s, n, k) && !AT(s, n, k, ':')) {
                        end = k;
                    }
                    if (end >= 0) {
                        int e = nor_dot(s, n, end);
                        if (e >= 0) end = e;
                    }
                }
                if (end < 0 && AT(s, n, j, '.') && RG(s, n, j + 1, '0', '5') && DG(s, n, j + 2)) end = nor_dot(s, n, j + 3);
                if (end < 0) continue;
                int h = hl[c] == 2 ? two(s, i) : (int)(s[i] - '0'), mi = two(s, j + 1);
                put(d, GLUE);
                cardinal_i(d, h);
                put_utf8(d, "นาฬิกา");
                if (mi) { cardinal_i(d, mi); put_utf8(d, "นาที"); }
                if (sec > 0) { cardinal_i(d, sec); put_utf8(d, "วินาที"); }
                put(d, GLUE);
                i = end;
                done = 1;
            }
            if (done) continue;
        }
        put(d, s[i++]);
    }
}

/* ([฿$€£¥])\s?(NUM) -> glued number currency */
static void p_money(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        const char *name = NULL;
        for (int k = 0; k < VTTS_TH_N_CURRENCY; k++) if (VTTS_TH_CURRENCY[k].cp == s[i]) name = VTTS_TH_CURRENCY[k].name;
        if (name) {
            int j = i + 1;
            if (SP(s, n, j)) j++;
            int e = num_match(s, n, j, always, NULL);
            if (e >= 0) {
                put(d, GLUE);
                number(d, x, s + j, e - j);
                put_utf8(d, name);
                put(d, GLUE);
                i = e;
                continue;
            }
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

/* (-?)(NUM)\s?% -> glued [ลบ] number เปอร์เซ็นต์ */
static void p_percent(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        int j = i + AT(s, n, i, '-'), pe = 0;
        int e = num_match(s, n, j, pct_ok, &pe);
        if (e >= 0) {
            put(d, GLUE);
            if (j > i) put_utf8(d, "ลบ");
            number(d, x, s + j, e - j);
            put_utf8(d, "เปอร์เซ็นต์");
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
    int p = end + SP(s, n, end);
    for (int k = 0; k < VTTS_TH_N_UNITS; k++) {
        int l = key_at(s, n, p, VTTS_TH_UNITS[k][0]);
        if (l && !AZ(s, n, p + l)) { m->end = p + l; m->unit = k; return 1; }
    }
    return 0;
}

/* (?<![\w.,])(-?)(NUM)\s?(km|kg|...)(?![A-Za-z]) -> glued [ลบ] number unit */
static void p_unit(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        if (!W(s, n, i - 1) && !AT(s, n, i - 1, '.') && !AT(s, n, i - 1, ',')) {
            int j = i + AT(s, n, i, '-');
            unit_m m = {0, 0};
            int e = num_match(s, n, j, unit_ok, &m);
            if (e >= 0) {
                put(d, GLUE);
                if (j > i) put_utf8(d, "ลบ");
                number(d, x, s + j, e - j);
                put_utf8(d, VTTS_TH_UNITS[m.unit][1]);
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
    int *pe = u, k;
    if (SP(s, n, end) && (AT(s, n, end + 1, '-') || AT(s, n, end + 1, 0x2013))) k = end + 2;
    else if (AT(s, n, end, '-') || AT(s, n, end, 0x2013)) k = end + 1;
    else return 0;
    if (SP(s, n, k) && DG(s, n, k + 1)) { *pe = k + 1; return 1; }
    if (DG(s, n, k)) { *pe = k; return 1; }
    return 0;
}

/* (?<![\d.,])(NUM)\s?[-–]\s?(?=\d) -> glued number ถึง */
static void p_range(const uint32_t *s, int n, kb_t *d, const scratch_t *x) {
    for (int i = 0; i < n;) {
        if (!DG(s, n, i - 1) && !AT(s, n, i - 1, '.') && !AT(s, n, i - 1, ',')) {
            int pe = 0, e = num_match(s, n, i, range_ok, &pe);
            if (e >= 0) {
                put(d, GLUE);
                number(d, x, s + i, e - i);
                put_utf8(d, "ถึง");
                put(d, GLUE);
                i = pe;
                continue;
            }
        }
        put(d, s[i++]);
    }
}

static void p_negative(const uint32_t *s, int n, kb_t *d) { /* (?<![\w\d])-(?=\d) -> glued ลบ */
    for (int i = 0; i < n; i++) {
        if (s[i] == '-' && !W(s, n, i - 1) && !DG(s, n, i - 1) && DG(s, n, i + 1)) {
            put(d, GLUE);
            put_utf8(d, "ลบ");
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
        while (k < VTTS_TH_N_SYMBOLS && VTTS_TH_SYMBOLS[k].cp != s[i]) k++;
        if (k == VTTS_TH_N_SYMBOLS) { put(d, s[i]); continue; }
        if (VTTS_TH_SYMBOLS[k].glue) put(d, GLUE);
        put_utf8(d, VTTS_TH_SYMBOLS[k].text);
        if (VTTS_TH_SYMBOLS[k].glue) put(d, GLUE);
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

static void p_thai_space(const uint32_t *s, int n, kb_t *d) { /* (?<=[ก-๎])\s+(?=[ก-๎]) -> " , " */
    for (int i = 0; i < n;) {
        if (SP(s, n, i) && TH(s, n, i - 1)) {
            int j = i;
            while (SP(s, n, j)) j++;
            if (TH(s, n, j)) { put_utf8(d, " , "); i = j; continue; }
        }
        put(d, s[i++]);
    }
}

static int is_mark(uint32_t c) { return c == ',' || c == '.' || c == '?' || c == '!' || c == ';' || c == ':'; }

/* findall([ก-๎]+|[a-z][a-z']*|[,.?!;:]) joined by single spaces; a mark after a mark is dropped */
static void p_words(const uint32_t *s, int n, kb_t *d) {
    int any = 0, last_mark = 0;
    for (int i = 0; i < n;) {
        int j = i;
        if (TH(s, n, i)) {
            while (TH(s, n, j)) j++;
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

int vtts_th_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, uint32_t *ea,
                      uint32_t *eb, int ecap, char *eout, int eout_cap, const uint32_t **out) {
    kb_t x = {a, 0, cap, 0}, y = {b, 0, cap, 0};
    scratch_t e = {ea, eb, ecap, eout, eout_cap};
    p_translate(in, n, &x);
    if (x.err) return -1;
#define PASS(call) do { y.n = 0; call; if (y.err) return -1; kb_t t_ = x; x = y; y = t_; } while (0)
    PASS(p_pause(x.p, x.n, &y));
    PASS(p_drop(x.p, x.n, &y));
    for (int k = 0; k < VTTS_TH_N_ABBREV_PLAIN; k++)
        PASS(p_replace(x.p, x.n, &y, VTTS_TH_ABBREV_PLAIN[k][0], VTTS_TH_ABBREV_PLAIN[k][1]));
    PASS(p_abbrev(x.p, x.n, &y));
    PASS(p_drop_char(x.p, x.n, &y, 0x0E2F)); /* any other ฯ */
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
    PASS(p_thai_space(x.p, x.n, &y));
    PASS(p_drop_char(x.p, x.n, &y, GLUE));
    PASS(p_words(x.p, x.n, &y));
#undef PASS
    *out = x.p;
    return x.n;
}

#endif /* VTTS_ENABLE_TH */
