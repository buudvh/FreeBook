/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_ko.h -- Korean pieces of the device front-end (internal). */
#ifndef VTTS_TEXT_KO_H
#define VTTS_TEXT_KO_H

#include <stdint.h>

/* Precomposed Hangul syllable U+AC00..U+D7A3 (hangul.is_hangul_syllable, [가-힣]). */
int vtts_ko_is_syllable(uint32_t cp);

/* lang._has_hangul: a Hangul syllable or a compatibility jamo (U+3131..U+318E). */
int vtts_ko_has_hangul(const uint32_t *w, int n);

/* Surface syllables of one word like g2p_ko.pronounce: overrides.tsv (forward longest match), then
 * the pronunciation rules over each run of Hangul syllables (other characters are skipped and
 * split the word). tmp (tmp_cap code points) is scratch for the override pass; syl receives 3 bytes
 * per syllable (onset code, vowel index, coda code; codes are compatibility jamo - 0x3130, onset
 * 23 = silent ㅇ, coda 0 = none), at most syl_cap syllables. Returns the syllable count or < 0. */
int vtts_ko_pronounce(const uint32_t *w, int n, uint32_t *tmp, int tmp_cap, uint8_t *syl, int syl_cap);

/* Token ids (set ko-en) of one surface syllable ([KO:I:onset] KO:V:vowel [KO:C:coda]): 1..3. */
int vtts_ko_syllable_ids(const uint8_t *syl, uint8_t *out);

/* Korean normalization of n code points, like normalize_ko(): Hangul words, lower-case Latin words
 * (read by the English module) and the marks , . ? ! ; : separated by single spaces. Buffers as for
 * vtts_zh_normalize (vtts_text_zh.h). Returns the length of the result (*out), or < 0 when a buffer
 * is too small. Only ASCII digits count as digits. */
int vtts_ko_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, uint32_t *ea,
                      uint32_t *eb, int ecap, char *eout, int eout_cap, const uint32_t **out);

#endif
