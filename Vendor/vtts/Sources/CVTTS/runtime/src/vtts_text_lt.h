/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_lt.h -- Latin-script pair languages of the device front-end (internal): Spanish
 * (es-en), Indonesian (id-en) and Brazilian Portuguese (pt-en). Mirrors src/vtts/frontend/es/,
 * id/, pt/, latin.py and latin_norm.py. All tables are in the generated vtts_text_tables.h. */
#ifndef VTTS_TEXT_LT_H
#define VTTS_TEXT_LT_H

#include <stdint.h>

enum { VTTS_LT_ES = 0, VTTS_LT_ID = 1, VTTS_LT_PT = 2 };

/* Malay (ms-en): the Indonesian code paths with the Malay tables (vtts_text_ms_tables.h); compiled
 * only with VTTS_ENABLE_MS (default 1; the firmware enables it for ms-en models). */
#include "vtts_langs.h" /* VTTS_ENABLE_MS */
enum { VTTS_LT_MS = 3 }; /* lang of vtts_lt_* (the functions below also take it) */

/* Python re classes of str patterns: \w, \d (value 0..9, or -1), \s (str.isspace), str.lower()
 * of one code point (U+0130 lowers to two code points; this returns the first, 'i'). */
int vtts_u_word(uint32_t c);
int vtts_u_digit(uint32_t c);
int vtts_u_space(uint32_t c);
uint32_t vtts_u_lower(uint32_t c);

/* lang.word_lang for a chunk core in the pair mode of `lang` (VTTS_LT_*):
 * 1: the pair language, 0: English, -1: neutral (read in the pair language). */
int vtts_lt_word_lang(int lang, const uint32_t *w, int n);

/* the lower-case ASCII word is in lexicons/latin/english.txt (shared by the Latin-script pairs) */
int vtts_lt_english_word(const char *low);

/* normalize_es / normalize_id / normalize_pt of n code points: lower-case words and the marks
 * , . ? ! ; : separated by single spaces. a and b are scratch buffers of cap code points each (the
 * result is left in one of them, *out points at it). Returns the length of the result or < 0 when
 * a buffer is too small. */
int vtts_lt_normalize(int lang, const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, const uint32_t **out);

/* word_tokens_es / _id / _pt of one normalized word (n code points): token ids of the pair's set,
 * at most cap (a longer result is cut). scratch: VTTS_LT_SCRATCH uint32 values. Returns the count. */
#define VTTS_LT_MAXW 512 /* letters of one word read (a longer word is cut) */
#define VTTS_LT_SCRATCH (7 * VTTS_LT_MAXW)
int vtts_lt_word_ids(int lang, const uint32_t *w, int n, uint32_t *scratch, uint8_t *out, int cap);


#endif
