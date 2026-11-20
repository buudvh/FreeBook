/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_de.h -- German front-end of the device (internal): token set de-en. Mirrors
 * src/vtts/frontend/de/ (normalize_de, split_sentences_de, g2p_de) and latin.py for mode "de".
 * All tables are in the generated vtts_text_de_tables.h; no blob is needed. Compiled only when
 * VTTS_ENABLE_DE is non-zero (default 1; the firmware enables it only for de-en models). */
#ifndef VTTS_TEXT_DE_H
#define VTTS_TEXT_DE_H

#include <stdint.h>

#include "vtts_langs.h" /* VTTS_ENABLE_DE */

/* lang.word_lang for a chunk core in mode "de": 1 German, 0 English, -1 neutral (read in German). */
int vtts_de_word_lang(const uint32_t *w, int n);

/* normalize_de of n code points (see vtts_lt_normalize: a and b are scratch buffers of cap code
 * points; *out points at the result). Returns its length or < 0 when a buffer is too small. */
int vtts_de_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, const uint32_t **out);

/* word_tokens_de of one normalized word: de-en ids, at most cap. scratch: VTTS_DE_SCRATCH bytes
 * (aligned for int). A word longer than VTTS_DE_MAXW letters is cut. Returns the count. */
#define VTTS_DE_MAXW 64
#define VTTS_DE_SCRATCH 24576
int vtts_de_word_ids(const uint32_t *w, int n, void *scratch, uint8_t *out, int cap);

/* split_sentences_de over t[0..z) (already stripped by the caller is not required): call
 * repeatedly with *st zeroed first; each call sets the next sentence [*s, *e) and returns 1, or
 * returns 0 when there is none left. */
typedef struct { int start, scan, done, init; } vtts_de_split;
int vtts_de_next_sentence(const uint32_t *t, int z, vtts_de_split *st, int *s, int *e);

#endif
