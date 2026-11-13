#!/usr/bin/env python3
"""Thêm hàm C `audiocpp_set_abort_file(path)` — ghi câu báo lỗi của ggml ra file trước khi tiến trình dừng.

Vì sao (1.3.925): bật codec qua Accelerate (1.3.924) làm app chết trên iPhone mà log không có dòng nào. ggml dừng
tiến trình bằng `GGML_ASSERT` → `ggml_abort` → `abort()`, câu báo chỉ in ra stderr (trên máy không ai đọc). ggml có sẵn
`ggml_set_abort_callback`, nhưng dylib của app chỉ xuất `audiocpp_*` nên app không gọi thẳng được. Hàm mới:
- `path` khác rỗng ⇒ cài callback: nối câu báo của `ggml_abort` vào file `path` (mở / ghi / đóng ngay, rồi `abort()`
  như cũ), và cài `std::terminate` handler ghi câu của exception chưa bắt (thay handler in backtrace của ggml — trên iOS
  không ai đọc).
- `path` NULL / rỗng ⇒ gỡ callback (ggml quay về in stderr).
App đặt file một lần; lần mở sau đọc file, đưa vào log rồi xoá. Không bắt được lỗi truy cập bộ nhớ sai (cần file .ips).
Symbol tự được xuất (`src/capi/audiocpp.symbols` là `_audiocpp_*`).

Sửa bằng mốc chuỗi cố định; mốc nào không khớp đúng một lần ⇒ dừng với lỗi (thà build đỏ còn hơn vá lệch).
Dùng: python3 capi_abort_file.py <thư mục nguồn audio.cpp>
"""
import pathlib
import sys

MARK = "FREEBOOK_PATCH_ABORT_FILE"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        sys.exit(f"[capi_abort_file] mốc '{label}' khớp {count} lần (cần đúng 1) — audio.cpp đã đổi, phải xem lại bản vá")
    return text.replace(old, new, 1)


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    if len(sys.argv) != 2:
        sys.exit("Dùng: capi_abort_file.py <thư mục nguồn audio.cpp>")
    root = pathlib.Path(sys.argv[1])

    header_path = root / "include/audiocpp.h"
    header = header_path.read_text(encoding="utf-8")
    if MARK in header:
        print("[capi_abort_file] đã vá từ trước, bỏ qua")
        return
    header = replace_once(
        header,
        "AUDIOCPP_API const char * audiocpp_status_string(audiocpp_status status);\n",
        "AUDIOCPP_API const char * audiocpp_status_string(audiocpp_status status);\n"
        "\n"
        "/* " + MARK + ": append ggml's abort message (GGML_ASSERT …) and the message of an uncaught exception to\n"
        " * `path` before the process stops; NULL or \"\" removes the hook. Process-wide. */\n"
        "AUDIOCPP_API audiocpp_status audiocpp_set_abort_file(const char * path);\n",
        "khai báo audiocpp_status_string",
    )

    source_path = root / "src/capi/audiocpp.cpp"
    source = source_path.read_text(encoding="utf-8")
    source = replace_once(
        source,
        "#include <cstddef>\n#include <cstdint>\n",
        "#include <cstddef>\n#include <cstdint>\n"
        "#include <cstdio>   // " + MARK + "\n"
        "#include <cstdlib>  // " + MARK + "\n"
        "#include <cstring>  // " + MARK + "\n"
        "#include <ggml.h>   // " + MARK + "\n",
        "include cstddef/cstdint",
    )
    source = replace_once(
        source,
        '    return "unknown status";\n}\n',
        '    return "unknown status";\n}\n'
        "\n"
        "// " + MARK + "\n"
        "namespace {\n"
        "char g_freebook_abort_path[1024] = {0};\n"
        "\n"
        "void freebook_write_abort_note(const char * message) noexcept {\n"
        "    if (g_freebook_abort_path[0] == '\\0' || message == nullptr) {\n"
        "        return;\n"
        "    }\n"
        "    if (FILE * file = std::fopen(g_freebook_abort_path, \"a\")) {\n"
        "        std::fputs(message, file);\n"
        "        std::fputc('\\n', file);\n"
        "        std::fclose(file);\n"
        "    }\n"
        "}\n"
        "\n"
        "void freebook_ggml_abort(const char * message) {\n"
        "    freebook_write_abort_note(message);\n"
        "    std::fprintf(stderr, \"%s\\n\", message != nullptr ? message : \"ggml abort\");\n"
        "}\n"
        "\n"
        "void freebook_terminate() {\n"
        "    const char * what = \"std::terminate (no active exception)\";\n"
        "    std::string text;\n"
        "    if (const auto current = std::current_exception()) {\n"
        "        try {\n"
        "            std::rethrow_exception(current);\n"
        "        } catch (const std::exception & e) {\n"
        "            text = std::string(\"uncaught exception: \") + e.what();\n"
        "            what = text.c_str();\n"
        "        } catch (...) {\n"
        "            what = \"uncaught non-std exception\";\n"
        "        }\n"
        "    }\n"
        "    freebook_write_abort_note(what);\n"
        "    std::abort();\n"
        "}\n"
        "}  // namespace\n"
        "\n"
        "audiocpp_status audiocpp_set_abort_file(const char * path) {\n"
        "    return guard([&]() {\n"
        "        if (path == nullptr || path[0] == '\\0') {\n"
        "            g_freebook_abort_path[0] = '\\0';\n"
        "            ggml_set_abort_callback(nullptr);\n"
        "            return AUDIOCPP_OK;\n"
        "        }\n"
        "        if (std::strlen(path) >= sizeof(g_freebook_abort_path)) {\n"
        "            throw std::invalid_argument(\"audiocpp_set_abort_file: path too long\");\n"
        "        }\n"
        "        std::snprintf(g_freebook_abort_path, sizeof(g_freebook_abort_path), \"%s\", path);\n"
        "        ggml_set_abort_callback(freebook_ggml_abort);\n"
        "        std::set_terminate(freebook_terminate);\n"
        "        return AUDIOCPP_OK;\n"
        "    });\n"
        "}\n",
        "cuối audiocpp_status_string",
    )

    header_path.write_text(header, encoding="utf-8")
    source_path.write_text(source, encoding="utf-8")
    print("[capi_abort_file] đã vá include/audiocpp.h + src/capi/audiocpp.cpp")


if __name__ == "__main__":
    main()
