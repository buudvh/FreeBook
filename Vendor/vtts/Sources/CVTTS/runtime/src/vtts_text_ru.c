/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_ru.c -- Russian front-end of the device (token set ru-en): stress from the RLEX blob
 * (vtts_rlex.h), spelling, softness, vowel reduction and voicing rules (mirrors
 * src/vtts/frontend/ru/g2p_ru.py), and normalization (mirrors src/vtts/frontend/ru/normalize_ru.py).
 * The regex passes run the Python patterns themselves (parse trees in vtts_text_ru_tables.h, matched
 * by vtts_re.c); the replacement functions follow the Python ones line by line. */
#include "vtts_langs.h"
#if VTTS_ENABLE_RU /* else an empty unit (vtts_langs.h) */

#include "vtts_text_ru.h"

#include <string.h>

#include "vtts_re.h"
#include "vtts_text_en.h"
#include "vtts_text_lt.h"
#include "vtts_text_ru_tables.h"

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

static int u8len(const char *s) { /* code points of a table string */
    int m = 0, l;
    uint32_t c;
    while ((l = dec1(s, &c)) > 0) { m++; s += l; }
    return m;
}

static int eq_u8(const uint32_t *w, int n, const char *k) { /* w (n code points) equals k */
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

int vtts_ru_has_cyrillic(const uint32_t *w, int n) {
    for (int i = 0; i < n; i++) if (w[i] >= 0x400 && w[i] <= 0x4FF) return 1;
    return 0;
}

int vtts_ru_latin_word(const uint32_t *w, int n) {
    return in_list(VTTS_RU_LATIN_WORDS, VTTS_N_RU_LATIN_WORDS, w, n);
}

/* ======================= output buffer ======================= */

typedef vtts_re_buf rb_t;

static void put(rb_t *d, uint32_t c) { if (d->n < d->cap) d->p[d->n++] = c; else d->err = 1; }
static void puts8(rb_t *d, const char *s) {
    uint32_t c;
    int l;
    while ((l = dec1(s, &c)) > 0) { put(d, c); s += l; }
}
static void putn(rb_t *d, const uint32_t *s, int n) { for (int i = 0; i < n; i++) put(d, s[i]); }

/* words joined by single spaces (" ".join) */
typedef struct { rb_t *d; int any; } wl_t;
static void wadd(wl_t *w, const char *s) {
    if (!*s) { if (w->any) put(w->d, ' '); w->any = 1; return; } /* an empty word still takes a space */
    if (w->any) put(w->d, ' ');
    puts8(w->d, s);
    w->any = 1;
}

/* ======================= g2p (g2p_ru.py) ======================= */

#define LET_A 0x430u
#define LET_YA 0x44Fu
#define LET_YO 0x451u
static int ru_letter(uint32_t c) { return (c >= LET_A && c <= LET_YA) || c == LET_YO; }
static int vowel_letter(uint32_t c) {
    switch (c) {
    case 0x430: case 0x435: case 0x451: case 0x438: case 0x43E: case 0x443: case 0x44B: case 0x44D: case 0x44E:
    case 0x44F: return 1;
    default: return 0;
    }
}
static int soft_vowel(uint32_t c) { return c == 0x435 || c == 0x451 || c == 0x438 || c == 0x44E || c == 0x44F; }
#define L_SOFT 0x44Cu /* ь */
#define L_HARD 0x44Au /* ъ */

static const char *fold_cp(uint32_t c) {
    int lo = 0, hi = VTTS_RU_N_FOLD - 1;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        if (VTTS_RU_FOLD[mid].cp == c) return VTTS_RU_FOLD[mid].to;
        if (VTTS_RU_FOLD[mid].cp < c) lo = mid + 1; else hi = mid - 1;
    }
    return NULL;
}

/* fold(): lower(), compose(), then each character kept (а-я ё - +), folded (VTTS_RU_FOLD) or dropped */
static int fold(const uint32_t *w, int n, uint32_t *o, int cap) {
    int m = 0;
    for (int i = 0; i < n; i++) {
        uint32_t c = w[i] == 0x130 ? 'i' : vtts_u_lower(w[i]);
        uint32_t next = i + 1 < n ? (w[i + 1] == 0x130 ? 'i' : vtts_u_lower(w[i + 1])) : 0;
        if (w[i] == 0x130) { /* lower() gives i + U+0307: neither is read */
            continue;
        }
        if (c == 0x435 && next == 0x308) { c = LET_YO; i++; }
        else if (c == 0x438 && next == 0x306) { c = 0x439; i++; }
        if (c == 0x301) continue;
        if (ru_letter(c) || c == '-' || c == '+') {
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

/* ---- phonemes as short strings (like Python) ---- */
typedef struct { char s[6]; } ph_t;

static void ph_set(ph_t *p, const char *s) {
    size_t l = strlen(s);
    if (l > 5) l = 5;
    memcpy(p->s, s, l);
    p->s[l] = 0;
}

static int in_strs(const char *const *list, int n, const char *s) {
    for (int i = 0; i < n; i++) if (strcmp(list[i], s) == 0) return 1;
    return 0;
}
static int paired(const char *s) { return in_strs(VTTS_RU_PAIRED, VTTS_N_RU_PAIRED, s); }

static const char *map2(const char *const (*t)[2], int n, const char *k) {
    for (int i = 0; i < n; i++) if (strcmp(t[i][0], k) == 0) return t[i][1];
    return NULL;
}

static const char *consonant_of(uint32_t c) {
    char k[5] = {0};
    if (!ru_letter(c)) return NULL;
    k[0] = (char)(0xC0 | (c >> 6));
    k[1] = (char)(0x80 | (c & 0x3F));
    return map2(VTTS_RU_CONSONANT, VTTS_N_RU_CONSONANT, k);
}
static const char *vowel_of(uint32_t c) {
    char k[5] = {0};
    if (!ru_letter(c)) return NULL;
    k[0] = (char)(0xC0 | (c >> 6));
    k[1] = (char)(0x80 | (c & 0x3F));
    return map2(VTTS_RU_VOWEL_OF, VTTS_N_RU_VOWEL_OF, k);
}

/* ---- stress (stressed) ---- */

static uint8_t lcode(uint32_t c) { return c == LET_YO ? 33 : (uint8_t)(c - LET_A + 1); }

/* the word (ё written е) as letter codes; 0 when a character is not a Russian letter */
static int keycodes(const uint32_t *w, int n, uint8_t *k) {
    for (int i = 0; i < n; i++) {
        uint32_t c = w[i] == LET_YO ? 0x435 : w[i];
        if (!ru_letter(c)) return 0;
        k[i] = lcode(c);
    }
    return 1;
}

static int is_unstressed(const uint32_t *w, int n) { return in_list(VTTS_RU_UNSTRESSED, VTTS_N_RU_UNSTRESSED, w, n); }

/* stressed(): writes the word with '+' before the stressed vowel into o (n + 1 code points) */
static int stressed(const vtts_rlex *lex, const uint32_t *w, int n, uint32_t *o) {
    int plus = -1, yo = -1;
    for (int i = 0; i < n; i++) {
        if (w[i] == '+') { memcpy(o, w, sizeof *w * (size_t)n); return n; }
        if (w[i] == LET_YO) yo = i;
    }
    memcpy(o, w, sizeof *w * (size_t)n);
    if (yo >= 0) {
        plus = yo;
    } else {
        uint8_t key[VTTS_RU_MAXW];
        const uint8_t *val = NULL;
        int ok = n <= VTTS_RU_MAXW && keycodes(w, n, key);
        if (lex && ok && n <= 255 && (vtts_rlex_find(lex, VTTS_RLEX_OVERRIDES, key, n, &val) >= 0 ||
                                     vtts_rlex_find(lex, VTTS_RLEX_WORDS, key, n, &val) >= 0)) {
            if (val[1] != 255 && val[1] < n) o[val[1]] = LET_YO;
            plus = val[0] < n ? val[0] : -1;
        } else {
            int vow[VTTS_RU_MAXW], nv = 0;
            for (int i = 0; i < n; i++) if (vowel_letter(w[i]) && nv < VTTS_RU_MAXW) vow[nv++] = i;
            if (!nv || is_unstressed(w, n)) return n;
            if (nv == 1) {
                plus = vow[0];
            } else {
                int back = lex ? (int)lex->root : 1;
                if (lex && ok) {
                    uint8_t rev[VTTS_RU_MAXW];
                    for (int i = 0; i < n; i++) rev[i] = key[n - 1 - i];
                    int longest = (int)lex->max_suffix < n ? (int)lex->max_suffix : n;
                    for (int l = longest; l > 0; l--) {
                        const uint8_t *v = NULL;
                        if (vtts_rlex_find(lex, VTTS_RLEX_SUFFIXES, rev, l, &v) >= 0) { back = v[0]; break; }
                    }
                }
                int k = nv - 1 - back;
                plus = vow[k < 0 ? 0 : k];
            }
        }
    }
    if (plus < 0) return n;
    memmove(o + plus + 1, o + plus, sizeof *o * (size_t)(n - plus));
    o[plus] = '+';
    return n + 1;
}

/* ---- spelling (_spelling) ---- */

#define re_sub vtts_re_sub
static void sub_lit(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)s; (void)n; (void)m;
    const char *rep = u;
    puts8(d, rep);
}

static void sub_go(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) { /* в\1 */
    (void)n; (void)u;
    put(d, 0x432);
    putn(d, s + m->gs[1], m->ge[1] - m->gs[1]);
}

static void sub_g1(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) { /* \1 */
    (void)n; (void)u;
    putn(d, s + m->gs[1], m->ge[1] - m->gs[1]);
}

/* replace the first occurrence of the two letters a b by c b' */
static void replace_first(uint32_t *w, int n, uint32_t a, uint32_t b, uint32_t c, uint32_t d) {
    for (int i = 0; i + 1 < n; i++)
        if (w[i] == a && w[i + 1] == b) { w[i] = c; w[i + 1] = d; return; }
}

static int spelling(uint32_t *w, int n, uint32_t *t, int cap) {
    uint32_t plain[VTTS_RU_MAXW + 2];
    int pn = 0, nv = 0;
    for (int i = 0; i < n && pn < VTTS_RU_MAXW + 2; i++) if (w[i] != '+') plain[pn++] = w[i];
    for (int i = 0; i < pn; i++) nv += vowel_letter(plain[i]);
    if (eq_u8(plain, pn, "что") || eq_u8(plain, pn, "чтобы") || eq_u8(plain, pn, "ничто") ||
        eq_u8(plain, pn, "кое-что") || starts_u8(plain, pn, "что"))
        replace_first(w, n, 0x447, 0x442, 0x448, 0x442); /* чт -> шт */
    for (int k = 0; k < VTTS_N_RU_CHN_SH; k++)
        if (starts_u8(plain, pn, VTTS_RU_CHN_SH[k])) { replace_first(w, n, 0x447, 0x43D, 0x448, 0x43D); break; }
    if (eq_u8(plain, pn, "сегодня") || starts_u8(plain, pn, "сегодняш"))
        for (int i = 0; i < n; i++) if (w[i] == 0x433) { w[i] = 0x432; break; }
    rb_t x = {t, 0, cap, 0}, y = {t + cap, 0, cap, 0};
    putn(&x, w, n);
    if ((ends_u8(plain, pn, "ого") || ends_u8(plain, pn, "его")) &&
        !in_list(VTTS_RU_GO_KEEP, VTTS_N_RU_GO_KEEP, plain, pn) && nv >= 2) {
        y.n = 0;
        re_sub(&VTTS_RU_RE_GO, x.p, x.n, &y, sub_go, NULL);
        rb_t s = x; x = y; y = s;
    }
    for (int k = 0; k < VTTS_RU_N_RULES; k++) {
        y.n = 0;
        re_sub(VTTS_RU_RULES_RE[k], x.p, x.n, &y, sub_lit, (void *)VTTS_RU_RULE_REP[k]);
        rb_t s = x; x = y; y = s;
    }
    y.n = 0;
    re_sub(&VTTS_RU_RE_DOUBLE, x.p, x.n, &y, sub_g1, NULL);
    if (y.err) return -1;
    int m = y.n < VTTS_RU_MAXW + 2 ? y.n : VTTS_RU_MAXW + 2;
    memcpy(w, y.p, sizeof *w * (size_t)m);
    return m;
}

/* ---- segments and reduction ---- */

typedef struct {
    char kind; /* 'C' or 'V' */
    char ph[6];
    uint8_t soft, stressed, soft_before, hush, final;
    uint32_t letter;
} seg_t;

static int segments(const uint32_t *w, int n, seg_t *S, int cap) {
    int ns = 0, stress_next = 0;
    uint32_t prev = 0; /* previous letter (0 at the start) */
    for (int i = 0; i < n; i++) {
        uint32_t ch = w[i];
        if (ch == '+') { stress_next = 1; continue; }
        if (ch == L_SOFT || ch == L_HARD) {
            if (ch == L_SOFT && ns && S[ns - 1].kind == 'C' && paired(S[ns - 1].ph)) S[ns - 1].soft = 1;
            prev = ch;
            continue;
        }
        if (vowel_letter(ch)) {
            if (ns + 2 > cap) break;
            char q[6];
            strcpy(q, vowel_of(ch));
            seg_t *last_c = ns && S[ns - 1].kind == 'C' && prev != L_SOFT && prev != L_HARD && prev != 0 &&
                            !vowel_letter(prev) ? &S[ns - 1] : NULL;
            if (((ch == 0x435 || ch == LET_YO || ch == 0x44E || ch == 0x44F) && !last_c) || (ch == 0x438 && prev == L_SOFT)) {
                seg_t *j = &S[ns++];
                memset(j, 0, sizeof *j);
                j->kind = 'C';
                strcpy(j->ph, "j");
                j->soft = 1;
                last_c = j;
            }
            if (last_c) {
                if (soft_vowel(ch) && paired(last_c->ph)) last_c->soft = 1;
                if ((!strcmp(last_c->ph, "zh") || !strcmp(last_c->ph, "sh") || !strcmp(last_c->ph, "ts")) && !strcmp(q, "i"))
                    strcpy(q, "y");
            }
            int soft = last_c && (last_c->soft || !strcmp(last_c->ph, "ch") || !strcmp(last_c->ph, "shch") ||
                                  !strcmp(last_c->ph, "j"));
            int hush = last_c && (!strcmp(last_c->ph, "zh") || !strcmp(last_c->ph, "sh") || !strcmp(last_c->ph, "ts"));
            seg_t *v = &S[ns++];
            memset(v, 0, sizeof *v);
            v->kind = 'V';
            strcpy(v->ph, q);
            v->stressed = (uint8_t)stress_next;
            v->soft_before = (uint8_t)soft;
            v->hush = (uint8_t)hush;
            v->letter = ch;
            stress_next = 0;
        } else {
            const char *c = consonant_of(ch);
            if (c) {
                if (ns + 1 > cap) break;
                seg_t *s = &S[ns++];
                memset(s, 0, sizeof *s);
                s->kind = 'C';
                strcpy(s->ph, c);
                s->soft = !strcmp(c, "ch") || !strcmp(c, "shch") || !strcmp(c, "j");
            }
        }
        prev = ch;
    }
    for (int k = ns - 1; k >= 0; k--) if (S[k].kind == 'V') { S[k].final = 1; break; }
    return ns;
}

static void cons_ph(const seg_t *s, ph_t *p) {
    ph_set(p, s->ph);
    if (s->soft && paired(s->ph)) { size_t l = strlen(p->s); p->s[l] = '\''; p->s[l + 1] = 0; }
}

static int reduce(const seg_t *S, int ns, ph_t *out) {
    int stress_at = 0, nv = 0, found = 0;
    for (int k = 0; k < ns; k++) if (S[k].kind == 'V') { if (S[k].stressed && !found) { stress_at = nv; found = 1; } nv++; }
    if (!found) stress_at = nv;
    int n = 0, vi = 0;
    for (int k = 0; k < ns; k++) {
        const seg_t *s = &S[k];
        if (s->kind == 'C') { cons_ph(s, &out[n++]); continue; }
        const char *q = s->ph;
        int idx = vi++;
        char buf[6];
        if (s->stressed) {
            size_t l = strlen(q);
            memcpy(buf, q, l);
            buf[l] = '1';
            buf[l + 1] = 0;
            ph_set(&out[n++], buf);
            continue;
        }
        if (!strcmp(q, "u") || !strcmp(q, "y") || (!strcmp(q, "i") && !s->soft_before)) {
            ph_set(&out[n++], !strcmp(q, "i") && s->hush ? "y" : q);
            continue;
        }
        int pretonic1 = idx == stress_at - 1, initial = k == 0;
        if (s->soft_before)
            ph_set(&out[n++], s->final && idx > stress_at && (s->letter == 0x44F || s->letter == 0x430) ? "@" : "i");
        else if (s->hush && !strcmp(q, "e"))
            ph_set(&out[n++], "y");
        else if (!strcmp(q, "e") || !strcmp(q, "i"))
            ph_set(&out[n++], "i");
        else
            ph_set(&out[n++], pretonic1 || initial ? "a" : "@");
    }
    return n;
}

/* ---- softness and voicing ---- */

static int is_vowel_ph(const char *p) { return strchr("aeiouy@", p[0]) != NULL; }

static void soften(ph_t *p, int n) {
    for (int k = n - 3; k >= 0; k--) {
        const char *nx = p[k + 1].s;
        if (!is_vowel_ph(p[k + 2].s)) continue;
        int sz = (!strcmp(p[k].s, "s") || !strcmp(p[k].s, "z")) &&
                 (!strcmp(nx, "t'") || !strcmp(nx, "d'") || !strcmp(nx, "n'"));
        int nn = !strcmp(p[k].s, "n") && (!strcmp(nx, "t'") || !strcmp(nx, "d'"));
        if (sz || nn) { size_t l = strlen(p[k].s); p[k].s[l] = '\''; p[k].s[l + 1] = 0; }
    }
}

static void base_of(const char *p, char *b, int *soft) {
    size_t l = strlen(p);
    *soft = l && p[l - 1] == '\'';
    memcpy(b, p, l - (size_t)*soft);
    b[l - (size_t)*soft] = 0;
}

static int is_obstruent(const char *b) { return in_strs(VTTS_RU_OBSTRUENTS, VTTS_N_RU_OBSTRUENTS, b); }
static const char *devoiced(const char *b) { return map2(VTTS_RU_VOICED, VTTS_N_RU_VOICED, b); } /* voiced -> voiceless */
static const char *voiced(const char *b) {
    for (int i = 0; i < VTTS_N_RU_VOICED; i++) if (!strcmp(VTTS_RU_VOICED[i][1], b)) return VTTS_RU_VOICED[i][0];
    return NULL;
}

static void voicing(ph_t *p, int n) {
    int target = 0; /* 0 voiceless, 1 voiced, -1 none */
    for (int k = n - 1; k >= 0; k--) {
        char b[6];
        int soft;
        base_of(p[k].s, b, &soft);
        if (!is_obstruent(b)) { target = -1; continue; }
        if (target >= 0) {
            const char *to = target ? voiced(b) : devoiced(b);
            if (to) {
                char buf[8];
                size_t l = strlen(to);
                memcpy(buf, to, l);
                buf[l] = soft ? '\'' : 0;
                buf[l + 1] = 0;
                ph_set(&p[k], buf);
            }
        }
        if (!strcmp(b, "v")) continue;
        char b2[6];
        base_of(p[k].s, b2, &soft);
        target = devoiced(b2) != NULL; /* in VOICED */
    }
}

static int part_phonemes(const vtts_rlex *lex, const uint32_t *w, int n, uint32_t *t, ph_t *out, int cap) {
    uint32_t sw[VTTS_RU_MAXW + 2];
    seg_t S[2 * VTTS_RU_MAXW + 4];
    if (n > VTTS_RU_MAXW) n = VTTS_RU_MAXW;
    int m = stressed(lex, w, n, sw);
    m = spelling(sw, m, t, 2 * VTTS_RU_MAXW + 8);
    if (m < 0) return 0;
    int ns = segments(sw, m, S, 2 * VTTS_RU_MAXW + 4), any_v = 0;
    for (int k = 0; k < ns; k++) any_v |= S[k].kind == 'V';
    if (ns > cap) ns = cap;
    if (!any_v) {
        for (int k = 0; k < ns; k++) cons_ph(&S[k], &out[k]);
        return ns;
    }
    ph_t tmp[2 * VTTS_RU_MAXW + 4];
    int r = reduce(S, ns, tmp);
    if (r > cap) r = cap;
    memcpy(out, tmp, sizeof *tmp * (size_t)r);
    return r;
}

static int ph_id(const char *p) {
    for (int i = 0; i < VTTS_N_RU_PHONEMES; i++) if (!strcmp(VTTS_RU_PHONEMES[i], p)) return VTTS_RU_FIRST_ID + i;
    return -1;
}

static int phonemes_ids(const vtts_rlex *lex, const uint32_t *f, int fn, uint32_t *t, uint8_t *out, int cap) {
    ph_t ph[3 * VTTS_RU_MAXW];
    int a = 0, b = fn, np = 0;
    while (a < b && f[a] == '-') a++; /* strip("-") */
    while (b > a && f[b - 1] == '-') b--;
    for (int i = a; i < b;) {
        int j = i;
        while (j < b && f[j] != '-') j++;
        if (j > i) np += part_phonemes(lex, f + i, j - i, t, ph + np, 3 * VTTS_RU_MAXW - np);
        i = j + 1;
    }
    soften(ph, np);
    voicing(ph, np);
    int k = 0;
    for (int i = 0; i < np && k < cap; i++) {
        int id = ph_id(ph[i].s);
        if (id >= 0) out[k++] = (uint8_t)id;
    }
    return k;
}

int vtts_ru_word_ids(const vtts_rlex *lex, const uint32_t *w, int n, uint32_t *scratch, uint8_t *out, int cap) {
    uint32_t *f = scratch, *t = scratch + VTTS_RU_MAXW + 8;
    int fn = fold(w, n, f, VTTS_RU_MAXW);
    int vowel = 0;
    for (int i = 0; i < fn; i++) vowel |= vowel_letter(f[i]);
    if (fn && !vowel && !(fn == 1 && (f[0] == 0x432 || f[0] == 0x43A || f[0] == 0x441 || f[0] == 0x431 || f[0] == 0x436))) {
        int k = 0;
        for (int i = 0; i < fn && k < cap; i++) {
            char key[5] = {0};
            if (!ru_letter(f[i])) continue;
            key[0] = (char)(0xC0 | (f[i] >> 6));
            key[1] = (char)(0x80 | (f[i] & 0x3F));
            const char *name = map2(VTTS_RU_LETTER_NAMES, VTTS_N_RU_LETTER_NAMES, key);
            if (!name) continue;
            while (*name) { /* each space-separated part is read as a word */
                const char *e = strchr(name, ' ');
                int len = e ? (int)(e - name) : (int)strlen(name);
                uint32_t part[32];
                int pn = 0, l;
                uint32_t c;
                for (const char *q = name; q < name + len && pn < 32; q += l) {
                    l = dec1(q, &c);
                    part[pn++] = c;
                }
                k += vtts_ru_word_ids(lex, part, pn, t, out + k, cap - k);
                name += len;
                while (*name == ' ') name++;
            }
        }
        return k;
    }
    return phonemes_ids(lex, f, fn, t, out, cap);
}

/* ======================= RLEX ======================= */

static uint32_t rd32(const uint8_t *p) { return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }

int vtts_rlex_init(vtts_rlex *r, const uint8_t *blob, size_t size) {
    if (!r || !blob || size < 96 || memcmp(blob, "RLEX", 4) != 0) return -1;
    if ((blob[4] | blob[5] << 8) != 1 || (blob[6] | blob[7] << 8) != 96) return -1;
    memset(r, 0, sizeof *r);
    r->blob = blob;
    r->size = size;
    r->block = rd32(blob + 8);
    r->root = rd32(blob + 12);
    r->max_suffix = rd32(blob + 16);
    if (!r->block) return -1;
    for (int t = 0; t < VTTS_RLEX_N_TABLES; t++) {
        const uint8_t *h = blob + 20 + 20 * t;
        uint32_t n = rd32(h), nb = rd32(h + 4), io = rd32(h + 8), dof = rd32(h + 12), ds = rd32(h + 16);
        if ((size_t)io + (size_t)nb * 4 > size || (size_t)dof + ds > size || nb != (n + r->block - 1) / r->block) return -1;
        r->t[t].n = n;
        r->t[t].n_blocks = nb;
        r->t[t].data_size = ds;
        r->t[t].index = blob + io;
        r->t[t].data = blob + dof;
    }
    return 0;
}

static int cmp_key(const uint8_t *a, int an, const uint8_t *b, int bn) {
    int m = an < bn ? an : bn;
    int c = memcmp(a, b, (size_t)m);
    return c ? c : an - bn;
}

int vtts_rlex_find(const vtts_rlex *r, int table, const uint8_t *key, int key_len, const uint8_t **value) {
    const vtts_rlex_table *t = &r->t[table];
    const int vlen = table == VTTS_RLEX_SUFFIXES ? 1 : 2;
    if (!t->n || key_len > 255) return -1;
    int lo = 0, hi = (int)t->n_blocks - 1, blk = -1;
    while (lo <= hi) { /* last block whose first key <= key */
        int mid = (lo + hi) / 2;
        const uint8_t *p = t->data + rd32(t->index + 4 * mid);
        if (cmp_key(p + 1, p[0], key, key_len) <= 0) { blk = mid; lo = mid + 1; } else hi = mid - 1;
    }
    if (blk < 0) return -1;
    const uint8_t *p = t->data + rd32(t->index + 4 * blk);
    const uint8_t *end = t->data + t->data_size;
    uint8_t cur[256];
    int cl = 0;
    for (uint32_t i = (uint32_t)blk * r->block; i < t->n && i < (uint32_t)(blk + 1) * r->block && p < end; i++) {
        if (i == (uint32_t)blk * r->block) {
            cl = p[0];
            memcpy(cur, p + 1, (size_t)cl);
            p += 1 + cl;
        } else {
            int shared = p[0], suf = p[1];
            memcpy(cur + shared, p + 2, (size_t)suf);
            cl = shared + suf;
            p += 2 + suf;
        }
        int c = cmp_key(cur, cl, key, key_len);
        if (c == 0) { *value = p; return vlen; }
        if (c > 0) return -1;
        p += vlen;
    }
    return -1;
}

/* ======================= normalization (normalize_ru.py) ======================= */

static int udig(uint32_t c) { return vtts_u_digit(c); }

/* a whole number: value when it has at most 18 significant digits, else big (>= 10**15 anyway) */
typedef struct { uint64_t v; int big; const uint32_t *d; int nd; } num_t; /* d, nd: significant digits */

static num_t num_of(const uint32_t *s, int n) { /* int() of decimal digits (other characters skipped) */
    num_t x = {0, 0, s, 0};
    int i = 0;
    while (i < n && (udig(s[i]) <= 0)) i++; /* leading zeros (and separators) */
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
static int last2(const num_t *x) { /* n % 100 */
    if (!x->big || !x->d) return (int)(x->v % 100);
    int a = 0, b = 0, cnt = 0; /* the last two digits of the digit string */
    for (int i = 0; cnt < x->nd; i++) { int v = udig(x->d[i]); if (v < 0) continue; a = b; b = v; cnt++; }
    return a * 10 + b;
}

static void digits_words(wl_t *w, const uint32_t *s, int n) { /* digits(): names of the decimal digits */
    for (int i = 0; i < n; i++) { int v = udig(s[i]); if (v >= 0) wadd(w, VTTS_RU_ONES[v]); }
}
static void digits_of_num(wl_t *w, const num_t *x) { /* digits(str(n)) */
    if (!x->big) {
        char buf[24];
        int k = 0;
        uint64_t v = x->v;
        do { buf[k++] = (char)('0' + v % 10); v /= 10; } while (v);
        while (k) wadd(w, VTTS_RU_ONES[buf[--k] - '0']);
        return;
    }
    int cnt = 0;
    for (int i = 0; cnt < x->nd; i++) { int v = udig(x->d[i]); if (v < 0) continue; wadd(w, VTTS_RU_ONES[v]); cnt++; }
}

static const char *plural_s(const num_t *x, const char *one, const char *few, const char *many) {
    int r = last2(x), u = r % 10;
    if (u == 1 && r != 11) return one;
    if (u >= 2 && u <= 4 && !(r >= 12 && r <= 14)) return few;
    return many;
}

static void below_1000(wl_t *w, int n, char gender) {
    int h = n / 100, r = n % 100;
    if (h) wadd(w, VTTS_RU_HUNDREDS[h]);
    if (r >= 20) { wadd(w, VTTS_RU_TENS[r / 10]); r %= 10; }
    if (r) {
        const char *word = VTTS_RU_ONES[r];
        if (r == 1 && gender != 'm') word = gender == 'f' ? VTTS_RU_L_ODNA : VTTS_RU_L_ODNO;
        else if (r == 2 && gender == 'f') word = VTTS_RU_L_DVE;
        wadd(w, word);
    }
}

static uint64_t pow10u(int e) { uint64_t v = 1; while (e--) v *= 10; return v; }

static void cardinal(wl_t *w, const num_t *x, char gender) {
    if (!x->big && x->v == 0) { wadd(w, VTTS_RU_L_ZERO); return; }
    if (x->big) { digits_of_num(w, x); return; }
    uint64_t n = x->v;
    for (int k = 0; k < VTTS_RU_N_SCALES; k++) {
        uint64_t value = pow10u(VTTS_RU_SCALES[k].exp), q = n / value;
        n %= value;
        if (q) {
            if (!(q == 1 && value == 1000)) below_1000(w, (int)q, VTTS_RU_SCALES[k].gender);
            num_t qq = num_v(q);
            wadd(w, plural_s(&qq, VTTS_RU_SCALES[k].one, VTTS_RU_SCALES[k].few, VTTS_RU_SCALES[k].many));
        }
    }
    below_1000(w, (int)n, gender);
}

static void card_v(wl_t *w, uint64_t v, char gender) { num_t x = num_v(v); cardinal(w, &x, gender); }

/* cardinal_gen into w; with nospace the words are written without the spaces between them */
static void cardinal_gen_v(wl_t *w, uint64_t n, int nospace);
static void cardinal_gen(wl_t *w, const num_t *x) {
    if (x->big) { digits_of_num(w, x); return; }
    cardinal_gen_v(w, x->v, 0);
}

/* cardinal_gen(q) with "одного" at the end -> "одной" (the thousands of cardinal_gen) */
static void cardinal_gen_v(wl_t *w, uint64_t n, int nospace) {
    rb_t *d = w->d;
    if (n == 0) { wadd(w, VTTS_RU_L_ZERO_GEN); return; }
    int start = d->n + (w->any ? 1 : 0);
    wl_t sub = {d, w->any};
    for (int k = 0; k < VTTS_RU_N_SCALES; k++) {
        uint64_t value = pow10u(VTTS_RU_SCALES[k].exp), q = n / value;
        n %= value;
        if (q) {
            if (q > 1) {
                int s0 = d->n + (sub.any ? 1 : 0);
                cardinal_gen_v(&sub, q, 0);
                if (value == 1000 && d->n - s0 >= u8len(VTTS_RU_L_ODNOGO) &&
                    eq_u8(d->p + d->n - u8len(VTTS_RU_L_ODNOGO), u8len(VTTS_RU_L_ODNOGO), VTTS_RU_L_ODNOGO)) {
                    d->n -= u8len(VTTS_RU_L_ODNOGO);
                    puts8(d, VTTS_RU_L_ODNOY);
                }
            }
            if (q % 10 == 1 && q % 100 != 11) {
                if (value == 1000) wadd(&sub, VTTS_RU_L_TYSYACHA_GEN);
                else { wadd(&sub, VTTS_RU_SCALES[k].one); puts8(d, "а"); }
            } else {
                wadd(&sub, VTTS_RU_SCALES[k].many);
            }
        }
    }
    int h = (int)(n / 100), r = (int)(n % 100);
    if (h) wadd(&sub, VTTS_RU_HUNDREDS_GEN[h]);
    if (r >= 20) { wadd(&sub, VTTS_RU_TENS_GEN[r / 10]); r %= 10; }
    if (r) wadd(&sub, VTTS_RU_ONES_GEN[r]);
    w->any = sub.any;
    if (nospace) { /* .replace(" ", "") */
        int o = start;
        for (int i = start; i < d->n; i++) if (d->p[i] != ' ') d->p[o++] = d->p[i];
        d->n = o;
    }
}

static int case_index(const char *c) {
    for (int i = 0; i < VTTS_N_RU_CASES; i++) if (!strcmp(VTTS_RU_CASES[i], c)) return i;
    return 0;
}
static int cls_index(const char *c) { return c[0] == 's' ? 1 : c[0] == 't' ? 2 : 0; }

static void ord_word(wl_t *w, const char *stem, const char *cls, int ci) {
    wadd(w, stem);
    puts8(w->d, VTTS_RU_ENDINGS[cls_index(cls)][ci]);
}

static void ordinal(wl_t *w, const num_t *x, int ci) {
    if (x->big || x->v == 0 || x->v >= 1000000000ULL) { cardinal(w, x, 'm'); return; }
    uint64_t n = x->v;
    int r100 = (int)(n % 100);
    if (r100) {
        uint64_t head = n - (uint64_t)r100;
        const char *stem, *cls;
        if (r100 < 20) { stem = VTTS_RU_ORD_ONES[r100][0]; cls = VTTS_RU_ORD_ONES[r100][1]; }
        else if (r100 % 10 == 0) { stem = VTTS_RU_ORD_TENS[r100 / 10]; cls = VTTS_RU_ORD_TENS_CLASS[r100 / 10]; }
        else { head += (uint64_t)(r100 - r100 % 10); stem = VTTS_RU_ORD_ONES[r100 % 10][0]; cls = VTTS_RU_ORD_ONES[r100 % 10][1]; }
        if (head) card_v(w, head, 'm');
        ord_word(w, stem, cls, ci);
    } else if (n % 1000) {
        uint64_t head = n - n % 1000;
        if (head) card_v(w, head, 'm');
        ord_word(w, VTTS_RU_ORD_HUNDREDS[(n % 1000) / 100], "h", ci);
    } else if (n % 1000000) {
        uint64_t q = (n % 1000000) / 1000, head = n - n % 1000000;
        if (head) card_v(w, head, 'm');
        if (q < 10) wadd(w, VTTS_RU_ORD_THOUSANDS[q]);
        else cardinal_gen_v(w, q, 1);
        puts8(w->d, VTTS_RU_L_TYSYACHN);
        puts8(w->d, VTTS_RU_ENDINGS[0][ci]);
    } else {
        uint64_t q = n / 1000000;
        if (q == 1) wadd(w, "");
        else if (q < 10) wadd(w, VTTS_RU_ORD_THOUSANDS[q]);
        else cardinal_gen_v(w, q, 1);
        puts8(w->d, VTTS_RU_L_MILLIONN);
        puts8(w->d, VTTS_RU_ENDINGS[0][ci]);
    }
}

/* ---- parse_number (latin_norm) on cleaned text ---- */

typedef struct { num_t n; const uint32_t *frac; int fn; int has_frac; } pnum_t;

static int is_space_num(uint32_t c) { return c == ' ' || c == 0xA0 || c == 0x202F; }

/* _clean_num(s) into o: the spaces of [   ] removed */
static int clean_num(const uint32_t *s, int n, uint32_t *o) {
    int m = 0;
    for (int i = 0; i < n; i++) if (!is_space_num(s[i])) o[m++] = s[i];
    return m;
}

static pnum_t parse_number(const uint32_t *s, int n) {
    pnum_t r;
    memset(&r, 0, sizeof r);
    while (n > 0 && s[0] == '+') { s++; n--; } /* lstrip("+") */
    vtts_re_match m;
    if (vtts_re_match_at(&VTTS_RU_RE_THOUSANDS_DOT, s, n, 0, &m) ||
        vtts_re_match_at(&VTTS_RU_RE_THOUSANDS_COMMA, s, n, 0, &m)) {
        uint32_t frac_mark = vtts_re_match_at(&VTTS_RU_RE_THOUSANDS_DOT, s, n, 0, &m) ? ',' : '.';
        int k = 0;
        while (k < n && s[k] != frac_mark) k++;
        r.n = num_of(s, k); /* the group marks are skipped by num_of */
        if (k < n && k + 1 < n) { r.frac = s + k + 1; r.fn = n - k - 1; r.has_frac = 1; }
        return r;
    }
    for (int mk = 0; mk < 2; mk++) {
        uint32_t mark = mk ? '.' : ',';
        for (int k = 0; k < n; k++)
            if (s[k] == mark) {
                r.n = num_of(s, k);
                r.frac = s + k + 1;
                r.fn = n - k - 1;
                r.has_frac = 1;
                return r;
            }
    }
    r.n = num_of(s, n);
    return r;
}

/* number(s, gender) */
static void number(wl_t *w, const uint32_t *s0, int n0, char gender) {
    uint32_t s[128] = {0}; /* GCC -Wmaybe-uninitialized on RISC-V -O2 */
    if (n0 > 128) n0 = 128;
    int n = clean_num(s0, n0, s), neg = n && s[0] == '-';
    const uint32_t *p = s;
    int pn = n;
    while (pn && *p == '-') { p++; pn--; } /* lstrip("-") */
    pnum_t x = parse_number(p, pn);
    if (neg) wadd(w, VTTS_RU_L_MINUS);
    if (!x.has_frac) { cardinal(w, &x.n, gender); return; }
    if (x.fn <= 3) {
        cardinal(w, &x.n, 'f');
        wadd(w, plural_s(&x.n, VTTS_RU_L_CELAYA, VTTS_RU_L_CELYKH, VTTS_RU_L_CELYKH));
        num_t k = num_of(x.frac, x.fn);
        cardinal(w, &k, 'f');
        int one = plural_s(&k, "1", "", "")[0] == '1';
        wadd(w, one ? VTTS_RU_FRACTION[x.fn] : VTTS_RU_FRACTION_PL[x.fn]);
        return;
    }
    cardinal(w, &x.n, 'm');
    wadd(w, VTTS_RU_L_ZAPYATAYA);
    digits_words(w, x.frac, x.fn);
}

static int has_frac_of(const uint32_t *s0, int n0) {
    uint32_t s[128];
    if (n0 > 128) n0 = 128;
    int n = clean_num(s0, n0, s);
    const uint32_t *p = s;
    while (n && *p == '-') { p++; n--; }
    return parse_number(p, n).has_frac;
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
    wadd(w, x.has_frac ? unit[3] : plural_s(&x.n, unit[2], unit[3], unit[4]));
}

/* ---- the passes ---- */

typedef struct { uint32_t *a, *b; int cap; char *out; int out_cap; } scratch_t;

static int sp(uint32_t c) { return vtts_u_space(c); }
static int is_mark(uint32_t c) { return c == ',' || c == '.' || c == '?' || c == '!' || c == ';' || c == ':'; }

/* prev_word(m): the chunk before the match (lower-cased into o), its length or -1 */
static int prev_word(const uint32_t *s, int start, uint32_t *o, int cap) {
    int j = start;
    while (j > 0 && sp(s[j - 1])) j--;
    if (j == start || j == 0) return -1;
    int i = j;
    while (i > 0 && !sp(s[i - 1])) i--;
    int m = 0;
    for (int k = i; k < j && m < cap; k++) o[m++] = s[k] == 0x130 ? 'i' : vtts_u_lower(s[k]);
    for (int k = i; k < j; k++) if (s[k] == 0x130 && m < cap) { /* lower() of İ is i + U+0307 */
        m = 0;
        for (int q = i; q < j && m + 1 < cap; q++) {
            if (s[q] == 0x130) { o[m++] = 'i'; o[m++] = 0x307; } else o[m++] = vtts_u_lower(s[q]);
        }
        break;
    }
    return m;
}

static int lower_in(const char *const *list, int n, const uint32_t *w, int wn) { return wn >= 0 && in_list(list, n, w, wn); }

static int gen_count(const uint32_t *s, const vtts_re_match *m, const uint32_t *num, int nn) {
    uint32_t pw[64];
    int pl = prev_word(s, m->start, pw, 64);
    return lower_in(VTTS_RU_GEN_COUNT, VTTS_N_RU_GEN_COUNT, pw, pl) && !has_frac_of(num, nn);
}

#define G(m, i) (m)->gs[i]
#define GL(m, i) ((m)->ge[i] - (m)->gs[i])
#define GP(s, m, i) ((s) + (m)->gs[i])

static void sub_phone(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    wl_t w = {d, 0};
    put(d, ' ');
    if (s[m->start] == '+') wadd(&w, VTTS_RU_L_PLUS);
    digits_words(&w, s + m->start, m->end - m->start);
    put(d, ' ');
}

static int small(const uint32_t *s, int i, int len) { num_t x = num_of(s + i, len); return x.big ? 1 << 30 : (int)(x.v > 100000 ? 100000 : x.v); }

static void date_out(rb_t *d, int dd, int mm, const uint32_t *y, int yl, const char *cs) {
    wl_t w = {d, 0};
    put(d, ' ');
    num_t x = num_v((uint64_t)dd);
    ordinal(&w, &x, case_index(cs));
    wadd(&w, VTTS_RU_MONTHS[mm]);
    if (y) {
        num_t yy = num_of(y, yl);
        if (yl == 2) yy = num_v(yy.v + 2000);
        ordinal(&w, &yy, case_index("gen_m"));
        wadd(&w, VTTS_RU_L_GODA);
    }
    put(d, ' ');
}

static void sub_date_iso(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    int dd = small(s, G(m, 3), GL(m, 3)), mm = small(s, G(m, 2), GL(m, 2));
    if (!(dd >= 1 && dd <= 31 && mm >= 1 && mm <= 12)) { putn(d, s + m->start, m->end - m->start); return; }
    date_out(d, dd, mm, GP(s, m, 1), GL(m, 1), "nom_n");
}

static void sub_date_dmy(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    int dd = small(s, G(m, 1), GL(m, 1)), mm = small(s, G(m, 3), GL(m, 3));
    if (!(dd >= 1 && dd <= 31 && mm >= 1 && mm <= 12)) { putn(d, s + m->start, m->end - m->start); return; }
    date_out(d, dd, mm, GP(s, m, 4), GL(m, 4), "nom_n");
}

static int rest_blank(const uint32_t *s, int n, int from) { /* not s[from:].strip() */
    for (int i = from; i < n; i++) if (!sp(s[i])) return 0;
    return 1;
}

static void sub_year(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)u;
    uint32_t pw[64];
    int pl = prev_word(s, m->start, pw, 64);
    const uint32_t *noun = GP(s, m, 2);
    int nl = GL(m, 2);
    const char *cs, *word = NULL;
    if (eq_u8(noun, nl, "г.") || eq_u8(noun, nl, "гг.")) {
        int plural_noun = eq_u8(noun, nl, "гг.");
        if (pl >= 0 && (eq_u8(pw, pl, "в") || eq_u8(pw, pl, "во"))) {
            cs = plural_noun ? "gen_pl" : "prep_m";
            word = plural_noun ? VTTS_RU_L_GODAKH : VTTS_RU_L_GODU;
        } else if (plural_noun) {
            cs = "nom_pl";
            word = VTTS_RU_L_GODY;
        } else {
            cs = "gen_m";
            word = VTTS_RU_L_GODA;
        }
    } else {
        cs = "nom_m";
        for (int k = 0; k < VTTS_N_RU_YEAR_NOUN; k++) if (eq_u8(noun, nl, VTTS_RU_YEAR_NOUN[k][0])) cs = VTTS_RU_YEAR_NOUN[k][1];
    }
    wl_t w = {d, 0};
    put(d, ' ');
    num_t y = num_of(GP(s, m, 1), GL(m, 1));
    ordinal(&w, &y, case_index(cs));
    put(d, ' ');
    if (word) puts8(d, word); else putn(d, noun, nl);
    if (nl && noun[nl - 1] == '.' && rest_blank(s, n, m->end)) puts8(d, " .");
    put(d, ' ');
}

static int roman_v(uint32_t c) { return c == 'I' ? 1 : c == 'V' ? 5 : c == 'X' ? 10 : c == 'L' ? 50 : c == 'C' ? 100 : 0; }
static void ord_roman(wl_t *w, const uint32_t *s, int n, int ci) {
    int64_t total = 0;
    for (int i = 0; i < n; i++) {
        int v = roman_v(s[i]);
        total += (i + 1 < n && roman_v(s[i + 1]) > v) ? -v : v;
    }
    if (total <= 0) { /* ordinal(n <= 0) -> cardinal(n) */
        if (total == 0) { wadd(w, VTTS_RU_L_ZERO); return; }
        wadd(w, VTTS_RU_L_MINUS);
        card_v(w, (uint64_t)(-total), 'm');
        return;
    }
    num_t x = num_v((uint64_t)total);
    ordinal(w, &x, ci);
}

static void sub_century(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    const uint32_t *noun = GP(s, m, 3);
    int nl = GL(m, 3);
    const char *cs = "nom_m";
    for (int k = 0; k < VTTS_N_RU_CENTURY_NOUN; k++) if (eq_u8(noun, nl, VTTS_RU_CENTURY_NOUN[k][0])) cs = VTTS_RU_CENTURY_NOUN[k][1];
    wl_t w = {d, 0};
    put(d, ' ');
    if (G(m, 2) >= 0) {
        if (!strcmp(cs, "gen_pl") && eq_u8(noun, nl, "вв.")) cs = "nom_m";
        ord_roman(&w, GP(s, m, 1), GL(m, 1), case_index(cs));
        ord_roman(&w, GP(s, m, 2), GL(m, 2), case_index(cs));
    } else {
        ord_roman(&w, GP(s, m, 1), GL(m, 1), case_index(cs));
    }
    put(d, ' ');
    if (eq_u8(noun, nl, "в.")) puts8(d, VTTS_RU_L_VEK);
    else if (eq_u8(noun, nl, "вв.")) puts8(d, VTTS_RU_L_VEKOV);
    else putn(d, noun, nl);
    put(d, ' ');
}

static void sub_abbr(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    const char *const *row = u; /* {key, reading} */
    size_t kl = strlen(row[0]);
    int end = row[0][kl - 1] == '.';
    put(d, ' ');
    puts8(d, row[1]);
    put(d, ' ');
    if (end && rest_blank(s, n, m->end)) put(d, '.');
}

static int is_upper(uint32_t c) { return vtts_u_lower(c) != c; }

static void sub_day_month(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    int dd = small(s, G(m, 1), GL(m, 1));
    if (!(dd >= 1 && dd <= 31)) { putn(d, s + m->start, m->end - m->start); return; }
    uint32_t pw[64];
    int pl = prev_word(s, m->start, pw, 64);
    const char *cs = "nom_n";
    if (lower_in(VTTS_RU_GEN_PREPOSITIONS, VTTS_N_RU_GEN_PREPOSITIONS, pw, pl)) cs = "gen_m";
    else if (pl >= 0 && (eq_u8(pw, pl, "к") || eq_u8(pw, pl, "ко"))) cs = "dat_m";
    wl_t w = {d, 0};
    put(d, ' ');
    num_t x = num_v((uint64_t)dd);
    ordinal(&w, &x, case_index(cs));
    put(d, ' ');
    putn(d, GP(s, m, 2), GL(m, 2));
    put(d, ' ');
}

static void sub_regnal(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    const uint32_t *r = GP(s, m, 2);
    int rl = GL(m, 2), start = 0;
    for (int i = m->start - 1; i >= 0; i--) if (s[i] == ' ') { start = i + 1; break; }
    const uint32_t *name = s + start;
    int nl = m->start - start;
    if ((rl == 1 && (r[0] == 'C' || r[0] == 'L')) || !(nl > 0 && is_upper(name[0]))) {
        putn(d, s + m->start, m->end - m->start);
        return;
    }
    const char *cs = nl && (name[nl - 1] == 0x430 || name[nl - 1] == 0x44F) ? "nom_f" : "nom_m";
    putn(d, GP(s, m, 1), GL(m, 1));
    wl_t w = {d, 0};
    ord_roman(&w, r, rl, case_index(cs));
}

static void sub_time(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    int h = small(s, G(m, 1), GL(m, 1)), mi = small(s, G(m, 2), GL(m, 2));
    wl_t w = {d, 0};
    put(d, ' ');
    card_v(&w, (uint64_t)h, 'm');
    if (mi == 0) { wadd(&w, VTTS_RU_L_ZERO); wadd(&w, VTTS_RU_L_ZERO); }
    else if (mi >= 10) card_v(&w, (uint64_t)mi, 'm');
    else { wadd(&w, VTTS_RU_L_ZERO); card_v(&w, (uint64_t)mi, 'm'); }
    if (G(m, 3) >= 0) {
        int sec = small(s, G(m, 3), GL(m, 3));
        if (sec) {
            wadd(&w, VTTS_RU_L_I);
            card_v(&w, (uint64_t)sec, 'f');
            num_t x = num_v((uint64_t)sec);
            wadd(&w, plural_s(&x, VTTS_RU_L_SEKUNDA, VTTS_RU_L_SEKUNDY, VTTS_RU_L_SEKUND));
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
    for (int k = 0; k < VTTS_RU_N_SCALE_ABBR; k++) if (eq_u8(GP(s, m, 2), GL(m, 2), VTTS_RU_SCALE_ABBR[k].key)) exp = VTTS_RU_SCALE_ABBR[k].exp;
    const char *forms[5] = {"", "m", "", "", ""};
    for (int k = 0; k < VTTS_RU_N_SCALES; k++)
        if (VTTS_RU_SCALES[k].exp == exp) {
            forms[1] = VTTS_RU_SCALES[k].gender == 'f' ? "f" : "m";
            forms[2] = VTTS_RU_SCALES[k].one;
            forms[3] = VTTS_RU_SCALES[k].few;
            forms[4] = VTTS_RU_SCALES[k].many;
        }
    wl_t w = {d, 0};
    put(d, ' ');
    count(&w, GP(s, m, 1), GL(m, 1), forms);
    if (G(m, 3) >= 0) {
        const char *const *cur = find_forms(VTTS_RU_CURRENCY, VTTS_N_RU_CURRENCY, GP(s, m, 3), GL(m, 3));
        if (cur) wadd(&w, cur[4]);
    }
    put(d, ' ');
}

static void money(rb_t *d, const uint32_t *num, int nl, const uint32_t *cur, int cl) {
    const char *const *unit = find_forms(VTTS_RU_CURRENCY, VTTS_N_RU_CURRENCY, cur, cl);
    uint32_t s[128];
    if (nl > 128) nl = 128;
    int sn = clean_num(num, nl, s);
    pnum_t x = parse_number(s, sn);
    wl_t w = {d, 0};
    put(d, ' ');
    const char *const *sub = NULL;
    if (unit) for (int k = 0; k < VTTS_N_RU_SUBUNIT; k++) if (!strcmp(VTTS_RU_SUBUNIT[k][0], unit[2])) sub = VTTS_RU_SUBUNIT[k];
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
    (void)u;
    money(d, GP(s, m, 1), GL(m, 1), GP(s, m, 2), GL(m, 2));
    if (GL(m, 2) && s[m->ge[2] - 1] == '.' && rest_blank(s, n, m->end)) puts8(d, " .");
}

static void sub_percent(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    static const char *const pct[5] = {"%", "m", VTTS_RU_L_PROCENT, VTTS_RU_L_PROCENTA, VTTS_RU_L_PROCENTOV};
    wl_t w = {d, 0};
    put(d, ' ');
    if (GL(m, 1)) wadd(&w, VTTS_RU_L_MINUS);
    count(&w, GP(s, m, 2), GL(m, 2), pct);
    put(d, ' ');
}

static void sub_unit(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    const char *const *forms = find_forms(VTTS_RU_UNITS, VTTS_N_RU_UNITS, GP(s, m, 3), GL(m, 3));
    wl_t w = {d, 0};
    put(d, ' ');
    if (!GL(m, 1) && gen_count(s, m, GP(s, m, 2), GL(m, 2))) {
        uint32_t c[128];
        int cn = clean_num(GP(s, m, 2), GL(m, 2) > 128 ? 128 : GL(m, 2), c);
        pnum_t x = parse_number(c, cn);
        cardinal_gen(&w, &x.n);
        wadd(&w, plural_s(&x.n, "1", "", "")[0] == '1' ? forms[3] : forms[4]);
        put(d, ' ');
        return;
    }
    if (GL(m, 1)) wadd(&w, VTTS_RU_L_MINUS);
    count(&w, GP(s, m, 2), GL(m, 2), forms);
    put(d, ' ');
}

static void sub_ordinal(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    num_t x = num_of(GP(s, m, 1), GL(m, 1));
    const uint32_t *suf = GP(s, m, 2);
    int sl = GL(m, 2);
    const uint32_t *nxt = G(m, 3) >= 0 ? GP(s, m, 3) : NULL;
    int xl = G(m, 3) >= 0 ? GL(m, 3) : 0;
    wl_t w = {d, 0};
    put(d, ' ');
    if ((eq_u8(suf, sl, "х") || eq_u8(suf, sl, "ти")) && !x.big && x.v < 10) {
        cardinal_gen(&w, &x);
        putn(d, nxt, xl);
        return;
    }
    const char *cs = "nom_m";
    for (int k = 0; k < VTTS_N_RU_SUFFIX_CASE; k++) if (eq_u8(suf, sl, VTTS_RU_SUFFIX_CASE[k][0])) cs = VTTS_RU_SUFFIX_CASE[k][1];
    if (eq_u8(suf, sl, "е")) { /* n >= 1000 or nxt.strip().strip(",.?!;:").lower() == "годы" */
        int a = 0, b = xl, gody = 0;
        while (a < b && sp(nxt[a])) a++;
        while (b > a && sp(nxt[b - 1])) b--;
        while (a < b && is_mark(nxt[a])) a++;
        while (b > a && is_mark(nxt[b - 1])) b--;
        if (b - a == 4) {
            uint32_t low[4];
            for (int i = 0; i < 4; i++) low[i] = nxt[a + i] == 0x130 ? 0 : vtts_u_lower(nxt[a + i]);
            gody = eq_u8(low, 4, VTTS_RU_L_GODY);
        }
        if (x.big || x.v >= 1000 || gody) cs = "nom_pl";
    }
    ordinal(&w, &x, case_index(cs));
    putn(d, nxt, xl);
}

static void sub_compound(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    num_t x = num_of(GP(s, m, 1), GL(m, 1));
    put(d, ' ');
    const char *prefix = NULL;
    if (!x.big)
        for (int k = 0; k < VTTS_N_RU_COMPOUND_PREFIX; k++) {
            uint64_t v = 0;
            for (const char *p = VTTS_RU_COMPOUND_PREFIX[k][0]; *p; p++) v = v * 10 + (uint64_t)(*p - '0');
            if (v == x.v) prefix = VTTS_RU_COMPOUND_PREFIX[k][1];
        }
    if (prefix) {
        puts8(d, prefix);
    } else {
        wl_t w = {d, 0};
        if (x.big) {
            int s0 = d->n;
            digits_of_num(&w, &x);
            int o = s0;
            for (int i = s0; i < d->n; i++) if (d->p[i] != ' ') d->p[o++] = d->p[i];
            d->n = o;
        } else {
            cardinal_gen_v(&w, x.v, 1);
        }
    }
    putn(d, GP(s, m, 2), GL(m, 2));
}

static void sub_range(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n; (void)u;
    wl_t w = {d, 0};
    put(d, ' ');
    wadd(&w, VTTS_RU_L_OT);
    num_t a = num_of(GP(s, m, 1), GL(m, 1)), b = num_of(GP(s, m, 2), GL(m, 2));
    cardinal_gen(&w, &a);
    wadd(&w, VTTS_RU_L_DO);
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
        if (c >= '0' && c <= '9') { wadd(&w, VTTS_RU_ONES[c - '0']); continue; }
        char k[3] = {(char)vtts_u_lower(c), 0, 0};
        const char *name = map2(VTTS_RU_LATIN_LETTERS, VTTS_N_RU_LATIN_LETTERS, k);
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
    if (G(m, 3) >= 0 && !x.has_frac) {
        const uint32_t *nw = GP(s, m, 3);
        int nwl = GL(m, 3), a = 0;
        while (a < nwl && sp(nw[a])) a++;
        uint32_t last = vtts_u_lower(nw[nwl - 1]);
        int r = last2(&x.n), lastd = r % 10;
        if (lastd == 1 && r != 11) {
            gender = (last == 0x430 || last == 0x44F) ? 'f' : (last == 0x43E || last == 0x435 || last == 0x451) ? 'n' : 'm';
        } else if (lastd == 2 && r != 12 && (last == 0x44B || last == 0x438)) {
            gender = 'f';
        }
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
    for (int i = 0; i < l && i < 8; i++) low[i] = vtts_u_lower(s[m->start + i]);
    if (in_list(VTTS_RU_ACRONYM_WORDS, VTTS_N_RU_ACRONYM_WORDS, low, l) && !in_list(VTTS_RU_SPELLED, VTTS_N_RU_SPELLED, low, l)) {
        putn(d, low, l);
        return;
    }
    wl_t w = {d, 0};
    put(d, ' ');
    for (int i = 0; i < l; i++) {
        char k[5] = {(char)(0xC0 | (low[i] >> 6)), (char)(0x80 | (low[i] & 0x3F)), 0, 0, 0};
        const char *name = map2(VTTS_RU_LETTER_NAMES, VTTS_N_RU_LETTER_NAMES, k);
        if (name) wadd(&w, name);
    }
    put(d, ' ');
}

static void sub_latin(const uint32_t *s, int n, const vtts_re_match *m, rb_t *d, void *u) {
    (void)n;
    const scratch_t *x = u;
    const int half = x->cap / 2;
    int f = 0;
    for (int k = m->start; k < m->end; k++) {
        uint32_t c = s[k];
        if (c < 0x80) { if (f < x->cap) x->b[f++] = c; continue; }
        if (c >= 0xC0 && c <= 0x24F)
            for (const char *p = VTTS_RU_LATIN_FOLD[c - 0xC0]; *p; p++) if (f < x->cap) x->b[f++] = (uint8_t)*p;
    }
    int r = vtts_en_normalize(x->b, f, x->a, x->a + half, half, x->out, x->out_cap);
    if (r < 0) { d->err = 1; return; }
    put(d, ' ');
    for (int k = 0; k < r; k++) put(d, (uint8_t)x->out[k]);
    put(d, ' ');
}

/* SYMBOLS in order (str.replace), then - and – -> space, — -> " , " */
static void p_symbols(const uint32_t *s, int n, rb_t *d, uint32_t *t, int cap) {
    rb_t x = {t, 0, cap, 0};
    putn(&x, s, n);
    for (int k = 0; k < VTTS_N_RU_SYMBOLS; k++) {
        uint32_t key;
        dec1(VTTS_RU_SYMBOLS[k][0], &key);
        d->n = 0;
        for (int i = 0; i < x.n; i++) {
            if (x.p[i] == key) puts8(d, VTTS_RU_SYMBOLS[k][1]);
            else put(d, x.p[i]);
        }
        x.n = 0;
        putn(&x, d->p, d->n);
    }
    d->n = 0;
    for (int i = 0; i < x.n; i++) {
        uint32_t c = x.p[i];
        if (c == '-' || c == 0x2013) put(d, ' ');
        else if (c == 0x2014) puts8(d, " , ");
        else put(d, c);
    }
}

/* WORD.findall(t.lower()) with a mark after a mark dropped, then _join_clitics (в к с + a word with
 * а-я ё -> в-word), joined by single spaces */
static void p_words(const uint32_t *s0, int n0, rb_t *d, uint32_t *t, int cap) {
    int n = 0;
    for (int i = 0; i < n0 && n + 1 < cap; i++) {
        if (s0[i] == 0x130) { t[n++] = 'i'; t[n++] = 0x307; continue; }
        t[n++] = vtts_u_lower(s0[i]);
    }
    int pos = 0, kept = 0, last_mark = 0, pending = 0; /* pending: the last word written is в к с */
    vtts_re_match m;
    while (pos < n && vtts_re_search(&VTTS_RU_RE_WORD, t, n, pos, &m)) {
        const uint32_t *w = t + m.start;
        int l = m.end - m.start, mark = l == 1 && is_mark(w[0]);
        pos = m.end > m.start ? m.end : m.start + 1;
        if (mark && kept && last_mark) continue;
        kept++;
        last_mark = mark;
        if (pending) {
            int cyr = 0;
            for (int i = 0; i < l; i++) cyr |= (w[i] >= 0x430 && w[i] <= 0x44F) || w[i] == LET_YO;
            pending = 0;
            if (!mark && cyr) { put(d, '-'); putn(d, w, l); continue; }
        }
        if (d->n) put(d, ' ');
        putn(d, w, l);
        pending = l == 1 && (w[0] == 0x432 || w[0] == 0x43A || w[0] == 0x441);
    }
}

int vtts_ru_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, uint32_t *ea, uint32_t *eb,
                      int ecap, char *eout, int eout_cap, const uint32_t **out) {
    rb_t x = {a, 0, cap, 0}, y = {b, 0, cap, 0};
    scratch_t e = {ea, eb, ecap, eout, eout_cap};
    /* compose(): е/Е + U+0308 -> ё/Ё, и/И + U+0306 -> й/Й, U+0301 dropped (in may share memory with a) */
    {
        int m = 0;
        for (int i = 0; i < n && m < ecap; i++) {
            uint32_t c = in[i], nx = i + 1 < n ? in[i + 1] : 0;
            if ((c == 0x435 || c == 0x415) && nx == 0x308) { ea[m++] = c == 0x435 ? 0x451 : 0x401; i++; continue; }
            if ((c == 0x438 || c == 0x418) && nx == 0x306) { ea[m++] = c == 0x438 ? 0x439 : 0x419; i++; continue; }
            if (c == 0x301) continue;
            ea[m++] = c;
        }
        putn(&x, ea, m);
        if (x.err) return -1;
    }
#define PASS(re, fn, u) do { y.n = 0; re_sub(re, x.p, x.n, &y, fn, u); if (y.err) return -1; rb_t t_ = x; x = y; y = t_; } while (0)
    PASS(&VTTS_RU_RE_PHONE, sub_phone, NULL);
    PASS(&VTTS_RU_RE_DATE_ISO, sub_date_iso, NULL);
    PASS(&VTTS_RU_RE_DATE_DMY, sub_date_dmy, NULL);
    PASS(&VTTS_RU_RE_YEAR, sub_year, NULL);
    PASS(&VTTS_RU_RE_CENTURY, sub_century, NULL);
    for (int k = 0; k < VTTS_N_RU_ABBREVIATIONS; k++) PASS(VTTS_RU_ABBR_RE[k], sub_abbr, (void *)VTTS_RU_ABBREVIATIONS[k]);
    { /* DROP -> space */
        y.n = 0;
        for (int i = 0; i < x.n; i++) {
            uint32_t c = x.p[i], k0;
            int hit = 0;
            for (const char *p = VTTS_RU_DROP; *p && !hit;) { int l = dec1(p, &k0); hit = k0 == c; p += l; }
            put(&y, hit ? ' ' : c);
        }
        if (y.err) return -1;
        rb_t t_ = x; x = y; y = t_;
    }
    PASS(&VTTS_RU_RE_DAY_MONTH, sub_day_month, NULL);
    PASS(&VTTS_RU_RE_REGNAL, sub_regnal, NULL);
    PASS(&VTTS_RU_RE_TIME, sub_time, NULL);
    PASS(&VTTS_RU_RE_SCALED, sub_scaled, NULL);
    PASS(&VTTS_RU_RE_MONEY_BEFORE, sub_money_before, NULL);
    PASS(&VTTS_RU_RE_MONEY_AFTER, sub_money_after, NULL);
    PASS(&VTTS_RU_RE_PERCENT, sub_percent, NULL);
    PASS(&VTTS_RU_RE_UNIT, sub_unit, NULL);
    PASS(&VTTS_RU_RE_ORDINAL, sub_ordinal, NULL);
    PASS(&VTTS_RU_RE_COMPOUND, sub_compound, NULL);
    PASS(&VTTS_RU_RE_RANGE, sub_range, NULL);
    PASS(&VTTS_RU_RE_PAUSE, sub_pause, NULL);
    PASS(&VTTS_RU_RE_PRODUCT_CODE, sub_code, NULL);
    PASS(&VTTS_RU_RE_NUMBER, sub_number, NULL);
    PASS(&VTTS_RU_RE_ACRONYM, sub_acronym, NULL);
    PASS(&VTTS_RU_RE_LATIN, sub_latin, &e);
#undef PASS
    y.n = 0;
    p_symbols(x.p, x.n, &y, ea, ecap);
    if (y.err) return -1;
    { rb_t t_ = x; x = y; y = t_; }
    y.n = 0;
    p_words(x.p, x.n, &y, ea, ecap);
    if (y.err) return -1;
    *out = y.p;
    return y.n;
}

#endif /* VTTS_ENABLE_RU */
