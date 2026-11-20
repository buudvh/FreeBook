/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_zlex.h -- Mandarin reading tables (per-character defaults, polyphone phrases) from a ZLEX blob.
 *
 * The blob is built by scripts/frontend/build_zh_blob.py (format in its docstring) from the tables
 * of the Python front-end (src/vtts/frontend/lexicons/zh). It is read in place: keep it alive while
 * the reader is used (flash is fine). No malloc.
 */
#ifndef VTTS_ZLEX_H
#define VTTS_ZLEX_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    const uint8_t *blob;
    size_t size;
    uint32_t n_syl, n_chars, n_phr[3]; /* phrases of 2, 3 and 4 characters */
    const uint8_t *syl, *chars, *phr[3];
} vtts_zlex;

/* 0 on success, < 0 if the blob is not a valid ZLEX v1. */
int vtts_zlex_init(vtts_zlex *z, const uint8_t *blob, size_t size);

/* Token ids (set zh-en) of one Han word read like g2p_zh.read_han (forward maximum matching over
 * the phrases, else per-character defaults; unreadable characters are skipped). word is UTF-8.
 * Each syllable is one call of cb with its ids ([ZI:initial] ZF:final ZTtone). Returns the number
 * of syllables. */
typedef void (*vtts_zh_unit_cb)(void *user, const uint8_t *ids, int n);
int vtts_zh_read_han(const vtts_zlex *z, const char *word, vtts_zh_unit_cb cb, void *user);

#ifdef __cplusplus
}
#endif
#endif
