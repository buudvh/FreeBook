/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_nsp.h -- normalization engine for scripts written without spaces between words
 * (Khmer, Burmese), mirroring src/vtts/frontend/nospace_norm.py (internal). */
#ifndef VTTS_TEXT_NSP_H
#define VTTS_TEXT_NSP_H

#include <stdint.h>

#define VTTS_NSP_GLUE 0x01u /* number words: spaces next to them are dropped */

typedef struct { uint32_t *p; int n, cap, err; } vtts_nsp_buf;

void vtts_nsp_put(vtts_nsp_buf *d, uint32_t c);
void vtts_nsp_put_utf8(vtts_nsp_buf *d, const char *s);

typedef struct vtts_nsp_spec vtts_nsp_spec;
struct vtts_nsp_spec {
    int (*is_letter)(uint32_t c);   /* the script class of the Spec (letters regex) */
    int (*is_word)(uint32_t c);     /* Python \w: 1 / 0, or -1 for code points outside the script block */
    uint32_t digit0;                /* native digit zero */
    /* language pass before the digits (NULL: none) into d, tmp is scratch; returns 0, or < 0 when a
     * buffer is too small */
    int (*pre)(const uint32_t *in, int n, vtts_nsp_buf *d, vtts_nsp_buf *tmp);
    void (*below_million)(vtts_nsp_buf *d, int v); /* 1..999999 */
    const char *million;
    const char *const *digits;      /* 10 digit words */
    const char *point, *minus, *to, *percent;
    const char *const (*currency)[2]; int n_currency; /* UTF-8 symbol (one code point), word */
    const char *const (*units)[2]; int n_units;       /* alternation order (longest first) */
    const char *const (*abbrev)[2]; int n_abbrev;     /* dotted abbreviations, longest first */
    const char *const (*punct)[2]; int n_punct;       /* str.replace, in this order */
    const char *const *symbols;     /* the words of + = & @ × (a word with spaces is not glued) */
    void (*date)(const vtts_nsp_spec *sp, vtts_nsp_buf *d, int day, int month, const uint32_t *y, int ny);
    void (*time)(const vtts_nsp_spec *sp, vtts_nsp_buf *d, int h, int m, int s);
    uint32_t repeat;                /* 0: none */
    int space_pause;
    const char *const *dedupe; int n_dedupe;
};

/* cardinal(int(s)) for ASCII digits (groups of six digits joined by the million word), digits() */
void vtts_nsp_cardinal_u(const vtts_nsp_spec *sp, vtts_nsp_buf *d, const uint32_t *s, int n);
void vtts_nsp_cardinal_i(const vtts_nsp_spec *sp, vtts_nsp_buf *d, int v);
void vtts_nsp_digits(const vtts_nsp_spec *sp, vtts_nsp_buf *d, const uint32_t *s, int n);

/* Normalizer(spec)(text): runs of script letters, lower-case Latin words and the marks , . ? ! ; :
 * separated by single spaces. a, b: cap code points each; ea, eb, eout: the English normalizer's
 * scratch. Returns the length of the result (*out points into a or b), or < 0 when a buffer is too
 * small. Only ASCII and the native digits count as digits. */
int vtts_nsp_normalize(const vtts_nsp_spec *sp, const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap,
                       uint32_t *ea, uint32_t *eb, int ecap, char *eout, int eout_cap, const uint32_t **out);

#endif
