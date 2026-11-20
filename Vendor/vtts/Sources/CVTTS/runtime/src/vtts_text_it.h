/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_it.h -- Italian device front-end (internal; token set it-en). Mirrors
 * src/vtts/frontend/it/ (normalize_it.py, g2p_it.py) and the Italian rules of latin.py and lang.py.
 * Compiled only with VTTS_ENABLE_IT (default 1); tables in the generated vtts_text_it_tables.h. */
#ifndef VTTS_TEXT_IT_H
#define VTTS_TEXT_IT_H

#include <stdint.h>

#include "vtts_langs.h" /* VTTS_ENABLE_IT */

#if VTTS_ENABLE_IT
/* lang.word_lang of a chunk core in mode "it": 1 Italian, 0 English, -1 neutral */
int vtts_it_word_lang(const uint32_t *w, int n);

/* latin.split_elision of a chunk (after ’ -> '): the index where a second chunk starts (the code
 * point after the first apostrophe: sull' / iPhone), or 0 when the chunk stays whole */
int vtts_it_split(const uint32_t *w, int n);

/* normalize_it of n code points into a or b (cap code points each); *out points at the result.
 * Returns its length or < 0 when a buffer is too small. */
int vtts_it_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, const uint32_t **out);

/* word_tokens_it of one normalized word: ids of the it-en set (at most cap). scratch holds
 * VTTS_IT_SCRATCH uint32 values. */
#define VTTS_IT_MAXW 512
#define VTTS_IT_SCRATCH (8 * VTTS_IT_MAXW)
int vtts_it_word_ids(const uint32_t *w, int n, uint32_t *scratch, uint8_t *out, int cap);
#endif

#endif
