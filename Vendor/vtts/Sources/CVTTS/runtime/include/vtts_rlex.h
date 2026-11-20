/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_rlex.h -- Russian stress tables (hand-written overrides, word forms, word endings) from an
 * RLEX blob.
 *
 * The blob is built by scripts/frontend/build_ru_blob.py (format in its docstring) from the tables of
 * the Python front-end (src/vtts/frontend/lexicons/ru). It is read in place: keep it alive while the
 * reader is used (flash is fine). No malloc.
 */
#ifndef VTTS_RLEX_H
#define VTTS_RLEX_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum { VTTS_RLEX_OVERRIDES = 0, VTTS_RLEX_WORDS, VTTS_RLEX_SUFFIXES, VTTS_RLEX_N_TABLES };

typedef struct {
    uint32_t n, n_blocks, data_size;
    const uint8_t *index, *data;
} vtts_rlex_table;

typedef struct {
    const uint8_t *blob;
    size_t size;
    uint32_t block, root, max_suffix; /* entries per block; stress of a word no ending matches; longest ending */
    vtts_rlex_table t[VTTS_RLEX_N_TABLES];
} vtts_rlex;

/* 0 on success, < 0 if the blob is not a valid RLEX v1. */
int vtts_rlex_init(vtts_rlex *r, const uint8_t *blob, size_t size);

/* Value of an exact key (letter codes: а..я = 1..32, ё = 33) in one table: its length in bytes with
 * *value pointing into the blob, or -1 when the key is absent. */
int vtts_rlex_find(const vtts_rlex *r, int table, const uint8_t *key, int key_len, const uint8_t **value);

#ifdef __cplusplus
}
#endif
#endif
