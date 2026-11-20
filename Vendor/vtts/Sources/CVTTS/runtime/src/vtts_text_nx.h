/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_nx.h -- Dutch, Swedish and Norwegian front-ends of the device (internal): token sets
 * nl-en, sv-en and no-en. Mirrors src/vtts/frontend/scan_norm.py (the shared scanner normalizer and
 * sentence split), latin.py (tagging), nl/ (g2p_nl.py), scand_g2p.py with sv/ and no/. All tables are
 * in the generated vtts_text_nx_tables.h; no blob is needed. Each language is compiled only when its
 * VTTS_ENABLE_<L> is non-zero (default 1; the firmware enables only the languages of its models). */
#ifndef VTTS_TEXT_NX_H
#define VTTS_TEXT_NX_H

#include <stdint.h>

#include "vtts_langs.h" /* VTTS_ENABLE_NL, _SV, _NO, VTTS_ENABLE_NX */

enum { VTTS_NX_NL = 0, VTTS_NX_SV = 1, VTTS_NX_NO = 2 };

/* 1 when the language is compiled in */
int vtts_nx_enabled(int lang);

/* lang.word_lang for a chunk core in the language's mode: 1 the language, 0 English, -1 neutral. */
int vtts_nx_word_lang(int lang, const uint32_t *w, int n);

/* scan_norm.normalize with the language's Spec over n code points: UTF-8 words and marks separated
 * by single spaces into out (cap bytes, NUL terminated). Returns the length, or < 0 when out is too
 * small (the result is then cut at a word boundary). */
int vtts_nx_normalize(int lang, const uint32_t *in, int n, char *out, int cap);

/* word_tokens_<lang> of one normalized word (n code points): token ids of the pair's set, at most
 * cap. scratch: VTTS_NX_SCRATCH bytes, aligned for int. A word longer than VTTS_NX_MAXW letters is
 * cut. Returns the count. */
#define VTTS_NX_MAXW 256
#define VTTS_NX_SCRATCH 24576
int vtts_nx_word_ids(int lang, const uint32_t *w, int n, void *scratch, uint8_t *out, int cap);

/* scan_norm.split_sentences over t[0..z): call repeatedly with *st zeroed first; each call sets the
 * next sentence [*s, *e) and returns 1, or returns 0 when there is none left. */
typedef struct { int start, i, end, init; } vtts_nx_split;
int vtts_nx_next_sentence(int lang, const uint32_t *t, int z, vtts_nx_split *st, int *s, int *e);

#endif
