#!/usr/bin/env python3
"""Thêm hàm C `audiocpp_set_log_file(path)` vào C API của audio.cpp — để app bật bộ đếm giờ có sẵn.

Vì sao: audio.cpp đo sẵn thời gian từng phần (nạp prompt, bước backbone, bộ giải mã âm học, codec…) qua
`engine::debug::timing_log_scalar`, nhưng chỉ ghi khi `engine::debug::configure_logging` được bật — mà C API v0.9.4
không có lối nào gọi nó (chỉ CLI / server có cờ `--log-file`). Hàm mới chỉ gọi đúng hàm đó; không đổi phép tính nào.

- `path` khác rỗng ⇒ bật log, ghi NỐI vào file `path` (toàn tiến trình). Gọi lại với path khác ⇒ đóng file cũ.
- `path` NULL / rỗng ⇒ tắt log, đóng file.
- Mở file lỗi ⇒ trả status lỗi (`audiocpp_last_error()` có chi tiết), log vẫn tắt.
Symbol tự được xuất: danh sách `src/capi/audiocpp.symbols` là `_audiocpp_*`.

Sửa bằng mốc chuỗi cố định; mốc nào không khớp đúng một lần ⇒ dừng với lỗi (thà build đỏ còn hơn vá lệch).
Dùng: python3 capi_log_file.py <thư mục nguồn audio.cpp>
"""
import pathlib
import sys

MARK = "FREEBOOK_PATCH_LOG_FILE"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        sys.exit(f"[capi_log_file] mốc '{label}' khớp {count} lần (cần đúng 1) — audio.cpp đã đổi, phải xem lại bản vá")
    return text.replace(old, new, 1)


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    if len(sys.argv) != 2:
        sys.exit("Dùng: capi_log_file.py <thư mục nguồn audio.cpp>")
    root = pathlib.Path(sys.argv[1])

    header_path = root / "include/audiocpp.h"
    header = header_path.read_text(encoding="utf-8")
    if MARK in header:
        print("[capi_log_file] đã vá từ trước, bỏ qua")
        return
    header = replace_once(
        header,
        "AUDIOCPP_API const char * audiocpp_status_string(audiocpp_status status);\n",
        "AUDIOCPP_API const char * audiocpp_status_string(audiocpp_status status);\n"
        "\n"
        "/* " + MARK + ": turn audio.cpp's own debug log (incl. the [TIMING ...] lines of its built-in stage\n"
        " * timers) on, appending to `path`; NULL or \"\" turns it off and closes the file. Process-wide. */\n"
        "AUDIOCPP_API audiocpp_status audiocpp_set_log_file(const char * path);\n",
        "khai báo audiocpp_status_string",
    )

    source_path = root / "src/capi/audiocpp.cpp"
    source = source_path.read_text(encoding="utf-8")
    source = replace_once(
        source,
        '#include "engine/framework/runtime/session.h"\n',
        '#include "engine/framework/runtime/session.h"\n'
        '#include "engine/framework/debug/trace.h"  // ' + MARK + '\n',
        "include runtime/session.h",
    )
    source = replace_once(
        source,
        '    return "unknown status";\n}\n',
        '    return "unknown status";\n}\n'
        "\n"
        "// " + MARK + "\n"
        "audiocpp_status audiocpp_set_log_file(const char * path) {\n"
        "    return guard([&]() {\n"
        "        const bool enabled = path != nullptr && path[0] != '\\0';\n"
        "        engine::debug::configure_logging(engine::debug::LoggingConfig{\n"
        "            enabled,\n"
        "            enabled ? std::optional<std::string>(path) : std::nullopt,\n"
        "        });\n"
        "        return AUDIOCPP_OK;\n"
        "    });\n"
        "}\n",
        "cuối audiocpp_status_string",
    )

    header_path.write_text(header, encoding="utf-8")
    source_path.write_text(source, encoding="utf-8")
    print("[capi_log_file] đã vá include/audiocpp.h + src/capi/audiocpp.cpp")


if __name__ == "__main__":
    main()
