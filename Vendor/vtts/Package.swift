// swift-tools-version: 5.9

// vtts — TTS Việt–Anh siêu nhẹ (https://github.com/tuanpmt/vtts, Apache-2.0, xem `LICENSE` + `NOTICE` cùng thư mục).
//
// Gói SPM cục bộ của FreeBook (plan `Docs/Plans/2026-11-20-vtts-integration.md`):
// - `Sources/CVTTS/runtime/{include,src}`: chép NGUYÊN VĂN `runtime/include` + `runtime/src` của commit ghim ở
//   `VTTS_COMMIT.txt`. Đừng sửa tay: `Scripts/ci/fetch_vtts_assets.sh` so từng byte với bản upstream của commit đó và
//   dừng CI nếu lệch. Từ điển VLEX (`lex_en.bin`) mà runtime đọc tại chỗ phải dựng từ CÙNG commit — script lo việc này.
// - `Sources/CVTTS/bridge/`: shim C của FreeBook (`vtts_bridge.h` là header công khai duy nhất Swift thấy).
//
// Chỉ bật tiếng Việt / tiếng Anh / auto: mọi ngôn ngữ phụ tắt bằng `VTTS_ENABLE_<L>=0` — đúng cấu hình
// `langs_test_none` mà Makefile upstream tự kiểm; module của chúng thành translation unit rỗng, bảng không vào binary.
// Danh sách phải khớp `VTTS_DISABLED_LANGS` trong `Scripts/ci/fetch_vtts_assets.sh` (bản dựng thử trên máy CI).
//
// Nâng phiên bản: thay `runtime/` bằng bản của commit mới, sửa `VTTS_COMMIT.txt`, xem lại danh sách ngôn ngữ ở Makefile
// upstream (`OPT_LANGS`) — xem `.claude/rules/ci-release.md`.

import PackageDescription

let disabledLanguages = [
    "ZH", "KO", "JA", "HI", "TH", "ES", "ID", "PT", "FR", "DE", "IT", "TR", "RU", "PL",
    "AR", "FI", "EL", "MS", "TL", "SW", "NL", "SV", "NO", "DA", "LO", "KM", "MY",
]

let runtimeSettings: [CSetting] = [
    .headerSearchPath("runtime/include"),
    .headerSearchPath("runtime/src"),
] + disabledLanguages.map { CSetting.define("VTTS_ENABLE_\($0)", to: "0") }

let package = Package(
    name: "vtts",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "CVTTS", targets: ["CVTTS"]),
    ],
    targets: [
        .target(
            name: "CVTTS",
            path: "Sources/CVTTS",
            publicHeadersPath: "bridge/include",
            cSettings: runtimeSettings
        ),
    ]
)
