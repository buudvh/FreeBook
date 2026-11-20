/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_tr.h -- Turkish device front-end (internal; token set tr-en). Mirrors
 * src/vtts/frontend/tr/ (normalize_tr.py, g2p_tr.py) and the Turkish rules of latin.py and lang.py.
 * Compiled only with VTTS_ENABLE_TR (default 1); tables in the generated vtts_text_tr_tables.h. */
#ifndef VTTS_TEXT_TR_H
#define VTTS_TEXT_TR_H

#include <stdint.h>

#include "vtts_langs.h" /* VTTS_ENABLE_TR */

#if VTTS_ENABLE_TR
/* lang.word_lang of a chunk core in mode "tr": 1 Turkish, 0 English, -1 neutral */
int vtts_tr_word_lang(const uint32_t *w, int n);

/* latin.split_elision of a chunk (after ’ -> '): the index of the apostrophe that starts a second
 * chunk (a suffix after an English word: iPhone / 'da), or 0 when the chunk stays whole */
int vtts_tr_split(const uint32_t *w, int n);

/* normalize_tr of n code points into a or b (cap code points each); *out points at the result.
 * Returns its length or < 0 when a buffer is too small. */
int vtts_tr_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, const uint32_t **out);

/* word_tokens_tr of one normalized word: ids of the tr-en set (at most cap). scratch holds
 * VTTS_TR_SCRATCH uint32 values. */
#define VTTS_TR_MAXW 512
#define VTTS_TR_SCRATCH (8 * VTTS_TR_MAXW)
int vtts_tr_word_ids(const uint32_t *w, int n, uint32_t *scratch, uint8_t *out, int cap);
#endif

#endif
