/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_port.h -- the few kernels a port may accelerate (SIMD), with portable defaults. */
#ifndef VTTS_PORT_H
#define VTTS_PORT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* sum_i a[i] * b[i] over n elements with int32 accumulation (|a|, |b| <= 127).
 * Callers pass 16-byte aligned pointers and n % 16 == 0 whenever they can, which SIMD ports
 * may rely on for their fast path (and fall back to scalar code otherwise). */
int32_t vtts_dot_s8s8(const int8_t *a, const int8_t *b, int n);

/* out[t] = vtts_dot_s8s8(w, x + t * stride, len) for t in [0, n): one weight row against n
 * activation rows, so a port can keep the per-call overhead out of the inner loop. */
void vtts_dots_s8s8(const int8_t *w, const int8_t *x, int stride, int n, int len, int32_t *out);

/* Run fn over [0, n), possibly split across cores: fn(lo, hi, ctx) for disjoint ranges that
 * together cover [0, n). The default runs fn(0, n, ctx) on the calling core. */
typedef void (*vtts_par_fn)(int lo, int hi, void *ctx);
void vtts_par_run(vtts_par_fn fn, int n, void *ctx);

#ifdef __cplusplus
}
#endif
#endif
