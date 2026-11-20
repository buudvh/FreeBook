/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_ru.h -- Russian pieces of the device front-end (internal). Compiled when VTTS_ENABLE_RU
 * is non-zero (vtts_langs.h; the default); with VTTS_ENABLE_RU=0 the module is an empty unit. */
#ifndef VTTS_TEXT_RU_H
#define VTTS_TEXT_RU_H

#include <stdint.h>

#include "vtts_rlex.h"

#include "vtts_langs.h" /* VTTS_ENABLE_RU */

/* g2p_ru.is_ru_word: a code point of U+0400..U+04FF. */
int vtts_ru_has_cyrillic(const uint32_t *w, int n);

/* normalize_ru.LATIN_WORDS (units and currency codes read in Russian with their number: km, GB, USD). */
int vtts_ru_latin_word(const uint32_t *w, int n);

/* Token ids (set ru-en) of one normalized Cyrillic word like word_tokens_ru. lex: the RLEX stress
 * tables (NULL: every word is stressed by the default ending rule). scratch: VTTS_RU_SCRATCH uint32
 * values. Returns the number of ids (at most cap; a longer result is cut). */
#define VTTS_RU_MAXW 64 /* letters of one word read (a longer word is cut) */
#define VTTS_RU_SCRATCH (8 * VTTS_RU_MAXW + 64)
int vtts_ru_word_ids(const vtts_rlex *lex, const uint32_t *w, int n, uint32_t *scratch, uint8_t *out, int cap);

/* Russian normalization of n code points, like normalize_ru(): lower-case words and the marks
 * , . ? ! ; : separated by single spaces. a and b (cap code points each) hold the passes; ea, eb
 * (ecap each) and eout are the English normalizer's scratch. Returns the length of the result (*out
 * points into a or b), or < 0 when a buffer is too small. */
int vtts_ru_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, uint32_t *ea, uint32_t *eb,
                      int ecap, char *eout, int eout_cap, const uint32_t **out);

#endif
