/* SPDX-License-Identifier: Apache-2.0 */
/* vtts.h -- tiny Vietnamese TTS runtime (C99, no malloc).
 *
 * Pipeline: phoneme ids -> durations -> latent [latent, frames] -> PCM (22.05 kHz).
 * The model file format is described in docs/model-format.md. All working
 * memory comes from a caller-provided arena sized with vtts_arena_bytes().
 */
#ifndef VTTS_H
#define VTTS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VTTS_MAX_TENSORS 256
#define VTTS_MAX_DIMS 64

enum {
    VTTS_OK = 0,
    VTTS_ERR_ARGS = -1,
    VTTS_ERR_FORMAT = -2,
    VTTS_ERR_MISSING = -3,
    VTTS_ERR_ARENA = -4,
    VTTS_ERR_RANGE = -5
};

/* Silence between the text front-end's chunks (sentences) in a rendered utterance: the teacher,
 * the Python renderers, tools/vtts_say and the firmware all join chunks with it (none after the last). */
#define VTTS_CHUNK_GAP_MS 150

enum { VTTS_DEC_HIFIGAN = 0, VTTS_DEC_ISTFT = 1, VTTS_DEC_VOCOS = 2 };

/* Token set a model was trained with (dim `token_set`, docs/model-format.md). Files without the
 * dim map by vocab: 65 -> V1, 107 -> VI_EN, 171 -> ZH_EN, 153 -> KO_EN, 144 -> JA_EN, 138 -> ES_EN,
 * 141 -> ID_EN, 150 -> PT_EN, 162 -> TH_EN, 157 -> HI_EN, any other vocab > 65 -> VI_EN and <= 65 -> V1
 * (the rule the firmware used before the dim existed). Sets added after the dim (FR_EN on) are known
 * only by their recorded code. */
typedef enum {
    VTTS_TOKSET_UNKNOWN = 0, /* a code newer than this runtime: only raw ids can be used */
    VTTS_TOKSET_V1 = 1,      /* Vietnamese, 65 ids */
    VTTS_TOKSET_VI_EN = 2,   /* "vi-en" (v2), 107 ids */
    VTTS_TOKSET_ZH_EN = 3,   /* "zh-en", 171 ids */
    VTTS_TOKSET_KO_EN = 4,   /* "ko-en", 153 ids */
    VTTS_TOKSET_JA_EN = 5,   /* "ja-en", 144 ids */
    VTTS_TOKSET_ES_EN = 6,   /* "es-en", 138 ids */
    VTTS_TOKSET_ID_EN = 7,   /* "id-en", 141 ids */
    VTTS_TOKSET_PT_EN = 8,   /* "pt-en", 150 ids */
    VTTS_TOKSET_TH_EN = 9,   /* "th-en", 162 ids */
    VTTS_TOKSET_HI_EN = 10,  /* "hi-en", 157 ids */
    VTTS_TOKSET_FR_EN = 11,  /* "fr-en", 143 ids */
    VTTS_TOKSET_DE_EN = 12,  /* "de-en", 167 ids */
    VTTS_TOKSET_IT_EN = 13,  /* "it-en", 142 ids (14: unused) */
    VTTS_TOKSET_TR_EN = 15,  /* "tr-en", 146 ids */
    VTTS_TOKSET_RU_EN = 16,  /* "ru-en", 154 ids */
    VTTS_TOKSET_PL_EN = 17,  /* "pl-en", 151 ids (18: unused) */
    VTTS_TOKSET_AR_EN = 19,  /* "ar-en", 149 ids (20: unused) */
    VTTS_TOKSET_NL_EN = 21,  /* "nl-en", 159 ids */
    VTTS_TOKSET_DA_EN = 22,  /* "da-en", 158 ids */
    VTTS_TOKSET_SV_EN = 23,  /* "sv-en", 155 ids */
    VTTS_TOKSET_NO_EN = 24,  /* "no-en", 156 ids */
    VTTS_TOKSET_FI_EN = 25,  /* "fi-en", 142 ids */
    VTTS_TOKSET_EL_EN = 26,  /* "el-en", 139 ids (27 reserved) */
    VTTS_TOKSET_MS_EN = 28,  /* "ms-en", 145 ids */
    VTTS_TOKSET_TL_EN = 29,  /* "tl-en", 139 ids */
    VTTS_TOKSET_MY_EN = 30,  /* "my-en", 160 ids */
    VTTS_TOKSET_KM_EN = 31,  /* "km-en", 176 ids */
    VTTS_TOKSET_LO_EN = 32,  /* "lo-en", 163 ids */
    VTTS_TOKSET_SW_EN = 33   /* "sw-en", 147 ids */
} vtts_token_set_t;

typedef struct {
    const char *name; /* points into the model blob (NUL padded field) */
    int dtype;        /* 0 = f32, 1 = i8 */
    int ndim;
    int32_t shape[4];
    const void *data;
    const float *scale; /* i8 only: per-out-channel scales */
} vtts_tensor;

typedef struct {
    /* dims */
    int vocab, latent, hop, sample_rate, max_duration;
    int d_hidden, d_depth, d_kernel;
    int a_hidden, a_token_depth, a_frame_depth, a_kernel;
    int decoder, c0, n_up, up[4], upk[4], n_res, res_d[4], res_kernel;
    int n_fft, istft_hop, v_dim, v_blocks, v_mult;
    int prosody, p_depth, expr_milli; /* prosody branch (v2) and its default expressiveness x1000 */
    int token_set;                   /* vtts_token_set_t, resolved by vtts_init (dim or vocab) */
    int token_set_in_file;           /* 1 when the file has the token_set dim */
    int text_mode;                   /* dim text_mode: the device text mode to start in, up to 4 ASCII
                                      * chars packed little-endian ("en" = 0x6e65); 0 = the token set's
                                      * first mode (vtts_text_model_lang in vtts_text.h) */
    float expressiveness;            /* scales the predicted log-F0 deviation; 1 = as trained */
    /* tensors */
    int n_tensors;
    vtts_tensor t[VTTS_MAX_TENSORS];
} vtts_model;

/* Parse a model blob (must stay alive while the model is used). */
int vtts_init(vtts_model *m, const void *blob, size_t blob_bytes);

/* Arena bytes needed for n_ids tokens and up to max_frames total frames. */
size_t vtts_arena_bytes(const vtts_model *m, int n_ids, long max_frames);

/* ids -> integer frame counts in [1, max_duration]; returns total frames (>0) or error (<0).
 * log_dur_out may be NULL. */
long vtts_durations(const vtts_model *m, const int32_t *ids, int n_ids, float length_scale,
                    int32_t *dur_out, float *log_dur_out, void *arena, size_t arena_bytes);

/* ids + durations -> latent [latent, frames] (channel-major). Returns frames or error. */
long vtts_latent(const vtts_model *m, const int32_t *ids, const int32_t *dur, int n_ids,
                 float *latent_out, void *arena, size_t arena_bytes);

/* latent [latent, frames] -> pcm[frames * hop] in [-1, 1]. Returns samples or error. */
long vtts_decode(const vtts_model *m, const float *latent, long frames, float *pcm_out,
                 void *arena, size_t arena_bytes);

/* Convenience: ids -> pcm. pcm_out must hold vtts_durations(...) * hop samples. */
long vtts_synthesize(const vtts_model *m, const int32_t *ids, int n_ids, float length_scale,
                     float *pcm_out, long pcm_capacity, void *arena, size_t arena_bytes);

/* Streaming synthesis (vocos decoder only): PCM is produced chunk by chunk through `cb`
 * (return non-zero from cb to abort). Output equals vtts_synthesize() exactly; working
 * memory depends on chunk_frames, not on utterance length. Returns total samples or error
 * (VTTS_ERR_ARGS for decoders that do not support streaming). */
typedef int (*vtts_pcm_cb)(const float *pcm, long n, void *user);
size_t vtts_stream_arena_bytes(const vtts_model *m, int n_ids, int chunk_frames);
long vtts_synthesize_stream(const vtts_model *m, const int32_t *ids, int n_ids, float length_scale,
                            int chunk_frames, vtts_pcm_cb cb, void *user, void *arena,
                            size_t arena_bytes);

/* Same, with a small first chunk for low time-to-first-audio; later chunks double in size up to
 * chunk_frames (first_chunk <= chunk_frames);
 * vtts_stream_arena_bytes(m, n_ids, chunk_frames) covers it. */
long vtts_synthesize_stream_ex(const vtts_model *m, const int32_t *ids, int n_ids, float length_scale,
                               int first_chunk, int chunk_frames, vtts_pcm_cb cb, void *user,
                               void *arena, size_t arena_bytes);

/* Optional: n bytes of fast memory (e.g. internal SRAM) for the most reused streaming buffers.
 * Buffers that do not fit stay in the arena; the arena size from vtts_stream_arena_bytes is
 * unchanged. The memory must stay valid while synthesizing; pass NULL to stop using it. */
void vtts_set_fast_scratch(void *p, size_t n);

/* Optional: n bytes of internal RAM where the int8 layers stage their outputs (a block of frames
 * at a time) before the calling core copies them to the arena; results are unchanged. Used on the
 * ESP32-S3, where two cores storing to PSRAM while streaming weights from it now and then lost a
 * value (vtts_synth.c). While it is set, only these int8 layers use two cores (vtts_par_run); the
 * other parallel passes, which also store to the arena, run on the calling core. NULL stops it. */
void vtts_set_out_stage(void *p, size_t n);

/* Prosody models only: scale the predicted pitch movement (1.0 = as trained, >1 livelier). */
void vtts_set_expressiveness(vtts_model *m, float e);

/* Token set of a loaded model (vtts_token_set_t); see the enum for files without the dim. */
int vtts_token_set(const vtts_model *m);

/* "v1", "vi-en", ... (the names of the codes above) or "unknown". */
const char *vtts_token_set_name(int token_set);

/* Number of ids of a token set (0 for VTTS_TOKSET_UNKNOWN). */
int vtts_token_set_size(int token_set);

/* Tensor lookup by name (NULL when missing). */
const vtts_tensor *vtts_find(const vtts_model *m, const char *name);

#ifdef __cplusplus
}
#endif
#endif
