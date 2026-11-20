/* vtts_bridge.c — cầu nối C của FreeBook tới runtime vtts. Hợp đồng, luật luồng, mã lỗi: xem `include/vtts_bridge.h`.
 *
 * Runtime vtts không malloc (viết cho vi điều khiển): người gọi cấp workspace front-end + arena tổng hợp. Ở đây mọi thứ
 * cấp trên heap; model và VLEX được mmap (chỉ đọc, trang sạch theo file ⇒ iOS tự nhả khi thiếu RAM, nạp lại khi cần) và
 * file descriptor đóng ngay sau mmap. */
#include "vtts_bridge.h"

#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include "vtts.h"
#include "vtts_lex.h"
#include "vtts_text.h"

/* Số code point tối đa đưa cho front-end mỗi lượt. `utf8_decode` của vtts dừng IM LẶNG ở VTTS_TEXT_MAX_CP (4096) —
 * phần sau bị bỏ, không báo lỗi — nên đoạn dài được cắt trước: ưu tiên ngay sau dấu kết câu, rồi khoảng trắng, cuối
 * cùng là ranh giới code point. Giữa hai phần vẫn là 150 ms im lặng như giữa hai chunk. */
#ifndef VTTS_BRIDGE_SEGMENT_CP
#define VTTS_BRIDGE_SEGMENT_CP 2000
#endif
#if VTTS_BRIDGE_SEGMENT_CP < 1 || VTTS_BRIDGE_SEGMENT_CP >= VTTS_TEXT_MAX_CP
#error "VTTS_BRIDGE_SEGMENT_CP phải trong [1, VTTS_TEXT_MAX_CP) — front-end bỏ im lặng phần vượt VTTS_TEXT_MAX_CP"
#endif

typedef struct {
    void *base;
    size_t size;
} mapped_file;

struct vtts_bridge {
    mapped_file model_file; /* vtts_init giữ con trỏ vào blob ⇒ phải sống suốt đời handle */
    mapped_file lex_file;   /* vtts_lex đọc blob tại chỗ ⇒ cũng vậy */
    vtts_model *model;      /* ~12 KB (256 tensor) */
    vtts_lex *lex;
    vtts_text_ws *ws; /* ~145 KB, không re-entrant */
    vtts_text_opts opts;
    int32_t *dur; /* số khung từng id của một chunk */
    int dur_cap;
    int last_chunks;
    int last_vtts_error;
};

struct vtts_bridge_cancel {
    int flag;
};

/* Trạng thái của một lượt tổng hợp (callback `on_ids` gọi một lần mỗi chunk ≤ 40 âm tiết). */
typedef struct {
    vtts_bridge *bridge;
    float length_scale;
    vtts_bridge_cancel *cancel;
    float *pcm;
    long n, cap;
    void *arena;
    size_t arena_cap;
    int err;
    int chunks;
} synth_run;

static int map_file(const char *path, mapped_file *out) {
    struct stat st;
    void *p;
    int fd;
    out->base = NULL;
    out->size = 0;
    fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    if (fstat(fd, &st) != 0 || st.st_size <= 0) {
        close(fd);
        return -1;
    }
    p = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (p == MAP_FAILED) return -1;
    out->base = p;
    out->size = (size_t)st.st_size;
    return 0;
}

static void unmap_file(mapped_file *f) {
    if (f->base) munmap(f->base, f->size);
    f->base = NULL;
    f->size = 0;
}

vtts_bridge *vtts_bridge_create(const char *model_path, const char *lex_path, int *error_out) {
    int err = VTTS_BRIDGE_OK;
    int rc, token_set;
    vtts_lang lang = VTTS_LANG_AUTO;
    vtts_bridge *b = NULL;

    if (!model_path || !lex_path) {
        err = VTTS_BRIDGE_ERR_ARGS;
        goto fail;
    }
    b = calloc(1, sizeof *b);
    if (!b) {
        err = VTTS_BRIDGE_ERR_NO_MEMORY;
        goto fail;
    }
    b->model = calloc(1, sizeof *b->model);
    b->lex = calloc(1, sizeof *b->lex);
    b->ws = calloc(1, sizeof *b->ws);
    b->dur_cap = VTTS_TEXT_MAX_IDS;
    b->dur = calloc((size_t)b->dur_cap, sizeof *b->dur);
    if (!b->model || !b->lex || !b->ws || !b->dur) {
        err = VTTS_BRIDGE_ERR_NO_MEMORY;
        goto fail;
    }

    if (map_file(model_path, &b->model_file) != 0) {
        err = VTTS_BRIDGE_ERR_MODEL_IO;
        goto fail;
    }
    rc = vtts_init(b->model, b->model_file.base, b->model_file.size);
    if (rc != VTTS_OK) {
        err = VTTS_BRIDGE_ERR_MODEL_FORMAT;
        goto fail;
    }
    /* Giọng Việt–Anh dùng bộ token vi-en (107 id) và chế độ "auto" (chọn ngôn ngữ theo từng từ). Model khác (bản chỉ
     * tiếng Việt v1, hay bộ token mới hơn runtime) bị từ chối ở đây với mã riêng thay vì đọc sai. */
    token_set = vtts_token_set(b->model);
    if (token_set != VTTS_TOKSET_VI_EN) {
        err = VTTS_BRIDGE_ERR_TOKEN_SET;
        goto fail;
    }
    if (vtts_text_lang_for(token_set, "auto", &lang) != 0 || lang != VTTS_LANG_AUTO) {
        err = VTTS_BRIDGE_ERR_NO_AUTO_MODE;
        goto fail;
    }

    if (map_file(lex_path, &b->lex_file) != 0) {
        err = VTTS_BRIDGE_ERR_LEX_IO;
        goto fail;
    }
    if (vtts_lex_init(b->lex, (const uint8_t *)b->lex_file.base, b->lex_file.size) != 0) {
        err = VTTS_BRIDGE_ERR_LEX_FORMAT;
        goto fail;
    }

    b->opts.lang = lang;
    b->opts.lex = b->lex;
    b->opts.zh = NULL;
    b->opts.ja = NULL;
    b->opts.ru = NULL;
    if (error_out) *error_out = VTTS_BRIDGE_OK;
    return b;

fail:
    if (error_out) *error_out = err;
    vtts_bridge_destroy(b);
    return NULL;
}

void vtts_bridge_destroy(vtts_bridge *bridge) {
    if (!bridge) return;
    unmap_file(&bridge->lex_file);
    unmap_file(&bridge->model_file);
    free(bridge->dur);
    free(bridge->ws);
    free(bridge->lex);
    free(bridge->model);
    free(bridge);
}

int vtts_bridge_sample_rate(const vtts_bridge *bridge) {
    return bridge ? bridge->model->sample_rate : 0;
}

static int cancel_requested(const vtts_bridge_cancel *cancel) {
    return cancel != NULL && __atomic_load_n(&cancel->flag, __ATOMIC_ACQUIRE) != 0;
}

/* Arena chỉ cần lớn dần trong một lượt (nội dung cũ không cần giữ) ⇒ free + malloc thay vì realloc. */
static int ensure_arena(synth_run *r, size_t bytes) {
    if (bytes <= r->arena_cap) return 0;
    free(r->arena);
    r->arena = malloc(bytes);
    r->arena_cap = r->arena ? bytes : 0;
    return r->arena ? 0 : -1;
}

static int ensure_pcm(synth_run *r, long want) {
    long cap;
    float *p;
    if (want <= r->cap) return 0;
    cap = r->cap > 0 ? r->cap : 65536;
    while (cap < want) cap *= 2;
    p = realloc(r->pcm, sizeof(float) * (size_t)cap);
    if (!p) return -1;
    r->pcm = p;
    r->cap = cap;
    return 0;
}

static int ensure_dur(vtts_bridge *b, int n) {
    int32_t *p;
    if (n <= b->dur_cap) return 0;
    p = realloc(b->dur, sizeof(int32_t) * (size_t)n);
    if (!p) return -1;
    b->dur = p;
    b->dur_cap = n;
    return 0;
}

/* Một chunk (BOS … EOS) → PCM nối vào cuối, trước nó VTTS_CHUNK_GAP_MS im lặng nếu đã có tiếng (như tools/vtts_say.c và
 * firmware). Khác vtts_say ở cách cấp bộ nhớ: vtts_say cấp arena + PCM theo n × max_duration khung (hàng chục MB với 320
 * id); ở đây lấy số khung thật bằng vtts_durations trước rồi mới cấp đúng cỡ — vtts_synthesize tính lại thời lượng
 * bằng cùng hàm nên ra đúng số khung đó. */
static int on_ids(const int32_t *ids, int n, void *user) {
    synth_run *r = user;
    vtts_bridge *b = r->bridge;
    const vtts_model *m = b->model;
    size_t need;
    long frames, samples, gap, produced;
    int i;

    if (cancel_requested(r->cancel)) {
        r->err = VTTS_BRIDGE_ERR_CANCELLED;
        return 1;
    }
    if (n < 1) return 0;
    for (i = 0; i < n; i++) {
        if (ids[i] < 0 || ids[i] >= m->vocab) { /* bảng embedding chỉ có `vocab` hàng: đừng đọc lố */
            r->err = VTTS_BRIDGE_ERR_BAD_IDS;
            return 1;
        }
    }
    if (ensure_dur(b, n) != 0) {
        r->err = VTTS_BRIDGE_ERR_NO_MEMORY;
        return 1;
    }

    need = vtts_arena_bytes(m, n, 1); /* ≥ phần việc tính thời lượng */
    if (need == 0 || ensure_arena(r, need) != 0) {
        r->err = VTTS_BRIDGE_ERR_NO_MEMORY;
        return 1;
    }
    frames = vtts_durations(m, ids, n, r->length_scale, b->dur, NULL, r->arena, r->arena_cap);
    if (frames <= 0) {
        b->last_vtts_error = frames < 0 ? (int)frames : VTTS_ERR_RANGE;
        r->err = VTTS_BRIDGE_ERR_SYNTH;
        return 1;
    }

    need = vtts_arena_bytes(m, n, frames);
    if (need == 0 || ensure_arena(r, need) != 0) {
        r->err = VTTS_BRIDGE_ERR_NO_MEMORY;
        return 1;
    }
    samples = frames * (long)m->hop;
    gap = r->n > 0 ? (long)VTTS_CHUNK_GAP_MS * m->sample_rate / 1000 : 0;
    if (ensure_pcm(r, r->n + gap + samples) != 0) {
        r->err = VTTS_BRIDGE_ERR_NO_MEMORY;
        return 1;
    }
    if (gap > 0) memset(r->pcm + r->n, 0, sizeof(float) * (size_t)gap);
    produced = vtts_synthesize(m, ids, n, r->length_scale, r->pcm + r->n + gap, samples, r->arena, r->arena_cap);
    if (produced < 0) {
        b->last_vtts_error = (int)produced;
        r->err = VTTS_BRIDGE_ERR_SYNTH;
        return 1;
    }
    r->n += gap + produced;
    r->chunks++;
    return 0;
}

static int is_space_byte(char c) {
    return c == ' ' || c == '\n' || c == '\r' || c == '\t' || c == '\f' || c == '\v';
}

/* Câu kết bằng . ! ? ; đứng trước khoảng trắng — cùng luật tách câu của front-end (vtts_text_to_ids_ex). */
static int is_sentence_end_byte(char c) {
    return c == '.' || c == '!' || c == '?' || c == ';';
}

static size_t utf8_lead_length(unsigned char c) {
    if (c < 0x80) return 1;
    if ((c >> 5) == 6) return 2;
    if ((c >> 4) == 14) return 3;
    if ((c >> 3) == 30) return 4;
    return 1; /* byte lạc: front-end tự bỏ qua */
}

/* Vị trí byte (sau `start`) nơi phần kế tiếp kết thúc, để mỗi phần ≤ VTTS_BRIDGE_SEGMENT_CP code point. */
static size_t next_segment_end(const char *s, size_t start, size_t len) {
    size_t i = start, count = 0, after_sentence = 0, after_space = 0;
    while (i < len && count < (size_t)VTTS_BRIDGE_SEGMENT_CP) {
        size_t step = utf8_lead_length((unsigned char)s[i]);
        if (is_space_byte(s[i])) {
            after_space = i + 1;
            if (s[i] == '\n' || (i > start && is_sentence_end_byte(s[i - 1]))) after_sentence = i + 1;
        }
        if (i + step > len) step = len - i;
        i += step;
        count++;
    }
    if (i >= len) return len;
    if (after_sentence > start) return after_sentence;
    if (after_space > start) return after_space;
    return i;
}

int vtts_bridge_synthesize(vtts_bridge *bridge, const char *utf8, float length_scale, float **out, long *n_out) {
    return vtts_bridge_synthesize_cancellable(bridge, utf8, length_scale, NULL, out, n_out);
}

int vtts_bridge_synthesize_cancellable(vtts_bridge *bridge, const char *utf8, float length_scale,
                                       vtts_bridge_cancel *cancel, float **out, long *n_out) {
    synth_run r;
    size_t len, start = 0, seg_cap = 0;
    char *seg = NULL;
    int status = VTTS_BRIDGE_OK;

    if (out) *out = NULL;
    if (n_out) *n_out = 0;
    if (!bridge || !utf8 || !out || !n_out || !(length_scale > 0.0f)) return VTTS_BRIDGE_ERR_ARGS;
    bridge->last_chunks = 0;
    bridge->last_vtts_error = 0;

    memset(&r, 0, sizeof r);
    r.bridge = bridge;
    r.length_scale = length_scale;
    r.cancel = cancel;

    len = strlen(utf8);
    while (start < len && status == VTTS_BRIDGE_OK) {
        size_t end = next_segment_end(utf8, start, len);
        const char *text = utf8 + start;
        int rc;
        if (end < len) { /* phần giữa: chép ra bộ đệm có NUL */
            size_t bytes = end - start;
            if (bytes + 1 > seg_cap) {
                char *p = realloc(seg, bytes + 1);
                if (!p) {
                    status = VTTS_BRIDGE_ERR_NO_MEMORY;
                    break;
                }
                seg = p;
                seg_cap = bytes + 1;
            }
            memcpy(seg, utf8 + start, bytes);
            seg[bytes] = '\0';
            text = seg;
        }
        rc = vtts_text_to_ids_ex(text, bridge->ws, &bridge->opts, on_ids, &r);
        if (r.err != VTTS_BRIDGE_OK) {
            status = r.err;
        } else if (rc < 0) {
            bridge->last_vtts_error = rc;
            status = VTTS_BRIDGE_ERR_TEXT;
        }
        start = end;
    }

    free(seg);
    free(r.arena);
    bridge->last_chunks = r.chunks;
    if (status != VTTS_BRIDGE_OK || r.n == 0) {
        free(r.pcm);
        return status;
    }
    *out = r.pcm;
    *n_out = r.n;
    return VTTS_BRIDGE_OK;
}

void vtts_bridge_free_pcm(float *pcm) {
    free(pcm);
}

int vtts_bridge_last_chunk_count(const vtts_bridge *bridge) {
    return bridge ? bridge->last_chunks : 0;
}

int vtts_bridge_last_vtts_error(const vtts_bridge *bridge) {
    return bridge ? bridge->last_vtts_error : 0;
}

const char *vtts_bridge_token_set_name(const vtts_bridge *bridge) {
    return bridge ? vtts_token_set_name(vtts_token_set(bridge->model)) : "none";
}

const char *vtts_bridge_error_name(int code) {
    switch (code) {
    case VTTS_BRIDGE_OK: return "ok";
    case VTTS_BRIDGE_ERR_ARGS: return "args";
    case VTTS_BRIDGE_ERR_MODEL_IO: return "model_io";
    case VTTS_BRIDGE_ERR_MODEL_FORMAT: return "model_format";
    case VTTS_BRIDGE_ERR_TOKEN_SET: return "token_set";
    case VTTS_BRIDGE_ERR_NO_AUTO_MODE: return "no_auto_mode";
    case VTTS_BRIDGE_ERR_LEX_IO: return "lex_io";
    case VTTS_BRIDGE_ERR_LEX_FORMAT: return "lex_format";
    case VTTS_BRIDGE_ERR_NO_MEMORY: return "no_memory";
    case VTTS_BRIDGE_ERR_TEXT: return "text";
    case VTTS_BRIDGE_ERR_BAD_IDS: return "bad_ids";
    case VTTS_BRIDGE_ERR_SYNTH: return "synth";
    case VTTS_BRIDGE_ERR_CANCELLED: return "cancelled";
    default: return "unknown";
    }
}

vtts_bridge_cancel *vtts_bridge_cancel_create(void) {
    return calloc(1, sizeof(vtts_bridge_cancel));
}

void vtts_bridge_cancel_request(vtts_bridge_cancel *cancel) {
    if (cancel) __atomic_store_n(&cancel->flag, 1, __ATOMIC_RELEASE);
}

void vtts_bridge_cancel_destroy(vtts_bridge_cancel *cancel) {
    free(cancel);
}
