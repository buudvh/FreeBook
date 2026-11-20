/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_en.h -- English pieces of the device front-end (internal). */
#ifndef VTTS_TEXT_EN_H
#define VTTS_TEXT_EN_H

#include <stdint.h>

#include "vtts_lex.h"

/* Token ids (set v2) of one English word (letters, apostrophes, hyphens), like g2p_word_en.
 * Returns the number of ids, or < 0 if cap is too small. lx may be NULL (lexicon-free: only
 * the spelling of short acronyms is available, other words give no ids). */
int vtts_en_g2p(const vtts_lex *lx, const char *word, uint8_t *out, int cap);

/* Python \w and \s for one code point (defined in vtts_text.c). */
int vtts_cp_is_word(uint32_t cp);
int vtts_cp_is_space(uint32_t cp);

/* English normalization of n code points, like normalize_en(): lower-case words and the marks
 * , . ? ! ; : separated by single spaces, written to out as a NUL-terminated ASCII string.
 * a and b are scratch buffers of cap code points each. Returns the length of out, or < 0 when a
 * buffer is too small. Only ASCII digits count as digits (Python's \d also takes other scripts). */
int vtts_en_normalize(const uint32_t *cp, int n, uint32_t *a, uint32_t *b, int cap, char *out, int out_cap);

#endif
