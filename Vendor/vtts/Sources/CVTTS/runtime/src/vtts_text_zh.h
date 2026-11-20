/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_zh.h -- Mandarin pieces of the device front-end (internal). */
#ifndef VTTS_TEXT_ZH_H
#define VTTS_TEXT_ZH_H

#include <stdint.h>

#include "vtts_zlex.h"

/* CJK Unified Ideographs U+4E00..U+9FFF (g2p_zh.is_han). */
int vtts_zh_is_han(uint32_t cp);

/* Mandarin normalization of n code points, like normalize_zh(): Han runs, lower-case Latin words
 * (read by the English module) and the marks , . ? ! ; : separated by single spaces. The result
 * (code points, no NUL) is left in a or b; *out points at it. a and b are scratch buffers of cap
 * code points each; ea, eb (ecap each) and eout (eout_cap bytes) are the scratch of the English
 * normalizer for Latin words. in may alias ea/eb (it is copied into a first). Returns the length
 * of the result, or < 0 when a buffer is too small. Only ASCII digits count as digits. */
int vtts_zh_normalize(const uint32_t *in, int n, uint32_t *a, uint32_t *b, int cap, uint32_t *ea,
                      uint32_t *eb, int ecap, char *eout, int eout_cap, const uint32_t **out);

#endif
