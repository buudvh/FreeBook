/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_fr.h -- French (fr-en) language module of the device front-end (internal). Mirrors
 * src/vtts/frontend/fr/ (normalize_fr.py with liaison, g2p_fr.py) and the fr rules of lang.py and
 * latin.py. All tables are in the generated vtts_text_fr_tables.h; no blob is needed.
 *
 * Compiled only when VTTS_ENABLE_FR is 1 (vtts_langs.h: the default for host builds and tests; the
 * firmware sets it from the token sets of the models it embeds). When it is 0 the module is empty
 * and the mode "fr" is not offered. */
#ifndef VTTS_TEXT_FR_H
#define VTTS_TEXT_FR_H

#include <stdint.h>

#include "vtts_langs.h" /* VTTS_ENABLE_FR */

/* lang._fr_tags for one whitespace-separated chunk of a sentence in mode fr: 1 French, 0 English,
 * -1 neutral (read in French). When an elided clitic is glued to an English word (l'iPhone) the
 * chunk is split: *split is the length of the clitic part (French), the rest is English (return 0);
 * otherwise *split is 0. */
int vtts_fr_chunk_tag(const uint32_t *chunk, int n, int *split);

/* normalize_fr of n code points: lower-case words (apostrophes kept, liaison applied) and the marks
 * , . ? ! ; : separated by single spaces. a and b are scratch buffers of cap code points each (the
 * result is left in one of them, *out points at it). Returns the length or < 0 when a buffer is too
 * small. */
int vtts_fr_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, const uint32_t **out);

/* word_tokens_fr of one normalized word (n code points): fr-en token ids, at most cap.
 * scratch: VTTS_FR_SCRATCH uint32 values. Returns the count. */
#define VTTS_FR_MAXW 512 /* letters of one word read (a longer word is cut) */
#define VTTS_FR_SCRATCH (8 * VTTS_FR_MAXW)
int vtts_fr_word_ids(const uint32_t *w, int n, uint32_t *scratch, uint8_t *out, int cap);

#endif
