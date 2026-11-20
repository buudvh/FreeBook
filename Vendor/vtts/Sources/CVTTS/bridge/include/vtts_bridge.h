/* vtts_bridge.h — cầu nối C của FreeBook tới runtime vtts (header công khai DUY NHẤT mà Swift `import CVTTS` thấy).
 *
 * Swift không thấy struct nào của vtts (`vtts_model` ~12 KB, `vtts_text_ws` ~145 KB sẽ thành tuple khổng lồ trên stack):
 * mọi thứ nằm sau handle mờ `vtts_bridge`.
 *
 * Luồng: `vtts_bridge_create` mmap model + từ điển VLEX (cả hai được runtime đọc TẠI CHỖ ⇒ giữ suốt đời handle) →
 * `vtts_bridge_synthesize` (chữ UTF-8 → `vtts_text_to_ids_ex` chế độ `VTTS_LANG_AUTO`, chọn Việt / Anh theo từng từ →
 * mỗi chunk ≤ 40 âm tiết tổng hợp riêng → nối, giữa hai chunk 150 ms im lặng như `tools/vtts_say.c`) → `vtts_bridge_free_pcm`
 * → `vtts_bridge_destroy`.
 *
 * KHÔNG an toàn đa luồng, kể cả giữa hai handle khác nhau: front-end của vtts dùng mảng `static` toàn cục
 * (`v2_sentence`) và runtime có setter toàn cục (`vtts_set_fast_scratch`, `vtts_set_out_stage`). Mọi lượt gọi phải đi qua
 * MỘT hàng đợi nối tiếp (phía Swift: `VttsRuntime`). Riêng `vtts_bridge_cancel_request` gọi được từ luồng bất kỳ.
 *
 * Mã trả về: `VTTS_BRIDGE_OK` (0) hoặc một mã lỗi DƯƠNG bên dưới (số nguyên trần để Swift nhập thành hằng `Int32`).
 */
#ifndef VTTS_BRIDGE_H
#define VTTS_BRIDGE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VTTS_BRIDGE_OK 0
#define VTTS_BRIDGE_ERR_ARGS 1         /* tham số NULL / sai */
#define VTTS_BRIDGE_ERR_MODEL_IO 2     /* không mở / mmap được file model */
#define VTTS_BRIDGE_ERR_MODEL_FORMAT 3 /* vtts_init từ chối file model (sai định dạng / runtime quá cũ) */
#define VTTS_BRIDGE_ERR_TOKEN_SET 4    /* model không phải bộ token vi-en */
#define VTTS_BRIDGE_ERR_NO_AUTO_MODE 5 /* bộ token không có chế độ "auto" (Việt + Anh theo từng từ) */
#define VTTS_BRIDGE_ERR_LEX_IO 6       /* không mở / mmap được file VLEX */
#define VTTS_BRIDGE_ERR_LEX_FORMAT 7   /* vtts_lex_init từ chối file VLEX */
#define VTTS_BRIDGE_ERR_NO_MEMORY 8    /* hết bộ nhớ */
#define VTTS_BRIDGE_ERR_TEXT 9         /* front-end chữ trả lỗi */
#define VTTS_BRIDGE_ERR_BAD_IDS 10     /* front-end sinh id ngoài từ vựng của model */
#define VTTS_BRIDGE_ERR_SYNTH 11       /* vtts_durations / vtts_synthesize trả lỗi (mã gốc: vtts_bridge_last_vtts_error) */
#define VTTS_BRIDGE_ERR_CANCELLED 12   /* lượt bị huỷ qua vtts_bridge_cancel_request */

typedef struct vtts_bridge vtts_bridge;
typedef struct vtts_bridge_cancel vtts_bridge_cancel;

/* Nạp một giọng. Lỗi ⇒ NULL và `*error_out` (có thể NULL) nhận mã lỗi. */
vtts_bridge *vtts_bridge_create(const char *model_path, const char *lex_path, int *error_out);

/* Nhả handle (munmap model + VLEX, giải phóng workspace). NULL được bỏ qua. */
void vtts_bridge_destroy(vtts_bridge *bridge);

/* Tần số lấy mẫu của model (22 050 Hz với các giọng vi-en). */
int vtts_bridge_sample_rate(const vtts_bridge *bridge);

/* Tổng hợp cả đoạn chữ UTF-8 thành PCM mono float [-1, 1]. `length_scale` = 1 là tốc độ gốc (> 1 chậm hơn).
 * Thành công ⇒ VTTS_BRIDGE_OK, `*out` (giải phóng bằng vtts_bridge_free_pcm) và `*n_out` số mẫu; đoạn không có gì để đọc
 * (chỉ dấu câu, rỗng) ⇒ VTTS_BRIDGE_OK với `*out == NULL`, `*n_out == 0`. Lỗi ⇒ mã lỗi, `*out == NULL`, `*n_out == 0`. */
int vtts_bridge_synthesize(vtts_bridge *bridge, const char *utf8, float length_scale, float **out, long *n_out);

/* Như trên, kèm thẻ huỷ (NULL = không huỷ được): thẻ được xét trước mỗi chunk ≤ 40 âm tiết. */
int vtts_bridge_synthesize_cancellable(vtts_bridge *bridge, const char *utf8, float length_scale,
                                       vtts_bridge_cancel *cancel, float **out, long *n_out);

void vtts_bridge_free_pcm(float *pcm);

/* Số chunk front-end của lượt tổng hợp gần nhất (để ghi log). */
int vtts_bridge_last_chunk_count(const vtts_bridge *bridge);

/* Mã lỗi gốc của vtts (âm, VTTS_ERR_*) của lượt gần nhất trả VTTS_BRIDGE_ERR_SYNTH / ERR_TEXT / ERR_MODEL_FORMAT; 0 nếu
 * không có. */
int vtts_bridge_last_vtts_error(const vtts_bridge *bridge);

/* Tên ngắn của bộ token model ("vi-en"…) — để ghi log. */
const char *vtts_bridge_token_set_name(const vtts_bridge *bridge);

/* Tên ngắn của mã lỗi (để ghi log). */
const char *vtts_bridge_error_name(int code);

/* Thẻ huỷ dùng cho MỘT lượt tổng hợp. `request` gọi được từ luồng bất kỳ (nguyên tử). */
vtts_bridge_cancel *vtts_bridge_cancel_create(void);
void vtts_bridge_cancel_request(vtts_bridge_cancel *cancel);
void vtts_bridge_cancel_destroy(vtts_bridge_cancel *cancel);

#ifdef __cplusplus
}
#endif
#endif
