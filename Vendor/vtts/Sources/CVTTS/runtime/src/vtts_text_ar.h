/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_ar.h -- Arabic pieces of the device front-end (internal). Compiled only when
 * VTTS_ENABLE_AR is 1 (vtts_langs.h; the default for host builds). */
#ifndef VTTS_TEXT_AR_H
#define VTTS_TEXT_AR_H

#include <stdint.h>

/* g2p_ar.is_arabic_word: an Arabic letter (Unicode category Lo in the Arabic blocks). */
int vtts_ar_has_arabic(const uint32_t *w, int n);

/* normalize_ar.LATIN_WORDS (units and currency words read in Arabic with their number: km, GB, USD). */
int vtts_ar_latin_word(const uint32_t *w, int n);

/* Token ids (set ar-en) of one normalized Arabic word like word_tokens_ar: the spelling table, the
 * word's own vowel marks, the word table with clitics and endings, the word patterns or the default
 * reading, then the pausal reading and stress. sa and sb (VTTS_AR_SCRATCH code points each) are
 * scratch; a word of more than VTTS_AR_MAXW code points is cut there. Returns the number of ids
 * (at most cap). */
#define VTTS_AR_MAXW 480
#define VTTS_AR_SCRATCH 6144
int vtts_ar_word_ids(const uint32_t *w, int n, uint32_t *sa, uint32_t *sb, uint8_t *out, int cap);

/* Arabic normalization of n code points, like normalize_ar(): Arabic words (the words it writes
 * carry their vowel marks), lower-case Latin words (read by the English module) and the marks
 * , . ? ! ; : separated by single spaces. Buffers as for vtts_hi_normalize (vtts_text_hi.h).
 * Returns the length of the result (*out), or < 0 when a buffer is too small. Only ASCII,
 * Arabic-Indic and Eastern Arabic digits count as digits. */
int vtts_ar_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, uint32_t *ea, uint32_t *eb,
                      int ecap, char *eout, int eout_cap, const uint32_t **out);

#endif
