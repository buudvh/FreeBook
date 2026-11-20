/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_sw.h -- Swahili + English (token set sw-en) of the device front-end (internal). Mirrors
 * src/vtts/frontend/sw/ (normalize_sw.py, g2p_sw.py) and latin.py (tagging of plain Latin words in
 * the sw pair). Tables are in the generated vtts_text_sw_tables.h; the English word list and the
 * Unicode classes of Python's re come from vtts_text_lt.c.
 *
 * Compile switch VTTS_ENABLE_SW (default 1): with 0 the module and its tables are not compiled, the
 * token set sw-en has no text mode (vtts_text_lang_for / vtts_text_default_lang fail, like a token
 * set without a device front-end) and vtts_text_to_ids_ex rejects VTTS_LANG_SW. */
#ifndef VTTS_TEXT_SW_H
#define VTTS_TEXT_SW_H

#include <stddef.h>
#include <stdint.h>

#include "vtts_langs.h" /* VTTS_ENABLE_SW */

#if VTTS_ENABLE_SW
/* lang.word_lang(core, "sw") for a chunk core: 1 Swahili, 0 English, -1 neutral (read in Swahili). */
int vtts_sw_word_lang(const uint32_t *w, int n);

/* normalize_sw of n code points: lower-case words and the marks , . ? ! ; : separated by single
 * spaces. a and b are scratch buffers of cap code points each (the result is left in one of them,
 * *out points at it). Returns the length of the result or < 0 when a buffer is too small. */
int vtts_sw_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, const uint32_t **out);

/* word_tokens_sw of one normalized word (n code points): token ids of sw-en, at most cap (a longer
 * result is cut). scratch: at least VTTS_SW_SCRATCH_BYTES bytes, 4-byte aligned. A word longer than
 * VTTS_SW_MAXW / 2 code points is cut. Returns the count. */
#define VTTS_SW_MAXW 512
#define VTTS_SW_SCRATCH_BYTES (2 * (VTTS_SW_MAXW + 8) + 8 * VTTS_SW_MAXW)
int vtts_sw_word_ids(const uint32_t *w, int n, void *scratch, size_t scratch_bytes, uint8_t *out, int cap);
#endif

#endif
