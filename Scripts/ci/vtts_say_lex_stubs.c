/* Stub cho `vtts_say` khi dựng với ĐÚNG cờ tắt ngôn ngữ của gói SPM (`check_vtts_assets.sh`).
 *
 * `vtts_say.c` (upstream) luôn gọi `vtts_zlex_init` / `vtts_jlex_init` / `vtts_rlex_init`, nhưng ba hàm này chỉ được
 * định nghĩa trong `#if VTTS_ENABLE_ZH / _JA / _RU` (`vtts_text_zh.c`, `vtts_text_ja.c`, `vtts_text_ru.c`). Tắt ba ngôn ngữ
 * đó thì link hỏng (`Undefined symbols`). App không gọi các hàm này (shim `vtts_bridge` chỉ dùng VLEX tiếng Anh), nên
 * stub chỉ link vào `vtts_say` của CI: trả lỗi, `vtts_say` coi như không có bảng tiếng Trung / Nhật / Nga.
 */
#include <stddef.h>
#include <stdint.h>

#include "vtts_jlex.h"
#include "vtts_rlex.h"
#include "vtts_zlex.h"

int vtts_zlex_init(vtts_zlex *z, const uint8_t *blob, size_t size) {
    (void)z;
    (void)blob;
    (void)size;
    return -1;
}

int vtts_jlex_init(vtts_jlex *j, const uint8_t *blob, size_t size) {
    (void)j;
    (void)blob;
    (void)size;
    return -1;
}

int vtts_rlex_init(vtts_rlex *r, const uint8_t *blob, size_t size) {
    (void)r;
    (void)blob;
    (void)size;
    return -1;
}
