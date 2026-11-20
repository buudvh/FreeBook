/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_tl.h -- Tagalog (Filipino) pair language of the device front-end (internal), token set
 * tl-en. Mirrors src/vtts/frontend/tl/ (normalize_tl.py, g2p_tl.py), the Tagalog rules of latin.py
 * and the helpers of latin_norm.py. Tables are generated into vtts_text_tl_tables.h; no blob.
 *
 * VTTS_ENABLE_TL (default 1): with 0 the Tagalog code and tables are not compiled and the mode
 * tl is unknown (vtts_text_lang_for fails, like a token set without a device front-end). */
#ifndef VTTS_TEXT_TL_H
#define VTTS_TEXT_TL_H

#include <stdint.h>

#include "vtts_langs.h" /* VTTS_ENABLE_TL */

/* lang.word_lang for a chunk core in mode tl: 1 Tagalog, 0 English, -1 neutral (read in Tagalog). */
int vtts_tl_word_lang(const uint32_t *w, int n);

/* normalize_tl of n code points: lower-case words and the marks , . ? ! ; : separated by single
 * spaces. a and b are scratch buffers of cap code points each (the result is left in one of them,
 * *out points at it). Returns the length of the result or < 0 when a buffer is too small. */
int vtts_tl_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, const uint32_t **out);

/* word_tokens_tl of one normalized word (n code points): token ids of tl-en, at most cap (a longer
 * result is cut). scratch: VTTS_TL_SCRATCH uint32 values. Returns the count. */
#define VTTS_TL_MAXW 512 /* code points of a folded word (a word is cut to VTTS_TL_MAXW / 2) */
#define VTTS_TL_SCRATCH (5 * VTTS_TL_MAXW + 8)
int vtts_tl_word_ids(const uint32_t *w, int n, uint32_t *scratch, uint8_t *out, int cap);

#endif
