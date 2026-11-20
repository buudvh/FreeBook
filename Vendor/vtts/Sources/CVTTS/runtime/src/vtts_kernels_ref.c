/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_kernels_ref.c -- portable reference kernels (weak so a port can override). */
#include "vtts_port.h"

__attribute__((weak)) int32_t vtts_dot_s8s8(const int8_t *a, const int8_t *b, int n) {
    int32_t s = 0;
    for (int i = 0; i < n; i++) s += (int32_t)a[i] * (int32_t)b[i];
    return s;
}

__attribute__((weak)) void vtts_dots_s8s8(const int8_t *w, const int8_t *x, int stride, int n, int len,
                                          int32_t *out) {
    for (int t = 0; t < n; t++) out[t] = vtts_dot_s8s8(w, x + (long)t * stride, len);
}

__attribute__((weak)) void vtts_par_run(vtts_par_fn fn, int n, void *ctx) { fn(0, n, ctx); }
