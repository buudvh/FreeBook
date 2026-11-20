/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_el.h -- Greek front-end of the device (internal), token set el-en. Mirrors
 * src/vtts/frontend/el/ (normalize_el.py, g2p_el.py) and the el rules of lang.py. All tables are in
 * the generated vtts_text_el_tables.h; no blob is needed. Compiled only when VTTS_ENABLE_EL is not 0
 * (1 by default). */
#ifndef VTTS_TEXT_EL_H
#define VTTS_TEXT_EL_H

#include <stdint.h>

#include "vtts_langs.h" /* VTTS_ENABLE_EL */

/* g2p_el.is_greek_word: a Greek letter (U+0370..U+03FF, U+1F00..U+1FFF, isalpha()). */
int vtts_el_is_greek_word(const uint32_t *w, int n);

/* normalize_el.LATIN_WORDS (units and currency words read in Greek with their number: km, GB). */
int vtts_el_latin_word(const uint32_t *w, int n);

/* normalize_el of n code points: Greek words (lower case, accents kept, final sigma), lower-case
 * Latin words (read by the English module) and the marks , . ? ! ; : separated by single spaces.
 * a and b (cap code points each) hold the passes; ea and eb (ecap each) and eout are the English
 * normalizer's scratch. Returns the length of the result (*out), or < 0 when a buffer is too small. */
int vtts_el_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, uint32_t *ea, uint32_t *eb,
                      int ecap, char *eout, int eout_cap, const uint32_t **out);

/* word_tokens_el of one Greek word (n code points): token ids of el-en, at most cap (a longer result
 * is cut). scratch: VTTS_EL_SCRATCH uint32 values. Returns the count. */
#define VTTS_EL_MAXW 512 /* letters of one word read (a longer word is cut) */
#define VTTS_EL_SCRATCH (6 * VTTS_EL_MAXW)
int vtts_el_word_ids(const uint32_t *w, int n, uint32_t *scratch, uint8_t *out, int cap);

#endif
