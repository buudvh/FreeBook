/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_ja.h -- Japanese pieces of the device front-end (internal). */
#ifndef VTTS_TEXT_JA_H
#define VTTS_TEXT_JA_H

#include <stdint.h>

#include "vtts_jlex.h"

/* lang._script_class_ja: 1 kanji, kana, 々 〆 ー and half-width katakana; 2 Japanese and full-width
 * punctuation; 0 other. */
int vtts_ja_script_class(uint32_t cp);

/* g2p_ja.is_ja_char: kanji (U+4E00..U+9FFF, 〆), kana (with ー ゝ ゞ ヽ ヾ) or 々. */
int vtts_ja_is_ja_char(uint32_t cp);

/* Japanese normalization of n code points, like normalize_ja(): runs of Japanese characters,
 * lower-case Latin words (read by the English module) and the marks , . ? ! ; : separated by single
 * spaces. Buffers as for vtts_zh_normalize (vtts_text_zh.h). j may be NULL (NFKC is then skipped).
 * Returns the length of the result (*out), or < 0 when a buffer is too small. */
int vtts_ja_normalize(const vtts_jlex *j, const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, uint32_t *ea,
                      uint32_t *eb, int ecap, char *eout, int eout_cap, const uint32_t **out);

/* Units of one Japanese word (n code points, all vtts_ja_is_ja_char) like g2p_ja.ja_units: forward
 * longest match over the JLEX tables, kanji defaults, kana runs, kana -> phonemes, at most
 * VTTS_JA_MAX_UNIT_MORAE morae per unit. Each unit is one call of cb with its token ids (set ja-en).
 * off (n + 1 entries) and scratch (scratch_cap bytes, >= 5 * n + 64) are work buffers. Returns the
 * number of units, or < 0 when a buffer is too small. */
typedef void (*vtts_ja_unit_cb)(void *user, const uint8_t *ids, int n);
int vtts_ja_units(const vtts_jlex *j, const uint32_t *w, int n, uint32_t *off, uint8_t *scratch, int scratch_cap,
                  vtts_ja_unit_cb cb, void *user);

#endif
