/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_my.h -- Burmese pieces of the device front-end (internal; VTTS_ENABLE_MY). */
#ifndef VTTS_TEXT_MY_H
#define VTTS_TEXT_MY_H

#include <stddef.h>
#include <stdint.h>

/* normalize_my's class (U+1000..U+103F, ၌ ၍ ၎ ၏) and lang._has_burmese (U+1000..U+109F without the
 * digits and ၊ ။, so Zawgyi text is Burmese too). */
int vtts_my_is_burmese(uint32_t cp);
int vtts_my_has_burmese(const uint32_t *w, int n);

/* Burmese normalization of n code points, like normalize_my() (Zawgyi converted, canonical order;
 * buffers as vtts_th_normalize). */
int vtts_my_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, uint32_t *ea,
                      uint32_t *eb, int ecap, char *eout, int eout_cap, const uint32_t **out);

/* Token ids (set my-en) of each syllable of one normalized Burmese word (UTF-8), like
 * g2p_my.burmese_syllable_tokens: cb is called once per syllable. scratch must hold VTTS_MY_SCRATCH
 * bytes. A word is read in pieces of at most VTTS_MY_MAX_RUN code points. Returns the number of
 * syllables, or < 0 on bad arguments. */
#define VTTS_MY_MAX_RUN 1536
#define VTTS_MY_SCRATCH ((VTTS_MY_MAX_RUN * 3 + 8) * 8)
typedef void (*vtts_my_syl_cb)(void *user, const uint8_t *ids, int n);
int vtts_my_read(const char *utf8, void *scratch, size_t size, vtts_my_syl_cb cb, void *user);

#endif
