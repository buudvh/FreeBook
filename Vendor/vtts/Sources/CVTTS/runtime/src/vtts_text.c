/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text.c -- device front-end (see vtts_text.h). Mirrors src/vtts/frontend (Python). */
#include "vtts_text.h"
#include "vtts.h" /* vtts_token_set_t */

#include <stddef.h>
#include <string.h>

#include "vtts_text_tables.h"

#define MAX_SYL 40
#define WORD_CAP 64 /* letters per word */

/* ---------------- letters ---------------- */

typedef struct {
    char code[WORD_CAP]; /* internal codes: a..z, 1=ă 2=â 3=ê 4=ô 5=ơ 6=ư 7=đ */
    int n, tone, valid, foreign;
} letters_t;

static const vtts_letter *find_letter(uint32_t cp) {
    int lo = 0, hi = VTTS_N_LETTERS - 1;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        if (VTTS_LETTERS[mid].cp == cp) return &VTTS_LETTERS[mid];
        if (VTTS_LETTERS[mid].cp < cp) lo = mid + 1; else hi = mid - 1;
    }
    return NULL;
}

static int tone_mark(uint32_t cp) {
    switch (cp) {
    case 0x0300: return 2;
    case 0x0301: return 3;
    case 0x0309: return 4;
    case 0x0303: return 5;
    case 0x0323: return 6;
    default: return 0;
    }
}

static int quality_mark(uint32_t cp) { return cp == 0x0302 || cp == 0x0306 || cp == 0x031B; }

/* Latin letters outside Vietnamese, folded to their ASCII base (spelled, never a syllable) */
static char fold_foreign(uint32_t cp) {
    static const char *const map[] = {
        /* 0xC0 */ "AAAAAAACEEEEIIII", "DNOOOOO*OUUUUYTs", "aaaaaaaceeeeiiii", "dnooooo/ouuuuyty"};
    if (cp >= 0xC0 && cp <= 0xFF) {
        char c = map[(cp - 0xC0) / 16][(cp - 0xC0) % 16];
        if (c == '*' || c == '/') return 0;
        return (char)(c >= 'A' && c <= 'Z' ? c + 32 : c);
    }
    return 0;
}

static int is_combining(uint32_t cp) { return cp >= 0x0300 && cp <= 0x036F; }

/* non-Latin alphabets: join words but produce nothing (Python drops them when spelling) */
static int is_other_alpha(uint32_t cp) {
    return (cp >= 0x0370 && cp <= 0x052F) || (cp >= 0x3040 && cp <= 0x30FF) ||
           (cp >= 0x3400 && cp <= 0x9FFF) || (cp >= 0xAC00 && cp <= 0xD7AF) ||
           (cp >= 0x0100 && cp <= 0x024F);
}

static int is_letter_cp(uint32_t cp) {
    if ((cp >= 'a' && cp <= 'z') || (cp >= 'A' && cp <= 'Z')) return 1;
    if (cp < 0x80) return 0;
    return find_letter(cp) || fold_foreign(cp) || is_other_alpha(cp);
}

static int is_digit_cp(uint32_t cp) { return cp >= '0' && cp <= '9'; }
static int is_space_cp(uint32_t cp) { /* str.isspace() */
    return cp == ' ' || (cp >= 0x09 && cp <= 0x0D) || (cp >= 0x1C && cp <= 0x1F) || cp == 0x85 || cp == 0xA0 ||
           cp == 0x1680 || (cp >= 0x2000 && cp <= 0x200A) || cp == 0x2028 || cp == 0x2029 || cp == 0x202F ||
           cp == 0x205F || cp == 0x3000;
}
static int is_word_cp(uint32_t cp) { return is_letter_cp(cp) || is_digit_cp(cp) || cp == '_'; }
int vtts_cp_is_word(uint32_t cp) { return is_word_cp(cp); } /* Python \w, for vtts_text_en.c */
int vtts_cp_is_space(uint32_t cp) { return is_space_cp(cp); }

/* ---------------- UTF-8 ---------------- */

static int utf8_decode(const char *s, uint32_t *out, int cap) {
    const unsigned char *p = (const unsigned char *)s;
    int n = 0;
    while (*p && n < cap) {
        uint32_t c = *p;
        int extra = c < 0x80 ? 0 : (c >> 5) == 6 ? 1 : (c >> 4) == 14 ? 2 : (c >> 3) == 30 ? 3 : -1;
        if (extra < 0) { p++; continue; }
        if (extra) c &= (uint32_t)(0x3F >> extra);
        p++;
        int ok = 1;
        for (int k = 0; k < extra; k++) {
            if ((*p & 0xC0) != 0x80) { ok = 0; break; }
            c = (c << 6) | (*p++ & 0x3F);
        }
        if (ok) out[n++] = c;
    }
    return n;
}

static int utf8_encode(uint32_t c, char *o) {
    if (c < 0x80) { o[0] = (char)c; return 1; }
    if (c < 0x800) { o[0] = (char)(0xC0 | (c >> 6)); o[1] = (char)(0x80 | (c & 0x3F)); return 2; }
    if (c < 0x10000) {
        o[0] = (char)(0xE0 | (c >> 12)); o[1] = (char)(0x80 | ((c >> 6) & 0x3F));
        o[2] = (char)(0x80 | (c & 0x3F)); return 3;
    }
    o[0] = (char)(0xF0 | (c >> 18)); o[1] = (char)(0x80 | ((c >> 12) & 0x3F));
    o[2] = (char)(0x80 | ((c >> 6) & 0x3F)); o[3] = (char)(0x80 | (c & 0x3F)); return 4;
}

/* code points of one word -> letters (tone separated, quality marks merged) */
static void to_letters(const uint32_t *cp, int n, letters_t *L) {
    memset(L, 0, sizeof(*L));
    L->tone = 1;
    L->valid = 1;
    for (int i = 0; i < n; i++) {
        uint32_t c = cp[i];
        int t = tone_mark(c);
        if (t) {
            if (L->tone != 1) L->valid = 0;
            L->tone = t;
            continue;
        }
        if (quality_mark(c)) {
            char *last = L->n ? &L->code[L->n - 1] : NULL;
            if (!last) { L->valid = 0; continue; }
            if (c == 0x0302 && *last == 'a') *last = '2';
            else if (c == 0x0306 && *last == 'a') *last = '1';
            else if (c == 0x0302 && *last == 'e') *last = '3';
            else if (c == 0x0302 && *last == 'o') *last = '4';
            else if (c == 0x031B && *last == 'o') *last = '5';
            else if (c == 0x031B && *last == 'u') *last = '6';
            else L->valid = 0;
            continue;
        }
        if (is_combining(c)) { L->valid = 0; continue; }
        const vtts_letter *v = find_letter(c);
        char code;
        int tone = 1;
        if (v) { code = v->code; tone = v->tone; }
        else if (c < 0x80 && ((c | 32) >= 'a' && (c | 32) <= 'z')) code = (char)(c | 32);
        else if ((code = fold_foreign(c)) != 0) L->foreign = 1;
        else { L->foreign = 1; L->valid = 0; continue; } /* non-Latin letter: dropped */
        if (tone != 1) {
            if (L->tone != 1) L->valid = 0;
            L->tone = tone;
        }
        if (L->n < WORD_CAP) L->code[L->n++] = code;
    }
    if (L->foreign) L->valid = 0;
}

/* ---------------- syllable parse (mirrors syllable.py) ---------------- */

typedef struct { const char *onset; int glide; const char *nucleus; const char *coda; int tone; } syl_t;

static int is_vowel(char c) { return c && strchr("a12e3io45u6y", c) != NULL; }

static const char *const ONSET_KEYS[][2] = {
    {"ngh", "ng"}, {"ng", "ng"}, {"gh", "g"}, {"gi", "gi"}, {"ch", "ch"}, {"tr", "tr"}, {"th", "th"},
    {"ph", "ph"}, {"kh", "kh"}, {"nh", "nh"}, {"b", "b"}, {"c", "k"}, {"k", "k"}, {"d", "d"},
    {"7", "đ"}, {"g", "g"}, {"h", "h"}, {"l", "l"}, {"m", "m"}, {"n", "n"}, {"p", "p"}, {"r", "r"},
    {"s", "s"}, {"t", "t"}, {"v", "v"}, {"x", "x"}, {"f", "ph"}, {"w", "v"}, {"z", "d"}, {"j", "gi"}};

static const char *onset_of(const char *head, size_t len) {
    for (size_t k = 0; k < sizeof(ONSET_KEYS) / sizeof(ONSET_KEYS[0]); k++)
        if (strlen(ONSET_KEYS[k][0]) == len && memcmp(ONSET_KEYS[k][0], head, len) == 0) return ONSET_KEYS[k][1];
    return NULL;
}

typedef struct { const char *key, *nucleus, *off; int open_only; } cluster_t;

static const cluster_t CLUSTERS[] = {
    {"a", "a", 0, 0}, {"1", "ă", 0, 0}, {"2", "â", 0, 0}, {"e", "e", 0, 0}, {"3", "ê", 0, 0},
    {"i", "i", 0, 0}, {"y", "i", 0, 0}, {"o", "o", 0, 0}, {"4", "ô", 0, 0}, {"5", "ơ", 0, 0},
    {"u", "u", 0, 0}, {"6", "ư", 0, 0}, {"oo", "oo", 0, 0}, {"44", "ô", 0, 0},
    {"i3", "iê", 0, 0}, {"y3", "iê", 0, 0}, {"ia", "iê", 0, 1}, {"ya", "iê", 0, 1},
    {"u4", "uô", 0, 0}, {"ua", "uô", 0, 1}, {"65", "ươ", 0, 0}, {"6a", "ươ", 0, 1},
    {"ai", "a", "j", 1}, {"ay", "ă", "j", 1}, {"2y", "â", "j", 1}, {"ao", "a", "w", 1},
    {"au", "ă", "w", 1}, {"2u", "â", "w", 1}, {"eo", "e", "w", 1}, {"3u", "ê", "w", 1},
    {"iu", "i", "w", 1}, {"yu", "i", "w", 1}, {"oi", "o", "j", 1}, {"4i", "ô", "j", 1},
    {"5i", "ơ", "j", 1}, {"ui", "u", "j", 1}, {"6i", "ư", "j", 1}, {"6u", "ư", "w", 1},
    {"i3u", "iê", "w", 1}, {"y3u", "iê", "w", 1}, {"65i", "ươ", "j", 1}, {"65u", "ươ", "w", 1},
    {"u4i", "uô", "j", 1}};

static int parse_syl(const letters_t *L, syl_t *s) {
    if (!L->valid || L->n == 0) return 0;
    char base[WORD_CAP + 2];
    memcpy(base, L->code, (size_t)L->n);
    base[L->n] = 0;
    int n = L->n;
    const char *onset = NULL;
    int glide = 0;
    char rest[WORD_CAP + 2];
    if (n > 2 && base[0] == 'q' && base[1] == 'u') {
        onset = "k"; glide = 1; strcpy(rest, base + 2);
    } else {
        strcpy(rest, base);
        for (int size = 3; size >= 1; size--) {
            if (size > n) continue;
            const char *o = onset_of(base, (size_t)size);
            int gi_alone = size == 2 && memcmp(base, "gi", 2) == 0 && n == 2;
            if (!o || !(n > size || gi_alone)) continue;
            char r[WORD_CAP + 2];
            strcpy(r, base + size);
            if (size == 2 && memcmp(base, "gi", 2) == 0) {
                int any_vowel = 0;
                for (const char *c = r; *c; c++) any_vowel |= is_vowel(*c);
                if (!any_vowel || r[0] == '3') { memmove(r + 1, r, strlen(r) + 1); r[0] = 'i'; }
            }
            if (is_vowel(r[0])) { onset = o; strcpy(rest, r); break; }
        }
        size_t rl = strlen(rest);
        if (rl >= 2 && ((rest[0] == 'o' && strchr("a1e", rest[1])) || (rest[0] == 'u' && strchr("3y25", rest[1])))) {
            glide = 1;
            memmove(rest, rest + 1, rl);
        }
    }
    static const char *const CODAS[][2] = {{"ng", "ng"}, {"nh", "nh"}, {"ch", "ch"}, {"c", "c"},
                                           {"m", "m"}, {"n", "n"}, {"p", "p"}, {"t", "t"}};
    const char *coda = NULL;
    size_t rl = strlen(rest);
    for (size_t k = 0; k < 8; k++) {
        size_t cl = strlen(CODAS[k][0]);
        if (rl > cl && memcmp(rest + rl - cl, CODAS[k][0], cl) == 0) {
            coda = CODAS[k][1];
            rest[rl - cl] = 0;
            break;
        }
    }
    const cluster_t *cl = NULL;
    for (size_t k = 0; k < sizeof(CLUSTERS) / sizeof(CLUSTERS[0]); k++)
        if (strcmp(CLUSTERS[k].key, rest) == 0) { cl = &CLUSTERS[k]; break; }
    if (!cl) return 0;
    if (cl->off || cl->open_only) {
        if (coda) return 0;
        if (cl->off) coda = cl->off;
    }
    s->onset = onset; s->glide = glide; s->nucleus = cl->nucleus; s->coda = coda; s->tone = L->tone;
    return 1;
}

/* ---------------- tokens ---------------- */

static int token_id(const char *prefix, const char *name) {
    char buf[16];
    size_t pl = strlen(prefix), nl = strlen(name);
    if (pl + nl >= sizeof buf) return -1;
    memcpy(buf, prefix, pl);
    memcpy(buf + pl, name, nl + 1);
    for (int i = 0; i < VTTS_N_TOKENS; i++) if (strcmp(VTTS_TOKENS[i], buf) == 0) return i;
    return -1;
}

static int is_punct_word(const char *w) {
    return w[1] == 0 && strchr(",.?!;:", w[0]) != NULL;
}

/* ---------------- normalized word buffer ---------------- */

typedef struct {
    vtts_text_ws *ws;
    vtts_ids_cb cb;
    void *user;
    int chunks, stop;
    int collect; /* v2: only collect normalized words (the caller assembles chunks) */
} ctx_t;

static void emit_sentence(ctx_t *c);

static const char *last_word(vtts_text_ws *ws) {
    return ws->n_words ? ws->words + ws->word_off[ws->n_words - 1] : NULL;
}

static void push_raw(ctx_t *c, const char *w) {
    vtts_text_ws *ws = c->ws;
    size_t len = strlen(w);
    if (ws->n_words >= VTTS_TEXT_MAX_WORDS || ws->words_used + (int)len + 1 > VTTS_TEXT_WORD_BYTES) {
        if (c->collect) return; /* v2: drop the rest of an oversized run (pathological input) */
        emit_sentence(c); /* overflow: flush early (only for pathological input) */
    }
    ws->word_off[ws->n_words++] = ws->words_used;
    memcpy(ws->words + ws->words_used, w, len + 1);
    ws->words_used += (int)len + 1;
}

/* append a normalized item: punctuation dedup like normalize(), terminators end a sentence */
static void push_word(ctx_t *c, const char *w) {
    if (is_punct_word(w)) {
        const char *lw = last_word(c->ws);
        if (!lw || is_punct_word(lw)) {
            /* leading or repeated punctuation is dropped; but a terminator after a flushed
             * sentence also lands here and is correctly dropped */
            return;
        }
        push_raw(c, w);
        if (!c->collect && strchr(".!?;", w[0])) emit_sentence(c);
        return;
    }
    push_raw(c, w);
}

/* push a space-separated phrase of words */
static void push_phrase(ctx_t *c, const char *p) {
    char w[96];
    while (*p) {
        while (*p == ' ') p++;
        size_t n = strcspn(p, " ");
        if (!n) break;
        if (n >= sizeof w) n = sizeof w - 1;
        memcpy(w, p, n);
        w[n] = 0;
        push_word(c, w);
        p += n;
    }
}

/* ---------------- numbers (mirrors numbers.py) ---------------- */

static const char *const DIGITS[10] = {"không", "một", "hai", "ba", "bốn", "năm", "sáu", "bảy", "tám", "chín"};

static void read_digits(ctx_t *c, const char *d, size_t n) {
    for (size_t i = 0; i < n; i++) push_word(c, DIGITS[d[i] - '0']);
}

static void read_group(ctx_t *c, int v, int leading, int *said) {
    int h = v / 100, t = v / 10 % 10, u = v % 10;
    int words = 0;
    if (h || !leading) { push_word(c, DIGITS[h]); push_word(c, "trăm"); words = 1; }
    if (t == 0) {
        if (u) { if (words) push_word(c, "linh"); push_word(c, DIGITS[u]); }
    } else if (t == 1) {
        push_word(c, "mười");
        if (u) push_word(c, u == 5 ? "lăm" : DIGITS[u]);
    } else {
        push_word(c, DIGITS[t]);
        push_word(c, "mươi");
        if (u) push_word(c, u == 1 ? "mốt" : u == 4 ? "tư" : u == 5 ? "lăm" : DIGITS[u]);
    }
    *said = 1;
}

/* integer given as a digit string without leading zeros (or "0") */
static void read_int_str(ctx_t *c, const char *d, size_t n) {
    static const char *const SCALES[5] = {"", "nghìn", "triệu", "tỷ", "nghìn tỷ"};
    while (n > 1 && *d == '0') { d++; n--; }
    if (n > 15) { read_digits(c, d, n); return; }
    if (n == 1 && d[0] == '0') { push_word(c, DIGITS[0]); return; }
    int groups = (int)((n + 2) / 3), said = 0;
    size_t first = n - (size_t)(groups - 1) * 3;
    size_t pos = 0;
    for (int gi = groups - 1; gi >= 0; gi--) {
        size_t len = gi == groups - 1 ? first : 3;
        int v = 0;
        for (size_t k = 0; k < len; k++) v = v * 10 + (d[pos + k] - '0');
        pos += len;
        if (v == 0) continue;
        read_group(c, v, !said, &said);
        if (SCALES[gi][0]) push_phrase(c, SCALES[gi]);
    }
}

static void read_unsigned(ctx_t *c, const char *s, size_t n);

static void read_fraction(ctx_t *c, const char *s, size_t n) {
    int all_digits = 1;
    for (size_t i = 0; i < n; i++) all_digits &= is_digit_cp((unsigned char)s[i]);
    if (!all_digits) { read_unsigned(c, s, n); return; }
    if (s[0] == '0') read_digits(c, s, n); else read_int_str(c, s, n);
}

static int is_thousands(const char *s, size_t n) {
    size_t i = 0, run = 0;
    while (i < n && is_digit_cp((unsigned char)s[i])) { i++; run++; }
    if (run < 1 || run > 3 || i == n) return 0;
    while (i < n) {
        if (s[i] != '.') return 0;
        i++;
        size_t r = 0;
        while (i < n && is_digit_cp((unsigned char)s[i])) { i++; r++; }
        if (r != 3) return 0;
    }
    return 1;
}

static void read_unsigned(ctx_t *c, const char *s, size_t n) {
    const char *comma = memchr(s, ',', n);
    if (comma) {
        read_unsigned(c, s, (size_t)(comma - s));
        push_word(c, "phẩy");
        read_fraction(c, comma + 1, n - (size_t)(comma - s) - 1);
        return;
    }
    if (is_thousands(s, n)) {
        char buf[64];
        size_t k = 0;
        for (size_t i = 0; i < n && k < sizeof buf - 1; i++) if (s[i] != '.') buf[k++] = s[i];
        read_int_str(c, buf, k);
        return;
    }
    const char *dot = memchr(s, '.', n);
    if (dot) {
        read_unsigned(c, s, (size_t)(dot - s));
        push_word(c, "chấm");
        read_fraction(c, dot + 1, n - (size_t)(dot - s) - 1);
        return;
    }
    if (n > 1 && s[0] == '0') { read_digits(c, s, n); return; }
    read_int_str(c, s, n);
}

static void read_number_token(ctx_t *c, const char *s, size_t n) {
    if (n && s[0] == '-') { push_word(c, "âm"); read_unsigned(c, s + 1, n - 1); return; }
    read_unsigned(c, s, n);
}

static void read_int_v(ctx_t *c, long v) {
    char b[24];
    int k = 0;
    if (v == 0) b[k++] = '0';
    char t[24];
    int m = 0;
    while (v > 0 && m < 23) { t[m++] = (char)('0' + v % 10); v /= 10; }
    while (m) b[k++] = t[--m];
    read_int_str(c, b, (size_t)k);
}

/* ---------------- words ---------------- */

static void letters_to_utf8(const letters_t *L, char *out, size_t cap);

static void spell(ctx_t *c, const letters_t *L) {
    for (int i = 0; i < L->n; i++) {
        char code = L->code[i];
        char key[4] = {0};
        if (L->tone != 1 && !L->foreign) {
            /* a toned quality letter is not in the table: Python falls back to its NFD base */
        }
        switch (code) {
        case '1': strcpy(key, "ă"); break;
        case '2': strcpy(key, "â"); break;
        case '3': strcpy(key, "ê"); break;
        case '4': strcpy(key, "ô"); break;
        case '5': strcpy(key, "ơ"); break;
        case '6': strcpy(key, "ư"); break;
        case '7': strcpy(key, "đ"); break;
        default: key[0] = code;
        }
        for (int k = 0; k < VTTS_N_LETTER_NAMES; k++)
            if (strcmp(VTTS_LETTER_NAMES[k][0], key) == 0) { push_phrase(c, VTTS_LETTER_NAMES[k][1]); break; }
    }
}

static int letters_equal_key(const letters_t *L, const char *key_utf8) {
    uint32_t cp[WORD_CAP];
    int n = utf8_decode(key_utf8, cp, WORD_CAP);
    letters_t K;
    to_letters(cp, n, &K);
    return K.n == L->n && K.tone == L->tone && memcmp(K.code, L->code, (size_t)L->n) == 0;
}

/* lowercase canonical UTF-8 of a valid syllable (tone placement does not matter for ids,
 * because ids are produced from the parsed syllable, not from this string) */
static void letters_to_utf8(const letters_t *L, char *out, size_t cap) {
    size_t k = 0;
    for (int i = 0; i < L->n && k + 8 < cap; i++) {
        uint32_t c;
        switch (L->code[i]) {
        case '1': c = 0x103; break;
        case '2': c = 0xE2; break;
        case '3': c = 0xEA; break;
        case '4': c = 0xF4; break;
        case '5': c = 0x1A1; break;
        case '6': c = 0x1B0; break;
        case '7': c = 0x111; break;
        default: c = (unsigned char)L->code[i];
        }
        k += (size_t)utf8_encode(c, out + k);
    }
    if (L->tone != 1 && k + 3 < cap) {
        static const uint32_t marks[7] = {0, 0, 0x300, 0x301, 0x309, 0x303, 0x323};
        k += (size_t)utf8_encode(marks[L->tone], out + k);
    }
    out[k] = 0;
}

/* one letter run: syllable, loanword or spelled letters */
static void push_letters(ctx_t *c, const uint32_t *cp, int n) {
    letters_t L;
    to_letters(cp, n, &L);
    if (L.n == 0) return;
    syl_t s;
    if (parse_syl(&L, &s)) {
        char w[WORD_CAP * 4 + 8];
        letters_to_utf8(&L, w, sizeof w);
        push_word(c, w);
        return;
    }
    if (!L.foreign && L.tone == 1)
        for (int k = 0; k < VTTS_N_LOANWORDS; k++)
            if (letters_equal_key(&L, VTTS_LOANWORDS[k][0])) { push_phrase(c, VTTS_LOANWORDS[k][1]); return; }
    if (L.tone != 1) {
        /* Python spells toned quality letters by their NFD base */
        letters_t B = L;
        for (int i = 0; i < B.n; i++) {
            char *x = &B.code[i];
            if (*x == '1' || *x == '2') *x = 'a';
            else if (*x == '3') *x = 'e';
            else if (*x == '4' || *x == '5') *x = 'o';
            else if (*x == '6') *x = 'u';
        }
        /* only the letter that carried the tone loses its quality mark in Python; approximate
         * by folding all quality letters when the word is toned */
        spell(c, &B);
        return;
    }
    spell(c, &L);
}

/* ---------------- sentence -> chunks -> ids ---------------- */

static int count_syl(vtts_text_ws *ws, int a, int b) {
    int n = 0;
    for (int i = a; i < b; i++) n += !is_punct_word(ws->words + ws->word_off[i]);
    return n;
}

static void emit_chunk(ctx_t *c, int a, int b) {
    vtts_text_ws *ws = c->ws;
    if (c->stop || count_syl(ws, a, b) == 0) return;
    int n = 0, last_space = 0, last_punct = 0;
    int bos = token_id("", "<bos>"), eos = token_id("", "<eos>"), space = token_id("", " ");
    ws->ids[n++] = bos;
    for (int i = a; i < b && n < VTTS_TEXT_MAX_IDS - 8; i++) {
        const char *w = ws->words + ws->word_off[i];
        if (is_punct_word(w)) {
            if (last_space) { n--; last_space = 0; }
            if (n > 1) { ws->ids[n++] = token_id("", w); last_punct = 1; }
            continue;
        }
        uint32_t cp[WORD_CAP];
        int m = utf8_decode(w, cp, WORD_CAP);
        letters_t L;
        to_letters(cp, m, &L);
        syl_t s;
        if (!parse_syl(&L, &s)) continue;
        if (n > 1 && !last_punct) ws->ids[n++] = space;
        if (s.onset) ws->ids[n++] = token_id("O:", s.onset);
        if (s.glide) ws->ids[n++] = token_id("", "G:w");
        ws->ids[n++] = token_id("N:", s.nucleus);
        if (s.coda) ws->ids[n++] = token_id("C:", s.coda);
        char t[4] = {'T', (char)('0' + s.tone), 0};
        ws->ids[n++] = token_id("", t);
        last_space = 0;
        last_punct = 0;
    }
    ws->ids[n++] = eos;
    c->chunks++;
    if (c->cb && c->cb(ws->ids, n, c->user)) c->stop = 1;
}

/* mirrors text._pack: split after soft breaks, pack pieces up to MAX_SYL, hard-cut long pieces */
static void emit_sentence(ctx_t *c) {
    vtts_text_ws *ws = c->ws;
    int N = ws->n_words;
    int cur_a = -1, cur_b = -1, cur_n = 0;
    int i = 0;
    while (i < N) {
        int p0 = i;
        while (i < N) {
            const char *w = ws->words + ws->word_off[i];
            i++;
            if (is_punct_word(w) && (w[0] == ',' || w[0] == ':')) break;
        }
        int p1 = i, pn = count_syl(ws, p0, p1);
        if (pn > MAX_SYL) {
            if (cur_a >= 0) { emit_chunk(c, cur_a, cur_b); cur_a = -1; cur_n = 0; }
            int b0 = p0, bn = 0;
            for (int k = p0; k < p1; k++) {
                const char *w = ws->words + ws->word_off[k];
                if (!is_punct_word(w) && bn == MAX_SYL) { emit_chunk(c, b0, k); b0 = k; bn = 0; }
                bn += !is_punct_word(w);
            }
            cur_a = b0; cur_b = p1; cur_n = bn;
        } else if (cur_n + pn > MAX_SYL) {
            if (cur_a >= 0) emit_chunk(c, cur_a, cur_b);
            cur_a = p0; cur_b = p1; cur_n = pn;
        } else {
            if (cur_a < 0) cur_a = p0;
            cur_b = p1;
            cur_n += pn;
        }
    }
    if (cur_a >= 0) emit_chunk(c, cur_a, cur_b);
    ws->n_words = 0;
    ws->words_used = 0;
}

/* ---------------- scanner (mirrors normalize._expand order) ---------------- */

static int match_ascii(const uint32_t *cp, int n, int i, const char *s) {
    for (int k = 0; s[k]; k++) if (i + k >= n || cp[i + k] != (unsigned char)s[k]) return 0;
    return 1;
}

static int digits_at(const uint32_t *cp, int n, int i) {
    int k = 0;
    while (i + k < n && is_digit_cp(cp[i + k])) k++;
    return k;
}

static long num_at(const uint32_t *cp, int i, int len) {
    long v = 0;
    for (int k = 0; k < len; k++) v = v * 10 + (long)(cp[i + k] - '0');
    return v;
}

static int prev_is(const uint32_t *cp, int i, int (*pred)(uint32_t)) { return i > 0 && pred(cp[i - 1]); }

static int is_code_cp(uint32_t c) { return (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'); }
static int is_word_or_dotcomma(uint32_t c) { return is_word_cp(c) || c == '.' || c == ','; }
static int is_digit_or_slash(uint32_t c) { return is_digit_cp(c) || c == '/'; }

/* absorb a preceding "ngày" (as in "ngày 2/9") */
static int same_word(const char *a, const char *b) {
    uint32_t ca[WORD_CAP], cb[WORD_CAP];
    letters_t la, lb;
    to_letters(ca, utf8_decode(a, ca, WORD_CAP), &la);
    to_letters(cb, utf8_decode(b, cb, WORD_CAP), &lb);
    return la.n == lb.n && la.tone == lb.tone && memcmp(la.code, lb.code, (size_t)la.n) == 0;
}

static int pop_ngay(ctx_t *c) {
    const char *lw = last_word(c->ws);
    if (lw && same_word(lw, "ngày")) {
        c->ws->n_words--;
        c->ws->words_used = c->ws->word_off[c->ws->n_words];
        return 1;
    }
    return 0;
}

static void read_date(ctx_t *c, long d, long mo, long y, int had_ngay) {
    if (d >= 1 && d <= 31 && mo >= 1 && mo <= 12) {
        push_word(c, "ngày"); read_int_v(c, d); push_word(c, "tháng"); read_int_v(c, mo);
        if (y >= 0) { push_word(c, "năm"); read_int_v(c, y); }
        return;
    }
    if (had_ngay) push_word(c, "ngày");
    read_int_v(c, d); push_word(c, "trên"); read_int_v(c, mo);
    if (y >= 0) read_int_v(c, y);
}

/* normalize() of n code points (modified in place: ellipsis and dashes mapped first, like
 * normalize()); fl is a flag array of n bytes (dates, product codes). Pushes words into ctx. */
static void scan_vi(ctx_t *c, uint32_t *cpm, uint8_t *fl, int n) {
    vtts_text_ws *ws = c->ws;
    (void)ws;
    for (int k = 0; k < n; k++) {
        if (cpm[k] == 0x2026) cpm[k] = '.';
        else if (cpm[k] == 0x2013 || cpm[k] == 0x2014) cpm[k] = ',';
    }
    const uint32_t *cp = cpm;
    int i = 0;
    for (int q = 0; q < n; q++) {
        fl[q] = 0;
        int dl = digits_at(cp, n, q);
        if (dl < 1 || dl > 2 || prev_is(cp, q, is_digit_cp) || q + dl >= n || cp[q + dl] != '/') continue;
        int m0 = q + dl + 1, ml = digits_at(cp, n, m0);
        if (ml < 1 || ml > 2) continue;
        int yl = (m0 + ml < n && cp[m0 + ml] == '/') ? digits_at(cp, n, m0 + ml + 1) : 0;
        int y_end = m0 + ml + 1 + 4;
        if (yl == 4 && !(y_end < n && is_digit_cp(cp[y_end]))) fl[q] = 1;
        else if (!prev_is(cp, q, is_digit_or_slash) && !(m0 + ml < n && is_digit_or_slash(cp[m0 + ml])))
            fl[q] = 1;
    }
    /* product codes (normalize.PRODUCT_CODE): a standalone run of A-Z and 0-9 with at least one
     * of each, e.g. ESP32, S3, RTX3060. Bit 1 marks its digits, which are read one by one. */
    for (int q = 0; q < n;) {
        if (prev_is(cp, q, is_word_cp) || !is_code_cp(cp[q])) { q++; continue; }
        int j = q, up = 0, dg = 0;
        while (j < n && is_code_cp(cp[j])) { up |= cp[j] >= 'A' && cp[j] <= 'Z'; dg |= is_digit_cp(cp[j]); j++; }
        if (up && dg && !(j < n && is_word_cp(cp[j])))
            for (int k = q; k < j; k++) if (is_digit_cp(cp[k])) fl[k] |= 2;
        q = j;
    }
    while (i < n && !c->stop) {
        uint32_t ch = cp[i];
        /* abbreviations (case-sensitive, not preceded by a word character) */
        if (!prev_is(cp, i, is_word_cp)) {
            int hit = 0;
            for (int k = 0; k < VTTS_N_ABBREVIATIONS && !hit; k++) {
                const char *key = VTTS_ABBREVIATIONS[k][0];
                size_t kl = strlen(key);
                if (!match_ascii(cp, n, i, key)) continue;
                if (key[kl - 1] != '.' && i + (int)kl < n && is_word_cp(cp[i + kl])) continue;
                push_phrase(c, VTTS_ABBREVIATIONS[k][1]);
                i += (int)kl;
                hit = 1;
            }
            if (hit) continue;
        }
        if (is_digit_cp(ch) && (fl[i] & 2)) { /* digits of a product code */
            int j = i;
            char d[64];
            int k = 0;
            while (j < n && (fl[j] & 2) && k < 63) d[k++] = (char)cp[j++];
            read_digits(c, d, (size_t)k);
            i = j;
            continue;
        }
        if (is_digit_cp(ch) || (ch == '-' && i + 1 < n && is_digit_cp(cp[i + 1]) && !prev_is(cp, i, is_word_or_dotcomma))) {
            int start = i, neg = ch == '-';
            int d0 = neg ? i + 1 : i;
            int dl = digits_at(cp, n, d0);
            /* dates */
            if (!neg && dl <= 2 && !prev_is(cp, d0, is_digit_cp) && d0 + dl < n && cp[d0 + dl] == '/') {
                int m0 = d0 + dl + 1, ml = digits_at(cp, n, m0);
                if (ml >= 1 && ml <= 2) {
                    int y0 = m0 + ml + 1, yl = (m0 + ml < n && cp[m0 + ml] == '/') ? digits_at(cp, n, y0) : 0;
                    if (yl == 4 && !(y0 + 4 < n && is_digit_cp(cp[y0 + 4]))) {
                        int had = pop_ngay(c);
                        read_date(c, num_at(cp, d0, dl), num_at(cp, m0, ml), num_at(cp, y0, 4), had);
                        i = y0 + 4;
                        continue;
                    }
                    if (!prev_is(cp, d0, is_digit_or_slash) && !(m0 + ml < n && is_digit_or_slash(cp[m0 + ml]))) {
                        int had = pop_ngay(c);
                        read_date(c, num_at(cp, d0, dl), num_at(cp, m0, ml), -1, had);
                        i = m0 + ml;
                        continue;
                    }
                }
            }
            /* times: 8:30, 8h30, 8h */
            if (!neg && dl <= 2 && !prev_is(cp, d0, is_digit_cp) && d0 + dl < n && (cp[d0 + dl] == ':' || cp[d0 + dl] == 'h')) {
                int m0 = d0 + dl + 1, ml = digits_at(cp, n, m0);
                if (ml == 2 && !(m0 + 2 < n && is_digit_cp(cp[m0 + 2]))) {
                    long h = num_at(cp, d0, dl), mi = num_at(cp, m0, 2);
                    read_int_v(c, h);
                    if (h <= 24 && mi < 60) { push_word(c, "giờ"); read_int_v(c, mi); push_word(c, "phút"); }
                    else read_int_v(c, mi);
                    i = m0 + 2;
                    continue;
                }
                if (cp[d0 + dl] == 'h' && !(m0 < n && is_word_cp(cp[m0]))) {
                    read_int_v(c, num_at(cp, d0, dl));
                    push_word(c, "giờ");
                    i = m0;
                    continue;
                }
            }
            /* number token -?\d+([.,]\d+)* */
            int j = d0 + dl;
            while (j + 1 < n && (cp[j] == '.' || cp[j] == ',') && is_digit_cp(cp[j + 1]) && !(fl[j + 1] & 1))
                j += 1 + digits_at(cp, n, j + 1);
            char buf[128];
            int k = 0;
            for (int q = start; q < j && k < 127; q++) buf[k++] = (char)cp[q];
            buf[k] = 0;
            int lookbehind_ok = !prev_is(cp, start, is_word_or_dotcomma);
            /* percent */
            int pj = j;
            if (pj < n && is_space_cp(cp[pj])) pj++;
            if (lookbehind_ok && pj < n && cp[pj] == '%') {
                read_number_token(c, buf, (size_t)k);
                push_phrase(c, "phần trăm");
                i = pj + 1;
                continue;
            }
            /* degrees: 25°C, 30° */
            if (lookbehind_ok && pj < n && cp[pj] == 0xB0) {
                read_number_token(c, buf, (size_t)k);
                if (pj + 1 < n && cp[pj + 1] == 'C' && !(pj + 2 < n && is_word_cp(cp[pj + 2]))) {
                    push_phrase(c, "độ xê");
                    i = pj + 2;
                    continue;
                    continue;
                }
                if (!(pj + 1 < n && is_word_cp(cp[pj + 1]))) {
                    push_word(c, "độ");
                    i = pj + 1;
                    continue;
                }
                i = j; /* "40°bắc": the sign is dropped later, like Python */
                continue;
            }
            if (lookbehind_ok) {
                read_number_token(c, buf, (size_t)k);
                i = j;
                continue;
            }
            /* preceded by '.', ',' or a word character: Python leaves the run untouched and later
             * reads each digit group on its own, with '.'/',' as punctuation */
            for (int q = d0; q < j;) {
                if (cp[q] == '.' || cp[q] == ',') {
                    char w[2] = {(char)cp[q], 0};
                    push_word(c, w);
                    q++;
                    continue;
                }
                int ql = digits_at(cp, n, q);
                char g[64];
                int gk = 0;
                for (int r = 0; r < ql && gk < 63; r++) g[gk++] = (char)cp[q + r];
                read_number_token(c, g, (size_t)gk);
                q += ql;
            }
            i = j;
            continue;
        }
        if (is_letter_cp(ch)) {
            int j = i;
            while (j < n && (is_letter_cp(cp[j]) || is_combining(cp[j]))) j++;
            push_letters(c, cp + i, j - i);
            i = j;
            continue;
        }
        switch (ch) {
        case ',': case '.': case '?': case '!': case ';': case ':': {
            char w[2] = {(char)ch, 0};
            push_word(c, w);
            break;
        }
        case 0x2026: push_word(c, "."); break;          /* … */
        case 0x2013: case 0x2014: push_word(c, ","); break; /* – — */
        case '+': push_word(c, "cộng"); break;
        case '=': push_word(c, "bằng"); break;
        case '&': push_word(c, "và"); break;
        case '@': push_phrase(c, "a còng"); break;
        default: break; /* separators, quotes, brackets, symbols, emoji */
        }
        i++;
    }
}

int vtts_text_to_ids(const char *utf8, vtts_text_ws *ws, vtts_ids_cb cb, void *user) {
    if (!utf8 || !ws) return -1;
    ctx_t ctx = {ws, cb, user, 0, 0, 0}, *c = &ctx;
    ws->n_cp = utf8_decode(utf8, ws->cp, VTTS_TEXT_MAX_CP);
    ws->n_words = ws->words_used = 0;
    scan_vi(c, ws->cp, ws->date_start, ws->n_cp);
    if (!c->stop && ws->n_words) emit_sentence(c);
    return c->chunks;
}

/* =================== bilingual front-end (phoneme set v2), mirrors text.py =================== */

#include "vtts_text_en.h"
#include "vtts_text_zh.h"
#include "vtts_text_ko.h"
#include "vtts_text_hi.h"
#include "vtts_text_ja.h"
#include "vtts_text_lt.h"
#include "vtts_text_th.h"
#include "vtts_text_fr.h"
#include "vtts_text_de.h"
#include "vtts_text_it.h"
#include "vtts_text_tr.h"
#include "vtts_text_ru.h"
#include "vtts_text_pl.h"
#include "vtts_text_ar.h"
#include "vtts_text_fi.h"
#include "vtts_text_el.h"
#include "vtts_text_tl.h"
#include "vtts_text_sw.h"
#include "vtts_text_nx.h"
#include "vtts_text_lo.h" /* VTTS_ENABLE_LO */
#include "vtts_text_da.h" /* VTTS_ENABLE_DA */
#if VTTS_ENABLE_KM
#include "vtts_text_km.h"
#endif
#if VTTS_ENABLE_MY
#include "vtts_text_my.h"
#endif
#include "vtts_text_sent_tables.h"

#define V2_MAX_WORDS 40
#define V2_MAX_TOKENS 318

/* lang.py: EDGE characters stripped from a chunk before tagging */
static int is_edge(uint32_t c) {
    static const uint32_t E[] = {'.', ',', ';', ':', '!', '?', '"', '\'', '(', ')', '[', ']', '{', '}',
                                 0x2026, 0x201C, 0x201D, 0x2018, 0x2019, 0x00AB, 0x00BB, 0x2013, 0x2014,
                                 0x060C, 0x061B, 0x061F}; /* Arabic comma, semicolon, question mark */
    for (size_t i = 0; i < sizeof E / sizeof *E; i++) if (E[i] == c) return 1;
    return 0;
}

static int ascii_alpha(uint32_t c) { return (c | 32) >= 'a' && (c | 32) <= 'z'; }

/* _has_vietnamese_letters: a non-ASCII letter after NFC (a combining mark on a Latin letter composes) */
static int has_vi_letters(const uint32_t *w, int n) {
    for (int i = 0; i < n; i++) {
        if (w[i] >= 0x80 && is_letter_cp(w[i])) return 1;
        if (is_combining(w[i]) && i > 0 && ascii_alpha(w[i - 1])) return 1;
    }
    return 0;
}

static int any_alpha(const uint32_t *w, int n) {
    for (int i = 0; i < n; i++) if (is_letter_cp(w[i])) return 1;
    return 0;
}

static int plain_latin(const uint32_t *w, int n) {
    int alpha = 0;
    for (int i = 0; i < n; i++) {
        if (w[i] >= 0x80 || !(ascii_alpha(w[i]) || w[i] == '-' || w[i] == '\'')) return 0;
        alpha |= ascii_alpha(w[i]);
    }
    return n > 0 && alpha;
}

static int ascii_syllable(const uint32_t *w, int n) { /* parse_syllable(p.lower()) is not None */
    uint32_t low[WORD_CAP];
    if (n <= 0 || n > WORD_CAP) return 0;
    for (int i = 0; i < n; i++) low[i] = w[i] | 32;
    letters_t L;
    to_letters(low, n, &L);
    syl_t s;
    return parse_syl(&L, &s);
}

enum { TAG_NEUTRAL = -1, TAG_VI = 0, TAG_EN = 1, TAG_ZH = 2, TAG_KO = 3, TAG_HI = 4, TAG_JA = 5, TAG_ES = 6,
       TAG_ID = 7, TAG_PT = 8, TAG_TH = 9, TAG_FR = 10,
       TAG_DE = 11, TAG_IT = 12, TAG_TR = 13,
       TAG_RU = 14, TAG_PL = 15, TAG_AR = 16, TAG_FI = 17,
       TAG_EL = 18, TAG_MS = 19, TAG_TL = 20, TAG_SW = 21,
       TAG_NX = 22, /* TAG_NX + VTTS_NX_* (nl sv no) */ TAG_DA = TAG_NX + 3, TAG_LO = TAG_DA + 1,
       TAG_KM = TAG_LO + 1, TAG_MY = TAG_KM + 1, TAG_LAST = TAG_MY + 1 }; /* indices into LANGS; TAG_ES + VTTS_LT_* */

static int key_eq(const uint32_t *w, int n, const char *k, int lower) {
    int i = 0;
    for (; k[i]; i++) if (i >= n || (lower ? (w[i] | 32) : w[i]) != (unsigned char)k[i]) return 0;
    return i == n;
}

/* word_lang(core, mode) */
static int word_tag(const uint32_t *w, int n, int sent_en) {
    if (n == 0) return TAG_NEUTRAL;
    if (has_vi_letters(w, n)) return TAG_VI;
    if (!plain_latin(w, n)) return TAG_NEUTRAL;
    if (sent_en) return TAG_EN;
    int all_syl = 1, all_caps = 1, parts = 0;
    for (int a = 0; a < n;) {
        int b = a;
        while (b < n && w[b] != '-' && w[b] != '\'') b++;
        if (b > a) {
            parts++;
            all_syl &= ascii_syllable(w + a, b - a);
            int up = b - a <= 5;
            for (int k = a; k < b; k++) up &= w[k] >= 'A' && w[k] <= 'Z';
            all_caps &= up;
        }
        a = b + 1;
    }
    if (parts && all_syl) return TAG_VI;
    for (int k = 0; k < VTTS_N_LOANWORDS; k++) if (key_eq(w, n, VTTS_LOANWORDS[k][0], 1)) return TAG_VI;
    for (int k = 0; k < VTTS_N_ABBREVIATIONS; k++) if (key_eq(w, n, VTTS_ABBREVIATIONS[k][0], 0)) return TAG_VI;
    if (parts && all_caps) return TAG_VI;
    return TAG_EN;
}

/* syllable tokens of a normalized Vietnamese word into out; 0 if not a syllable */
static int syl_ids(const char *word, uint8_t *out) {
    uint32_t cp[WORD_CAP];
    int m = utf8_decode(word, cp, WORD_CAP), n = 0;
    letters_t L;
    to_letters(cp, m, &L);
    syl_t s;
    if (!parse_syl(&L, &s)) return 0;
    if (s.onset) out[n++] = (uint8_t)token_id("O:", s.onset);
    if (s.glide) out[n++] = (uint8_t)token_id("", "G:w");
    out[n++] = (uint8_t)token_id("N:", s.nucleus);
    if (s.coda) out[n++] = (uint8_t)token_id("C:", s.coda);
    char t[4] = {'T', (char)('0' + s.tone), 0};
    out[n++] = (uint8_t)token_id("", t);
    return n;
}

static void add_item(vtts_text_ws *ws, const uint8_t *ids, int n, int punct, int join) {
    if (ws->n_items >= VTTS_TEXT_MAX_ITEMS || ws->pool_used + n > VTTS_TEXT_POOL) return;
    ws->item_off[ws->n_items] = (uint16_t)ws->pool_used;
    ws->item_len[ws->n_items] = (uint16_t)n;
    ws->item_punct[ws->n_items] = (uint8_t)(punct ? ids[0] : 0);
    ws->item_join[ws->n_items] = (uint8_t)join;
    memcpy(ws->pool + ws->pool_used, ids, (size_t)n);
    ws->pool_used += n;
    ws->n_items++;
}

static int last_is_word(const vtts_text_ws *ws) { return ws->n_items && !ws->item_punct[ws->n_items - 1]; }

/* ---- language modules (mirror src/vtts/frontend/languages.py) ----
 * normalize: the words of one same-language run into ws->words (punctuation marks included);
 * word_ids: token ids of one normalized word, 0 if it cannot be pronounced (NULL with add_word);
 * add_word (optional, for a language written without spaces or with long items): adds the items of
 * one normalized word itself, like word_units in Python (the first syllable is a word, the next
 * ones are joined to it without SPACE).
 * Adding a language: one entry here, its tag rule in word_tag(), its tables and tests. */
typedef struct {
    const char *code;
    void (*normalize)(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o);
    int (*word_ids)(const char *w, const vtts_text_opts *o, uint8_t *out, int cap);
    void (*add_word)(vtts_text_ws *ws, const char *w, const vtts_text_opts *o);
} lang_mod_t;

static void vi_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) {
    (void)o;
    c->collect = 1;
    scan_vi(c, run, c->ws->date_start, n);
    c->collect = 0;
}

static int vi_word_ids(const char *w, const vtts_text_opts *o, uint8_t *out, int cap) {
    (void)o;
    return cap >= 8 ? syl_ids(w, out) : 0;
}

static void en_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) {
    vtts_text_ws *ws = c->ws;
    (void)o;
    if (vtts_en_normalize(run, n, ws->en_a, ws->en_b, VTTS_TEXT_EN_CAP, ws->en_out, (int)sizeof ws->en_out) < 0) return;
    for (char *w = ws->en_out; *w;) { /* split on single spaces */
        char *sp = strchr(w, ' ');
        if (sp) *sp = 0;
        if (*w) push_raw(c, w);
        if (!sp) break;
        w = sp + 1;
    }
}

static int en_word_ids(const char *w, const vtts_text_opts *o, uint8_t *out, int cap) {
    return vtts_en_g2p(o->lex, w, out, cap);
}

#if defined(__GNUC__)
#define VTTS_MAYBE_UNUSED __attribute__((unused)) /* used only by some optional languages */
#else
#define VTTS_MAYBE_UNUSED
#endif

/* one word of n code points into ws->words as UTF-8 (dropped when full, like push_raw) */
VTTS_MAYBE_UNUSED static void push_cps(ctx_t *c, const uint32_t *cp, int n) {
    vtts_text_ws *ws = c->ws;
    if (ws->n_words >= VTTS_TEXT_MAX_WORDS || ws->words_used + 4 * n + 1 > VTTS_TEXT_WORD_BYTES) return;
    int k = ws->words_used;
    ws->word_off[ws->n_words++] = k;
    for (int i = 0; i < n; i++) k += utf8_encode(cp[i], ws->words + k);
    ws->words[k++] = 0;
    ws->words_used = k;
}

/* the reading callback of zh and ja, its state also th's (one unit per syllable / reading unit,
 * joined to the first) */
#if VTTS_ENABLE_ZH || VTTS_ENABLE_JA || VTTS_ENABLE_TH || VTTS_ENABLE_LO || VTTS_ENABLE_KM || VTTS_ENABLE_MY
typedef struct { vtts_text_ws *ws; int n; } zh_units_t;
#endif

#if VTTS_ENABLE_ZH || VTTS_ENABLE_JA
static void zh_unit(void *user, const uint8_t *ids, int n) {
    zh_units_t *u = user;
    add_item(u->ws, ids, n, 0, u->n++ > 0);
}
#endif

#if VTTS_ENABLE_ZH
/* normalize_zh; its result holds words separated by single spaces. ws->run (the input) is free
 * once the first pass has copied it, so its halves are the English normalizer's scratch. */
static void zh_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) {
    vtts_text_ws *ws = c->ws;
    const uint32_t *r = NULL;
    const int half = VTTS_TEXT_MAX_CP / 2;
    (void)o;
    int m = vtts_zh_normalize(run, n, ws->en_a, ws->en_b, VTTS_TEXT_EN_CAP, run, run + half, half, ws->en_out,
                              (int)sizeof ws->en_out, &r);
    for (int i = 0; i < m;) {
        int j = i;
        while (j < m && r[j] != ' ') j++;
        if (j > i) push_cps(c, r + i, j - i);
        i = j + 1;
    }
}

static int zh_word_ids(const char *w, const vtts_text_opts *o, uint8_t *out, int cap) {
    return vtts_en_g2p(o->lex, w, out, cap); /* a Latin word of a Chinese run is read in English */
}

/* _zh_units: a Han run is read syllable by syllable; any other word is one English unit */
static void zh_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) {
    uint32_t c0 = 0;
    if (utf8_decode(w, &c0, 1) == 1 && vtts_zh_is_han(c0)) {
        zh_units_t u = {ws, 0};
        if (o->zh) vtts_zh_read_han(o->zh, w, zh_unit, &u);
        return;
    }
    uint8_t ids[256];
    int n = zh_word_ids(w, o, ids, (int)sizeof ids);
    if (n > 0) add_item(ws, ids, n, 0, 0);
}
#endif

#if VTTS_ENABLE_KO
/* normalize_ko; same buffers as zh_normalize */
static void ko_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) {
    vtts_text_ws *ws = c->ws;
    const uint32_t *r = NULL;
    const int half = VTTS_TEXT_MAX_CP / 2;
    (void)o;
    int m = vtts_ko_normalize(run, n, ws->en_a, ws->en_b, VTTS_TEXT_EN_CAP, run, run + half, half, ws->en_out,
                              (int)sizeof ws->en_out, &r);
    for (int i = 0; i < m;) {
        int j = i;
        while (j < m && r[j] != ' ') j++;
        if (j > i) push_cps(c, r + i, j - i);
        i = j + 1;
    }
}

static int ko_word_ids(const char *w, const vtts_text_opts *o, uint8_t *out, int cap) {
    return vtts_en_g2p(o->lex, w, out, cap); /* a Latin word of a Korean run is read in English */
}

/* _ko_units: a Hangul word is one unit, or one unit per syllable when it has more tokens than a
 * chunk holds; any other word is one English unit. ws->run, en_a and en_b are free here (the
 * run's words were copied to ws->words). */
static void ko_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) {
    uint32_t *cp = ws->run;
    int n = utf8_decode(w, cp, VTTS_TEXT_MAX_CP), hangul = n > 0;
    for (int i = 0; i < n && hangul; i++) hangul = vtts_ko_is_syllable(cp[i]);
    uint8_t ids[V2_MAX_TOKENS + 4];
    if (!hangul) {
        int k = ko_word_ids(w, o, ids, 256);
        if (k > 0) add_item(ws, ids, k, 0, 0);
        return;
    }
    uint8_t *syl = (uint8_t *)ws->en_a;
    int ns = vtts_ko_pronounce(cp, n, ws->en_b, VTTS_TEXT_EN_CAP, syl, (int)(sizeof ws->en_a / 3));
    if (ns <= 0) return;
    int total = 0;
    for (int s = 0; s < ns; s++) total += 1 + (syl[3 * s] != 23) + (syl[3 * s + 2] != 0);
    if (total <= V2_MAX_TOKENS) {
        int k = 0;
        for (int s = 0; s < ns; s++) k += vtts_ko_syllable_ids(syl + 3 * s, ids + k);
        add_item(ws, ids, k, 0, 0);
        return;
    }
    for (int s = 0; s < ns; s++) add_item(ws, ids, vtts_ko_syllable_ids(syl + 3 * s, ids), 0, s > 0);
}
#endif

#if VTTS_ENABLE_HI
/* normalize_hi; the run's halves hold the passes, en_a and en_b the first pass and English scratch */
static void hi_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) {
    vtts_text_ws *ws = c->ws;
    const uint32_t *r = NULL;
    const int half = VTTS_TEXT_MAX_CP / 2;
    (void)o;
    int m = vtts_hi_normalize(run, n, run, run + half, half, ws->en_a, ws->en_b, VTTS_TEXT_EN_CAP, ws->en_out,
                              (int)sizeof ws->en_out, &r);
    for (int i = 0; i < m;) {
        int j = i;
        while (j < m && r[j] != ' ') j++;
        if (j > i) push_cps(c, r + i, j - i);
        i = j + 1;
    }
}

static int hi_word_ids(const char *w, const vtts_text_opts *o, uint8_t *out, int cap) {
    return vtts_en_g2p(o->lex, w, out, cap); /* a word without Devanagari is read in English */
}

/* _hi_word: a Devanagari word (up to a chunk's worth of tokens), else an English word. ws->run,
 * en_a and en_b are free here (the run's words were copied to ws->words). */
static void hi_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) {
    uint32_t *cp = ws->run;
    int n = utf8_decode(w, cp, VTTS_TEXT_MAX_CP), k;
    uint8_t ids[V2_MAX_TOKENS];
    int ascii = 1;
    for (int i = 0; i < n; i++) ascii &= cp[i] < 0x80;
    if (vtts_hi_has_devanagari(cp, n))
        k = vtts_hi_word_ids(cp, n, ws->en_b, VTTS_TEXT_EN_CAP, ws->en_a, VTTS_TEXT_EN_CAP, ids, V2_MAX_TOKENS);
    else if (ascii) /* Latin letters reach here as ASCII (normalize_en); other scripts read as nothing */
        k = hi_word_ids(w, o, ids, 256);
    else
        k = 0;
    if (k > 0) add_item(ws, ids, k, 0, 0);
}
#endif

#if VTTS_ENABLE_JA
/* normalize_ja; same buffers as zh_normalize */
static void ja_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) {
    vtts_text_ws *ws = c->ws;
    const uint32_t *r = NULL;
    const int half = VTTS_TEXT_MAX_CP / 2;
    int m = vtts_ja_normalize(o->ja, run, n, ws->en_a, ws->en_b, VTTS_TEXT_EN_CAP, run, run + half, half, ws->en_out,
                              (int)sizeof ws->en_out, &r);
    for (int i = 0; i < m;) {
        int j = i;
        while (j < m && r[j] != ' ') j++;
        if (j > i) push_cps(c, r + i, j - i);
        i = j + 1;
    }
}

static int ja_word_ids(const char *w, const vtts_text_opts *o, uint8_t *out, int cap) {
    return vtts_en_g2p(o->lex, w, out, cap); /* a Latin word of a Japanese run is read in English */
}

/* _ja_units: a Japanese run is read unit by unit (table words, kanji, kana runs of <= 10 morae);
 * any other word is one English unit. ws->run, en_a and en_b are free here. */
static void ja_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) {
    uint32_t *cp = ws->run;
    int n = utf8_decode(w, cp, VTTS_TEXT_MAX_CP), ja = n > 0;
    for (int i = 0; i < n && ja; i++) ja = vtts_ja_is_ja_char(cp[i]);
    if (ja) {
        zh_units_t u = {ws, 0};
        if (o->ja) vtts_ja_units(o->ja, cp, n, ws->en_a, (uint8_t *)ws->en_b, (int)sizeof ws->en_b, zh_unit, &u);
        return;
    }
    uint8_t ids[256];
    int k = ja_word_ids(w, o, ids, (int)sizeof ids);
    if (k > 0) add_item(ws, ids, k, 0, 0);
}
#endif

#if VTTS_ENABLE_LT
/* Latin-script pairs (es, id, pt): normalize_es|id|pt and one item per word (vtts_text_lt.c). ws->run
 * and en_a are free when words are added (the run's words were copied to ws->words). */
static void lt_normalize(ctx_t *c, uint32_t *run, int n, int lang) {
    vtts_text_ws *ws = c->ws;
    const uint32_t *r = NULL;
    int m = vtts_lt_normalize(lang, run, n, ws->en_a, ws->en_b, VTTS_TEXT_EN_CAP, &r);
    for (int i = 0; i < m;) {
        int j = i;
        while (j < m && r[j] != ' ') j++;
        if (j > i) push_cps(c, r + i, j - i);
        i = j + 1;
    }
}

static void lt_add_word(vtts_text_ws *ws, const char *w, int lang) {
    uint8_t ids[V2_MAX_TOKENS];
    int n = utf8_decode(w, ws->run, VTTS_TEXT_MAX_CP);
    int k = vtts_lt_word_ids(lang, ws->run, n, ws->en_a, ids, V2_MAX_TOKENS);
    if (k > 0) add_item(ws, ids, k, 0, 0);
}
#endif
#if VTTS_ENABLE_ES
static void es_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) { (void)o; lt_normalize(c, run, n, VTTS_LT_ES); }
static void es_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) { (void)o; lt_add_word(ws, w, VTTS_LT_ES); }
#endif
#if VTTS_ENABLE_ID
static void id_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) { (void)o; lt_normalize(c, run, n, VTTS_LT_ID); }
static void id_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) { (void)o; lt_add_word(ws, w, VTTS_LT_ID); }
#endif
#if VTTS_ENABLE_PT
static void pt_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) { (void)o; lt_normalize(c, run, n, VTTS_LT_PT); }
static void pt_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) { (void)o; lt_add_word(ws, w, VTTS_LT_PT); }
#endif

#if VTTS_ENABLE_TH
/* normalize_th; the passes run in en_a / en_b (Thai number words are long), the English
 * normalizer's scratch is ws->run (free once the first pass has copied it) */
static void th_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) {
    vtts_text_ws *ws = c->ws;
    const uint32_t *r = NULL;
    const int half = VTTS_TEXT_MAX_CP / 2;
    (void)o;
    int m = vtts_th_normalize(run, n, ws->en_a, ws->en_b, VTTS_TEXT_EN_CAP, run, run + half, half, ws->en_out,
                              (int)sizeof ws->en_out, &r);
    for (int i = 0; i < m;) {
        int j = i;
        while (j < m && r[j] != ' ') j++;
        if (j > i) push_cps(c, r + i, j - i);
        i = j + 1;
    }
}
#endif

/* shared by th, lo, km and my: a Latin word of a Thai-like run is read in English; one syllable unit */
#if VTTS_ENABLE_TH || VTTS_ENABLE_KM || VTTS_ENABLE_MY
static int th_word_ids(const char *w, const vtts_text_opts *o, uint8_t *out, int cap) {
    return vtts_en_g2p(o->lex, w, out, cap); /* a Latin word of a Thai run is read in English */
}
#endif

#if VTTS_ENABLE_TH || VTTS_ENABLE_LO || VTTS_ENABLE_KM || VTTS_ENABLE_MY
static void th_unit(void *user, const uint8_t *ids, int n) {
    zh_units_t *u = user;
    add_item(u->ws, ids, n, 0, u->n++ > 0);
}
#endif

#if VTTS_ENABLE_TH

/* _th_units: a Thai run is read syllable by syllable (en_a and en_b are its scratch: the run's
 * words were copied to ws->words); any other word is one English unit */
static void th_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) {
    uint32_t c0 = 0;
    if (utf8_decode(w, &c0, 1) == 1 && vtts_th_is_thai(c0)) {
        zh_units_t u = {ws, 0};
        vtts_th_read(w, ws->en_a, sizeof ws->en_a, ws->en_b, sizeof ws->en_b, th_unit, &u);
        return;
    }
    uint8_t ids[256];
    int n = th_word_ids(w, o, ids, (int)sizeof ids);
    if (n > 0) add_item(ws, ids, n, 0, 0);
}

/* lang.THAI_LATIN: a boundary between Thai and Latin letters splits a chunk (เปิดWi-Fiให้) */
static int th_latin_edge(uint32_t a, uint32_t b) {
    return (vtts_th_is_thai(a) && ascii_alpha(b)) || (ascii_alpha(a) && vtts_th_is_thai(b));
}
#endif

#if VTTS_ENABLE_FR
/* French: normalize_fr (with liaison) and one item per word (vtts_text_fr.c); en_a and en_b are the
 * normalizer's buffers, en_a the reader's scratch (the run's words were copied to ws->words) */
static void fr_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) {
    vtts_text_ws *ws = c->ws;
    const uint32_t *r = NULL;
    (void)o;
    int m = vtts_fr_normalize(run, n, ws->en_a, ws->en_b, VTTS_TEXT_EN_CAP, &r);
    for (int i = 0; i < m;) {
        int j = i;
        while (j < m && r[j] != ' ') j++;
        if (j > i) push_cps(c, r + i, j - i);
        i = j + 1;
    }
}

static void fr_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) {
    uint8_t ids[V2_MAX_TOKENS];
    (void)o;
    int n = utf8_decode(w, ws->run, VTTS_TEXT_MAX_CP);
    int k = vtts_fr_word_ids(ws->run, n, ws->en_a, ids, V2_MAX_TOKENS);
    if (k > 0) add_item(ws, ids, k, 0, 0);
}
#endif

#if VTTS_ENABLE_DE
/* German (de): normalize_de and one item per word (vtts_text_de.c); en_a is free when words are added */
static void de_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) {
    vtts_text_ws *ws = c->ws;
    const uint32_t *r = NULL;
    (void)o;
    int m = vtts_de_normalize(run, n, ws->en_a, ws->en_b, VTTS_TEXT_EN_CAP, &r);
    for (int i = 0; i < m;) {
        int j = i;
        while (j < m && r[j] != ' ') j++;
        if (j > i) push_cps(c, r + i, j - i);
        i = j + 1;
    }
}

static void de_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) {
    uint8_t ids[V2_MAX_TOKENS];
    (void)o;
    int n = utf8_decode(w, ws->run, VTTS_TEXT_MAX_CP);
    int k = vtts_de_word_ids(ws->run, n, ws->en_a, ids, V2_MAX_TOKENS);
    if (k > 0) add_item(ws, ids, k, 0, 0);
}
#endif

/* Italian and Turkish (vtts_text_it.c, vtts_text_tr.c): like the Latin-script pairs, one item per word */
#if VTTS_ENABLE_IT || VTTS_ENABLE_TR
static void lt2_push(ctx_t *c, const uint32_t *r, int m) {
    for (int i = 0; i < m;) {
        int j = i;
        while (j < m && r[j] != ' ') j++;
        if (j > i) push_cps(c, r + i, j - i);
        i = j + 1;
    }
}
#endif

#if VTTS_ENABLE_IT
static void it_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) {
    const uint32_t *r = NULL;
    (void)o;
    int m = vtts_it_normalize(run, n, c->ws->en_a, c->ws->en_b, VTTS_TEXT_EN_CAP, &r);
    lt2_push(c, r, m);
}

static void it_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) {
    uint8_t ids[V2_MAX_TOKENS];
    (void)o;
    int n = utf8_decode(w, ws->run, VTTS_TEXT_MAX_CP);
    int k = vtts_it_word_ids(ws->run, n, ws->en_a, ids, V2_MAX_TOKENS);
    if (k > 0) add_item(ws, ids, k, 0, 0);
}
#endif

#if VTTS_ENABLE_TR
static void tr_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) {
    const uint32_t *r = NULL;
    (void)o;
    int m = vtts_tr_normalize(run, n, c->ws->en_a, c->ws->en_b, VTTS_TEXT_EN_CAP, &r);
    lt2_push(c, r, m);
}

static void tr_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) {
    uint8_t ids[V2_MAX_TOKENS];
    (void)o;
    int n = utf8_decode(w, ws->run, VTTS_TEXT_MAX_CP);
    int k = vtts_tr_word_ids(ws->run, n, ws->en_a, ids, V2_MAX_TOKENS);
    if (k > 0) add_item(ws, ids, k, 0, 0);
}
#endif

#if VTTS_ENABLE_RU
/* normalize_ru; the passes run in en_a / en_b (number words are long), the English normalizer's
 * scratch is ws->run (free once the compose pass has copied it) */
static void ru_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) {
    vtts_text_ws *ws = c->ws;
    const uint32_t *r = NULL;
    const int half = VTTS_TEXT_MAX_CP / 2;
    (void)o;
    int m = vtts_ru_normalize(run, n, ws->en_a, ws->en_b, VTTS_TEXT_EN_CAP, run, run + half, half, ws->en_out,
                              (int)sizeof ws->en_out, &r);
    for (int i = 0; i < m;) {
        int j = i;
        while (j < m && r[j] != ' ') j++;
        if (j > i) push_cps(c, r + i, j - i);
        i = j + 1;
    }
}

static int ru_word_ids(const char *w, const vtts_text_opts *o, uint8_t *out, int cap) {
    return vtts_en_g2p(o->lex, w, out, cap); /* a word without Cyrillic is read in English */
}

/* _ru_word: a Cyrillic word, else an English word (ws->run, en_a and en_b are free here) */
static void ru_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) {
    uint32_t *cp = ws->run;
    int n = utf8_decode(w, cp, VTTS_TEXT_MAX_CP), k = 0, ascii = 1;
    uint8_t ids[V2_MAX_TOKENS];
    for (int i = 0; i < n; i++) ascii &= cp[i] < 0x80;
    if (vtts_ru_has_cyrillic(cp, n)) k = vtts_ru_word_ids(o->ru, cp, n, ws->en_a, ids, V2_MAX_TOKENS);
    else if (ascii) k = ru_word_ids(w, o, ids, 256); /* Latin words reach here as ASCII (normalize_en) */
    if (k > 0) add_item(ws, ids, k, 0, 0);
}
#endif

#if VTTS_ENABLE_PL
/* normalize_pl; the passes run in en_a / en_b, en_out's space is not needed (no English pass) */
static void pl_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) {
    vtts_text_ws *ws = c->ws;
    const uint32_t *r = NULL;
    (void)o;
    int m = vtts_pl_normalize(run, n, ws->en_a, ws->en_b, run, VTTS_TEXT_MAX_CP, &r);
    for (int i = 0; i < m;) {
        int j = i;
        while (j < m && r[j] != ' ') j++;
        if (j > i) push_cps(c, r + i, j - i);
        i = j + 1;
    }
}

/* _pl_word: word_tokens_pl reads every word of a Polish run */
static void pl_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) {
    uint8_t ids[V2_MAX_TOKENS];
    (void)o;
    int n = utf8_decode(w, ws->run, VTTS_TEXT_MAX_CP);
    int k = vtts_pl_word_ids(ws->run, n, ids, V2_MAX_TOKENS);
    if (k > 0) add_item(ws, ids, k, 0, 0);
}
#endif

#if VTTS_ENABLE_AR
/* normalize_ar; same buffers as hi_normalize */
static void ar_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) {
    vtts_text_ws *ws = c->ws;
    const uint32_t *r = NULL;
    const int half = VTTS_TEXT_MAX_CP / 2;
    (void)o;
    int m = vtts_ar_normalize(run, n, run, run + half, half, ws->en_a, ws->en_b, VTTS_TEXT_EN_CAP, ws->en_out,
                              (int)sizeof ws->en_out, &r);
    for (int i = 0; i < m;) {
        int j = i;
        while (j < m && r[j] != ' ') j++;
        if (j > i) push_cps(c, r + i, j - i);
        i = j + 1;
    }
}

/* _ar_word: an Arabic word (vowels restored, up to a chunk's worth of tokens), else an English word.
 * ws->run, en_a and en_b are free here (the run's words were copied to ws->words). */
static void ar_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) {
    uint32_t *cp = ws->run;
    int n = utf8_decode(w, cp, VTTS_TEXT_MAX_CP), k, ascii = 1;
    uint8_t ids[V2_MAX_TOKENS];
    for (int i = 0; i < n; i++) ascii &= cp[i] < 0x80;
    if (vtts_ar_has_arabic(cp, n))
        k = vtts_ar_word_ids(cp, n, ws->en_a, ws->en_b, ids, V2_MAX_TOKENS);
    else if (ascii) /* Latin letters reach here as ASCII (normalize_en); other scripts read as nothing */
        k = vtts_en_g2p(o->lex, w, ids, 256);
    else
        k = 0;
    if (k > 0) add_item(ws, ids, k, 0, 0);
}
#endif

#if VTTS_ENABLE_FI
/* normalize_fi and one item per word (vtts_text_fi.c); same buffers as the Latin-script pairs */
static void fi_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) {
    vtts_text_ws *ws = c->ws;
    const uint32_t *r = NULL;
    (void)o;
    int m = vtts_fi_normalize(run, n, ws->en_a, ws->en_b, VTTS_TEXT_EN_CAP, &r);
    for (int i = 0; i < m;) {
        int j = i;
        while (j < m && r[j] != ' ') j++;
        if (j > i) push_cps(c, r + i, j - i);
        i = j + 1;
    }
}

static void fi_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) {
    uint8_t ids[V2_MAX_TOKENS];
    (void)o;
    int n = utf8_decode(w, ws->run, VTTS_TEXT_MAX_CP);
    int k = vtts_fi_word_ids(ws->run, n, ws->en_a, ids, V2_MAX_TOKENS);
    if (k > 0) add_item(ws, ids, k, 0, 0);
}

/* lang._by_context: a Finnish word of both word lists (on, he) is English when the nearest tagged
 * word on each side (or the only one) is English. tag: 1 fi, 0 en, -1 neutral (word_lang), in place */
static void fi_context(const uint32_t *cp, const int *cs, const int *ce, int nc, int *tag) {
    for (int k = 0; k < nc; k++) {
        int a = cs[k], b = ce[k];
        while (a < b && is_edge(cp[a])) a++;
        while (b > a && is_edge(cp[b - 1])) b--;
        if (tag[k] == 1 && vtts_fi_ambiguous(cp + a, b - a)) tag[k] = 2; /* 2: of both lists */
    }
    for (int k = 0; k < nc; k++) { /* the neighbours skip words of both lists (2, -3, -4) and neutral ones */
        if (tag[k] != 2) continue;
        int en = 0, fi = 0;
        for (int step = -1; step <= 1; step += 2)
            for (int q = k + step; q >= 0 && q < nc; q += step) {
                if (tag[q] != 0 && tag[q] != 1) continue;
                if (tag[q] == 0) en = 1; else fi = 1;
                break;
            }
        tag[k] = en && !fi ? -4 : -3; /* -4 en, -3 fi */
    }
    for (int k = 0; k < nc; k++) tag[k] = tag[k] == -3 ? 1 : tag[k] == -4 ? 0 : tag[k];
}
#endif

#if VTTS_ENABLE_EL
/* normalize_el; the passes run in en_a / en_b (number words are long), the English normalizer's
 * scratch is ws->run (free once the first pass has copied it), like th_normalize */
static void el_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) {
    vtts_text_ws *ws = c->ws;
    const uint32_t *r = NULL;
    const int half = VTTS_TEXT_MAX_CP / 2;
    (void)o;
    int m = vtts_el_normalize(run, n, ws->en_a, ws->en_b, VTTS_TEXT_EN_CAP, run, run + half, half, ws->en_out,
                              (int)sizeof ws->en_out, &r);
    for (int i = 0; i < m;) {
        int j = i;
        while (j < m && r[j] != ' ') j++;
        if (j > i) push_cps(c, r + i, j - i);
        i = j + 1;
    }
}

/* _el_word: a Greek word, else an English word (Latin letters reach here as ASCII; other scripts
 * read as nothing). ws->run and en_a are free here. */
static void el_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) {
    uint8_t ids[V2_MAX_TOKENS];
    int n = utf8_decode(w, ws->run, VTTS_TEXT_MAX_CP), k = 0, ascii = 1;
    for (int i = 0; i < n; i++) ascii &= ws->run[i] < 0x80;
    if (vtts_el_is_greek_word(ws->run, n)) k = vtts_el_word_ids(ws->run, n, ws->en_a, ids, V2_MAX_TOKENS);
    else if (ascii) k = vtts_en_g2p(o->lex, w, ids, 256);
    if (k > 0) add_item(ws, ids, k, 0, 0);
}
#endif

#if VTTS_ENABLE_MS
static void ms_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) { (void)o; lt_normalize(c, run, n, VTTS_LT_MS); }
static void ms_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) { (void)o; lt_add_word(ws, w, VTTS_LT_MS); }
#endif

#if VTTS_ENABLE_TL
/* Tagalog: normalize_tl and one item per word (vtts_text_tl.c); en_a / en_b are free here as for es */
static void tl_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) {
    vtts_text_ws *ws = c->ws;
    const uint32_t *r = NULL;
    (void)o;
    int m = vtts_tl_normalize(run, n, ws->en_a, ws->en_b, VTTS_TEXT_EN_CAP, &r);
    for (int i = 0; i < m;) {
        int j = i;
        while (j < m && r[j] != ' ') j++;
        if (j > i) push_cps(c, r + i, j - i);
        i = j + 1;
    }
}

static void tl_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) {
    uint8_t ids[V2_MAX_TOKENS];
    (void)o;
    int n = utf8_decode(w, ws->run, VTTS_TEXT_MAX_CP);
    int k = vtts_tl_word_ids(ws->run, n, ws->en_a, ids, V2_MAX_TOKENS);
    if (k > 0) add_item(ws, ids, k, 0, 0);
}
#endif

#if VTTS_ENABLE_SW
/* Swahili (sw): normalize_sw and one item per word (vtts_text_sw.c); scratch as for es, id, pt */
static void sw_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) {
    vtts_text_ws *ws = c->ws;
    const uint32_t *r = NULL;
    (void)o;
    int m = vtts_sw_normalize(run, n, ws->en_a, ws->en_b, VTTS_TEXT_EN_CAP, &r);
    for (int i = 0; i < m;) {
        int j = i;
        while (j < m && r[j] != ' ') j++;
        if (j > i) push_cps(c, r + i, j - i);
        i = j + 1;
    }
}

static void sw_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) {
    uint8_t ids[V2_MAX_TOKENS];
    (void)o;
    int n = utf8_decode(w, ws->run, VTTS_TEXT_MAX_CP);
    int k = vtts_sw_word_ids(ws->run, n, ws->en_a, sizeof ws->en_a, ids, V2_MAX_TOKENS);
    if (k > 0) add_item(ws, ids, k, 0, 0);
}
#endif

#if VTTS_ENABLE_NX
/* Dutch, Swedish, Norwegian (nl, sv, no): the scanner normalizer and one item per word
 * (vtts_text_nx*.c). The normalizer writes UTF-8 words into en_a; en_b is the g2p scratch. */
static void nx_normalize(ctx_t *c, uint32_t *run, int n, int lang) {
    vtts_text_ws *ws = c->ws;
    char *out = (char *)ws->en_a;
    vtts_nx_normalize(lang, run, n, out, (int)sizeof ws->en_a);
    for (char *w = out; *w;) {
        char *sp = strchr(w, ' ');
        if (sp) *sp = 0;
        if (*w) push_raw(c, w);
        if (!sp) break;
        w = sp + 1;
    }
}

static void nx_add_word(vtts_text_ws *ws, const char *w, int lang) {
    uint8_t ids[V2_MAX_TOKENS];
    int n = utf8_decode(w, ws->run, VTTS_TEXT_MAX_CP);
    int k = vtts_nx_word_ids(lang, ws->run, n, ws->en_b, ids, V2_MAX_TOKENS);
    if (k > 0) add_item(ws, ids, k, 0, 0);
}

#endif

#if VTTS_ENABLE_NL
static void nl_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) { (void)o; nx_normalize(c, run, n, VTTS_NX_NL); }
static void nl_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) { (void)o; nx_add_word(ws, w, VTTS_NX_NL); }
#endif
#if VTTS_ENABLE_SV
static void sv_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) { (void)o; nx_normalize(c, run, n, VTTS_NX_SV); }
static void sv_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) { (void)o; nx_add_word(ws, w, VTTS_NX_SV); }
#endif
#if VTTS_ENABLE_NO
static void no_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) { (void)o; nx_normalize(c, run, n, VTTS_NX_NO); }
static void no_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) { (void)o; nx_add_word(ws, w, VTTS_NX_NO); }
#endif
/* the VTTS_NX_* language of a mode, or -1 (also when it is not compiled in) */
static int nx_of(int mode) {
#if VTTS_ENABLE_NX
    int k = mode == VTTS_LANG_NL ? VTTS_NX_NL : mode == VTTS_LANG_SV ? VTTS_NX_SV : mode == VTTS_LANG_NO ? VTTS_NX_NO : -1;
    return k >= 0 && vtts_nx_enabled(k) ? k : -1;
#else
    (void)mode;
    return -1;
#endif
}

#if VTTS_ENABLE_LO
/* normalize_lo, scratch as for Thai */
static void lo_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) {
    vtts_text_ws *ws = c->ws;
    const uint32_t *r = NULL;
    const int half = VTTS_TEXT_MAX_CP / 2;
    (void)o;
    int m = vtts_lo_normalize(run, n, ws->en_a, ws->en_b, VTTS_TEXT_EN_CAP, run, run + half, half, ws->en_out,
                              (int)sizeof ws->en_out, &r);
    for (int i = 0; i < m;) {
        int j = i;
        while (j < m && r[j] != ' ') j++;
        if (j > i) push_cps(c, r + i, j - i);
        i = j + 1;
    }
}

static int lo_word_ids(const char *w, const vtts_text_opts *o, uint8_t *out, int cap) {
    return vtts_en_g2p(o->lex, w, out, cap); /* a Latin word of a Lao run is read in English */
}

/* _lo_units: a Lao run is read syllable by syllable (en_a and en_b are its scratch); any other word
 * is one English unit */
static void lo_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) {
    uint32_t c0 = 0;
    if (utf8_decode(w, &c0, 1) == 1 && vtts_lo_is_lao(c0)) {
        zh_units_t u = {ws, 0};
        vtts_lo_read(w, ws->en_a, sizeof ws->en_a, ws->en_b, sizeof ws->en_b, th_unit, &u);
        return;
    }
    uint8_t ids[256];
    int n = lo_word_ids(w, o, ids, (int)sizeof ids);
    if (n > 0) add_item(ws, ids, n, 0, 0);
}

/* lang.LAO_LATIN: a boundary between Lao and Latin letters splits a chunk (ເປີດWi-Fiໃຫ້) */
static int lo_latin_edge(uint32_t a, uint32_t b) {
    return (vtts_lo_is_lao(a) && ascii_alpha(b)) || (ascii_alpha(a) && vtts_lo_is_lao(b));
}
#endif

#if VTTS_ENABLE_DA
/* Danish: normalize_da and one item per word (vtts_text_da.c); en_a / en_b are free here as for es */
static void da_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) {
    vtts_text_ws *ws = c->ws;
    const uint32_t *r = NULL;
    (void)o;
    int m = vtts_da_normalize(run, n, ws->en_a, ws->en_b, VTTS_TEXT_EN_CAP, &r);
    for (int i = 0; i < m;) {
        int j = i;
        while (j < m && r[j] != ' ') j++;
        if (j > i) push_cps(c, r + i, j - i);
        i = j + 1;
    }
}

static void da_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) {
    uint8_t ids[V2_MAX_TOKENS];
    (void)o;
    int n = utf8_decode(w, ws->run, VTTS_TEXT_MAX_CP);
    int k = vtts_da_word_ids(ws->run, n, ws->en_a, sizeof ws->en_a, ids, V2_MAX_TOKENS);
    if (k > 0) add_item(ws, ids, k, 0, 0);
}
#endif

/* indexed by TAG_*; a language that is not compiled in (vtts_langs.h) has an empty row */
#if VTTS_ENABLE_KM
/* normalize_km, in en_a / en_b like Thai */
static void km_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) {
    vtts_text_ws *ws = c->ws;
    const uint32_t *r = NULL;
    const int half = VTTS_TEXT_MAX_CP / 2;
    (void)o;
    int m = vtts_km_normalize(run, n, ws->en_a, ws->en_b, VTTS_TEXT_EN_CAP, run, run + half, half, ws->en_out,
                              (int)sizeof ws->en_out, &r);
    for (int i = 0; i < m;) {
        int j = i;
        while (j < m && r[j] != ' ') j++;
        if (j > i) push_cps(c, r + i, j - i);
        i = j + 1;
    }
}

/* _km_units: a Khmer run is read syllable by syllable (en_a and en_b, adjacent, are its scratch);
 * any other word is one English unit */
static void km_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) {
    uint32_t c0 = 0;
    if (utf8_decode(w, &c0, 1) == 1 && vtts_km_is_khmer(c0)) {
        zh_units_t u = {ws, 0};
        vtts_km_read(w, ws->en_a, sizeof ws->en_a + sizeof ws->en_b, th_unit, &u);
        return;
    }
    uint8_t ids[256];
    int n = th_word_ids(w, o, ids, (int)sizeof ids);
    if (n > 0) add_item(ws, ids, n, 0, 0);
}
typedef char km_scratch_fits[(sizeof(((vtts_text_ws *)0)->en_a) + sizeof(((vtts_text_ws *)0)->en_b) >=
                              VTTS_KM_SCRATCH && offsetof(vtts_text_ws, en_b) == offsetof(vtts_text_ws, en_a) +
                              sizeof(((vtts_text_ws *)0)->en_a)) ? 1 : -1];

/* lang.KHMER_LATIN: a boundary between Khmer and Latin letters splits a chunk (បើកWi-Fi) */
static int km_latin_edge(uint32_t a, uint32_t b) {
    return (vtts_km_is_khmer(a) && ascii_alpha(b)) || (ascii_alpha(a) && vtts_km_is_khmer(b));
}
#endif

#if VTTS_ENABLE_MY
/* normalize_my, in en_a / en_b */
static void my_normalize(ctx_t *c, uint32_t *run, int n, const vtts_text_opts *o) {
    vtts_text_ws *ws = c->ws;
    const uint32_t *r = NULL;
    const int half = VTTS_TEXT_MAX_CP / 2;
    (void)o;
    int m = vtts_my_normalize(run, n, ws->en_a, ws->en_b, VTTS_TEXT_EN_CAP, run, run + half, half, ws->en_out,
                              (int)sizeof ws->en_out, &r);
    for (int i = 0; i < m;) {
        int j = i;
        while (j < m && r[j] != ' ') j++;
        if (j > i) push_cps(c, r + i, j - i);
        i = j + 1;
    }
}

/* _my_units: a Burmese run is read syllable by syllable (en_a and en_b are its scratch) */
static void my_add_word(vtts_text_ws *ws, const char *w, const vtts_text_opts *o) {
    uint32_t c0 = 0;
    if (utf8_decode(w, &c0, 1) == 1 && vtts_my_is_burmese(c0)) {
        zh_units_t u = {ws, 0};
        vtts_my_read(w, ws->en_a, sizeof ws->en_a + sizeof ws->en_b, th_unit, &u);
        return;
    }
    uint8_t ids[256];
    int n = th_word_ids(w, o, ids, (int)sizeof ids);
    if (n > 0) add_item(ws, ids, n, 0, 0);
}
typedef char my_scratch_fits[(sizeof(((vtts_text_ws *)0)->en_a) + sizeof(((vtts_text_ws *)0)->en_b) >=
                              VTTS_MY_SCRATCH && offsetof(vtts_text_ws, en_b) == offsetof(vtts_text_ws, en_a) +
                              sizeof(((vtts_text_ws *)0)->en_a)) ? 1 : -1];

/* lang.BURMESE_LATIN: a boundary between Burmese (U+1000..U+103F, U+104C..U+109F) and Latin letters */
static int my_edge_cp(uint32_t c) { return (c >= 0x1000 && c <= 0x103F) || (c >= 0x104C && c <= 0x109F); }
static int my_latin_edge(uint32_t a, uint32_t b) {
    return (my_edge_cp(a) && ascii_alpha(b)) || (ascii_alpha(a) && my_edge_cp(b));
}
#endif

static const lang_mod_t LANGS[] = {
    [TAG_VI] = {"vi", vi_normalize, vi_word_ids, NULL},
    [TAG_EN] = {"en", en_normalize, en_word_ids, NULL},
#if VTTS_ENABLE_ZH
    [TAG_ZH] = {"zh", zh_normalize, zh_word_ids, zh_add_word},
#endif
#if VTTS_ENABLE_KO
    [TAG_KO] = {"ko", ko_normalize, ko_word_ids, ko_add_word},
#endif
#if VTTS_ENABLE_HI
    [TAG_HI] = {"hi", hi_normalize, hi_word_ids, hi_add_word},
#endif
#if VTTS_ENABLE_JA
    [TAG_JA] = {"ja", ja_normalize, ja_word_ids, ja_add_word},
#endif
#if VTTS_ENABLE_ES
    [TAG_ES] = {"es", es_normalize, NULL, es_add_word},
#endif
#if VTTS_ENABLE_ID
    [TAG_ID] = {"id", id_normalize, NULL, id_add_word},
#endif
#if VTTS_ENABLE_PT
    [TAG_PT] = {"pt", pt_normalize, NULL, pt_add_word},
#endif
#if VTTS_ENABLE_TH
    [TAG_TH] = {"th", th_normalize, th_word_ids, th_add_word},
#endif
#if VTTS_ENABLE_FR
    [TAG_FR] = {"fr", fr_normalize, NULL, fr_add_word},
#endif
#if VTTS_ENABLE_DE
    [TAG_DE] = {"de", de_normalize, NULL, de_add_word},
#endif
#if VTTS_ENABLE_IT
    [TAG_IT] = {"it", it_normalize, NULL, it_add_word},
#endif
#if VTTS_ENABLE_TR
    [TAG_TR] = {"tr", tr_normalize, NULL, tr_add_word},
#endif
#if VTTS_ENABLE_RU
    [TAG_RU] = {"ru", ru_normalize, ru_word_ids, ru_add_word},
#endif
#if VTTS_ENABLE_PL
    [TAG_PL] = {"pl", pl_normalize, NULL, pl_add_word},
#endif
#if VTTS_ENABLE_AR
    [TAG_AR] = {"ar", ar_normalize, NULL, ar_add_word},
#endif
#if VTTS_ENABLE_FI
    [TAG_FI] = {"fi", fi_normalize, NULL, fi_add_word},
#endif
#if VTTS_ENABLE_EL
    [TAG_EL] = {"el", el_normalize, NULL, el_add_word},
#endif
#if VTTS_ENABLE_MS
    [TAG_MS] = {"ms", ms_normalize, NULL, ms_add_word},
#endif
#if VTTS_ENABLE_TL
    [TAG_TL] = {"tl", tl_normalize, NULL, tl_add_word},
#endif
#if VTTS_ENABLE_SW
    [TAG_SW] = {"sw", sw_normalize, NULL, sw_add_word},
#endif
#if VTTS_ENABLE_NL
    [TAG_NX + VTTS_NX_NL] = {"nl", nl_normalize, NULL, nl_add_word},
#endif
#if VTTS_ENABLE_SV
    [TAG_NX + VTTS_NX_SV] = {"sv", sv_normalize, NULL, sv_add_word},
#endif
#if VTTS_ENABLE_NO
    [TAG_NX + VTTS_NX_NO] = {"no", no_normalize, NULL, no_add_word},
#endif
#if VTTS_ENABLE_DA
    [TAG_DA] = {"da", da_normalize, NULL, da_add_word},
#endif
#if VTTS_ENABLE_LO
    [TAG_LO] = {"lo", lo_normalize, lo_word_ids, lo_add_word},
#endif
#if VTTS_ENABLE_KM
    [TAG_KM] = {"km", km_normalize, th_word_ids, km_add_word},
#endif
#if VTTS_ENABLE_MY
    [TAG_MY] = {"my", my_normalize, th_word_ids, my_add_word},
#endif
    [TAG_LAST] = {NULL, NULL, NULL, NULL},
};

static void add_word_or_mark(vtts_text_ws *ws, const char *w, const lang_mod_t *m, const vtts_text_opts *o) {
    uint8_t ids[256];
    if (is_punct_word(w)) {
        if (last_is_word(ws)) { ids[0] = (uint8_t)token_id("", w); add_item(ws, ids, 1, 1, 0); }
        return;
    }
    if (m->add_word) { m->add_word(ws, w, o); return; }
    int n = m->word_ids(w, o, ids, (int)sizeof ids);
    if (n > 0) add_item(ws, ids, n, 0, 0);
}

/* _assemble size of items [a, b): (tokens, words) */
static void part_size(const vtts_text_ws *ws, int a, int b, int *tok, int *words) {
    int t = 0, w = 0, last_punct = 0;
    for (int i = a; i < b; i++) {
        if (ws->item_punct[i]) { if (t) { t++; last_punct = 1; } continue; }
        if (t && !last_punct && !ws->item_join[i]) t++;
        t += ws->item_len[i];
        last_punct = 0;
        w++;
    }
    *tok = t;
    *words = w;
}

static void emit_part(ctx_t *c, int a, int b) {
    vtts_text_ws *ws = c->ws;
    int n = 0, last_punct = 0, words = 0;
    if (c->stop) return;
    ws->ids[n++] = VTTS_V2_BOS;
    for (int i = a; i < b && n < VTTS_TEXT_MAX_IDS - 1; i++) {
        const uint8_t *t = ws->pool + ws->item_off[i];
        if (ws->item_punct[i]) {
            if (n > 1) { ws->ids[n++] = t[0]; last_punct = 1; }
            continue;
        }
        if (n > 1 && !last_punct && !ws->item_join[i]) ws->ids[n++] = VTTS_V2_SPACE;
        for (int k = 0; k < ws->item_len[i] && n < VTTS_TEXT_MAX_IDS - 1; k++) ws->ids[n++] = t[k];
        last_punct = 0;
        words++;
    }
    if (!words) return; /* only punctuation */
    ws->ids[n++] = VTTS_V2_EOS;
    c->chunks++;
    if (c->cb && c->cb(ws->ids, n, c->user)) c->stop = 1;
}

static int fits(const vtts_text_ws *ws, int a, int b) {
    int t, w;
    part_size(ws, a, b, &t, &w);
    return t <= V2_MAX_TOKENS && w <= V2_MAX_WORDS;
}

/* _pack_items: pieces end after ',' or ':'; pack whole pieces, hard-cut a piece that is too long */
static void pack_items(ctx_t *c) {
    vtts_text_ws *ws = c->ws;
    int N = ws->n_items, ca = -1, cb = -1, i = 0;
    int comma = token_id("", ","), colon = token_id("", ":");
    while (i < N && !c->stop) {
        int p0 = i;
        while (i < N) {
            int pm = ws->item_punct[i++];
            if (pm && (pm == comma || pm == colon)) break;
        }
        int p1 = i;
        if (fits(ws, ca < 0 ? p0 : ca, p1)) { if (ca < 0) ca = p0; cb = p1; continue; }
        if (ca >= 0) { emit_part(c, ca, cb); ca = -1; }
        for (int k = p0; k < p1; k++) {
            if (ca >= 0 && !fits(ws, ca, k + 1)) { emit_part(c, ca, cb); ca = -1; }
            if (ca < 0) ca = k;
            cb = k + 1;
        }
    }
    if (ca >= 0) emit_part(c, ca, cb);
}

/* lang.py _script_class: 1 Han, 2 CJK punctuation and full-width forms, 0 other */
static int is_thai_cp(uint32_t c) { return c >= 0x0E01 && c <= 0x0E4E; } /* vtts_th_is_thai */

#if VTTS_ENABLE_ZH
static int is_han_cp(uint32_t c) { return c >= 0x4E00 && c <= 0x9FFF; } /* vtts_zh_is_han */
static int script_class(uint32_t c) {
    if (is_han_cp(c)) return 1;
    if ((c >= 0x3000 && c <= 0x303F) || (c >= 0xFF00 && c <= 0xFFEF) || c == 0x201C || c == 0x201D ||
        c == 0x2018 || c == 0x2019 || c == 0x2026 || c == 0x2014 || c == 0x00B7)
        return 2;
    return 0;
}

static int has_han(const uint32_t *w, int n) {
    for (int i = 0; i < n; i++) if (is_han_cp(w[i])) return 1;
    return 0;
}
#endif

/* the text mode is compiled in (vtts_langs.h) */
static int lang_enabled(vtts_lang l) {
    switch (l) {
    case VTTS_LANG_ZH: return VTTS_ENABLE_ZH;
    case VTTS_LANG_KO: return VTTS_ENABLE_KO;
    case VTTS_LANG_HI: return VTTS_ENABLE_HI;
    case VTTS_LANG_JA: return VTTS_ENABLE_JA;
    case VTTS_LANG_ES: return VTTS_ENABLE_ES;
    case VTTS_LANG_ID: return VTTS_ENABLE_ID;
    case VTTS_LANG_PT: return VTTS_ENABLE_PT;
    case VTTS_LANG_TH: return VTTS_ENABLE_TH;
    case VTTS_LANG_FR: return VTTS_ENABLE_FR;
    case VTTS_LANG_DE: return VTTS_ENABLE_DE;
    case VTTS_LANG_IT: return VTTS_ENABLE_IT;
    case VTTS_LANG_TR: return VTTS_ENABLE_TR;
    case VTTS_LANG_RU: return VTTS_ENABLE_RU;
    case VTTS_LANG_PL: return VTTS_ENABLE_PL;
    case VTTS_LANG_AR: return VTTS_ENABLE_AR;
    case VTTS_LANG_FI: return VTTS_ENABLE_FI;
    case VTTS_LANG_EL: return VTTS_ENABLE_EL;
    case VTTS_LANG_MS: return VTTS_ENABLE_MS;
    case VTTS_LANG_TL: return VTTS_ENABLE_TL;
    case VTTS_LANG_SW: return VTTS_ENABLE_SW;
    case VTTS_LANG_NL: return VTTS_ENABLE_NL;
    case VTTS_LANG_SV: return VTTS_ENABLE_SV;
    case VTTS_LANG_NO: return VTTS_ENABLE_NO;
    case VTTS_LANG_DA: return VTTS_ENABLE_DA;
    case VTTS_LANG_LO: return VTTS_ENABLE_LO;
    case VTTS_LANG_KM: return VTTS_ENABLE_KM;
    case VTTS_LANG_MY: return VTTS_ENABLE_MY;
    default: return 1;
    }
}

/* split_scripts and THAI_LATIN: does c start a new chunk after the chunk w[0..n) of the mode? */
static int script_edge(int mode, const uint32_t *w, int n, uint32_t c) {
    (void)mode; (void)w; (void)n; (void)c;
#if VTTS_ENABLE_ZH
    if (mode == VTTS_LANG_ZH) return script_class(c) != script_class(w[0]);
#endif
#if VTTS_ENABLE_JA
    if (mode == VTTS_LANG_JA) return vtts_ja_script_class(c) != vtts_ja_script_class(w[0]);
#endif
#if VTTS_ENABLE_TH
    if (mode == VTTS_LANG_TH) return n > 0 && th_latin_edge(w[n - 1], c);
#endif
#if VTTS_ENABLE_LO
    if (mode == VTTS_LANG_LO) return n > 0 && lo_latin_edge(w[n - 1], c);
#endif
#if VTTS_ENABLE_KM
    if (mode == VTTS_LANG_KM) return n > 0 && km_latin_edge(w[n - 1], c);
#endif
#if VTTS_ENABLE_MY
    if (mode == VTTS_LANG_MY) return n > 0 && my_latin_edge(w[n - 1], c);
#endif
    return 0;
}

/* ======================= sentence language (latin.sentence_is_english) =======================
 * In the Latin-script pair modes and the vi mode, a sentence whose words are mostly English (word
 * lists of vtts_text_sent_tables.h, the word tags) is read in English: every chunk but those with the
 * language's own letters, numbers included. */
enum { EV_OTHER, EV_MAIN, EV_BOTH, EV_EN, EV_STRONG };

typedef struct {
    int vi;                                        /* the vi mode: own letters = Vietnamese letters */
    const char *const *main, *const *both, *own;   /* main-language words, words of both, own letters */
    int n_main, n_both;
} sent_spec_t;

static int sent_in(const char *const *list, int n, const char *w) {
    int lo = 0, hi = n - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2, c = strcmp(list[m], w);
        if (!c) return 1;
        if (c < 0) lo = m + 1; else hi = m - 1;
    }
    return 0;
}

/* one of the n code points w is in the UTF-8 string set */
static int sent_own(const char *set, const uint32_t *w, int n) {
    uint32_t cps[64];
    int m = utf8_decode(set, cps, 64);
    for (int i = 0; i < n; i++)
        for (int k = 0; k < m; k++) if (w[i] == cps[k]) return 1;
    return 0;
}

/* core.lower().replace("’", "'") in key when it is lower-case ASCII of at most VTTS_SENT_MAX_KEY
 * characters (else it is in no list: 0). İ lower-cases to i + U+0307 in Python. */
static int sent_key(const uint32_t *w, int n, char *key) {
    if (n > VTTS_SENT_MAX_KEY) return 0;
    for (int i = 0; i < n; i++) {
        uint32_t c = w[i] == 0x2019 ? '\'' : w[i] == 0x130 ? 0x130 : vtts_u_lower(w[i]);
        if (c >= 0x80) return 0;
        key[i] = (char)c;
    }
    key[n] = 0;
    return 1;
}

#define SENT_LIST(L) S->main = VTTS_SENT_MAIN_##L; S->n_main = VTTS_SENT_MAIN_##L##_N; \
                     S->both = VTTS_SENT_BOTH_##L; S->n_both = VTTS_SENT_BOTH_##L##_N; S->own = VTTS_SENT_OWN_##L

/* the rule applies to the mode: fills S */
static int sent_spec(int mode, sent_spec_t *S) {
    memset(S, 0, sizeof *S);
    switch (mode) {
    case VTTS_LANG_VI: S->vi = 1; return 1;
#if VTTS_ENABLE_ES
    case VTTS_LANG_ES: SENT_LIST(ES); return 1;
#endif
#if VTTS_ENABLE_ID
    case VTTS_LANG_ID: SENT_LIST(ID); return 1;
#endif
#if VTTS_ENABLE_PT
    case VTTS_LANG_PT: SENT_LIST(PT); return 1;
#endif
#if VTTS_ENABLE_FR
    case VTTS_LANG_FR: SENT_LIST(FR); return 1;
#endif
#if VTTS_ENABLE_DE
    case VTTS_LANG_DE: SENT_LIST(DE); return 1;
#endif
#if VTTS_ENABLE_IT
    case VTTS_LANG_IT: SENT_LIST(IT); return 1;
#endif
#if VTTS_ENABLE_TR
    case VTTS_LANG_TR: SENT_LIST(TR); return 1;
#endif
#if VTTS_ENABLE_PL
    case VTTS_LANG_PL: SENT_LIST(PL); return 1;
#endif
#if VTTS_ENABLE_FI
    case VTTS_LANG_FI: SENT_LIST(FI); return 1;
#endif
#if VTTS_ENABLE_MS
    case VTTS_LANG_MS: SENT_LIST(MS); return 1;
#endif
#if VTTS_ENABLE_TL
    case VTTS_LANG_TL: SENT_LIST(TL); return 1;
#endif
#if VTTS_ENABLE_SW
    case VTTS_LANG_SW: SENT_LIST(SW); return 1;
#endif
#if VTTS_ENABLE_NL
    case VTTS_LANG_NL: SENT_LIST(NL); return 1;
#endif
#if VTTS_ENABLE_SV
    case VTTS_LANG_SV: SENT_LIST(SV); return 1;
#endif
#if VTTS_ENABLE_NO
    case VTTS_LANG_NO: SENT_LIST(NO); return 1;
#endif
#if VTTS_ENABLE_DA
    case VTTS_LANG_DA: SENT_LIST(DA); return 1;
#endif
    default: return 0;
    }
}
#undef SENT_LIST

static int sent_own_letters(const sent_spec_t *S, const uint32_t *w, int n) {
    return S->vi ? has_vi_letters(w, n) : sent_own(S->own, w, n);
}

/* latin.word_evidence of a chunk core tagged English (is_en) or the main language */
static int sent_evidence(const sent_spec_t *S, const uint32_t *w, int n, int is_en) {
    char key[VTTS_SENT_MAX_KEY + 1];
    if (sent_own_letters(S, w, n)) return EV_MAIN;
    int k = sent_key(w, n, key);
    if (S->vi) {
        if (!is_en)
            return k && (sent_in(VTTS_SENT_STRONG, VTTS_SENT_STRONG_N, key) ||
                         sent_in(VTTS_SENT_COMMON, VTTS_SENT_COMMON_N, key) || vtts_lt_english_word(key))
                       ? EV_BOTH : EV_OTHER;
        return k && sent_in(VTTS_SENT_STRONG, VTTS_SENT_STRONG_N, key) ? EV_STRONG : EV_EN;
    }
    if (k && sent_in(S->main, S->n_main, key)) return EV_MAIN;
    if (k && sent_in(S->both, S->n_both, key)) return EV_BOTH;
    if (k && sent_in(VTTS_SENT_STRONG, VTTS_SENT_STRONG_N, key)) return EV_STRONG;
    return is_en || (k && sent_in(VTTS_SENT_COMMON, VTTS_SENT_COMMON_N, key)) ? EV_EN : EV_OTHER;
}

/* latin.sentence_is_english over the chunks [cs, ce) of cp (tag: TAG_EN or the main language's tag,
 * neu: the chunk is neutral) */
static int sent_english(const sent_spec_t *S, const uint32_t *cp, const int *cs, const int *ce, int nc,
                        const int *tag, const unsigned char *neu) {
    int n = 0, n_en = 0, n_strong = 0, n_main = 0, runs = 0, prev = 0;
    for (int k = 0; k < nc; k++) {
        if (neu[k]) continue;
        int a = cs[k], b = ce[k];
        while (a < b && is_edge(cp[a])) a++;
        while (b > a && is_edge(cp[b - 1])) b--;
        int e = sent_evidence(S, cp + a, b - a, tag[k] == TAG_EN);
        n += e != EV_BOTH;
        n_en += e >= EV_EN;
        n_strong += e == EV_STRONG;
        n_main += e == EV_MAIN;
        runs += e >= EV_EN && !prev;
        prev = e >= EV_EN;
    }
    return n_en >= 2 && n_strong >= 1 && n_en > 3 * n_main && 4 * n_en >= n && (2 * n_en >= n || runs >= 2);
}

/* one sentence (code points [s, e) of ws->cp): tags, runs, normalization, items, chunks */
static void v2_sentence(ctx_t *c, int s, int e, const vtts_text_opts *o) {
    vtts_text_ws *ws = c->ws;
    const uint32_t *cp = ws->cp;
    /* each flag is 0 when its language is not compiled in (vtts_text_to_ids_ex refuses the mode) */
    const int mode = o->lang, zh = VTTS_ENABLE_ZH && mode == VTTS_LANG_ZH, ko = VTTS_ENABLE_KO && mode == VTTS_LANG_KO,
              hi = VTTS_ENABLE_HI && mode == VTTS_LANG_HI, ja = VTTS_ENABLE_JA && mode == VTTS_LANG_JA;
    const int lt = mode == VTTS_LANG_ES ? VTTS_LT_ES : mode == VTTS_LANG_ID ? VTTS_LT_ID
                 : mode == VTTS_LANG_PT ? VTTS_LT_PT : (VTTS_ENABLE_MS && mode == VTTS_LANG_MS) ? VTTS_LT_MS : -1;
    const int th = VTTS_ENABLE_TH && mode == VTTS_LANG_TH, fr = VTTS_ENABLE_FR && mode == VTTS_LANG_FR;
    const int de = VTTS_ENABLE_DE && mode == VTTS_LANG_DE;
    /* it, tr: Latin-script pairs with apostrophes inside words (latin.APOSTROPHE_MODES) */
    const int lt2 = (VTTS_ENABLE_IT && mode == VTTS_LANG_IT) ? TAG_IT : (VTTS_ENABLE_TR && mode == VTTS_LANG_TR) ? TAG_TR : -1;
    const int ru = VTTS_ENABLE_RU && mode == VTTS_LANG_RU, pl = VTTS_ENABLE_PL && mode == VTTS_LANG_PL;
    const int ar = VTTS_ENABLE_AR && mode == VTTS_LANG_AR;
    const int fi = VTTS_ENABLE_FI && mode == VTTS_LANG_FI, el = VTTS_ENABLE_EL && mode == VTTS_LANG_EL;
    const int tl = VTTS_ENABLE_TL && mode == VTTS_LANG_TL, sw = VTTS_ENABLE_SW && mode == VTTS_LANG_SW;
    const int nx = nx_of(mode);
    const int da = VTTS_ENABLE_DA && mode == VTTS_LANG_DA, lo = VTTS_ENABLE_LO && mode == VTTS_LANG_LO;
    const int km = VTTS_ENABLE_KM && mode == VTTS_LANG_KM, my = VTTS_ENABLE_MY && mode == VTTS_LANG_MY;
    (void)tl; (void)sw; (void)da; (void)lo; (void)km; (void)my;
    (void)zh; (void)ko; (void)hi; (void)ja; (void)th; (void)fr; (void)de; (void)ru; (void)pl; (void)ar; (void)fi;
    if (el) /* lang.tag_words: ";" and U+037E are the Greek question mark */
        for (int q = s; q < e; q++) if (ws->cp[q] == ';' || ws->cp[q] == 0x37E) ws->cp[q] = '?';
    enum { MAXCH = 1024 };
    static int cs[MAXCH], ce[MAXCH], tag[MAXCH];
    static unsigned char neu[MAXCH]; /* the chunk is neutral (word_lang), for the sentence language */
    int nc = 0;
    /* sentence.split(); zh, ja: split_scripts(sentence).split(); es, id, pt: ¿ and ¡ are spaces */
#define SEP(c) (is_space_cp(c) || ((lt >= 0 || fr || de || lt2 >= 0 || pl || fi || tl || sw || nx >= 0 || da) && ((c) == 0xBF || (c) == 0xA1)))
    if (lt2 >= 0) /* ’ is read as ' */
        for (int i = s; i < e; i++) if (ws->cp[i] == 0x2019) ws->cp[i] = '\'';
    for (int i = s; i < e && nc < MAXCH;) {
        while (i < e && SEP(cp[i])) i++;
        if (i >= e) break;
        int j = i;
        while (j < e && !SEP(cp[j]) && !script_edge(mode, cp + i, j - i, cp[j])) j++;
        int k2 = 0; /* latin.split_elision (it, tr): sull' / iPhone, iPhone / 'da */
#if VTTS_ENABLE_IT
        if (lt2 == TAG_IT) k2 = vtts_it_split(cp + i, j - i);
#endif
#if VTTS_ENABLE_TR
        if (lt2 == TAG_TR) k2 = vtts_tr_split(cp + i, j - i);
#endif
        if (k2 > 0 && nc + 1 < MAXCH) { cs[nc] = i; ce[nc] = i + k2; nc++; i += k2; }
        cs[nc] = i; ce[nc] = j; nc++;
        i = j;
    }
#undef SEP
    if (!nc) return;
    int sent_en = mode == VTTS_LANG_EN;
    if (mode == VTTS_LANG_AUTO) { /* share of words with Vietnamese letters >= 0.2 -> vi */
        int words = 0, vi = 0;
        for (int k = 0; k < nc; k++) {
            int a = cs[k], b = ce[k];
            while (a < b && is_edge(cp[a])) a++;
            while (b > a && is_edge(cp[b - 1])) b--;
            if (!any_alpha(cp + a, b - a)) continue;
            words++;
            vi += has_vi_letters(cp + a, b - a);
        }
        sent_en = words && !((double)vi / words >= 0.2);
    }
    for (int k = 0; k < nc; k++) {
        int a = cs[k], b = ce[k];
        while (a < b && is_edge(cp[a])) a++;
        while (b > a && is_edge(cp[b - 1])) b--;
        neu[k] = 0;
#if VTTS_ENABLE_ZH
        if (zh) { /* word_lang in "zh" mode: Han -> zh, plain Latin -> en, neutral -> zh */
            tag[k] = has_han(cp + a, b - a) ? TAG_ZH : plain_latin(cp + a, b - a) ? TAG_EN : TAG_ZH;
            continue;
        }
#endif
#if VTTS_ENABLE_TH
        if (th) { /* "th" mode: Thai letters -> th, plain Latin -> en, neutral -> th */
            tag[k] = vtts_th_has_thai(cp + a, b - a) ? TAG_TH : plain_latin(cp + a, b - a) ? TAG_EN : TAG_TH;
            continue;
        }
#endif
#if VTTS_ENABLE_PL
        if (pl) { /* "pl" mode: Polish letters, word lists, CamelCase, acronyms, spelling (latin.py) */
            int r = vtts_pl_word_lang(cp + a, b - a);
            neu[k] = r < 0;
            tag[k] = r == 0 ? TAG_EN : TAG_PL;
            continue;
        }
#endif
#if VTTS_ENABLE_RU
        if (ru) { /* "ru" mode: Cyrillic -> ru, plain Latin -> en (the normalizer's units and currency
                   * codes -> ru), neutral -> ru */
            tag[k] = vtts_ru_has_cyrillic(cp + a, b - a) ? TAG_RU
                     : plain_latin(cp + a, b - a) && !vtts_ru_latin_word(cp + a, b - a) ? TAG_EN : TAG_RU;
            continue;
        }
#endif
#if VTTS_ENABLE_EL
        if (el) { /* "el" mode: Greek letters -> el, plain Latin -> en (the normalizer's units and currency
                   * words -> el), neutral -> el */
            tag[k] = vtts_el_is_greek_word(cp + a, b - a) ? TAG_EL
                     : plain_latin(cp + a, b - a) && !vtts_el_latin_word(cp + a, b - a) ? TAG_EN : TAG_EL;
            continue;
        }
#endif
#if VTTS_ENABLE_FI
        if (fi) { /* fi: as es, id, pt; the neighbours decide the words of both lists (fi_context) */
            tag[k] = vtts_fi_word_lang(cp + a, b - a); /* 1 fi, 0 en, -1 neutral; resolved below */
            neu[k] = tag[k] < 0;
            continue;
        }
#endif
#if VTTS_ENABLE_AR
        if (ar) { /* "ar" mode: Arabic letters -> ar, plain Latin -> en (the normalizer's units and currency
                   * words -> ar), neutral -> ar */
            tag[k] = vtts_ar_has_arabic(cp + a, b - a) ? TAG_AR
                     : plain_latin(cp + a, b - a) && !vtts_ar_latin_word(cp + a, b - a) ? TAG_EN : TAG_AR;
            continue;
        }
#endif
#if VTTS_ENABLE_KO
#if VTTS_ENABLE_DA
        if (da) { /* da: æ ø å é, word lists, CamelCase, acronyms, known words, compounds, spelling */
            int r = vtts_da_word_lang(cp + a, b - a);
            neu[k] = r < 0;
            tag[k] = r == 0 ? TAG_EN : TAG_DA;
            continue;
        }
#endif
#if VTTS_ENABLE_LO
        if (lo) { /* "lo" mode: Lao letters -> lo, plain Latin -> en, neutral -> lo */
            tag[k] = vtts_lo_has_lao(cp + a, b - a) ? TAG_LO : plain_latin(cp + a, b - a) ? TAG_EN : TAG_LO;
            continue;
        }
#endif
#if VTTS_ENABLE_MY
        if (my) { /* "my" mode: Burmese letters (Unicode or Zawgyi) -> my, plain Latin -> en, neutral -> my */
            tag[k] = vtts_my_has_burmese(cp + a, b - a) ? TAG_MY : plain_latin(cp + a, b - a) ? TAG_EN : TAG_MY;
            continue;
        }
#endif
#if VTTS_ENABLE_KM
        if (km) { /* "km" mode: Khmer letters -> km, plain Latin -> en, neutral -> km */
            tag[k] = vtts_km_has_khmer(cp + a, b - a) ? TAG_KM : plain_latin(cp + a, b - a) ? TAG_EN : TAG_KM;
            continue;
        }
#endif
        if (ko) { /* "ko" mode: Hangul (syllables or jamo) -> ko, plain Latin -> en, neutral -> ko */
            tag[k] = vtts_ko_has_hangul(cp + a, b - a) ? TAG_KO : plain_latin(cp + a, b - a) ? TAG_EN : TAG_KO;
            continue;
        }
#endif
#if VTTS_ENABLE_HI
        if (hi) { /* "hi" mode: Devanagari -> hi, plain Latin -> en (the normalizer's units and currency
                   * words -> hi), neutral -> hi */
            tag[k] = vtts_hi_has_devanagari(cp + a, b - a) ? TAG_HI
                     : plain_latin(cp + a, b - a) && !vtts_hi_latin_word(cp + a, b - a) ? TAG_EN : TAG_HI;
            continue;
        }
#endif
#if VTTS_ENABLE_JA
        if (ja) { /* "ja" mode: kana or kanji (_has_japanese) -> ja, plain Latin -> en, neutral -> ja */
            int has = 0;
            for (int q = a; q < b && !has; q++) has = vtts_ja_script_class(cp[q]) == 1;
            tag[k] = has ? TAG_JA : plain_latin(cp + a, b - a) ? TAG_EN : TAG_JA;
            continue;
        }
#endif
#if VTTS_ENABLE_FR
        if (fr) { /* fr: lang._fr_tags; an elided clitic glued to an English word is its own chunk */
            int split = 0, t = vtts_fr_chunk_tag(cp + cs[k], ce[k] - cs[k], &split);
            if (split > 0 && nc < MAXCH) {
                for (int q = nc; q > k + 1; q--) { cs[q] = cs[q - 1]; ce[q] = ce[q - 1]; }
                nc++;
                cs[k + 1] = cs[k] + split;
                ce[k + 1] = ce[k];
                ce[k] = cs[k] + split;
                tag[k] = TAG_FR;
                tag[++k] = TAG_EN;
                neu[k] = 0;
                continue;
            }
            neu[k] = t < 0;
            tag[k] = t == 0 ? TAG_EN : TAG_FR;
            continue;
        }
#endif
#if VTTS_ENABLE_DE
        if (de) { /* de: German letters, word lists, CamelCase, acronyms, spelling (latin.py) */
            int r = vtts_de_word_lang(cp + a, b - a);
            neu[k] = r < 0;
            tag[k] = r == 0 ? TAG_EN : TAG_DE;
            continue;
        }
#endif
#if VTTS_ENABLE_IT
        if (lt2 == TAG_IT) { /* it: as es, id, pt (latin.py) */
            int r = vtts_it_word_lang(cp + a, b - a);
            neu[k] = r < 0;
            tag[k] = r == 0 ? TAG_EN : TAG_IT;
            continue;
        }
#endif
#if VTTS_ENABLE_TR
        if (lt2 == TAG_TR) { /* tr: as es, id, pt (latin.py) */
            int r = vtts_tr_word_lang(cp + a, b - a);
            neu[k] = r < 0;
            tag[k] = r == 0 ? TAG_EN : TAG_TR;
            continue;
        }
#endif
#if VTTS_ENABLE_NX
        if (nx >= 0) { /* nl, sv, no: own letters, word lists, CamelCase, acronyms, spelling (latin.py) */
            int r = vtts_nx_word_lang(nx, cp + a, b - a);
            neu[k] = r < 0;
            tag[k] = r == 0 ? TAG_EN : TAG_NX + nx;
            continue;
        }
#endif
#if VTTS_ENABLE_TL
        if (tl) { /* tl: ñ and accent marks, word lists, hyphenated English, CamelCase, acronyms, spelling */
            int r = vtts_tl_word_lang(cp + a, b - a);
            neu[k] = r < 0;
            tag[k] = r == 0 ? TAG_EN : TAG_TL;
            continue;
        }
#endif
#if VTTS_ENABLE_SW
        if (sw) { /* sw: word lists, CamelCase, acronyms, Swahili spelling (latin.py; ng' is one word) */
            int r = vtts_sw_word_lang(cp + a, b - a);
            neu[k] = r < 0;
            tag[k] = r == 0 ? TAG_EN : TAG_SW;
            continue;
        }
#endif
#if VTTS_ENABLE_LT
        if (lt >= 0) { /* es, id, pt: own letters, word lists, CamelCase, acronyms, spelling (latin.py) */
            int r = vtts_lt_word_lang(lt, cp + a, b - a);
            neu[k] = r < 0;
            tag[k] = r == 0 ? TAG_EN : lt == VTTS_LT_MS ? TAG_MS : TAG_ES + lt;
            continue;
        }
#endif
        int t = word_tag(cp + a, b - a, sent_en);
        neu[k] = t == TAG_NEUTRAL;
        tag[k] = t == TAG_NEUTRAL ? (sent_en ? TAG_EN : TAG_VI) : t;
    }
#if VTTS_ENABLE_FI
    if (fi) {
        fi_context(cp, cs, ce, nc, tag);
        for (int k = 0; k < nc; k++) tag[k] = tag[k] == 0 ? TAG_EN : TAG_FI; /* neutral -> fi */
    }
#endif
    sent_spec_t S;
    if (sent_spec(mode, &S) && sent_english(&S, cp, cs, ce, nc, tag, neu))
        for (int k = 0; k < nc; k++) { /* lang.tag_words: an English sentence, own letters aside */
            int a = cs[k], b = ce[k];
            while (a < b && is_edge(cp[a])) a++;
            while (b > a && is_edge(cp[b - 1])) b--;
            if (neu[k] || tag[k] == TAG_EN || !sent_own_letters(&S, cp + a, b - a)) tag[k] = TAG_EN;
        }
    ws->n_items = ws->pool_used = 0;
    for (int k = 0; k < nc && !c->stop;) { /* runs of one language, chunks joined by single spaces */
        int k1 = k, len = 0;
        while (k1 < nc && tag[k1] == tag[k]) {
            if (k1 > k && len < VTTS_TEXT_MAX_CP) ws->run[len++] = ' ';
            for (int q = cs[k1]; q < ce[k1] && len < VTTS_TEXT_MAX_CP; q++) ws->run[len++] = cp[q];
            k1++;
        }
        const lang_mod_t *m = &LANGS[tag[k]];
        ws->n_words = ws->words_used = 0;
        c->collect = 1;
        m->normalize(c, ws->run, len, o);
        for (int w = 0; w < ws->n_words; w++) add_word_or_mark(ws, ws->words + ws->word_off[w], m, o);
        ws->n_words = ws->words_used = 0;
        c->collect = 0;
        k = k1;
    }
    pack_items(c);
}

/* lang.py SENTENCE_END: split at whitespace after . ! ? ; (not after a dot that follows a Thai
 * letter) and, in the zh, ko, hi, ja, es, id, pt and th modes, right after 。！？；।॥ (the vi-en modes
 * keep their earlier behaviour) */
/* lang.DOT_CONTINUES: the characters that continue a sentence after a dot and whitespace */
static int dot_continues_cp(int lang, uint32_t c) {
    if (c >= '0' && c <= '9') return 1;
    if (lang == VTTS_LANG_FI)
        return (c >= 'a' && c <= 'z') || c == 0xE5 || c == 0xE4 || c == 0xF6 || c == 0x161 || c == 0x17E;
    if (lang == VTTS_LANG_EL) return (c >= 0x3AC && c <= 0x3CE) || c == 0x390; /* α-ω ς, accented, ΐ ΰ */
    if (lang == VTTS_LANG_DA) return (c >= 'a' && c <= 'z') || c == 0xE6 || c == 0xF8 || c == 0xE5 || c == 0xE9;
    return 0;
}

/* [a-zçğıöşüâîû] */
static int tr_lower_letter(uint32_t c) {
    return (c >= 'a' && c <= 'z') || c == 0xE7 || c == 0x11F || c == 0x131 || c == 0xF6 || c == 0x15F || c == 0xFC ||
           c == 0xE2 || c == 0xEE || c == 0xFB;
}

/* A dot at cp[i - 1] followed by whitespace at cp[i] (the text is cp[a..z)) that does not end a
 * sentence (lang.py SENTENCE_END and the per-mode rules):
 * - every mode: a dot after a Thai or Khmer letter ends an abbreviation (พ.ศ. 2567, ព.ស.);
 * - every mode: a dot before whitespace and a lower-case Cyrillic letter ends an abbreviation (т. е.,
 *   ул. ленина);
 * - tr (SENTENCE_END_TR): a dot after a digit before exactly one space and a lower-case word is an
 *   ordinal (5. sınıf; two spaces still split, as the regex);
 * - fi, el, da (lang.DOT_CONTINUES): a dot before whitespace and a lower-case letter of the language
 *   or a digit (n. 50, 3. toukokuuta, χλμ. σε, den 5. marts);
 * - lo (lang.DOT_AFTER_LETTER): a dot after a Lao letter ends an abbreviation too (ຄ.ສ. 2024). */
static int dot_continues(int lang, const uint32_t *cp, int a, int z, int i) {
    if (i - 2 >= a && is_thai_cp(cp[i - 2])) return 1;
    if (i - 2 >= a && cp[i - 2] >= 0x1780 && cp[i - 2] <= 0x17DD) return 1; /* Khmer */
#if VTTS_ENABLE_LO
    if (lang == VTTS_LANG_LO && i - 2 >= a && vtts_lo_is_lao(cp[i - 2])) return 1;
#endif
    if (is_space_cp(cp[i])) {
        int j = i;
        while (j < z && is_space_cp(cp[j])) j++;
        if (j < z && ((cp[j] >= 0x430 && cp[j] <= 0x44F) || cp[j] == 0x451)) return 1;
    }
    if (lang == VTTS_LANG_TR && i - 2 >= a && vtts_u_digit(cp[i - 2]) >= 0 && is_space_cp(cp[i]) && i + 1 < z &&
        tr_lower_letter(cp[i + 1]))
        return 1;
    if ((lang == VTTS_LANG_FI || lang == VTTS_LANG_EL || lang == VTTS_LANG_DA) && is_space_cp(cp[i])) {
        int q = i;
        while (q < z && is_space_cp(cp[q])) q++;
        if (q < z && dot_continues_cp(lang, cp[q])) return 1;
    }
    return 0;
}

static int cjk_end(uint32_t c) {
    return c == 0x3002 || c == 0xFF01 || c == 0xFF1F || c == 0xFF1B || c == 0x0964 || c == 0x0965 ||
           c == 0x17D4 || c == 0x17D5 || c == 0x104B; /* Khmer ។ ៕, Burmese ။ */
}

int vtts_text_to_ids_ex(const char *utf8, vtts_text_ws *ws, const vtts_text_opts *o, vtts_ids_cb cb, void *user) {
    if (!o || o->lang == VTTS_LANG_V1) return vtts_text_to_ids(utf8, ws, cb, user);
    if (!utf8 || !ws || !lang_enabled(o->lang)) return -1; /* a mode that is not compiled in */
    ctx_t ctx = {ws, cb, user, 0, 0, 0}, *c = &ctx;
    const int cjk = o->lang == VTTS_LANG_ZH || o->lang == VTTS_LANG_KO || o->lang == VTTS_LANG_HI ||
                    o->lang == VTTS_LANG_JA || o->lang == VTTS_LANG_ES || o->lang == VTTS_LANG_ID ||
                    o->lang == VTTS_LANG_PT || o->lang == VTTS_LANG_TH || o->lang == VTTS_LANG_FR ||
                    o->lang == VTTS_LANG_IT || o->lang == VTTS_LANG_TR || o->lang == VTTS_LANG_RU ||
                    o->lang == VTTS_LANG_PL || o->lang == VTTS_LANG_AR || o->lang == VTTS_LANG_FI ||
                    o->lang == VTTS_LANG_EL || o->lang == VTTS_LANG_MS || o->lang == VTTS_LANG_TL ||
                    o->lang == VTTS_LANG_SW || o->lang == VTTS_LANG_DA || o->lang == VTTS_LANG_LO ||
                    o->lang == VTTS_LANG_KM || o->lang == VTTS_LANG_MY;
    int n = ws->n_cp = utf8_decode(utf8, ws->cp, VTTS_TEXT_MAX_CP);
#if VTTS_ENABLE_NX
    if (o->lang == VTTS_LANG_NL || o->lang == VTTS_LANG_SV || o->lang == VTTS_LANG_NO) {
        /* scan_norm.split_sentences: abbreviations, initials and (no) ordinals keep their dot */
        int nx = nx_of(o->lang);
        vtts_nx_split st = {0, 0, 0, 0};
        int s0, e0;
        while (!c->stop && vtts_nx_next_sentence(nx, ws->cp, n, &st, &s0, &e0)) v2_sentence(c, s0, e0, o);
        return c->chunks;
    }
#endif
#if VTTS_ENABLE_DE
    if (o->lang == VTTS_LANG_DE) { /* split_sentences_de: ordinals and abbreviations keep their dot */
        vtts_de_split st = {0, 0, 0, 0};
        int s0, e0;
        while (!c->stop && vtts_de_next_sentence(ws->cp, n, &st, &s0, &e0)) v2_sentence(c, s0, e0, o);
        return c->chunks;
    }
#endif
    int a = 0, z = n;
    while (a < z && is_space_cp(ws->cp[a])) a++; /* text.strip() */
    while (z > a && is_space_cp(ws->cp[z - 1])) z--;
    int s = a;
    for (int i = a; i < z && !c->stop; i++) {
        uint32_t pc = i > s ? ws->cp[i - 1] : 0;
        int thai_dot = pc == '.' && dot_continues(o->lang, ws->cp, a, z, i);
        /* SENTENCE_END: . ! ? ; and the Arabic ؟ ؛ ۔ before whitespace (every mode) */
        if ((is_space_cp(ws->cp[i]) && (pc == '.' || pc == '!' || pc == '?' || pc == ';' || pc == 0x061F ||
                                        pc == 0x061B || pc == 0x06D4) && !thai_dot) ||
            (cjk && cjk_end(pc))) {
            v2_sentence(c, s, i, o);
            while (i < z && is_space_cp(ws->cp[i])) i++;
            s = i;
            i--;
        }
    }
    if (s < z && !c->stop) v2_sentence(c, s, z, o);
    return c->chunks;
}

/* ---------------- text modes per token set ---------------- */

/* the first mode of a token set is its default; a language that is not compiled in has no mode */
static const struct { int token_set; const char *name; vtts_lang lang; } MODES[] = {
    {VTTS_TOKSET_V1, "vi", VTTS_LANG_V1},       {VTTS_TOKSET_VI_EN, "vi", VTTS_LANG_VI},
    {VTTS_TOKSET_VI_EN, "en", VTTS_LANG_EN},    {VTTS_TOKSET_VI_EN, "auto", VTTS_LANG_AUTO},
#if VTTS_ENABLE_ZH
    {VTTS_TOKSET_ZH_EN, "zh", VTTS_LANG_ZH},
#endif
#if VTTS_ENABLE_KO
    {VTTS_TOKSET_KO_EN, "ko", VTTS_LANG_KO},
#endif
#if VTTS_ENABLE_HI
    {VTTS_TOKSET_HI_EN, "hi", VTTS_LANG_HI},
#endif
#if VTTS_ENABLE_JA
    {VTTS_TOKSET_JA_EN, "ja", VTTS_LANG_JA},
#endif
#if VTTS_ENABLE_ES
    {VTTS_TOKSET_ES_EN, "es", VTTS_LANG_ES},
#endif
#if VTTS_ENABLE_ID
    {VTTS_TOKSET_ID_EN, "id", VTTS_LANG_ID},
#endif
#if VTTS_ENABLE_PT
    {VTTS_TOKSET_PT_EN, "pt", VTTS_LANG_PT},
#endif
#if VTTS_ENABLE_TH
    {VTTS_TOKSET_TH_EN, "th", VTTS_LANG_TH},
#endif
#if VTTS_ENABLE_FR
    {VTTS_TOKSET_FR_EN, "fr", VTTS_LANG_FR},
#endif
#if VTTS_ENABLE_DE
    {VTTS_TOKSET_DE_EN, "de", VTTS_LANG_DE},
#endif
#if VTTS_ENABLE_IT
    {VTTS_TOKSET_IT_EN, "it", VTTS_LANG_IT},
#endif
#if VTTS_ENABLE_TR
    {VTTS_TOKSET_TR_EN, "tr", VTTS_LANG_TR},
#endif
#if VTTS_ENABLE_RU
    {VTTS_TOKSET_RU_EN, "ru", VTTS_LANG_RU},
#endif
#if VTTS_ENABLE_PL
    {VTTS_TOKSET_PL_EN, "pl", VTTS_LANG_PL},
#endif
#if VTTS_ENABLE_AR
    {VTTS_TOKSET_AR_EN, "ar", VTTS_LANG_AR},
#endif
#if VTTS_ENABLE_FI
    {VTTS_TOKSET_FI_EN, "fi", VTTS_LANG_FI},
#endif
#if VTTS_ENABLE_EL
    {VTTS_TOKSET_EL_EN, "el", VTTS_LANG_EL},
#endif
#if VTTS_ENABLE_MS
    {VTTS_TOKSET_MS_EN, "ms", VTTS_LANG_MS},
#endif
#if VTTS_ENABLE_TL
    {VTTS_TOKSET_TL_EN, "tl", VTTS_LANG_TL},
#endif
#if VTTS_ENABLE_SW
    {VTTS_TOKSET_SW_EN, "sw", VTTS_LANG_SW},
#endif
#if VTTS_ENABLE_NL
    {VTTS_TOKSET_NL_EN, "nl", VTTS_LANG_NL},
#endif
#if VTTS_ENABLE_SV
    {VTTS_TOKSET_SV_EN, "sv", VTTS_LANG_SV},
#endif
#if VTTS_ENABLE_NO
    {VTTS_TOKSET_NO_EN, "no", VTTS_LANG_NO},
#endif
#if VTTS_ENABLE_LO
    {VTTS_TOKSET_LO_EN, "lo", VTTS_LANG_LO},
#endif
#if VTTS_ENABLE_DA
    {VTTS_TOKSET_DA_EN, "da", VTTS_LANG_DA},
#endif
#if VTTS_ENABLE_KM
    {VTTS_TOKSET_KM_EN, "km", VTTS_LANG_KM},
#endif
#if VTTS_ENABLE_MY
    {VTTS_TOKSET_MY_EN, "my", VTTS_LANG_MY},
#endif
};
#define N_MODES ((int)(sizeof(MODES) / sizeof(MODES[0])))

int vtts_text_lang_for(int token_set, const char *mode, vtts_lang *out) {
    if (!mode || !out) return -1;
    for (int i = 0; i < N_MODES; i++)
        if (MODES[i].token_set == token_set && strcmp(MODES[i].name, mode) == 0) {
            *out = MODES[i].lang;
            return 0;
        }
    return -1;
}

int vtts_text_default_lang(int token_set, vtts_lang *out) { /* the first mode listed */
    for (int i = 0; i < N_MODES; i++)
        if (MODES[i].token_set == token_set) {
            if (out) *out = MODES[i].lang;
            return 0;
        }
    return -1;
}

int vtts_text_model_lang(int token_set, int text_mode, vtts_lang *out) {
    char mode[5] = {0};
    for (int i = 0; i < 4; i++) mode[i] = (char)(((unsigned)text_mode >> (8 * i)) & 0x7f);
    if (text_mode != 0 && vtts_text_lang_for(token_set, mode, out) == 0) return 0;
    return vtts_text_default_lang(token_set, out); /* no dim, or a mode this set does not offer */
}

const char *vtts_text_modes(int token_set) {
    vtts_lang l;
    if (token_set == VTTS_TOKSET_VI_EN) return "vi|en|auto";
    return vtts_text_default_lang(token_set, &l) == 0 ? vtts_text_lang_name(l) : ""; /* one mode per pair set */
}

const char *vtts_text_lang_name(vtts_lang lang) {
    switch (lang) {
    case VTTS_LANG_EN: return "en";
    case VTTS_LANG_AUTO: return "auto";
    case VTTS_LANG_ZH: return "zh";
    case VTTS_LANG_KO: return "ko";
    case VTTS_LANG_HI: return "hi";
    case VTTS_LANG_JA: return "ja";
    case VTTS_LANG_ES: return "es";
    case VTTS_LANG_ID: return "id";
    case VTTS_LANG_PT: return "pt";
    case VTTS_LANG_TH: return "th";
    case VTTS_LANG_FR: return "fr";
    case VTTS_LANG_DE: return "de";
    case VTTS_LANG_IT: return "it";
    case VTTS_LANG_TR: return "tr";
    case VTTS_LANG_RU: return "ru";
    case VTTS_LANG_PL: return "pl";
    case VTTS_LANG_AR: return "ar";
    case VTTS_LANG_FI: return "fi";
    case VTTS_LANG_EL: return "el";
    case VTTS_LANG_MS: return "ms";
    case VTTS_LANG_TL: return "tl";
    case VTTS_LANG_SW: return "sw";
    case VTTS_LANG_NL: return "nl";
    case VTTS_LANG_SV: return "sv";
    case VTTS_LANG_NO: return "no";
    case VTTS_LANG_LO: return "lo";
    case VTTS_LANG_DA: return "da";
    case VTTS_LANG_KM: return "km";
    case VTTS_LANG_MY: return "my";
    default: return "vi";
    }
}
