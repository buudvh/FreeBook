/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_th.h -- Thai pieces of the device front-end (internal). */
#ifndef VTTS_TEXT_TH_H
#define VTTS_TEXT_TH_H

#include <stddef.h>
#include <stdint.h>

/* Thai letters and signs U+0E01..U+0E4E (the [ก-๎] class of lang.py and normalize_th.py). */
int vtts_th_is_thai(uint32_t cp);

/* lang._has_thai: any Thai letter or sign. */
int vtts_th_has_thai(const uint32_t *w, int n);

/* Thai normalization of n code points, like normalize_th(): runs of Thai letters, lower-case Latin
 * words (read by the English module) and the marks , . ? ! ; : separated by single spaces. Buffers
 * as for vtts_zh_normalize (vtts_text_zh.h). Returns the length of the result (*out), or < 0 when a
 * buffer is too small. Only ASCII and Thai digits count as digits. */
int vtts_th_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, uint32_t *ea,
                      uint32_t *eb, int ecap, char *eout, int eout_cap, const uint32_t **out);

/* Token ids (set th-en) of each syllable of one normalized Thai word (UTF-8, all letters
 * U+0E01..U+0E4E), like g2p_th.thai_syllable_tokens: cb is called once per syllable with its
 * 3..5 ids. sa (>= 20 KB) and sb (>= 16 KB) are scratch. A word is read in pieces of at most
 * VTTS_TH_MAX_RUN letters (a whole Thai clause; longer ones are cut there). Returns the number
 * of syllables, or < 0 on bad arguments. */
#define VTTS_TH_MAX_RUN 1024
typedef void (*vtts_th_syl_cb)(void *user, const uint8_t *ids, int n);
int vtts_th_read(const char *utf8, void *sa, size_t na, void *sb, size_t nb, vtts_th_syl_cb cb, void *user);

#endif
