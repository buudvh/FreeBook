/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_say.c -- host tool: text -> token ids -> WAV, with the front-end chosen from the model's
 * token set the way the firmware does (vtts_token_set, vtts_text_model_lang / vtts_text_lang_for).
 * usage: vtts_say MODEL.vtts OUT.wav [--lex VLEX] [--zh ZLEX] [--ja JLEX] [--ru RLEX] [--lang MODE] [--speed X] TEXT
 * Chunks are joined with VTTS_CHUNK_GAP_MS of silence, and samples are rounded to int16 like the
 * firmware does, so a device `dump` of the same text can be compared sample by sample.
 * Prints "token_set <name> <header|vocab> mode <mode>" and one "ids ..." line per chunk on stdout. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "vtts.h"
#include "vtts_text.h"

static void *read_file(const char *path, size_t *n) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    *n = (size_t)ftell(f);
    fseek(f, 0, SEEK_SET);
    void *b = malloc(*n ? *n : 1);
    if (b && fread(b, 1, *n, f) != *n) { free(b); b = NULL; }
    fclose(f);
    return b;
}

typedef struct {
    const vtts_model *m;
    float speed;
    float *pcm;
    long n, cap;
    int max_id, err;
} out_t;

static int on_ids(const int32_t *ids, int n, void *user) {
    out_t *o = user;
    printf("ids");
    for (int i = 0; i < n; i++) {
        printf(" %d", ids[i]);
        if (ids[i] > o->max_id) o->max_id = ids[i];
    }
    printf("\n");
    long max_frames = (long)n * o->m->max_duration;
    size_t ab = vtts_arena_bytes(o->m, n, max_frames);
    void *arena = malloc(ab);
    long gap = o->n ? (long)VTTS_CHUNK_GAP_MS * o->m->sample_rate / 1000 : 0; /* between chunks, as on the device */
    long want = o->n + gap + max_frames * o->m->hop;
    if (want > o->cap) {
        float *p = realloc(o->pcm, sizeof(float) * (size_t)want);
        if (!p) { free(arena); o->err = VTTS_ERR_ARENA; return 1; }
        o->pcm = p;
        o->cap = want;
    }
    for (long i = 0; i < gap; i++) o->pcm[o->n++] = 0.0f;
    long s = arena ? vtts_synthesize(o->m, ids, n, o->speed, o->pcm + o->n, o->cap - o->n, arena, ab) : VTTS_ERR_ARENA;
    free(arena);
    if (s < 0) { o->err = (int)s; return 1; }
    o->n += s;
    return 0;
}

static void write_wav(const char *path, const float *pcm, long n, int sr) {
    FILE *f = fopen(path, "wb");
    if (!f) return;
    uint32_t data = (uint32_t)n * 2, riff = 36 + data, sr32 = (uint32_t)sr, br = sr32 * 2, fmt = 16;
    uint16_t tag = 1, ch = 1, align = 2, bits = 16;
    fwrite("RIFF", 1, 4, f); fwrite(&riff, 4, 1, f); fwrite("WAVEfmt ", 1, 8, f);
    fwrite(&fmt, 4, 1, f); fwrite(&tag, 2, 1, f); fwrite(&ch, 2, 1, f); fwrite(&sr32, 4, 1, f);
    fwrite(&br, 4, 1, f); fwrite(&align, 2, 1, f); fwrite(&bits, 2, 1, f);
    fwrite("data", 1, 4, f); fwrite(&data, 4, 1, f);
    for (long i = 0; i < n; i++) {
        float v = pcm[i] > 1.0f ? 1.0f : pcm[i] < -1.0f ? -1.0f : pcm[i];
        int16_t s = (int16_t)lrintf(v * 32767.0f); /* the firmware's int16 conversion */
        fwrite(&s, 2, 1, f);
    }
    fclose(f);
}

int main(int argc, char **argv) {
    const char *lex_path = NULL, *zh_path = NULL, *ja_path = NULL, *ru_path = NULL, *mode = NULL, *text = NULL;
    float speed = 1.0f;
    if (argc < 4) {
        fprintf(stderr, "usage: %s model.vtts out.wav [--lex VLEX] [--zh ZLEX] [--ja JLEX] [--ru RLEX] [--lang MODE] [--speed X] text\n", argv[0]);
        return 2;
    }
    for (int i = 3; i < argc; i++) {
        if (strcmp(argv[i], "--lex") == 0 && i + 1 < argc) lex_path = argv[++i];
        else if (strcmp(argv[i], "--zh") == 0 && i + 1 < argc) zh_path = argv[++i];
        else if (strcmp(argv[i], "--ja") == 0 && i + 1 < argc) ja_path = argv[++i];
        else if (strcmp(argv[i], "--ru") == 0 && i + 1 < argc) ru_path = argv[++i];
        else if (strcmp(argv[i], "--lang") == 0 && i + 1 < argc) mode = argv[++i];
        else if (strcmp(argv[i], "--speed") == 0 && i + 1 < argc) speed = (float)atof(argv[++i]);
        else text = argv[i];
    }
    size_t mb = 0, lb = 0, zb = 0, jb = 0, rb = 0;
    void *blob = read_file(argv[1], &mb), *lex_blob = NULL, *zh_blob = NULL, *ja_blob = NULL, *ru_blob = NULL;
    static vtts_model m;
    int rc = blob ? vtts_init(&m, blob, mb) : VTTS_ERR_ARGS;
    if (rc) { fprintf(stderr, "init failed %d\n", rc); return 1; }
    int ts = vtts_token_set(&m);
    vtts_lang lang;
    if (mode ? vtts_text_lang_for(ts, mode, &lang) : vtts_text_model_lang(ts, m.text_mode, &lang)) {
        fprintf(stderr, "token set %s: no text mode %s (modes: %s)\n", vtts_token_set_name(ts), mode ? mode : "",
                vtts_text_modes(ts));
        return 2;
    }
    static vtts_lex lex;
    static vtts_zlex zh;
    static vtts_jlex ja;
    static vtts_rlex ru;
    int has_lex = 0, has_zh = 0, has_ja = 0, has_ru = 0;
    if (lex_path && (lex_blob = read_file(lex_path, &lb))) has_lex = vtts_lex_init(&lex, lex_blob, lb) == 0;
    if (zh_path && (zh_blob = read_file(zh_path, &zb))) has_zh = vtts_zlex_init(&zh, zh_blob, zb) == 0;
    if (ja_path && (ja_blob = read_file(ja_path, &jb))) has_ja = vtts_jlex_init(&ja, ja_blob, jb) == 0;
    if (ru_path && (ru_blob = read_file(ru_path, &rb))) has_ru = vtts_rlex_init(&ru, ru_blob, rb) == 0;
    printf("token_set %s %s mode %s lex %d zh %d ja %d ru %d\n", vtts_token_set_name(ts),
           m.token_set_in_file ? "header" : "vocab", vtts_text_lang_name(lang), has_lex, has_zh, has_ja, has_ru);
    vtts_text_ws *ws = malloc(sizeof *ws);
    out_t o = {.m = &m, .speed = speed, .max_id = -1};
    vtts_text_opts opts = {.lang = lang, .lex = has_lex ? &lex : NULL, .zh = has_zh ? &zh : NULL,
                           .ja = has_ja ? &ja : NULL, .ru = has_ru ? &ru : NULL};
    int chunks = vtts_text_to_ids_ex(text ? text : "", ws, &opts, on_ids, &o);
    printf("chunks %d samples %ld max_id %d vocab %d\n", chunks, o.n, o.max_id, m.vocab);
    if (o.err) { fprintf(stderr, "synth failed %d\n", o.err); return 1; }
    write_wav(argv[2], o.pcm, o.n, m.sample_rate);
    free(o.pcm); free(ws); free(blob); free(lex_blob); free(zh_blob); free(ja_blob); free(ru_blob);
    return chunks > 0 ? 0 : 1;
}
