/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_lex.h -- English lexicon (CMUdict) and letter-to-sound rules from a VLEX blob.
 *
 * The blob is built by scripts/frontend/build_lexicon.py (format: src/vtts/frontend/en/vlex.py,
 * docs/model-format.md). It is read in place: keep it alive while the reader is used. No malloc.
 */
#ifndef VTTS_LEX_H
#define VTTS_LEX_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VTTS_LEX_MAX_LABELS 256

typedef struct {
    const uint8_t *blob;
    size_t size;
    uint32_t n_words, n_blocks, lts_off, lts_n, lab_off;
    uint16_t block, n_labels;
    const uint8_t *blocks;               /* first block */
    uint32_t lab[VTTS_LEX_MAX_LABELS];   /* offset of each label entry */
} vtts_lex;

/* 0 on success, < 0 if the blob is not a valid VLEX v1. */
int vtts_lex_init(vtts_lex *lx, const uint8_t *blob, size_t size);

/* Token ids (set v2) of a lower-case word from the lexicon. Returns the number of ids, 0 if the
 * word is not in the lexicon, or < 0 if cap is too small. */
int vtts_lex_lookup(const vtts_lex *lx, const char *word, uint8_t *out, int cap);

/* Token ids from the letter-to-sound rules (letters a-z of the word, any case; other characters
 * are ignored), with exactly one primary stress. Returns the number of ids or < 0 if cap is too
 * small. */
int vtts_lex_predict(const vtts_lex *lx, const char *word, uint8_t *out, int cap);

#ifdef __cplusplus
}
#endif
#endif
