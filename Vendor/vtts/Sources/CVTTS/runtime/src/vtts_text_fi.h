/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_fi.h -- Finnish front-end of the device (internal), token set fi-en. Mirrors
 * src/vtts/frontend/fi/ (normalize_fi.py, g2p_fi.py) and the fi rules of latin.py and lang.py. All
 * tables are in the generated vtts_text_fi_tables.h; no blob is needed. Compiled only when
 * VTTS_ENABLE_FI is not 0 (1 by default). */
#ifndef VTTS_TEXT_FI_H
#define VTTS_TEXT_FI_H

#include <stdint.h>

#include "vtts_langs.h" /* VTTS_ENABLE_FI */

/* lang.word_lang(core, "fi") for a chunk core: 1 Finnish, 0 English, -1 neutral (read in Finnish). */
int vtts_fi_word_lang(const uint32_t *w, int n);

/* The core is in both lexicons/fi/native.txt and the English list (lang._by_context: it follows
 * its neighbours). Only meaningful for a core tagged Finnish. */
int vtts_fi_ambiguous(const uint32_t *w, int n);

/* normalize_fi of n code points: lower-case words and the marks , . ? ! ; : separated by single
 * spaces. a and b are scratch buffers of cap code points each (the result is left in one of them,
 * *out points at it). Returns the length of the result or < 0 when a buffer is too small. */
int vtts_fi_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, const uint32_t **out);

/* word_tokens_fi of one normalized word (n code points): token ids of fi-en, at most cap (a longer
 * result is cut). scratch: VTTS_FI_SCRATCH uint32 values. Returns the count. */
#define VTTS_FI_MAXW 512 /* letters of one word read (a longer word is cut) */
#define VTTS_FI_SCRATCH (4 * VTTS_FI_MAXW)
int vtts_fi_word_ids(const uint32_t *w, int n, uint32_t *scratch, uint8_t *out, int cap);

#endif
