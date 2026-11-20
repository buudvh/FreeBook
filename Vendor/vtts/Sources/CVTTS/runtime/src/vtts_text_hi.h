/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_hi.h -- Hindi pieces of the device front-end (internal). */
#ifndef VTTS_TEXT_HI_H
#define VTTS_TEXT_HI_H

#include <stdint.h>

/* Devanagari code point (g2p_hi.is_devanagari: U+0900..U+097F, U+A8E0..U+A8FF). */
int vtts_hi_is_devanagari(uint32_t cp);

/* g2p_hi.is_devanagari_word: a Devanagari character other than the danda, double danda and the
 * Devanagari digits. */
int vtts_hi_has_devanagari(const uint32_t *w, int n);

/* normalize_hi.LATIN_WORDS (units and currency words read in Hindi with their number: km, GB, Rs). */
int vtts_hi_latin_word(const uint32_t *w, int n);

/* Token ids (set hi-en) of one Devanagari word like word_tokens_hi: NFC, overrides.tsv (whole word),
 * then the letter, nasal and schwa-deletion rules. chars (chars_cap code points) and segs (segs_cap)
 * are scratch; a word longer than the scratch is cut. Returns the number of ids (at most cap). */
int vtts_hi_word_ids(const uint32_t *w, int n, uint32_t *chars, int chars_cap, uint32_t *segs, int segs_cap,
                     uint8_t *out, int cap);

/* Hindi normalization of n code points, like normalize_hi(): Devanagari words, lower-case Latin words
 * (read by the English module) and the marks , . ? ! ; : separated by single spaces. a and b
 * (cap code points each) hold the passes; ea and eb (ecap each) and eout are scratch (the first pass
 * and the English normalizer). Returns the length of the result (*out), or < 0 when a buffer is too
 * small. Only ASCII and Devanagari digits count as digits. */
int vtts_hi_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, uint32_t *ea, uint32_t *eb,
                      int ecap, char *eout, int eout_cap, const uint32_t **out);

#endif
