/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_lo.h -- Lao pieces of the device front-end (internal), token set lo-en. Mirrors
 * src/vtts/frontend/lo/ (normalize_lo.py, g2p_lo.py); tables in vtts_text_lo_tables.h, no blob.
 *
 * VTTS_ENABLE_LO (default 1): with 0 the Lao code and tables are not compiled and the mode lo is
 * unknown (vtts_text_lang_for fails, vtts_text_to_ids_ex returns -1). vtts_lo_is_lao stays
 * available (sentence splitting does not depend on the switch). */
#ifndef VTTS_TEXT_LO_H
#define VTTS_TEXT_LO_H

#include <stddef.h>
#include <stdint.h>

#include "vtts_langs.h" /* VTTS_ENABLE_LO */

/* Lao letters and signs U+0E81..U+0ECD and U+0EDC..U+0EDF (the LAO class of lang.py and
 * normalize_lo.py; not the Lao digits). */
int vtts_lo_is_lao(uint32_t cp);

/* lang._has_lao: any Lao letter or sign. */
int vtts_lo_has_lao(const uint32_t *w, int n);

/* Lao normalization of n code points, like normalize_lo(): runs of Lao letters, lower-case Latin
 * words (read by the English module) and the marks , . ? ! ; : separated by single spaces. Buffers
 * as for vtts_th_normalize. Returns the length of the result (*out), or < 0 when a buffer is too
 * small. */
int vtts_lo_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, uint32_t *ea,
                      uint32_t *eb, int ecap, char *eout, int eout_cap, const uint32_t **out);

/* Token ids (set lo-en) of each syllable of one normalized Lao word (UTF-8, Lao letters only), like
 * g2p_lo.lao_syllable_tokens: cb is called once per syllable with its 3..5 ids. sa (>= 24 KB) and
 * sb (>= 16 KB) are scratch. A word is read in pieces of at most VTTS_LO_MAX_RUN letters (a whole
 * clause; longer ones are cut there). Returns the number of syllables, or < 0 on bad arguments. */
#define VTTS_LO_MAX_RUN 1024
typedef void (*vtts_lo_syl_cb)(void *user, const uint8_t *ids, int n);
int vtts_lo_read(const char *utf8, void *sa, size_t na, void *sb, size_t nb, vtts_lo_syl_cb cb, void *user);

#endif
