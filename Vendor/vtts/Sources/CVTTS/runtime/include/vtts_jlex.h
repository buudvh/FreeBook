/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_jlex.h -- Japanese reading tables (words, context tables, kanji defaults) and the NFKC data of
 * the Japanese normalizer, from a JLEX blob.
 *
 * The blob is built by scripts/frontend/build_ja_blob.py (format in its docstring) from the tables of
 * the Python front-end (src/vtts/frontend/lexicons/ja). It is read in place: keep it alive while the
 * reader is used (flash is fine). No malloc.
 */
#ifndef VTTS_JLEX_H
#define VTTS_JLEX_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum { VTTS_JLEX_WORDS = 0, VTTS_JLEX_AFTER_KANJI, VTTS_JLEX_AFTER_KATAKANA, VTTS_JLEX_KANJI, VTTS_JLEX_N_TABLES };

typedef struct {
    uint32_t n, n_blocks, data_size;
    const uint8_t *index, *data;
} vtts_jlex_table;

typedef struct {
    const uint8_t *blob;
    size_t size;
    uint32_t max_len, block; /* longest word key (code points); entries per block */
    vtts_jlex_table t[VTTS_JLEX_N_TABLES];
    uint32_t n_dec, dec_data_size, n_ccc, n_comp;
    const uint8_t *dec, *dec_data, *ccc, *comp;
} vtts_jlex;

/* 0 on success, < 0 if the blob is not a valid JLEX v1. */
int vtts_jlex_init(vtts_jlex *j, const uint8_t *blob, size_t size);

/* Reading of an exact key (UTF-8, key_len bytes) in one table: its length in bytes (katakana code
 * points - 0x30A0) with *reading pointing into the blob, or -1 when the key is absent. */
int vtts_jlex_find(const vtts_jlex *j, int table, const uint8_t *key, int key_len, const uint8_t **reading);

/* unicodedata.normalize("NFKC") of n code points into out (cap code points); in and out must not
 * overlap. Returns the output length, or < 0 when out is too small. */
int vtts_jlex_nfkc(const vtts_jlex *j, const uint32_t *in, int n, uint32_t *out, int cap);

#ifdef __cplusplus
}
#endif
#endif
