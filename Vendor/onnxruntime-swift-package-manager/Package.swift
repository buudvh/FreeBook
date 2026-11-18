// swift-tools-version: 5.9

// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License (xem `LICENSE` cùng thư mục).
//
// Bản chép cục bộ của gói `onnxruntime-swift-package-manager` 1.24.2 (FreeBook 1.3.979).
//
// - Mã nguồn `objectivec/` chép nguyên văn từ commit b7fb7f7dea8a2469e6335d95a61b8f36d0dc83b2 ("Update ORT to 1.24.2
//   (#43)") — commit upstream của Microsoft, lấy từ bản fork `masicai/onnxruntime-swift-package-manager` vì repo gốc
//   `microsoft/onnxruntime-swift-package-manager` trả 404 từ 2026-11-17. Chỉ giữ file target `OnnxRuntimeBindings` cần
//   (bỏ test, tài liệu, phần training — gói gốc cũng `exclude` chúng) và bỏ product `onnxruntime_extensions` (app không dùng).
// - File nhị phân `onnxruntime` (pod archive 1.24.2, 52 MB) lưu ở release `onnxruntime-1.24.2` của repo
//   `buudvh/FreeBook-deps`; checksum trùng checksum gốc của Microsoft (`download.onnxruntime.ai`).
//
// Tên package, product (`onnxruntime`) và target (`OnnxRuntimeBindings`) giữ y như gói gốc ⇒ `project.yml` và
// `import OnnxRuntimeBindings` không đổi. Nâng ORT: thay `objectivec/` bằng bản mới, tải pod archive mới lên một release
// mới của `FreeBook-deps`, cập nhật `url` + `checksum` (`swift package compute-checksum <zip>` = SHA-256 của zip).

import PackageDescription

let package = Package(
    name: "onnxruntime",
    platforms: [.iOS(.v15),
                .macOS(.v14)],
    products: [
        .library(name: "onnxruntime",
                 type: .static,
                 targets: ["OnnxRuntimeBindings"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "OnnxRuntimeBindings",
                dependencies: ["onnxruntime"],
                path: "objectivec",
                cxxSettings: [
                    .define("SPM_BUILD"),
                ]),
        .binaryTarget(name: "onnxruntime",
                      url: "https://github.com/buudvh/FreeBook-deps/releases/download/onnxruntime-1.24.2/pod-archive-onnxruntime-c-1.24.2.zip",
                      // SHA-256 của zip — trùng checksum gốc của Microsoft cho bản 1.24.2.
                      checksum: "f7100a992d2a8135168c8afd831e6a58b465349101982aa58b3e11d36e600b54"),
    ],
    cxxLanguageStandard: .cxx17
)
