/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_da.h -- Danish pair language of the device front-end (internal), token set da-en.
 * Mirrors src/vtts/frontend/da/ (normalize_da.py, g2p_da.py), the Danish rules of latin.py and the
 * helpers of latin_norm.py. Tables (with the NST readings of the frequent words) are generated into
 * vtts_text_da_tables.h; no blob.
 *
 * VTTS_ENABLE_DA (default 1): with 0 the Danish code and tables are not compiled and the mode da is
 * unknown (vtts_text_lang_for fails, vtts_text_to_ids_ex returns -1). */
#ifndef VTTS_TEXT_DA_H
#define VTTS_TEXT_DA_H

#include <stddef.h>
#include <stdint.h>

#include "vtts_langs.h" /* VTTS_ENABLE_DA */

/* lang.word_lang for a chunk core in mode da: 1 Danish, 0 English, -1 neutral (read in Danish). */
int vtts_da_word_lang(const uint32_t *w, int n);

/* normalize_da of n code points: lower-case words and the marks , . ? ! ; : separated by single
 * spaces. a and b are scratch buffers of cap code points each (the result is left in one of them,
 * *out points at it). Returns the length of the result or < 0 when a buffer is too small. */
int vtts_da_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, const uint32_t **out);

/* word_tokens_da of one normalized word (n code points): token ids of da-en, at most cap (a longer
 * result is cut). scratch: at least VTTS_DA_SCRATCH bytes. A word is read up to VTTS_DA_MAXW letters.
 * Returns the count. */
#define VTTS_DA_MAXW 192
#define VTTS_DA_SCRATCH 16384
int vtts_da_word_ids(const uint32_t *w, int n, void *scratch, size_t ns, uint8_t *out, int cap);

#endif
