/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_pl.h -- Polish pieces of the device front-end (internal). Compiled when VTTS_ENABLE_PL
 * is non-zero (vtts_langs.h; the default); with VTTS_ENABLE_PL=0 the module is an empty unit. */
#ifndef VTTS_TEXT_PL_H
#define VTTS_TEXT_PL_H

#include <stdint.h>

#include "vtts_langs.h" /* VTTS_ENABLE_PL */

/* lang.word_lang for a chunk core in mode "pl" (latin.latin_word_lang): 1 Polish, 0 English,
 * -1 neutral (read in Polish). */
int vtts_pl_word_lang(const uint32_t *w, int n);

/* Token ids (set pl-en) of one normalized word like word_tokens_pl; at most cap (a longer result is
 * cut). Returns the count. */
#define VTTS_PL_MAXW 64 /* letters of one word read (a longer word is cut) */
int vtts_pl_word_ids(const uint32_t *w, int n, uint8_t *out, int cap);

/* Polish normalization of n code points, like normalize_pl(): lower-case words and the marks
 * , . ? ! ; : separated by single spaces. a and b (cap code points each) hold the passes, t (cap)
 * is scratch. Returns the length of the result (*out points into a or b), or < 0 when a buffer is
 * too small. */
int vtts_pl_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, uint32_t *t, int cap,
                      const uint32_t **out);

#endif
