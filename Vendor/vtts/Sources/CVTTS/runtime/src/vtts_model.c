/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_model.c -- parse a VTTS model blob (format version 1) (docs/model-format.md). */
#include <string.h>

#include "vtts.h"

#define HEADER_BYTES 20
#define DIM_BYTES 36
#define ROW_BYTES 80

static uint32_t rd_u32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static int32_t rd_i32(const uint8_t *p) { return (int32_t)rd_u32(p); }

static int field_eq(const uint8_t *field, size_t width, const char *s) {
    size_t n = strlen(s);
    if (n >= width) return 0;
    return memcmp(field, s, n) == 0 && field[n] == 0;
}

typedef struct {
    const char *key;
    size_t off;
    int required;
} dim_spec;

#define D(name, req) {#name, offsetof(vtts_model, name), req}

static const dim_spec DIMS[] = {
    D(vocab, 1), D(latent, 1), D(hop, 1), D(sample_rate, 1), D(max_duration, 1),
    D(d_hidden, 1), D(d_depth, 1), D(d_kernel, 1), D(a_hidden, 1), D(a_token_depth, 1),
    D(a_frame_depth, 1), D(a_kernel, 1), D(decoder, 1), D(c0, 0), D(n_up, 0), D(n_res, 0),
    D(res_kernel, 0), D(n_fft, 0), D(istft_hop, 0), D(v_dim, 0), D(v_blocks, 0), D(v_mult, 0),
    D(prosody, 0), D(p_depth, 0), D(expr_milli, 0), D(token_set, 0),
    D(text_mode, 0),
};

static int set_indexed(vtts_model *m, const uint8_t *key, int32_t v) {
    static const struct { const char *prefix; size_t off; } arr[] = {
        {"upk", offsetof(vtts_model, upk)}, {"up", offsetof(vtts_model, up)},
        {"res_d", offsetof(vtts_model, res_d)}};
    for (size_t a = 0; a < sizeof(arr) / sizeof(arr[0]); a++) {
        size_t n = strlen(arr[a].prefix);
        if (memcmp(key, arr[a].prefix, n) == 0 && key[n] >= '0' && key[n] <= '3' && key[n + 1] == 0) {
            int *base = (int *)((char *)m + arr[a].off);
            base[key[n] - '0'] = v;
            return 1;
        }
    }
    return 0;
}

/* indexed by code; codes without a row (reserved or unused) are unknown here: {NULL, 0} */
static const struct { const char *name; int size; } TOKEN_SETS[] = {
    [VTTS_TOKSET_UNKNOWN] = {"unknown", 0},
    [VTTS_TOKSET_V1] = {"v1", 65},        [VTTS_TOKSET_VI_EN] = {"vi-en", 107}, [VTTS_TOKSET_ZH_EN] = {"zh-en", 171},
    [VTTS_TOKSET_KO_EN] = {"ko-en", 153}, [VTTS_TOKSET_JA_EN] = {"ja-en", 144}, [VTTS_TOKSET_ES_EN] = {"es-en", 138},
    [VTTS_TOKSET_ID_EN] = {"id-en", 141}, [VTTS_TOKSET_PT_EN] = {"pt-en", 150}, [VTTS_TOKSET_TH_EN] = {"th-en", 162},
    [VTTS_TOKSET_HI_EN] = {"hi-en", 157},
    [VTTS_TOKSET_FR_EN] = {"fr-en", 143}, [VTTS_TOKSET_DE_EN] = {"de-en", 167}, [VTTS_TOKSET_IT_EN] = {"it-en", 142},
    [VTTS_TOKSET_TR_EN] = {"tr-en", 146}, [VTTS_TOKSET_RU_EN] = {"ru-en", 154}, [VTTS_TOKSET_PL_EN] = {"pl-en", 151},
    [VTTS_TOKSET_AR_EN] = {"ar-en", 149}, [VTTS_TOKSET_NL_EN] = {"nl-en", 159}, [VTTS_TOKSET_SV_EN] = {"sv-en", 155},
    [VTTS_TOKSET_NO_EN] = {"no-en", 156}, [VTTS_TOKSET_FI_EN] = {"fi-en", 142}, [VTTS_TOKSET_EL_EN] = {"el-en", 139},
    [VTTS_TOKSET_MS_EN] = {"ms-en", 145}, [VTTS_TOKSET_TL_EN] = {"tl-en", 139}, [VTTS_TOKSET_SW_EN] = {"sw-en", 147},
    [VTTS_TOKSET_DA_EN] = {"da-en", 158}, [VTTS_TOKSET_LO_EN] = {"lo-en", 163}, [VTTS_TOKSET_MY_EN] = {"my-en", 160},
    [VTTS_TOKSET_KM_EN] = {"km-en", 176},
};
#define N_TOKEN_SETS ((int)(sizeof(TOKEN_SETS) / sizeof(TOKEN_SETS[0])))
/* files written before the dim existed hold one of the sets up to hi-en: only those are inferred from
 * the vocab (their sizes are distinct); every later set needs its recorded code (sizes collide) */
#define LAST_LEGACY_TOKEN_SET VTTS_TOKSET_HI_EN

/* dim token_set present (non-zero): a known code must fit the embedding; a code newer than this
 * runtime loads as UNKNOWN. Absent (or 0): by vocab, as the firmware did before the dim. */
static int resolve_token_set(vtts_model *m) {
    int code = m->token_set;
    m->token_set_in_file = code != 0;
    if (code > 0 && code < N_TOKEN_SETS && TOKEN_SETS[code].size) /* a known code (size 0: unknown here) */
        return m->vocab >= TOKEN_SETS[code].size ? VTTS_OK : VTTS_ERR_FORMAT;
    if (code != 0) { m->token_set = VTTS_TOKSET_UNKNOWN; return VTTS_OK; }
    m->token_set = m->vocab > 65 ? VTTS_TOKSET_VI_EN : VTTS_TOKSET_V1;
    for (int k = 1; k <= LAST_LEGACY_TOKEN_SET; k++)
        if (m->vocab == TOKEN_SETS[k].size) m->token_set = k;
    return VTTS_OK;
}

int vtts_token_set(const vtts_model *m) { return m ? m->token_set : VTTS_TOKSET_UNKNOWN; }

const char *vtts_token_set_name(int ts) {
    const char *name = TOKEN_SETS[ts > 0 && ts < N_TOKEN_SETS ? ts : 0].name;
    return name ? name : "unknown";
}

int vtts_token_set_size(int ts) { return TOKEN_SETS[ts > 0 && ts < N_TOKEN_SETS ? ts : 0].size; }

int vtts_init(vtts_model *m, const void *blob, size_t size) {
    const uint8_t *b = (const uint8_t *)blob;
    if (!m || !b || size < HEADER_BYTES) return VTTS_ERR_ARGS;
    memset(m, 0, sizeof(*m));
    if (memcmp(b, "VTTS", 4) != 0 || rd_u32(b + 4) != 1) return VTTS_ERR_FORMAT;
    uint32_t n_dims = rd_u32(b + 8), n_tensors = rd_u32(b + 12);
    if (n_dims > VTTS_MAX_DIMS || n_tensors > VTTS_MAX_TENSORS) return VTTS_ERR_FORMAT;
    size_t table_end = HEADER_BYTES + (size_t)n_dims * DIM_BYTES + (size_t)n_tensors * ROW_BYTES;
    if (table_end > size) return VTTS_ERR_FORMAT;

    int seen[sizeof(DIMS) / sizeof(DIMS[0])] = {0};
    for (uint32_t i = 0; i < n_dims; i++) {
        const uint8_t *row = b + HEADER_BYTES + i * DIM_BYTES;
        int32_t v = rd_i32(row + 32);
        int matched = 0;
        for (size_t k = 0; k < sizeof(DIMS) / sizeof(DIMS[0]); k++) {
            if (field_eq(row, 32, DIMS[k].key)) {
                *(int *)((char *)m + DIMS[k].off) = v;
                seen[k] = matched = 1;
            }
        }
        if (!matched) set_indexed(m, row, v);
    }
    for (size_t k = 0; k < sizeof(DIMS) / sizeof(DIMS[0]); k++)
        if (DIMS[k].required && !seen[k]) return VTTS_ERR_MISSING;
    if (m->n_up < 0 || m->n_up > 4 || m->n_res < 0 || m->n_res > 4) return VTTS_ERR_FORMAT;

    const uint8_t *rows = b + HEADER_BYTES + (size_t)n_dims * DIM_BYTES;
    for (uint32_t i = 0; i < n_tensors; i++) {
        const uint8_t *r = rows + (size_t)i * ROW_BYTES;
        vtts_tensor *t = &m->t[i];
        if (r[47] != 0) return VTTS_ERR_FORMAT; /* name must be NUL terminated */
        t->name = (const char *)r;
        t->dtype = r[48];
        t->ndim = r[49];
        if (t->dtype > 1 || t->ndim < 1 || t->ndim > 4) return VTTS_ERR_FORMAT;
        size_t elems = 1;
        for (int d = 0; d < 4; d++) {
            t->shape[d] = rd_i32(r + 52 + 4 * d);
            if (t->shape[d] < 1) return VTTS_ERR_FORMAT;
            elems *= (size_t)t->shape[d];
        }
        uint32_t off = rd_u32(r + 68), nbytes = rd_u32(r + 72), soff = rd_u32(r + 76);
        size_t esz = t->dtype == 0 ? 4 : 1;
        if (nbytes != elems * esz || off < table_end || (size_t)off + nbytes > size || off % 4)
            return VTTS_ERR_FORMAT;
        t->data = b + off;
        if (t->dtype == 1) {
            size_t sbytes = (size_t)t->shape[0] * 4;
            if (soff < table_end || (size_t)soff + sbytes > size || soff % 4) return VTTS_ERR_FORMAT;
            t->scale = (const float *)(b + soff);
        }
    }
    m->n_tensors = (int)n_tensors;
    if (resolve_token_set(m) != VTTS_OK) return VTTS_ERR_FORMAT;
    m->expressiveness = m->expr_milli > 0 ? (float)m->expr_milli / 1000.0f : 1.0f;
    if (m->prosody && (m->p_depth < 0 || m->p_depth > 8)) return VTTS_ERR_FORMAT;
    return VTTS_OK;
}

void vtts_set_expressiveness(vtts_model *m, float e) {
    if (m && e > 0.0f && e < 4.0f) m->expressiveness = e;
}

const vtts_tensor *vtts_find(const vtts_model *m, const char *name) {
    for (int i = 0; i < m->n_tensors; i++)
        if (strncmp(m->t[i].name, name, 48) == 0) return &m->t[i];
    return NULL;
}
