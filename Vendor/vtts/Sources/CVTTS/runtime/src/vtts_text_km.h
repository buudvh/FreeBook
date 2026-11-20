/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_km.h -- Khmer pieces of the device front-end (internal; VTTS_ENABLE_KM). */
#ifndef VTTS_TEXT_KM_H
#define VTTS_TEXT_KM_H

#include <stddef.h>
#include <stdint.h>

/* is_khmer: Khmer letters and signs U+1780..U+17D3, ៗ, ៝ (lang._has_khmer, normalize_km's class). */
int vtts_km_is_khmer(uint32_t cp);
int vtts_km_has_khmer(const uint32_t *w, int n);

/* Khmer normalization of n code points, like normalize_km() (buffers as vtts_th_normalize). */
int vtts_km_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, uint32_t *ea,
                      uint32_t *eb, int ecap, char *eout, int eout_cap, const uint32_t **out);

/* Token ids (set km-en) of each syllable of one normalized Khmer word (UTF-8, Khmer letters), like
 * g2p_km.khmer_syllable_tokens: cb is called once per syllable that has ids. scratch must hold
 * VTTS_KM_SCRATCH bytes. A word is read in pieces of at most VTTS_KM_MAX_RUN code points. Returns
 * the number of syllables, or < 0 on bad arguments. */
#define VTTS_KM_MAX_RUN 1024
#define VTTS_KM_SCRATCH 49152 /* about 47 KB: the DP, clusters and syllables of 1,024 letters */
typedef void (*vtts_km_syl_cb)(void *user, const uint8_t *ids, int n);
int vtts_km_read(const char *utf8, void *scratch, size_t size, vtts_km_syl_cb cb, void *user);

#endif
